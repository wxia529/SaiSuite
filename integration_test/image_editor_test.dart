import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:saisuite/features/image_editor_page.dart';
import 'package:saisuite/core/localizations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (!ready() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue);
  }

  testWidgets(
    'editor exports preserve alpha, fill JPEG, honor sizes and protect input',
    (tester) async {
      final temp = await getTemporaryDirectory();
      final source = File('${temp.path}/saisuite_editor_source.png');
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1600, 800),
        Paint()..color = Colors.red,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(3200, 1600);
      await source.writeAsBytes(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      image.dispose();
      picture.dispose();
      final originalHash = sha256.convert(await source.readAsBytes());
      final prepared = (await imageEditorChannel.invokeMapMethod(
        'imagePrepareEditor',
        {'path': source.path},
      ))!;
      final png = (await imageEditorChannel.invokeMapMethod(
        'imageEditorExport',
        {
          'path': prepared['path'],
          'format': 'PNG',
          'maxEdge': 2048,
          'quality': 90,
        },
      ))!;
      expect(png['width'], 2048);
      expect(png['height'], 1024);
      final pngCodec = await ui.instantiateImageCodec(
        await File(png['path'] as String).readAsBytes(),
      );
      final pngFrame = (await pngCodec.getNextFrame()).image;
      final pngPixels = (await pngFrame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(pngPixels[(900 * 2048 + 1800) * 4 + 3], 0);
      pngFrame.dispose();
      pngCodec.dispose();
      final jpeg = (await imageEditorChannel.invokeMapMethod(
        'imageEditorExport',
        {
          'path': prepared['path'],
          'format': 'JPEG',
          'maxEdge': 1024,
          'quality': 95,
        },
      ))!;
      expect(jpeg['width'], 1024);
      expect(jpeg['height'], 512);
      final jpegCodec = await ui.instantiateImageCodec(
        await File(jpeg['path'] as String).readAsBytes(),
      );
      final jpegFrame = (await jpegCodec.getNextFrame()).image;
      final jpegPixels = (await jpegFrame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      for (var channel = 0; channel < 3; channel++) {
        expect(jpegPixels[(400 * 1024 + 900) * 4 + channel], greaterThan(245));
      }
      jpegFrame.dispose();
      jpegCodec.dispose();
      expect(sha256.convert(await source.readAsBytes()), originalHash);
      await imageEditorChannel.invokeMethod('mediaCleanup', {
        'paths': [prepared['path'], png['path'], jpeg['path'], source.path],
      });
      expect(
        await source.exists(),
        isTrue,
        reason: 'cleanup must not delete caller-owned input',
      );
      expect(await File(prepared['path'] as String).exists(), isFalse);
      await source.delete();
    },
  );

  testWidgets(
    'full-screen Chinese editor undo, settings, cancelled and successful system saves',
    (tester) async {
      final temp = await getTemporaryDirectory();
      final source = File('${temp.path}/saisuite_editor_ui_source.png');
      final outputName =
          'editor-sample-${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('EDITOR_TEST_OUTPUT=$outputName-edited.png');
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 160, 80),
        Paint()..color = Colors.red,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(320, 160);
      await source.writeAsBytes(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      image.dispose();
      picture.dispose();
      final originalHash = sha256.convert(await source.readAsBytes());
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: saiLocalizationsDelegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImageEditingSession(
                      sourcePath: source.path,
                      sourceName: '$outputName.png',
                    ),
                  ),
                ),
                child: const Text('打开编辑器'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑器'));
      await until(
        tester,
        () =>
            find.byType(ProImageEditor).evaluate().isNotEmpty &&
            find
                .byKey(const ValueKey('image-editor-export'))
                .evaluate()
                .isNotEmpty &&
            tester
                    .widget<IconButton>(
                      find.byKey(const ValueKey('image-editor-export')),
                    )
                    .onPressed !=
                null,
      );
      final editor = tester.state<ProImageEditorState>(
        find.byType(ProImageEditor),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('文字'));
      await until(
        tester,
        () => find.byType(EditableText).evaluate().isNotEmpty,
      );
      await tester.enterText(find.byType(EditableText), '样品 A');
      await tester.tap(find.byTooltip('完成').last);
      await until(
        tester,
        () =>
            editor.activeLayers.length == 1 &&
            find.byTooltip('撤销').evaluate().isNotEmpty,
      );
      await until(tester, () => !editor.isSubEditorOpen);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('撤销'));
      await until(tester, () => editor.activeLayers.isEmpty);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('重做'));
      await until(tester, () => editor.activeLayers.length == 1);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回').first);
      await until(tester, () => find.text('图片尚未导出').evaluate().isNotEmpty);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('导出设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PNG').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用设置'));
      await tester.pumpAndSettle();
      // The host dismisses the first Android document dialog, then saves the second.
      debugPrint('EDITOR_TEST_WAIT_CANCEL_SAVE');
      await tester.tap(find.byKey(const ValueKey('image-editor-export')));
      await tester.pump();
      await until(tester, () => find.text('正在导出 PNG').evaluate().isEmpty);
      expect(find.textContaining('已另存为新文件'), findsNothing);
      await tester.tap(find.byTooltip('返回').first);
      await until(tester, () => find.text('图片尚未导出').evaluate().isNotEmpty);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      debugPrint('EDITOR_TEST_WAIT_SUCCESS_SAVE');
      await tester.tap(find.byKey(const ValueKey('image-editor-export')));
      await until(
        tester,
        () => find.textContaining('已另存为新文件').evaluate().isNotEmpty,
      );
      expect(find.textContaining('320 × 160 px'), findsOneWidget);
      expect(sha256.convert(await source.readAsBytes()), originalHash);
      await tester.tap(find.byTooltip('返回').first);
      await until(tester, () => find.text('打开编辑器').evaluate().isNotEmpty);
      expect(find.text('图片尚未导出'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await source.delete();
    },
  );
}
