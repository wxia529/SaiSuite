import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/app/sai_app.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/tool_page.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tzdata.initializeTimeZones();
  });
  test('favorites, recent, theme and calculator history persist', () async {
    final prefs = await SharedPreferences.getInstance(),
        state = AppState(prefs);
    await state.star('C01');
    await state.star('S01');
    await state.reorder(0, 1);
    await state.visit('S01');
    await state.visit('C01');
    await state.visit('S01');
    await state.setTheme(ThemeMode.dark);
    await state.rememberCalculation('1+1', '2');
    final reload = AppState(prefs);
    expect(reload.favorites, ['S01', 'C01']);
    expect(reload.recent, ['S01', 'C01']);
    expect(reload.theme, ThemeMode.dark);
    expect(reload.calculatorHistory.length, 1);
    await reload.clearHistory();
    expect(reload.favorites.length, 2);
    expect(reload.recent, isEmpty);
    expect(reload.calculatorHistory, isEmpty);
  });
  testWidgets('search alias finds PDF merge and favorite updates', (
    tester,
  ) async {
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(SaiApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '拼 PDF');
    await tester.pumpAndSettle();
    expect(find.text('PDF 合并'), findsOneWidget);
    await tester.tap(find.byTooltip('收藏 PDF 合并'));
    await tester.pumpAndSettle();
    expect(state.favorites, ['P01']);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('home has no overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        SaiApp(state: AppState(await SharedPreferences.getInstance())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('calculator runs and invalid input produces feedback', (
    tester,
  ) async {
    final state = AppState(await SharedPreferences.getInstance());
    final tool = tools.firstWhere((t) => t.id == 'C01');
    await tester.pumpWidget(
      MaterialApp(
        home: ToolPage(tool: tool, state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('计算 / 处理'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('计算 / 处理'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('8.5'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('8.5'), findsOneWidget);
    expect(state.calculatorHistory.length, 1);
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField).first, '1/0');
    await tester.scrollUntilVisible(
      find.text('计算 / 处理'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('计算 / 处理'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('不能除以零'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('不能除以零'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'long electrochemistry form works with narrow screen and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ToolPage(
            tool: tools.firstWhere((t) => t.id == 'EC04'),
            state: AppState(await SharedPreferences.getInstance()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('计算 / 处理'));
      await tester.tap(find.text('计算 / 处理'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('结果'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('oversized QR content shows error and removes stale result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ToolPage(
          tool: tools.firstWhere((t) => t.id == 'C06'),
          state: AppState(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('计算 / 处理'));
    await tester.tap(find.text('计算 / 处理'));
    await tester.pumpAndSettle();
    expect(find.text('结果'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'a' * 3500);
    await tester.ensureVisible(find.text('计算 / 处理'));
    await tester.tap(find.text('计算 / 处理'));
    await tester.pumpAndSettle();
    expect(find.textContaining('内容超过二维码容量'), findsOneWidget);
    expect(find.text('结果'), findsNothing);
  });
}
