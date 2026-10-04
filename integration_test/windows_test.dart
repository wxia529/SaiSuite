import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_win/video_player_win.dart';
import 'package:saisuite/app/sai_app.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/core/platform_channel.dart';
import 'package:saisuite/core/updates.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/core/files.dart';
import 'package:saisuite/features/image_editor_page.dart';
import 'package:saisuite/core/localizations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WindowsVideoPlayer.registerWith();
  const pdf = SaiChannel('saisuite/pdf'), media = SaiChannel('saisuite/media');

  testWidgets(
    'Windows worker, PDF original dimensions, password, preview and protected inputs',
    (tester) async {
      final dir = await getTemporaryDirectory();
      final recording = ui.PictureRecorder();
      Canvas(recording).drawRect(
        const Rect.fromLTWH(0, 0, 240, 120),
        Paint()..color = const Color(0x80228844),
      );
      final picture = recording.endRecording();
      final im = await picture.toImage(240, 120);
      final file = File('${dir.path}/saisuite_windows_input.png');
      await file.writeAsBytes(
        (await im.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      await file.setLastModified(
        DateTime.now().subtract(const Duration(days: 2)),
      );
      await Files.cleanOldCache();
      expect(
        await file.exists(),
        isTrue,
        reason: 'Shared Windows TEMP inputs must never be swept',
      );
      im.dispose();
      picture.dispose();
      final hash = sha256.convert(await file.readAsBytes());
      final out = (await pdf.invokeMethod<String>('images', {
        'images': [file.path],
        'paper': '按图片尺寸',
        'margin': 0,
      }))!;
      final info = (await pdf.invokeMapMethod<String, dynamic>('inspect', {
        'path': out,
      }))!;
      expect(info['count'], 1);
      expect((info['pages'] as List).first['width'], 240);
      final encrypted = (await pdf.invokeMethod<String>('encrypt', {
        'path': out,
        'newPassword': 'windows-密码',
      }))!;
      final decrypted = (await pdf.invokeMethod<String>('decrypt', {
        'path': encrypted,
        'password': 'windows-密码',
      }))!;
      final render = (await pdf.invokeMethod<String>('render', {
        'path': decrypted,
        'page': 0,
        'dpi': 72,
      }))!;
      expect(await File(render).exists(), isTrue);
      await pdf.invokeMethod<void>('cleanup', {
        'paths': [file.path, out, encrypted, decrypted, render],
      });
      // Input paths never become owned outputs, even when passed to cleanup.
      expect(sha256.convert(await file.readAsBytes()), hash);
      expect(await File(out).exists(), isFalse);
      final prepared = (await media.invokeMapMethod<String, dynamic>(
        'imagePrepareEditor',
        {'path': file.path},
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: saiLocalizationsDelegates,
          home: ImageEditingSession(
            sourcePath: prepared['path'] as String,
            sourceName: 'input.png',
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('裁剪'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await media.invokeMethod<void>('mediaCleanup', {
        'paths': [prepared['path']],
      });
      await file.delete();
    },
  );

  testWidgets('Windows video decoder, trim, frame and embedded playback', (
    tester,
  ) async {
    final source = File(
      '${Directory.current.path}/.buildlog/windows-fixture.mp4',
    );
    expect(await source.exists(), isTrue);
    final info = (await media.invokeMapMethod<String, dynamic>('videoInfo', {
      'path': source.path,
    }))!;
    expect(info['width'], 320);
    final clip = (await media.invokeMapMethod<String, dynamic>('videoProcess', {
      'path': source.path,
      'start': .5,
      'end': 2.0,
      'mute': true,
      'height': 0,
      'bitrate': 1000000,
    }))!;
    expect((clip['duration'] as num).toDouble(), closeTo(1.5, .2));
    final frame = (await media.invokeMapMethod<String, dynamic>('videoFrame', {
      'path': clip['path'],
      'seconds': .5,
    }))!;
    expect(await File(frame['path'] as String).exists(), isTrue);
    final controller = VideoPlayerController.file(File(clip['path'] as String));
    await controller.initialize();
    expect(controller.value.isInitialized, isTrue);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: VideoPlayer(controller))),
    );
    await controller.play();
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.value.position, greaterThan(Duration.zero));
    await controller.pause();
    await controller.dispose();
    await tester.pumpWidget(const SizedBox());
    await media.invokeMethod<void>('mediaCleanup', {
      'paths': [clip['path'], frame['path']],
    });
  });

  testWidgets(
    'Windows navigation, toolbox availability and platform-specific updates',
    (tester) async {
      SharedPreferences.setMockInitialValues({'autoCheckUpdates': false});
      final app = await InstalledApp.read();
      expect(app.variant, 'windows-x64');
      expect(app.version, '1.4.0');
      final screenshotKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: screenshotKey,
          child: SaiApp(state: AppState(await SharedPreferences.getInstance())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('浏览 ${tools.length - 3} 个工具'), findsOneWidget);
      final screenshot =
          await (screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      await File('${Directory.current.path}/.buildlog/windows-home.png')
          .writeAsBytes(
            (await screenshot.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List(),
          );
      screenshot.dispose();
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '指南针');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, '指南针'), findsNothing);
      await tester.enterText(find.byType(TextField), '电解液');
      await tester.pumpAndSettle();
      await tester.tap(find.text('电解液配方'));
      await tester.pumpAndSettle();
      expect(find.text('溶剂'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
