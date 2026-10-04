import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:saisuite/core/platform_channel.dart';
import 'package:saisuite/core/files.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/poster_page.dart';
import 'package:saisuite/features/extra_daily_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = SaiChannel('saisuite/creative');
  testWidgets(
    'native Chinese/English OCR, EXIF edits and source preservation',
    (tester) async {
      final dir = await Files.temporaryDirectory();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      final paragraph = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 58))
        ..pushStyle(ui.TextStyle(color: Colors.black))
        ..addText('电解液测试 SaiSuite 123');
      final words = paragraph.build()
        ..layout(const ui.ParagraphConstraints(width: 1000));
      canvas.drawParagraph(words, const Offset(30, 35));
      final picture = recorder.endRecording();
      final image = await picture.toImage(1100, 150);
      picture.dispose();
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      words.dispose();
      final ocrFile = File('${dir.path}/saisuite_native_ocr.png');
      await ocrFile.writeAsBytes(png);
      final recognized = await channel.invokeMapMethod<String, dynamic>('ocr', {
        'path': ocrFile.path,
      });
      expect(
        (recognized!['text'] as String).replaceAll(' ', ''),
        contains('电解液测试'),
      );
      expect(recognized['text'], contains('123'));
      expect(recognized['lines'], isNotEmpty);
      final photo = img.Image(width: 80, height: 40)
        ..clear(img.ColorRgb8(130, 55, 200));
      photo.exif.imageIfd[0x0112] = 6;
      photo.exif.imageIfd[0x010f] = 'SaiSuite Test';
      final source = File('${dir.path}/saisuite_native_exif.jpg');
      await source.writeAsBytes(img.encodeJpg(photo));
      final original = sha256.convert(await source.readAsBytes());
      final edited = await channel.invokeMapMethod<String, dynamic>(
        'exifWrite',
        {
          'path': source.path,
          'clear': false,
          'fields': {
            '作者': 'SaiSuite',
            '描述': 'Sample',
            '拍摄时间': '2026:10:04 12:34:56',
            '版权': 'Test',
          },
        },
      );
      final info = await channel.invokeMapMethod<String, dynamic>('exifRead', {
        'path': edited!['path'],
      });
      expect(info!['作者'], 'SaiSuite');
      expect(info['拍摄时间'], '2026:10:04 12:34:56');
      final cleared = await channel.invokeMapMethod<String, dynamic>(
        'exifWrite',
        {'path': edited['path'], 'clear': true},
      );
      final cleanInfo = await channel.invokeMapMethod<String, dynamic>(
        'exifRead',
        {'path': cleared!['path']},
      );
      expect(cleanInfo!['作者'], '');
      expect(cleanInfo['方向'], '6');
      expect(sha256.convert(await source.readAsBytes()), original);
      final a = img.decodeJpg(await source.readAsBytes())!,
          b = img.decodeJpg(
            await File(cleared['path'] as String).readAsBytes(),
          )!;
      expect(b.width, a.width);
      expect(b.height, a.height);
      expect(b.getPixel(10, 10).r, a.getPixel(10, 10).r);
      for (final p in [
        ocrFile.path,
        source.path,
        edited['path'] as String,
        cleared['path'] as String,
      ]) {
        await File(p).delete();
      }
    },
  );
  testWidgets('real audio extraction has an audio track and preserves input', (
    tester,
  ) async {
    final dir = await Files.temporaryDirectory();
    final fixture = Platform.isWindows
        ? File('${Directory.current.path}/.buildlog/creative-audio.mp4')
        : File('${dir.path}/saisuite-creative-audio.mp4');
    expect(
      await fixture.exists(),
      isTrue,
      reason: 'Prepare synthetic AAC test video before running',
    );
    final hash = sha256.convert(await fixture.readAsBytes());
    final result = await channel.invokeMapMethod<String, dynamic>(
      'extractAudio',
      {'path': fixture.path},
    );
    final output = File(result!['path'] as String);
    expect(await output.length(), greaterThan(5000));
    expect(sha256.convert(await fixture.readAsBytes()), hash);
    await output.delete();
    if (Platform.isWindows) {
      await const MethodChannel('saisuite/windows')
          .invokeMethod('fullScreen', true);
      await const MethodChannel('saisuite/windows')
          .invokeMethod('fullScreen', false);
    }
  });
  testWidgets('poster and stopwatch render on the actual device', (
    tester,
  ) async {
    final state = AppState(await SharedPreferences.getInstance());
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: PosterPage(
            tool: tools.firstWhere((t) => t.id == 'B04'),
            state: state,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (Platform.isWindows) {
      await File(
        '${Directory.current.path}/.buildlog/creative-poster-windows.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } else {
      final dir = await Files.temporaryDirectory();
      await File('${dir.path}/saisuite-creative-poster.png')
          .writeAsBytes(data!.buffer.asUint8List());
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ExtraDailyPage(
          tool: tools.firstWhere((t) => t.id == 'U03'),
          state: state,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('开始'));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('暂停'), findsOneWidget);
    await tester.tap(find.text('分段'));
    await tester.pump();
    expect(find.text('分段 · 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    state.dispose();
  });
}
