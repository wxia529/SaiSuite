import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/core/palette.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/tool_page.dart';
import 'package:saisuite/features/palette_page.dart';
import 'package:saisuite/features/pomodoro_page.dart';
import 'package:saisuite/features/drawing_page.dart';
import 'package:saisuite/features/analysis_page.dart';

void main() {
  test(
    'analysis worker honors the header flag for cycles and lithium data',
    () {
      final cycle = analyzeData({
        'text': 'A,1,1,.9\nA,2,1,.8',
        'delimiter': ',',
        'hasHeader': false,
        'columns': {'样品': 0, '循环': 1, '充电/沉积容量': 2, '放电/剥离容量': 3},
        'mode': '循环汇总',
        'baseline': 1,
        'first': 1,
        'compare': 2,
      });
      expect(cycle.csv, contains('"A",1,1,0.9,90,100'));
      final lithium = analyzeData({
        'text': 'A,1,1,0,.1\nA,1,1,10,.05',
        'delimiter': ',',
        'hasHeader': false,
        'columns': {'样品': 0, '循环': 1, '步骤': 2, '时间': 3, '电压': 4},
        'mode': 'Li‖Li极化',
        'exclude': 0.0,
      });
      expect(lithium.curves.first.points.first.$2, closeTo(.075, 1e-12));
      expect(
        parseData({'text': '1,1,.9', 'delimiter': ',', 'hasHeader': false})
            .rows
            .length,
        1,
      );
    },
  );
  for (final id in ['N06', 'N07']) {
    testWidgets(
      '$id header switch keeps source text and changes the import mode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          MaterialApp(
            home: AnalysisPage(
              tool: tools.firstWhere((t) => t.id == id),
              state: AppState(prefs),
            ),
          ),
        );
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );
        final input = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '表头与数据',
        );
        await tester.enterText(input, 'A,1,1,.9\nA,2,1,.8');
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse,
        );
        final noHeader = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '数据（无表头）',
        );
        expect(
          tester.widget<TextField>(noHeader).controller!.text,
          'A,1,1,.9\nA,2,1,.8',
        );
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );
        expect(prefs.getKeys(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('lab calculation does not persist inputs and warns before exit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ToolPage(
                    tool: tools.firstWhere((t) => t.id == 'N05'),
                    state: state,
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('计算 / 处理').hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('计算 / 处理'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('结果'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('结果'), findsOneWidget);
    expect(state.prefs.getKeys(), isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('结果尚未导出'), findsOneWidget);
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(state.prefs.getKeys(), isEmpty);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('palette wraps hues and contrast follows luminance', () {
    expect(
      hexColor(colorPalette(const Color(0xffff0000), '互补色').last),
      '#00FFFF',
    );
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 1e-8));
    expect(contrastRatio(Colors.red, Colors.red), 1);
    expect(() => parseHex('#xyzxyz'), throwsFormatException);
  });
  testWidgets('keypad evaluates and edits a selected expression', (
    tester,
  ) async {
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: ToolPage(
          tool: tools.firstWhere((t) => t.id == 'C01'),
          state: state,
        ),
      ),
    );
    await tester.tap(find.text('AC'));
    await tester.pump();
    for (final key in ['7', '×', '6', '=']) {
      await tester.ensureVisible(find.text(key));
      await tester.tap(find.text(key));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.text('42'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('42'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    final field = tester.widget<TextField>(find.byType(TextField).first);
    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 1,
    );
    await tester.ensureVisible(find.text('9'));
    await tester.tap(find.text('9'));
    await tester.pump();
    expect(field.controller!.text, '9*6');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('⌫').hitTestable(),
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    field.controller!.selection = const TextSelection.collapsed(offset: 1);
    await tester.tap(find.text('⌫'));
    await tester.pump();
    expect(field.controller!.text, '*6');
    expect(tester.takeException(), isNull);
  });
  testWidgets('palette accepts RGB input and rejects out of range values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PalettePage(
          tool: tools.firstWhere((t) => t.id == 'A01'),
          state: AppState(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('HEX').hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('HEX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RGB').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '255,0,0');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('#FF0000').hitTestable(),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('#FF0000'), findsOneWidget);
    expect(find.text('#00FFFF'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(TextField).hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), '256,0,0');
    await tester.pump();
    expect(find.text('RGB 范围为 0—255'), findsOneWidget);
  });
  testWidgets('timer restores deadline and pause cancels background reminder', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('saisuite/device'),
      (call) async {
        calls.add(call.method);
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('saisuite/device'),
        null,
      ),
    );
    SharedPreferences.setMockInitialValues({
      'pom_deadline': DateTime.now().millisecondsSinceEpoch + 65000,
      'pom_phase': '专注',
      'pom_round': 2,
    });
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: PomodoroPage(
          tool: tools.firstWhere((t) => t.id == 'A03'),
          state: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('专注 · 第 2 轮'), findsOneWidget);
    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();
    expect(calls, contains('timerCancel'));
    expect(state.prefs.getInt('pom_deadline'), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('canvas keeps vertical strokes instead of scrolling the page', (
    tester,
  ) async {
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
    await tester.ensureVisible(canvas);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(canvas);
    final gesture = await tester.startGesture(tester.getCenter(canvas));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -120));
    await gesture.up();
    await tester.pumpAndSettle();
    final painter =
        tester.widget<CustomPaint>(canvas).painter! as DrawingPainter;
    expect(painter.strokes.length, 1);
    expect(painter.strokes.first.points.length, greaterThanOrEqualTo(3));
    expect(
      painter.strokes.first.points.last.dy,
      lessThan(painter.strokes.first.points.first.dy),
    );
    expect(tester.getTopLeft(canvas), before);
    expect(tester.takeException(), isNull);
  });
  test('drawing renders strokes and eraser into exported pixels', () async {
    final recorder = ui.PictureRecorder();
    DrawingPainter([
      DrawingStroke(const Color(0xffff0000), 10, false, [const Offset(10, 10)]),
      DrawingStroke(Colors.black, 2, true, [const Offset(10, 10)]),
    ]).paint(Canvas(recorder), const Size(20, 20));
    final picture = recorder.endRecording(),
        image = await picture.toImage(20, 20);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    expect(bytes[(10 * 20 + 10) * 4 + 1], greaterThan(180));
    expect(bytes[(10 * 20 + 13) * 4], 255);
    expect(bytes[(10 * 20 + 13) * 4 + 1], 0);
    image.dispose();
    picture.dispose();
  });
}
