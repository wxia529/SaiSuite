import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'files.dart';

/// Android keeps its existing native channel; Windows uses the bundled worker.
class SaiChannel {
  const SaiChannel(this.name);
  final String name;
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return MethodChannel(name).invokeMethod<T>(method, arguments);
    }
    return await WindowsBackend.invoke(name, method, arguments) as T?;
  }

  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    dynamic args,
  ]) async {
    final value = await invokeMethod<dynamic>(method, args);
    return value == null ? null : Map<K, V>.from(value as Map);
  }
}

class WindowsBackend {
  static Future<void> stopAll() async {
    _alarm?.cancel();
    for (final process in _running.values.expand((v) => v).toSet()) {
      await Process.run('taskkill.exe', ['/PID', '${process.pid}', '/T', '/F']);
    }
  }

  static final _running = <String, Set<Process>>{};
  static final _owned = <String>{};
  static final _pendingFiles = <Process, Set<String>>{};
  static Timer? _alarm;
  static String? _progress;
  static double _duration = 0;
  static String get runtime =>
      '${File(Platform.resolvedExecutable).parent.path}/backend';

  static Future<String> _cache() async =>
      (await Files.temporaryDirectory()).resolveSymbolicLinks();

  static Future<dynamic> invoke(
    String channel,
    String method,
    dynamic args,
  ) async {
    final a = Map<String, dynamic>.from(args as Map? ?? {});
    if (method == 'cleanup' || method == 'mediaCleanup') {
      for (final p in (a['paths'] as List? ?? []).cast<String>()) {
        if (_owned.remove(p)) {
          final file = File(p);
          if (await file.exists()) await file.delete();
        }
      }
      return null;
    }
    if (channel == 'saisuite/updates') {
      if (method == 'appInfo') {
        return await const MethodChannel('saisuite/windows')
            .invokeMapMethod<String, dynamic>('appInfo');
      }
      if (method == 'openUrl') {
        final uri = Uri.parse(a['url'] as String);
        if (uri.scheme != 'https' ||
            uri.host != 'github.com' ||
            uri.userInfo.isNotEmpty ||
            uri.port != 443 ||
            uri.hasQuery ||
            uri.hasFragment ||
            !(uri.path == '/wxia529/SaiSuite/releases' ||
                uri.path.startsWith('/wxia529/SaiSuite/releases/'))) {
          throw PlatformException(code: 'URL', message: '地址不属于当前发布仓库');
        }
        await Process.run('explorer.exe', [uri.toString()]);
        return null;
      }
    }
    if (channel == 'saisuite/device') {
      if (method == 'displayMetrics') {
        // Windows reported DPI describes UI scaling, not physical panel size.
        // The ruler explicitly requires physical calibration before measuring.
        return {'xdpi': 96.0, 'ydpi': 96.0, 'density': 1.0};
      }
      if (method == 'sensors') return <dynamic>[];
      if (method == 'timerCancel') {
        _alarm?.cancel();
        return null;
      }
      if (method == 'timerSchedule') {
        _alarm?.cancel();
        final delay =
            (a['deadline'] as int) - DateTime.now().millisecondsSinceEpoch;
        _alarm = Timer(Duration(milliseconds: delay < 0 ? 0 : delay), () {
          // Native dialog remains visible even when the main window is minimized.
          const MethodChannel('saisuite/windows')
              .invokeMethod<void>('timerAlert');
        });
        return true;
      }
    }
    if (method == 'saveOutput') {
      final path = a['path'] as String;
      if (!_owned.contains(path)) {
        throw PlatformException(code: 'OUTPUT', message: '只能导出本次生成的文件');
      }
      final uri = await FilePicker.saveFile(
        dialogTitle: '另存为新文件',
        fileName: a['name'] as String,
        bytes: await File(path).readAsBytes(),
        mimeType: a['mime'] as String? ?? 'application/octet-stream',
      );
      return uri?.toString();
    }
    if (method == 'videoPreview') {
      // The workbench also provides an embedded Windows video preview.
      await Process.run('explorer.exe', [a['path'] as String]);
      return null;
    }
    if (method == 'videoProgress') {
      if (_progress == null || _duration <= 0) return -1;
      try {
        final text = await File(_progress!).readAsString();
        final matches = RegExp(r'out_time_us=(\d+)').allMatches(text);
        if (matches.isEmpty) return 0;
        return (int.parse(matches.last[1]!) / 1000000 / _duration * 100)
            .round()
            .clamp(0, 100);
      } on FileSystemException {
        return 0;
      }
    }
    if (method == 'cancel' || method == 'videoCancel') {
      final key = method == 'videoCancel' ? 'videoProcess' : channel;
      for (final p in _running[key]?.toList() ?? <Process>[]) {
        await Process.run('taskkill.exe', ['/PID', '${p.pid}', '/T', '/F']);
      }
      return null;
    }
    final python = File('$runtime/python.exe');
    if (!await python.exists()) {
      throw PlatformException(
        code: 'RUNTIME',
        message: '处理组件缺失，请完整解压 Windows 安装包',
      );
    }
    final cache = await _cache();
    if (method == 'videoProcess') {
      if (_running['videoProcess']?.isNotEmpty == true) {
        throw PlatformException(code: 'BUSY', message: '视频正在处理中');
      }
      _duration = (a['end'] as num).toDouble() - (a['start'] as num).toDouble();
      _progress =
          '$cache/saisuite_progress_${DateTime.now().microsecondsSinceEpoch}.txt';
      a['progressPath'] = _progress;
      _owned.add(_progress!);
    }
    final process = await Process.start(python.path, [
      '-X',
      'utf8',
      '$runtime/worker.py',
    ]);
    final key = method == 'videoProcess' ? method : channel;
    (_running[key] ??= {}).add(process);
    _pendingFiles[process] = {};
    // Each request gets an output manifest. It lets cancellation clean files
    // written before the worker was terminated without touching user inputs.
    final manifest = '$cache/saisuite_manifest_${process.pid}.txt';
    process.stdin.write(
      jsonEncode({
        'channel': channel,
        'method': method,
        'args': a,
        'cache': cache,
        'manifest': manifest,
      }),
    );
    await process.stdin.close();
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final output = await stdout;
      final errors = await stderr;
      final exit = await process.exitCode;
      if (exit != 0) {
        throw PlatformException(
          code: 'WORKER',
          message:
              '处理已取消或失败${errors.isEmpty ? '' : '：${errors.substring(0, errors.length.clamp(0, 600))}'}',
        );
      }
      final response = jsonDecode(output) as Map;
      if (response['error'] != null) {
        throw PlatformException(
          code: response['code'] as String,
          message: response['error'] as String,
        );
      }
      final result = response['result'];
      final path = result is Map
          ? result['path']
          : result is String && method != 'text'
          ? result
          : null;
      if (path is String) {
        _owned.add(path);
        _pendingFiles[process]!.add(path);
      }
      return result;
    } finally {
      _running[key]?.remove(process);
      if (method == 'videoProcess') {
        final progressPath = a['progressPath'] as String;
        _owned.remove(progressPath);
        try {
          await File(progressPath).delete();
        } on FileSystemException {
          /* optional progress file */
        }
        _progress = null;
      }
      final keep = _pendingFiles.remove(process) ?? {};
      final file = File(manifest);
      if (await file.exists()) {
        for (final p in await file.readAsLines()) {
          if (!keep.contains(p) &&
              File(p).parent.absolute.path == Directory(cache).absolute.path &&
              File(p).uri.pathSegments.last.startsWith('saisuite_')) {
            try {
              await File(p).delete();
            } on FileSystemException {
              /* already removed */
            }
          }
        }
        await file.delete();
      }
    }
  }
}
