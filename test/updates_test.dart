import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/app/sai_app.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/core/updates.dart';

Map<String, dynamic> releaseJson({String tag = 'v1.5.0'}) {
  final name = ReleaseVersion.parse(tag).name;
  return {
    'tag_name': tag,
    'draft': false,
    'prerelease': false,
    'body': '改进 PDF 与计算工具。',
    'html_url': 'https://github.com/$githubRepository/releases/tag/$tag',
    'assets': [
      for (final abi in ['universal', 'arm64-v8a', 'armeabi-v7a', 'x86_64'])
        {
          'name': 'SaiSuite-$name-$abi.apk',
          'size': 35000000,
          'state': 'uploaded',
          'browser_download_url':
              'https://github.com/$githubRepository/releases/download/$tag/SaiSuite-$name-$abi.apk',
        },
    ],
  };
}

const current = InstalledApp('1.4.0', 4009, 'x86_64');

class TestHeaders implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestResponse extends Stream<List<int>> implements HttpClientResponse {
  TestResponse(this.statusCode, this.chunks);
  @override
  final int statusCode;
  final List<List<int>> chunks;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable(chunks).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestRequest implements HttpClientRequest {
  TestRequest(this.response);
  final HttpClientResponse response;
  @override
  final TestHeaders headers = TestHeaders();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestClient implements HttpClient {
  TestClient(int status, List<List<int>> chunks)
    : request = TestRequest(TestResponse(status, chunks));
  final TestRequest request;
  Object? failure;
  Uri? requested;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested = url;
    if (failure != null) throw failure!;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('versions compare numbers, ignore older releases and accept explicit newer build', () {
    expect(
      ReleaseVersion.parse('v1.10.0').compareTo(ReleaseVersion.parse('1.9.9')),
      greaterThan(0),
    );
    expect(GitHubRelease.parse(releaseJson()).newerThan(current), isTrue);
    expect(
      GitHubRelease.parse(releaseJson(tag: 'v1.4.0')).newerThan(current),
      isFalse,
    );
    expect(
      GitHubRelease.parse(releaseJson(tag: 'v1.4.0+10')).newerThan(current),
      isTrue,
    );
    expect(
      GitHubRelease.parse(releaseJson(tag: 'v1.4.0+8')).newerThan(current),
      isFalse,
    );
    expect(
      GitHubRelease.parse(releaseJson(tag: 'v1.3.0')).newerThan(current),
      isFalse,
    );
    expect(() => ReleaseVersion.parse('v1.5.0-beta'), throwsFormatException);
  });
  test('only stable releases and same-variant APKs are offered', () {
    for (final flag in ['draft', 'prerelease']) {
      expect(
        () => GitHubRelease.parse({...releaseJson(), flag: true}),
        throwsFormatException,
      );
    }
    final release = GitHubRelease.parse(releaseJson());
    for (final variant in ['universal', 'arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      expect(
        release.assetFor(InstalledApp('1.4.0', 9, variant))!.name,
        'SaiSuite-1.5.0-$variant.apk',
      );
    }
    final json = releaseJson();
    (json['assets'] as List).removeLast();
    expect(
      GitHubRelease.parse(json).assetFor(current),
      isNull,
    ); // No universal downgrade fallback.
  });
  test('foreign, credentialed, redirected and incomplete asset URLs are rejected', () {
    final json = releaseJson();
    final asset = (json['assets'] as List).last as Map;
    for (final url in [
      'http://github.com/$githubRepository/releases/download/v1.5.0/SaiSuite-1.5.0-x86_64.apk',
      'https://evil.example/$githubRepository/releases/download/v1.5.0/SaiSuite-1.5.0-x86_64.apk',
      'https://github.com/other/repo/releases/download/v1.5.0/SaiSuite-1.5.0-x86_64.apk',
      'https://user@github.com/$githubRepository/releases/download/v1.5.0/SaiSuite-1.5.0-x86_64.apk',
      '${asset['browser_download_url']}?redirect=evil',
    ]) {
      final changed = releaseJson();
      (changed['assets'] as List).last['browser_download_url'] = url;
      expect(GitHubRelease.parse(changed).assetFor(current), isNull);
    }
    expect(
      () => GitHubRelease.parse({
        ...json,
        'html_url': 'https://evil.example/release',
      }),
      throwsFormatException,
    );
    asset['state'] = 'new';
    expect(GitHubRelease.parse(json).assetFor(current), isNull);
  });
  test('HTTP latest release handles metadata, missing release, limits and malformed responses', () async {
    final ok = TestClient(200, [utf8.encode(jsonEncode(releaseJson()))]);
    expect(
      (await GitHubUpdates.fetchLatest(httpClient: ok))!.version.name,
      '1.5.0',
    );
    expect(
      ok.requested.toString(),
      'https://api.github.com/repos/$githubRepository/releases/latest',
    );
    expect(ok.request.headers.values['User-Agent'], 'SaiSuite/$appVersion');
    expect(ok.request.followRedirects, isFalse);
    expect(ok.closed, isTrue);
    final missing = TestClient(404, []);
    expect(await GitHubUpdates.fetchLatest(httpClient: missing), isNull);
    expect(missing.closed, isTrue);
    for (final code in [403, 429, 500, 302]) {
      final client = TestClient(code, []);
      await expectLater(
        GitHubUpdates.fetchLatest(httpClient: client),
        throwsA(isA<UpdateFailure>()),
      );
      expect(client.closed, isTrue);
    }
    for (final chunks in [
      [utf8.encode('bad json')],
      [List<int>.filled(1048577, 32)],
    ]) {
      final client = TestClient(200, chunks);
      await expectLater(
        GitHubUpdates.fetchLatest(httpClient: client),
        throwsA(isA<UpdateFailure>()),
      );
      expect(client.closed, isTrue);
    }
  });
  test(
    'connection errors are recoverable and always close the client',
    () async {
      for (final error in [
        const SocketException('offline'),
        TimeoutException('timeout'),
        const HandshakeException('TLS'),
      ]) {
        final client = TestClient(200, [])..failure = error;
        await expectLater(
          GitHubUpdates.fetchLatest(httpClient: client),
          throwsA(isA<UpdateFailure>()),
        );
        expect(client.closed, isTrue);
      }
      var reads = 0;
      final service = GitHubUpdates(
        readApp: () async {
          if (++reads == 1) throw const UpdateFailure('暂不可用');
          return current;
        },
      );
      await expectLater(service.installed, throwsA(isA<UpdateFailure>()));
      expect(await service.installed, current);
    },
  );
  test('automatic setting persists, off prevents network and manual checking still works', () async {
    final state = AppState(await SharedPreferences.getInstance());
    expect(state.autoCheckUpdates, isTrue);
    await state.setAutoCheckUpdates(false);
    var calls = 0;
    final controller = UpdateController(
      state,
      GitHubUpdates(
        readApp: () async => current,
        fetchRelease: () async {
          calls++;
          return null;
        },
      ),
    );
    await controller.initialize();
    expect(calls, 0);
    expect(AppState(state.prefs).autoCheckUpdates, isFalse);
    await controller.check();
    expect(calls, 1);
    expect(controller.checked, isTrue);
    await state.clearHistory();
    expect(AppState(state.prefs).autoCheckUpdates, isFalse);
    controller.dispose();
  });
  test('daily attempts are deduplicated, failures can retry manually and cache survives restart', () async {
    final state = AppState(await SharedPreferences.getInstance());
    var time = DateTime(2026, 10, 4, 12), calls = 0;
    final gate = Completer<GitHubRelease?>();
    final controller = UpdateController(
      state,
      GitHubUpdates(
        readApp: () async => current,
        fetchRelease: () {
          calls++;
          return gate.future;
        },
      ),
      now: () => time,
    );
    final a = controller.check(), b = controller.check();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    gate.complete(GitHubRelease.parse(releaseJson()));
    await Future.wait([a, b]);
    expect(controller.available, isTrue);
    await controller.check(automatic: true);
    expect(calls, 1);
    time = time.add(const Duration(hours: 24));
    await controller.check(automatic: true);
    expect(calls, 2);
    controller.dispose();
    await state.setAutoCheckUpdates(false);
    final restored = UpdateController(
      AppState(state.prefs),
      GitHubUpdates(
        readApp: () async => current,
        fetchRelease: () async => throw const UpdateFailure('should not run'),
      ),
    );
    await restored.initialize();
    expect(restored.available, isTrue);
    restored.dispose();
    final failing = UpdateController(
      state,
      GitHubUpdates(
        readApp: () async => current,
        fetchRelease: () async {
          throw const UpdateFailure('网络失败');
        },
      ),
      now: () => time,
    );
    await failing.check();
    expect(failing.error, '网络失败');
    expect(failing.checking, isFalse);
    expect(failing.due, isFalse);
    failing.dispose();
  });
  test(
    'disposing a pending check does not notify or persist a late response',
    () async {
      final state = AppState(await SharedPreferences.getInstance());
      final gate = Completer<GitHubRelease?>();
      final controller = UpdateController(
        state,
        GitHubUpdates(
          readApp: () async => current,
          fetchRelease: () => gate.future,
        ),
      );
      final pending = controller.check();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      gate.complete(GitHubRelease.parse(releaseJson()));
      await pending;
      expect(state.prefs.getString('updateCachedRelease'), isNull);
    },
  );
  testWidgets(
    'settings toggle, update notes and matching download work on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(await SharedPreferences.getInstance());
      await state.setAutoCheckUpdates(false);
      var calls = 0;
      Uri? opened;
      final updates = UpdateController(
        state,
        GitHubUpdates(
          readApp: () async => current,
          fetchRelease: () async {
            calls++;
            return GitHubRelease.parse(releaseJson());
          },
          openUrl: (uri) async {
            opened = uri;
          },
        ),
      );
      addTearDown(updates.dispose);
      await tester.pumpWidget(SaiApp(state: state, updates: updates));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('自动检查更新'));
      expect(find.byType(Switch), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(state.autoCheckUpdates, isTrue);
      expect(calls, 1);
      await tester.ensureVisible(find.text('查看新版本'));
      await tester.tap(find.text('查看新版本'));
      await tester.pumpAndSettle();
      expect(find.text('改进 PDF 与计算工具。'), findsOneWidget);
      await tester.tap(find.text('下载 APK'));
      await tester.pumpAndSettle();
      expect(opened!.pathSegments.last, 'SaiSuite-1.5.0-x86_64.apk');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('manual retry exposes network errors without blocking tools', (
    tester,
  ) async {
    final state = AppState(await SharedPreferences.getInstance());
    var attempts = 0;
    final updates = UpdateController(
      state,
      GitHubUpdates(
        readApp: () async => current,
        fetchRelease: () async {
          attempts++;
          throw const UpdateFailure('无法连接 GitHub，请检查网络后重试');
        },
      ),
    );
    addTearDown(updates.dispose);
    await tester.pumpWidget(SaiApp(state: state, updates: updates));
    await tester.pumpAndSettle();
    expect(find.text('浏览 60 个工具'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('无法连接 GitHub，请检查网络后重试'));
    expect(find.text('无法连接 GitHub，请检查网络后重试'), findsOneWidget);
    await tester.ensureVisible(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
