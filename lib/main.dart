import 'dart:io';

import 'package:video_player_win/video_player_win.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'core/app_state.dart';
import 'core/files.dart';
import 'core/updates.dart';
import 'core/platform_channel.dart';
import 'app/sai_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) WindowsVideoPlayer.registerWith();
  if (Platform.isWindows) {
    const MethodChannel('saisuite/windows').setMethodCallHandler((call) async {
      if (call.method != 'requestClose') return null;
      final nav = saiNavigatorKey.currentState;
      if (nav == null) return false;
      if (nav.canPop()) {
        final close = await showDialog<bool>(
          context: nav.overlay!.context,
          builder: (c) => AlertDialog(
            title: const Text('关闭工具箱？'),
            content: const Text('尚未导出的图片、PDF 和计算结果会丢失。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('继续使用'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
        if (close != true) return false;
      }
      await WindowsBackend.stopAll();
      return true;
    });
  }
  tzdata.initializeTimeZones();
  await Files.cleanOldCache();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['pro_image_editor and bundled libraries'],
      await rootBundle.loadString(
        'assets/licenses/pro-image-editor-NOTICES.txt',
      ),
    );
    yield LicenseEntryWithLineBreaks([
      'AndroidX Media3',
    ], await rootBundle.loadString('assets/licenses/media3-LICENSE.txt'));
    yield LicenseEntryWithLineBreaks(
      ['PdfBox-Android / Apache PDFBox'],
      '${await rootBundle.loadString('assets/licenses/pdfbox-LICENSE.txt')}\n${await rootBundle.loadString('assets/licenses/pdfbox-NOTICE.txt')}',
    );
  });
  final state = AppState(await SharedPreferences.getInstance());
  await state.migrateRetiredTools();
  runApp(
    SaiApp(state: state, updates: UpdateController(state, GitHubUpdates())),
  );
}
