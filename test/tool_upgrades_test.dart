import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/core/dominant_colors.dart';
import 'package:saisuite/core/electrolyte.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/collage_page.dart';
import 'package:saisuite/features/drawing_page.dart';
import 'package:saisuite/features/electrolyte_page.dart';
import 'package:saisuite/features/palette_page.dart';
import 'package:saisuite/features/pdf_preview.dart';
import 'package:saisuite/features/pdf_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppState> state() async =>
      AppState(await SharedPreferences.getInstance());
  ToolSpec tool(String id) => tools.firstWhere((t) => t.id == id);
  testWidgets(
    'image-size PDF mode hides paper margins and restores A4 controls',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        MaterialApp(
          home: PdfPage(tool: tool('P06'), state: await state()),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('A4').hitTestable(),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('A4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按图片尺寸').last);
      await tester.pumpAndSettle();
      expect(find.text('横向纸张'), findsNothing);
      expect(find.text('边距 mm'), findsNothing);
      expect(find.textContaining('1 像素对应 1 PDF 点'), findsOneWidget);
      await tester.tap(find.text('按图片尺寸'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A4').last);
      await tester.pumpAndSettle();
      expect(find.text('横向纸张'), findsOneWidget);
      expect(find.text('边距 mm'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );
  test('formulations reject overflowing mass ratios and weighing totals', () {
    final p = tool('N01').defaults;
    p['溶剂：名称,质量比'] = 'EC,1e308\nDEC,1e308';
    expect(() => electrolyteRecipe(p), throwsFormatException);
    p['实际溶剂：名称,质量g'] = 'EC,1e308\nDEC,1e308';
    expect(() => reverseRecipe(p), throwsFormatException);
  });
  test('dominant extraction ignores alpha, merges nearby colors and ranks by frequency', () {
    final bytes = Uint8List.fromList([
      for (var i = 0; i < 300; i++) ...[255, 0, 0, 255],
      for (var i = 0; i < 100; i++) ...[0, 0, 255, 255],
      for (var i = 0; i < 1000; i++) ...[0, 255, 0, 0],
    ]);
    expect(dominantColors(bytes), [0xffff0000, 0xff0000ff]);
    expect(dominantColors(Uint8List(16)), isEmpty);
  });
  test('collage geometry retains long image aspect and respects margins', () {
    final rects = collageRects([2, .5], '长图拼接', 1000, 20, 10);
    expect(rects[0], const Rect.fromLTWH(10, 10, 980, 490));
    expect(rects[1], const Rect.fromLTWH(10, 520, 980, 1960));
    expect(collageRects([1, 1, 1], '双列', 1000, 20, 10).last.top, 510);
  });
  test(
    'transparent drawing genuinely erases alpha and undo restores ink',
    () async {
      final stroke = DrawingStroke(Colors.red, 10, false, [
        const Offset(10, 10),
      ]);
      final eraser = DrawingStroke(Colors.black, 4, true, [
        const Offset(10, 10),
      ]);
      Future<int> alpha(List<DrawingStroke> strokes) async {
        final recorder = ui.PictureRecorder();
        DrawingPainter(
          strokes,
          transparent: true,
        ).paint(Canvas(recorder), const Size(20, 20));
        final picture = recorder.endRecording(),
            image = await picture.toImage(20, 20);
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .getUint8((10 * 20 + 10) * 4 + 3);
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      expect(await alpha([stroke, eraser]), 0);
      expect(await alpha([stroke]), 255);
    },
  );
  testWidgets(
    'electrolyte live results disappear for invalid input and modes hide unrelated fields',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ElectrolytePage(tool: tool('N01'), state: await state()),
        ),
      );
      TextField amount = tester.widget<TextField>(find.byType(TextField).first);
      expect(amount.controller!.text, '10');
      await tester.enterText(find.byType(TextField).first, '-1');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('检查输入后查看结果'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('实时称量结果'), findsNothing);
      expect(find.text('请检查标出的输入字段'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('目标配方').hitTestable(),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('目标配方'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('实际称量反算').last);
      await tester.pumpAndSettle();
      expect(find.text('目标量'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('实测最终体积 mL'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('实测最终体积 mL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('palette randomization preserves locked color and count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PalettePage(tool: tool('A01'), state: await state()),
      ),
    );
    final original = find.text('#147D73');
    await tester.scrollUntilVisible(
      find.byTooltip('锁定颜色 1').hitTestable(),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('锁定颜色 1'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('random-palette')).hitTestable(),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('random-palette')));
    await tester.pump();
    expect(original, findsOneWidget);
    await tester.tap(find.byTooltip('增加颜色'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('锁定颜色 6').hitTestable(),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byTooltip('锁定颜色 6'), findsOneWidget);
  });
  testWidgets('two-finger drawing gesture leaves no accidental ink', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingPage(tool: tool('A04'), state: await state()),
      ),
    );
    final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DrawingPainter,
    );
    final center = tester.getCenter(canvas);
    final a = await tester.startGesture(center, pointer: 1);
    await tester.pump();
    final b = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await tester.pump();
    await b.moveBy(const Offset(50, 0));
    await tester.pump();
    await b.moveBy(const Offset(30, 0));
    await tester.pump();
    await b.up();
    await a.up();
    await tester.pump();
    expect(
      (tester.widget<CustomPaint>(canvas).painter! as DrawingPainter).strokes,
      isEmpty,
    );
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'drawing text move can be undone without losing original placement',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingPage(tool: tool('A04'), state: await state()),
        ),
      );
      await tester.tap(find.byTooltip('添加文字'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is DrawingPainter,
      );
      DrawingPainter painter() =>
          tester.widget<CustomPaint>(canvas).painter! as DrawingPainter;
      final original = painter().strokes.single.points.first;
      final rect = tester.getRect(canvas), scale = rect.width / 900;
      final touch = rect.topLeft + original * scale + const Offset(5, 5);
      await tester.dragFrom(touch, const Offset(50, 20));
      await tester.pump();
      expect(painter().strokes, hasLength(2));
      expect(painter().strokes.last.points.first.dx, greaterThan(original.dx));
      await tester.tap(find.byTooltip('撤销'));
      await tester.pump();
      expect(painter().strokes.single.points.first, original);
      await tester.tap(find.byTooltip('重做'));
      await tester.pump();
      expect(painter().strokes, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'PDF page selection disallows empty export and preserves duplicate occurrences',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PdfPageGrid(
            pages: const [0, 0, 2],
            initialSelection: const {0, 1, 2},
            load: (p, dpi) => Future.error('fixture'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('反选'));
      await tester.pump();
      expect(find.text('已选 3/3 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
