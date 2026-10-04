import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saisuite/features/collage_page.dart';
import 'package:saisuite/features/pdf_page.dart';
import 'package:saisuite/features/pdf_preview.dart';
import 'package:saisuite/features/video_studio_preview.dart';
import 'package:video_player/video_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const media = MethodChannel('saisuite/media');
  Future<void> until(WidgetTester tester, bool Function() ready) async {
    final end = DateTime.now().add(const Duration(seconds: 50));
    while (!ready() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue);
  }

  Future<ui.Image> solid(Color color) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
        .drawRect(const Rect.fromLTWH(0, 0, 200, 100), Paint()..color = color);
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 100);
    picture.dispose();
    return image;
  }

  testWidgets(
    'collage preview and PNG share geometry; PDF grids preserve original and duplicate pages',
    (tester) async {
      final temp = await getTemporaryDirectory(),
          red = await solid(const Color(0xffff0000)),
          blue = await solid(const Color(0xff0000ff));
      final redFile = File('${temp.path}/saisuite_upgrades_red.png'),
          blueFile = File('${temp.path}/saisuite_upgrades_blue.png');
      for (final pair in [(red, redFile), (blue, blueFile)]) {
        await pair.$2.writeAsBytes(
          (await pair.$1.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
      }
      final cells = [CollageCell(red), CollageCell(blue)];
      final rects = collageRects([2, 2], '双列', 200, 0, 0);
      final painter = CollagePainter(
        cells,
        rects,
        Colors.white,
        0,
        const Size(200, 100),
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(200, 100));
      final picture = recorder.endRecording(),
          output = await picture.toImage(200, 100);
      final bytes = (await output.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(bytes.getUint8((50 * 200 + 50) * 4), 255);
      expect(bytes.getUint8((50 * 200 + 150) * 4 + 2), 255);
      output.dispose();
      picture.dispose();
      red.dispose();
      blue.dispose();
      final source = (await pdfChannel.invokeMethod<String>('images', {
        'images': [redFile.path, blueFile.path],
        'paper': 'A4',
        'margin': 20,
      }))!;
      final hash = sha256.convert(await File(source).readAsBytes());
      final previews = <String>[];
      Future<String> load(int page, int dpi) async {
        final path = (await pdfChannel.invokeMethod<String>('render', {
          'path': source,
          'page': page,
          'dpi': dpi,
        }))!;
        previews.add(path);
        return path;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: PdfPageGrid(
            pages: const [0, 1],
            load: load,
            initialSelection: const {0, 1},
          ),
        ),
      );
      await until(tester, () => find.byType(Image).evaluate().length == 2);
      await tester.tap(find.byTooltip('全屏预览').first);
      await tester.pumpAndSettle();
      expect(find.text('第 1 页 · 1/2'), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 页 · 2/2'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      expect(find.text('已选 1/2 页'), findsOneWidget);
      final transformed = (await pdfChannel.invokeMethod<String>('transform', {
        'path': source,
        'pages': [1, 0, 1],
        'rotation': 0,
      }))!;
      final info = await pdfChannel.invokeMapMethod<String, dynamic>(
        'inspect',
        {'path': transformed},
      );
      expect(info!['count'], 3);
      expect(sha256.convert(await File(source).readAsBytes()), hash);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await pdfChannel.invokeMethod<void>('cleanup', {
        'paths': [source, transformed, ...previews],
      });
      expect(await File(source).exists(), isFalse);
      await redFile.delete();
      await blueFile.delete();
    },
  );
  testWidgets(
    'native video frames, inline player, selected loop and clip export protect input',
    (tester) async {
      final temp = await getTemporaryDirectory();
      final source = File('${temp.path}/saisuite-video-fixture.mp4');
      expect(
        await source.exists(),
        isTrue,
        reason: 'Run tools/test_tool_upgrades.ps1 to install the official Flutter video fixture',
      );
      final hash = sha256.convert(await source.readAsBytes()),
          owned = <String>[];
      final thumb = (await media.invokeMapMethod<String, dynamic>(
        'videoThumbnail',
        {'path': source.path, 'seconds': 1.0},
      ))!;
      owned.add(thumb['path'] as String);
      final codec = await ui.instantiateImageCodec(
        await File(owned.last).readAsBytes(),
      );
      final image = (await codec.getNextFrame()).image;
      expect(image.width, lessThanOrEqualTo(320));
      expect(image.height, lessThanOrEqualTo(320));
      image.dispose();
      codec.dispose();
      final frame = (await media.invokeMapMethod<String, dynamic>(
        'videoFrame',
        {'path': source.path, 'seconds': 1.0},
      ))!;
      owned.add(frame['path'] as String);
      expect(await File(owned.last).length(), greaterThan(1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoStudioPreview(
              path: source.path,
              start: .5,
              end: 1.5,
              frame: 1,
              frameMode: false,
              onFrame: (_) {},
            ),
          ),
        ),
      );
      await until(tester, () => find.byType(VideoPlayer).evaluate().isNotEmpty);
      final player = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      await tester.tap(find.byTooltip('播放'));
      await Future<void>.delayed(const Duration(seconds: 3));
      await tester.pump();
      expect(player.value.hasError, isFalse);
      expect(player.value.position.inMilliseconds, inInclusiveRange(450, 1700));
      await player.pause();
      final duration = player.value.duration;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoStudioPreview(
              path: source.path,
              start: 0,
              end: duration.inMilliseconds / 1000,
              frame: 1,
              frameMode: false,
              onFrame: (_) {},
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
      await player.seekTo(duration - const Duration(milliseconds: 300));
      await player.play();
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
      expect(player.value.isPlaying, isTrue);
      expect(
        player.value.position,
        lessThan(duration - const Duration(milliseconds: 300)),
      );
      await player.pause();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final clip = (await media.invokeMapMethod<String, dynamic>(
        'videoProcess',
        {
          'path': source.path,
          'start': .5,
          'end': 1.5,
          'mute': true,
          'height': 360,
          'bitrate': 800000,
        },
      ))!;
      owned.add(clip['path'] as String);
      final info = (await media.invokeMapMethod<String, dynamic>('videoInfo', {
        'path': owned.last,
      }))!;
      expect((info['duration'] as num).toDouble(), closeTo(1, .2));
      expect(int.parse(info['height'].toString()), 360);
      expect(sha256.convert(await source.readAsBytes()), hash);
      await media.invokeMethod<void>('mediaCleanup', {'paths': owned});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await File(owned.last).exists(), isFalse);
    },
  );
}
