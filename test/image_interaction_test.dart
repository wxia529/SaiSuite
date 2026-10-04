import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/core/creative_images.dart';
import 'package:saisuite/core/image_framing.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/image_framing_preview.dart';
import 'package:saisuite/features/image_studio_page.dart';
import 'package:saisuite/features/poster_page.dart';
import 'package:saisuite/features/tool_page.dart';

Uint8List coordinateImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p
      ..r = p.x
      ..g = p.y
      ..b = 33;
  }
  return img.encodePng(image);
}

Future<AppState> testAppState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await SharedPreferences.getInstance());
}

Future<void> pinch(WidgetTester tester, Rect rect) async {
  final center = rect.center;
  final first = await tester.startGesture(
    center - const Offset(25, 0),
    pointer: 1,
  );
  final second = await tester.startGesture(
    center + const Offset(25, 0),
    pointer: 2,
  );
  await tester.pump();
  await first.moveTo(center - const Offset(45, 0));
  await second.moveTo(center + const Offset(45, 0));
  await tester.pump();
  await first.moveTo(center - const Offset(65, 0));
  await second.moveTo(center + const Offset(65, 0));
  await tester.pump();
  await first.up();
  await second.up();
  await tester.pump();
}

Future<void> dragObject(
  WidgetTester tester,
  Offset start,
  Offset distance,
) async {
  final gesture = await tester.startGesture(start);
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(start + distance * (i / 10));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await gesture.up();
  await tester.pump();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
  for (var i = 0; i < 15 && target.evaluate().isEmpty; i++) {
    scroll.position.jumpTo(
      (scroll.position.pixels + 350).clamp(0, scroll.position.maxScrollExtent),
    );
    await tester.pump();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Offset inkCenter(img.Image image) {
  var x = 0.0, y = 0.0, n = 0.0;
  for (final p in image) {
    if (p.a > 128) {
      x += p.x;
      y += p.y;
      n++;
    }
  }
  expect(n, greaterThan(50));
  return Offset(x / n, y / n);
}

Future<void> cleanFixture(File file, Directory folder) async {
  await FileImage(file).evict();
  for (var i = 0; ; i++) {
    try {
      await file.delete();
      break;
    } on FileSystemException {
      if (i == 4) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  await folder.delete();
}

Future<void> releaseFixture(
  WidgetTester tester,
  File file,
  Directory folder,
) async {
  // Image.file decoding crosses real I/O and fake widget-frame microtasks.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.runAsync(() => cleanFixture(file, folder));
}

Future<void> captureView(GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  final folder = Platform.isWindows
      ? Directory('${Directory.current.path}/.buildlog')
      : Directory.systemTemp;
  await File('${folder.path}/image-interaction-$name.png').writeAsBytes(png);
}

/// Run the same pointer/export regressions on the real Android/Windows view.
void registerImageGestureTests({bool onDevice = false}) {
  testWidgets('framing pans and pinches inside a scrolling page', (
    tester,
  ) async {
    final bytes = coordinateImage(180, 90);
    final image = (await tester.runAsync<ui.Image>(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      return image;
    }))!;
    var frame = const ImageFrame();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Center(
                child: SizedBox(
                  width: 280,
                  child: StatefulBuilder(
                    builder: (context, update) => ImageFramingPreview(
                      image: image,
                      value: frame,
                      grid: true,
                      onChanged: (value) => update(() => frame = value),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final target = find.byType(ImageFramingPreview);
    await dragObject(tester, tester.getCenter(target), const Offset(70, 0));
    expect(frame.x, lessThan(.5));
    await pinch(tester, tester.getRect(target));
    expect(frame.zoom, greaterThan(1.5));
    final previousY = frame.y;
    await dragObject(tester, tester.getCenter(target), const Offset(0, -80));
    expect(frame.y, greaterThan(previousY));
    final crop = imageCrop(180, 90, 280, 280, frame, grid: true);
    expect(crop.top + crop.height, lessThanOrEqualTo(90));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    image.dispose();
  });

  testWidgets(
    'poster text drag changes transparent export and custom emoji survives',
    (tester) async {
      final app = await testAppState();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundaryKey,
            child: PosterPage(
              tool: tools.firstWhere((t) => t.id == 'B04'),
              state: app,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(PosterPage));
      state.change(() {
        state.transparent = true;
        state.text.text = 'SaiSuite';
      });
      await tester.pump();
      final before = img.decodePng(
        (await tester.runAsync<Uint8List>(
          () => state.renderPng() as Future<Uint8List>,
        ))!,
      )!;
      final target = find.byKey(const ValueKey('poster-canvas'));
      final bounds = tester.getRect(target);
      final oldPosition = state.position as Offset;
      await dragObject(
        tester,
        bounds.topLeft + Offset(bounds.width * .5, bounds.height * .65),
        const Offset(45, -35),
      );
      expect((state.position as Offset).dx, greaterThan(oldPosition.dx));
      expect((state.position as Offset).dy, lessThan(oldPosition.dy));
      final after = img.decodePng(
        (await tester.runAsync<Uint8List>(
          () => state.renderPng() as Future<Uint8List>,
        ))!,
      )!;
      final delta = inkCenter(after) - inkCenter(before);
      expect(delta.dx, greaterThan(60));
      expect(delta.dy, lessThan(-40));
      expect(
        after.getPixel(0, 0).a,
        0,
        reason: 'checkerboard and selection handles must not export',
      );
      final input = find.byKey(const ValueKey('poster-custom-sticker'));
      await reveal(tester, input);
      await tester.enterText(input, '👩🏽‍🔬🫶');
      FocusManager.instance.primaryFocus?.unfocus();
      final add = find.text('添加自定义贴纸');
      await reveal(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(state.stickers.single.text, '👩🏽‍🔬🫶');
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final sticker = state.stickers.single;
      final oldSticker = sticker.position as Offset;
      final rect = tester.getRect(target);
      await dragObject(
        tester,
        rect.topLeft +
            Offset(rect.width * oldSticker.dx, rect.height * oldSticker.dy),
        const Offset(-40, 30),
      );
      expect((sticker.position as Offset).dx, lessThan(oldSticker.dx));
      expect((sticker.position as Offset).dy, greaterThan(oldSticker.dy));
      if (onDevice) {
        // A retained Unicode string can still draw a missing glyph. Check
        // colored pixels of this newer emoji separately from the ZWJ one.
        final originalEmoji = sticker.text as String;
        state.change(() => sticker.text = '🫶');
        final exported = img.decodePng(
          (await tester.runAsync<Uint8List>(
            () => state.renderPng() as Future<Uint8List>,
          ))!,
        )!;
        final colored = exported
            .where(
              (p) => p.a > 128 && (p.r - p.g).abs() + (p.g - p.b).abs() > 60,
            )
            .length;
        expect(
          colored,
          greaterThan(200),
          reason: 'new emoji must render, not a missing box or blank glyph',
        );
        state.change(() => sticker.text = originalEmoji);
        await tester.pumpAndSettle();
        await captureView(boundaryKey, 'poster');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'landscape photo keeps its ratio and exported crop follows gesture',
    (tester) async {
      final app = await testAppState();
      final folder = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('saisuite-image-'),
      ))!;
      final path = File('${folder.path}/landscape.png');
      final original = coordinateImage(160, 80);
      await tester.runAsync(() => path.writeAsBytes(original));
      await tester.pumpWidget(
        MaterialApp(
          home: PosterPage(
            tool: tools.firstWhere((t) => t.id == 'B04'),
            state: app,
          ),
        ),
      );
      final dynamic state = tester.state(find.byType(PosterPage));
      await tester.runAsync(() => state.loadPhoto(path.path) as Future<void>);
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('poster-canvas'));
      expect(tester.getSize(target).aspectRatio, closeTo(2, .001));
      state.change(() {
        state.text.clear();
        state.width.text = '80';
        state.height.text = '80';
      });
      await tester.pump();
      await pinch(tester, tester.getRect(target));
      expect((state.photoFrame as ImageFrame).zoom, greaterThan(1.5));
      await dragObject(tester, tester.getCenter(target), const Offset(-70, 0));
      final frame = state.photoFrame as ImageFrame;
      expect(frame.x, greaterThan(.5));
      final output = img.decodePng(
        (await tester.runAsync<Uint8List>(
          () => state.renderPng() as Future<Uint8List>,
        ))!,
      )!;
      final crop = imageCrop(160, 80, 80, 80, frame);
      expect(output.width, 80);
      expect(output.height, 80);
      expect(output.getPixel(40, 40).r, closeTo(crop.left + crop.width / 2, 2));
      expect(output.getPixel(40, 40).g, closeTo(crop.top + crop.height / 2, 2));
      expect(await tester.runAsync(() => path.readAsBytes()), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await releaseFixture(tester, path, folder);
      app.dispose();
    },
  );

  testWidgets('calculator label stays above the right aligned input', (
    tester,
  ) async {
    final app = await testAppState();
    final boundaryKey = GlobalKey();
    if (!onDevice) await tester.binding.setSurfaceSize(const Size(320, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: ToolPage(
            tool: tools.firstWhere((t) => t.id == 'C01'),
            state: app,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = find.byKey(const ValueKey('calculator-expression-label'));
    final input = find.byKey(const ValueKey('calculator-expression-input'));
    final first = tester.getRect(label);
    final field = tester.getRect(input);
    expect(first.bottom, lessThan(field.top));
    expect(first.right, closeTo(field.right, 1));
    await tester.enterText(input, 'sin(30)+2^3');
    await tester.pump();
    expect(tester.getRect(label), first);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (onDevice) await captureView(boundaryKey, 'calculator');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    if (!onDevice) await tester.binding.setSurfaceSize(null);
    app.dispose();
  });
  testWidgets('nine grid page exports the crop manipulated in its preview', (
    tester,
  ) async {
    final app = await testAppState();
    final boundaryKey = GlobalKey();
    final folder = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('saisuite-grid-'),
    ))!;
    final source = File('${folder.path}/portrait.png');
    final original = coordinateImage(90, 180);
    await tester.runAsync(() => source.writeAsBytes(original));
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: ImageStudioPage(
            tool: tools.firstWhere((t) => t.id == 'B02'),
            state: app,
          ),
        ),
      ),
    );
    final dynamic state = tester.state(find.byType(ImageStudioPage));
    final dynamic loaded = await tester.runAsync(
      () => state.loadFraming(source.path) as Future<dynamic>,
    );
    await tester.runAsync(
      () => precacheImage(
        ResizeImage(FileImage(source), width: 160),
        tester.element(find.byType(ImageStudioPage)),
      ),
    );
    state.invalidate(() {
      state.source = source.path;
      state.framingImage = loaded.image;
      state.framingSize = loaded.size;
    });
    await tester.pumpAndSettle();
    final target = find.byType(ImageFramingPreview);
    await reveal(tester, target);
    await pinch(tester, tester.getRect(target));
    await dragObject(tester, tester.getCenter(target), const Offset(0, -65));
    final framing = state.framing as ImageFrame;
    expect(framing.y, greaterThan(.5));
    await tester.runAsync(() => state.generate() as Future<void>);
    await tester.pumpAndSettle();
    expect(state.error, isEmpty);
    final files = ZipDecoder().decodeBytes(state.output as Uint8List).files;
    final first = img.decodePng(Uint8List.fromList(files.first.content))!;
    final crop = imageCrop(90, 180, 1, 1, framing, grid: true);
    expect(first.width, crop.width / 3);
    expect(first.getPixel(0, 0).r, crop.left);
    expect(first.getPixel(0, 0).g, crop.top);
    expect(await tester.runAsync(() => source.readAsBytes()), original);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (onDevice) await captureView(boundaryKey, 'grid');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await releaseFixture(tester, source, folder);
    app.dispose();
  });
}

void main() {
  registerImageGestureTests();
  test('merged tool shortcuts migrate without duplicates or losing other preferences', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': ['C01', 'B05', 'B04'],
      'recent': ['B05', 'U01', 'B04'],
      'autoCheckUpdates': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(prefs);
    expect(state.favorites, ['C01', 'B04']);
    expect(state.recent, ['B04', 'U01']);
    await state.migrateRetiredTools();
    expect(prefs.getStringList('favorites'), ['C01', 'B04']);
    expect(prefs.getBool('autoCheckUpdates'), false);
    expect(tools.where((t) => t.id == 'B05'), isEmpty);
    expect(tools.firstWhere((t) => t.id == 'B04').matches('文字转图'), isTrue);
    state.dispose();
  });
  test(
    'landscape and portrait nine grids export the selected pixels in order',
    () {
      for (final example in [
        (90, 60, .9, .1, 60, 0),
        (60, 90, .1, .9, 0, 60),
      ]) {
        final original = coordinateImage(example.$1, example.$2);
        final result = creativeImageJob({
          'action': 'grid',
          'bytes': original,
          'frame': ImageFrame(zoom: 2, x: example.$3, y: example.$4).toMap(),
        });
        final files = ZipDecoder()
            .decodeBytes(result['bytes'] as Uint8List)
            .files;
        expect(files.length, 9);
        for (var i = 0; i < 9; i++) {
          final tile = img.decodePng(Uint8List.fromList(files[i].content))!;
          expect(tile.width, 10);
          expect(tile.height, 10);
          expect(tile.getPixel(0, 0).r, example.$5 + i % 3 * 10);
          expect(tile.getPixel(9, 9).g, example.$6 + i ~/ 3 * 10 + 9);
        }
        final preview = img.decodePng(result['preview'] as Uint8List)!;
        expect(preview.width, 30);
        expect(preview.getPixel(0, 0).r, example.$5);
        expect(preview.getPixel(29, 29).g, example.$6 + 29);
      }
    },
  );
  test(
    'GIF individual frame crop selects the right side without stretching',
    () {
      final image = img.Image(width: 128, height: 64);
      for (final p in image) {
        p
          ..r = p.x < 64 ? 255 : 0
          ..g = 0
          ..b = p.x < 64 ? 0 : 255;
      }
      final result = creativeImageJob({
        'action': 'gifMake',
        'images': [img.encodePng(image), img.encodePng(image)],
        'frames': [
          const ImageFrame(x: .75).toMap(),
          const ImageFrame(x: .25).toMap(),
        ],
        'durations': [100, 300],
        'edge': 64,
        'loop': true,
      });
      final gif = img.decodeGif(result['bytes'] as Uint8List)!;
      expect(gif.frames[0].getPixel(5, 32).b, greaterThan(240));
      expect(gif.frames[1].getPixel(58, 32).r, greaterThan(240));
      expect(gif.frames[1].frameDuration, 300);
    },
  );
  testWidgets('loaded GIF frames have usable controls on a narrow screen', (
    tester,
  ) async {
    final app = await testAppState();
    await tester.binding.setSurfaceSize(const Size(320, 800));
    final folder = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('saisuite-gif-'),
    ))!;
    final path = File('${folder.path}/frame.png');
    await tester.runAsync(() => path.writeAsBytes(coordinateImage(160, 80)));
    await tester.pumpWidget(
      MaterialApp(
        home: ImageStudioPage(
          tool: tools.firstWhere((t) => t.id == 'B03'),
          state: app,
        ),
      ),
    );
    final dynamic state = tester.state(find.byType(ImageStudioPage));
    await tester.runAsync(
      () => precacheImage(
        ResizeImage(FileImage(path), width: 100),
        tester.element(find.byType(ImageStudioPage)),
      ),
    );
    state.invalidate(() {
      state.images.add(path.path);
      state.durations.add(100);
      state.frames.add(null);
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('调整帧画面'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextFormField)).width, greaterThan(100));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
    await releaseFixture(tester, path, folder);
    app.dispose();
  });
}
