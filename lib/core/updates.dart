import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'platform_channel.dart';
import 'update_links.dart';

export 'update_links.dart';

const appVersion = '1.4.3';
const updateChannel = SaiChannel('saisuite/updates');

class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion(this.major, this.minor, this.patch, [this.build]);
  final int major, minor, patch;
  final int? build;
  static ReleaseVersion parse(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$')
        .firstMatch(value);
    if (match == null) throw const FormatException('发布版本号格式不正确');
    return ReleaseVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      match[4] == null ? null : int.parse(match[4]!),
    );
  }

  String get name => '$major.$minor.$patch';
  @override
  int compareTo(ReleaseVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }
}

class InstalledApp {
  const InstalledApp(this.version, this.versionCode, this.variant);
  final String version, variant;
  final int versionCode;
  static Future<InstalledApp> read() async {
    final info = await updateChannel.invokeMapMethod<String, dynamic>(
      'appInfo',
    );
    if (info == null) throw const FormatException('无法读取当前版本');
    return InstalledApp(
      (info['version'] as String).replaceFirst(RegExp(r'-dev$'), ''),
      info['versionCode'] as int,
      info['variant'] as String,
    );
  }
}

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size);
  final String name;
  final Uri url;
  final int size;
  Map<String, dynamic> toJson() => {
    'name': name,
    'browser_download_url': url.toString(),
    'size': size,
    'state': 'uploaded',
  };
}

class GitHubRelease {
  GitHubRelease(this.tag, this.version, this.notes, this.url, this.assets);
  final String tag, notes;
  final ReleaseVersion version;
  final Uri url;
  final List<ReleaseAsset> assets;
  factory GitHubRelease.parse(Map<String, dynamic> json) {
    if (json['draft'] != false || json['prerelease'] != false) {
      throw const FormatException('只接收正式发布版本');
    }
    final tag = json['tag_name'] as String;
    final version = ReleaseVersion.parse(tag);
    final url = Uri.parse(json['html_url'] as String);
    if (!isRepositoryUrl(url) ||
        url.pathSegments.skip(2).toList().join('/') != 'releases/tag/$tag') {
      throw const FormatException('发布地址不属于当前仓库');
    }
    final assets = <ReleaseAsset>[];
    for (final item in json['assets'] as List) {
      if (item is! Map ||
          item['state'] != 'uploaded' ||
          item['name'] is! String ||
          item['browser_download_url'] is! String ||
          item['size'] is! int) {
        continue;
      }
      final assetUrl = Uri.tryParse(item['browser_download_url'] as String);
      final name = item['name'] as String;
      if (assetUrl == null ||
          !isRepositoryUrl(assetUrl) ||
          (item['size'] as int) <= 0 ||
          assetUrl.pathSegments.skip(2).toList().join('/') !=
              'releases/download/$tag/$name') {
        continue;
      }
      assets.add(ReleaseAsset(name, assetUrl, item['size'] as int));
    }
    final body = json['body'];
    final notes = body is String ? body : '';
    return GitHubRelease(
      tag,
      version,
      notes.length > 6000 ? notes.substring(0, 6000) : notes,
      url,
      assets,
    );
  }
  bool newerThan(InstalledApp app) {
    final order = version.compareTo(ReleaseVersion.parse(app.version));
    return order > 0 ||
        (order == 0 &&
            version.build != null &&
            version.build! > app.versionCode % 1000);
  }

  ReleaseAsset? assetFor(InstalledApp app) {
    final base = 'SaiSuite-${version.name}-${app.variant}';
    final names = app.variant.startsWith('windows-')
        ? ['$base-setup.exe', '$base.zip']
        : ['$base.apk'];
    for (final name in names) {
      final asset = assets.where((a) => a.name == name).firstOrNull;
      if (asset != null) return asset;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'tag_name': tag,
    'draft': false,
    'prerelease': false,
    'body': notes,
    'html_url': url.toString(),
    'assets': assets.map((a) => a.toJson()).toList(),
  };
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class GitHubUpdates {
  GitHubUpdates({
    Future<InstalledApp> Function()? readApp,
    Future<GitHubRelease?> Function()? fetchRelease,
    Future<void> Function(Uri)? openUrl,
  }) : _readApp = readApp ?? InstalledApp.read,
       _fetchRelease = fetchRelease ?? (() => fetchLatest()),
       _openUrl = openUrl ?? openGitHubUrl;
  final Future<InstalledApp> Function() _readApp;
  final Future<GitHubRelease?> Function() _fetchRelease;
  final Future<void> Function(Uri) _openUrl;
  Future<InstalledApp>? _installed;
  Future<InstalledApp> get installed => _installed ??= _loadInstalled();
  Future<InstalledApp> _loadInstalled() async {
    try {
      return await _readApp();
    } catch (_) {
      _installed = null;
      rethrow;
    }
  }

  Future<GitHubRelease?> fetch() => _fetchRelease();
  Future<void> open(Uri uri) async {
    if (!isUpdateUrl(uri)) throw const UpdateFailure('下载地址不属于当前 GitHub 仓库');
    await _openUrl(
      isReleaseDownloadUrl(uri) ? acceleratedDownloadUrl(uri) : uri,
    );
  }

  static Future<void> openGitHubUrl(Uri uri) async =>
      updateChannel.invokeMethod<void>('openUrl', {'url': uri.toString()});
  static Future<GitHubRelease?> fetchLatest({HttpClient? httpClient}) async {
    final client = httpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.parse(
            'https://api.github.com/repos/$githubRepository/releases/latest',
          ),
        );
        request.followRedirects = false;
        request.headers.set('Accept', 'application/vnd.github+json');
        request.headers.set('User-Agent', 'SaiSuite/$appVersion');
        request.headers.set('X-GitHub-Api-Version', '2022-11-28');
        final response = await request.close();
        if (response.statusCode == 404) return null;
        if (response.statusCode == 403 || response.statusCode == 429) {
          throw const UpdateFailure('GitHub 暂时限制请求，请稍后重试');
        }
        if (response.statusCode != 200) {
          throw const UpdateFailure('暂时无法读取 GitHub 发布信息');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 1048576) throw const UpdateFailure('发布信息超过读取上限');
        }
        return GitHubRelease.parse(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        );
      })().timeout(const Duration(seconds: 15));
    } on UpdateFailure {
      rethrow;
    } on TimeoutException {
      throw const UpdateFailure('连接 GitHub 超时，请稍后重试');
    } on SocketException {
      throw const UpdateFailure('无法连接 GitHub，请检查网络后重试');
    } on HandshakeException {
      throw const UpdateFailure('无法安全连接 GitHub，请稍后重试');
    } catch (_) {
      throw const UpdateFailure('发布信息暂时不可用，请稍后重试');
    } finally {
      client.close(force: true);
    }
  }
}

class UpdateController extends ChangeNotifier {
  UpdateController(this.state, this.service, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final AppState state;
  final GitHubUpdates service;
  final DateTime Function() now;
  InstalledApp? app;
  GitHubRelease? release;
  String? error;
  bool checking = false, checked = false, _disposed = false;
  Future<void>? _running;
  bool get available =>
      app != null && release != null && release!.newerThan(app!);
  DateTime? get lastAttempt {
    final value = state.prefs.getInt('updateLastAttempt');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  bool get due =>
      lastAttempt == null ||
      now().difference(lastAttempt!).isNegative ||
      now().difference(lastAttempt!) >= const Duration(hours: 24);
  Future<void> initialize() async {
    try {
      app = await service.installed;
      final cached = state.prefs.getString('updateCachedRelease');
      if (cached != null) {
        try {
          final json = jsonDecode(cached);
          release = json == null
              ? null
              : GitHubRelease.parse(json as Map<String, dynamic>);
          checked = true;
        } catch (_) {
          /* An invalid cache never prevents a fresh check. */
        }
      }
      _notify();
      if (!_disposed) await check(automatic: true);
    } catch (_) {
      error = '无法读取当前应用版本';
      _notify();
    }
  }

  Future<void> check({bool automatic = false}) {
    if (_disposed || (automatic && (!state.autoCheckUpdates || !due))) {
      return Future.value();
    }
    return _running ??= _check().whenComplete(() => _running = null);
  }

  Future<void> _check() async {
    checking = true;
    error = null;
    _notify();
    try {
      app = await service.installed;
      if (_disposed) return;
      await state.prefs.setInt(
        'updateLastAttempt',
        now().millisecondsSinceEpoch,
      );
      release = await service.fetch();
      if (_disposed) return;
      checked = true;
      await state.prefs.setString(
        'updateCachedRelease',
        jsonEncode(release?.toJson()),
      );
    } catch (e) {
      error = e is UpdateFailure ? e.message : '检查更新失败，请稍后重试';
    } finally {
      checking = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
