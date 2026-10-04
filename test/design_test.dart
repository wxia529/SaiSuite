import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/core/engine.dart';
import 'package:saisuite/core/palette.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/drawing_page.dart';
import 'package:saisuite/features/image_tools_hub.dart';
import 'package:saisuite/features/image_editor_page.dart';
import 'package:saisuite/features/media_page.dart';
import 'package:saisuite/features/collage_page.dart';
import 'package:saisuite/features/palette_page.dart';
import 'package:saisuite/features/pdf_page.dart';
import 'package:saisuite/features/image_picker_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'boundary spacing preserves unrelated spaces, indentation and newlines',
    () {
      expect(
        removeCjkBoundarySpaces('  中文 A 中文 3 中文\nHello world 12 34 中 文  '),
        '  中文A中文3中文\nHello world 12 34中 文  ',
      );
      expect(removeCjkBoundarySpaces('Ａ　中文\t２ 中文\nA\n中文'), 'Ａ中文２中文\nA\n中文');
      expect(removeCjkBoundarySpaces('中  A  中  1  中'), '中A中1中');
      expect(removeCjkBoundarySpaces('𠀀 A 𠀀 2'), '𠀀A𠀀2');
      expect(runTool('T09', {'文本': '中文 ABC 123 中文'}), '中文ABC 123中文');
    },
  );
  test('catalog keeps password at 14 and all lab tools in one category', () {
    expect(tools.firstWhere((t) => t.id == 'C05').defaults['长度'], '14');
    expect(categories.where((c) => c == '科研').length, 1);
    expect(categories, isNot(contains('电化学')));
    expect(
      tools
          .where((t) => t.id.startsWith('EC') || t.id.startsWith('N'))
          .every((t) => t.category == '科研'),
      isTrue,
    );
  });
  test('five color presets and random palettes have usable opaque colors', () {
    expect(palettePresets.length, 12);
    expect(palettePresets.every((p) => p.colors.length == 5), isTrue);
    final random = math.Random(12);
    final first = randomPalette(random), second = randomPalette(random);
    expect(first.colors.length, 5);
    expect(first.colors.every((c) => c.a == 1), isTrue);
    expect(
      first.colors.map(hexColor).toList(),
      isNot(second.colors.map(hexColor).toList()),
    );
    for (final style in paletteStyles) {
      expect(designPalette(const Color(0xff147d73), style).length, 5);
    }
  });
  for (final size in [const Size(320, 700), const Size(844, 390)]) {
    testWidgets('drawing fullscreen preserves strokes at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingPage(
            tool: tools.firstWhere((t) => t.id == 'A04'),
            state: AppState(await SharedPreferences.getInstance()),
          ),
        ),
      );
      final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is DrawingPainter,
      );
      await tester.tap(find.byTooltip('全屏画板'));
      await tester.pumpAndSettle();
      await tester.tap(canvas);
      await tester.pump();
      final stroke =
          (tester.widget<CustomPaint>(canvas).painter! as DrawingPainter)
              .strokes
              .single;
      final original = List<Offset>.of(stroke.points);
      await tester.tap(find.byTooltip('退出全屏'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('全屏画板'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      expect(
        (tester.widget<CustomPaint>(canvas).painter! as DrawingPainter)
            .strokes
            .single
            .points,
        original,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byTooltip('全屏画板'), findsOneWidget);
      await tester.tap(find.byTooltip('全屏画板'));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<CustomPaint>(canvas).painter! as DrawingPainter)
            .strokes
            .single
            .points,
        original,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('image hub separates single-image actions from collage', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('saisuite/media'),
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('saisuite/media'),
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImageToolsHub(
          tool: tools.firstWhere((t) => t.id == 'A09'),
          state: AppState(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('图片编辑').hitTestable(),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('图片编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageEditorPage), findsOneWidget);
    expect(find.text('选择图片开始编辑'), findsOneWidget);
    expect(find.text('拼图排列'), findsNothing);
    expect(find.text('裁剪 X%'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('尺寸与格式').hitTestable(),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('尺寸与格式'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MediaPage>(find.byType(MediaPage)).imageAction,
      ImageAction.resize,
    );
    expect(find.text('选择一张图片'), findsOneWidget);
    expect(find.text('裁剪 X%'), findsNothing);
    expect(find.text('拼图排列'), findsNothing);
    expect(find.text('文字水印'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('图片拼图').hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('图片拼图'));
    await tester.pumpAndSettle();
    expect(find.byType(CollagePage), findsOneWidget);
    expect(find.text('选择 2—9 张图片'), findsOneWidget);
    expect(find.text('裁剪 X%'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
    'palette random button changes the seed and remains narrow-screen safe',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: PalettePage(
            tool: tools.firstWhere((t) => t.id == 'A01'),
            state: AppState(await SharedPreferences.getInstance()),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('random-palette')));
      await tester.pump();
      expect(find.text('随机灵感'), findsNWidgets(2));
      await tester.scrollUntilVisible(
        find.byType(TextField).hitTestable(),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isNot('#147D73'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'PDF watermark shows one content type and collapses style settings',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: PdfPage(
            tool: tools.firstWhere((t) => t.id == 'P08'),
            state: AppState(await SharedPreferences.getInstance()),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('文字').hitTestable(),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('选择水印图片'), findsNothing);
      await tester.tap(find.text('图片'));
      await tester.pumpAndSettle();
      expect(find.text('选择水印图片'), findsOneWidget);
      expect(find.text('水印文字'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      await tester.scrollUntilVisible(
        find.text('位置与样式').hitTestable(),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('位置与样式'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  test('magnifier paints the selected original pixel at its center', () async {
    final source = ui.PictureRecorder();
    Canvas(source)
        .drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = Colors.red);
    final picture = source.endRecording();
    final image = await picture.toImage(4, 4);
    final recorder = ui.PictureRecorder();
    PickerOverlayPainter(
      image,
      Offset.zero,
      const Offset(40, 150),
      Colors.red,
    ).paint(Canvas(recorder), const Size(220, 360));
    final outputPicture = recorder.endRecording();
    final output = await outputPicture.toImage(220, 360);
    final bytes = (await output.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final index = (70 * 220 + 125) * 4;
    expect(bytes[index], 244);
    expect(bytes[index + 1], 67);
    expect(bytes[index + 2], 54);
    output.dispose();
    outputPicture.dispose();
    image.dispose();
    picture.dispose();
  });
}
