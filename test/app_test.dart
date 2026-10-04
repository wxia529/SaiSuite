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
  test(
    'upgrade removes retired shortcuts and keeps remaining settings and order',
    () async {
      SharedPreferences.setMockInitialValues({
        'favorites': ['N06', 'C01', 'EC21', 'P01', 'N02', 'N07'],
        'recent': ['N02', 'N01', 'N06', 'C01', 'EC21', 'N07'],
        'theme': ThemeMode.dark.index,
        'calculatorHistory': ['{"expression":"1+1","result":"2"}'],
        'pom_remaining': 57,
        'ruler_scale': 1.12,
      });
      final prefs = await SharedPreferences.getInstance(),
          state = AppState(prefs);
      expect(state.favorites, ['C01', 'P01']);
      expect(state.recent, ['N01', 'C01']);
      await state.migrateRetiredTools();
      expect(prefs.getStringList('favorites'), ['C01', 'P01']);
      expect(prefs.getStringList('recent'), ['N01', 'C01']);
      await state.reorder(0, 1);
      final reload = AppState(prefs);
      expect(reload.favorites, ['P01', 'C01']);
      expect(reload.theme, ThemeMode.dark);
      expect(reload.calculatorHistory, hasLength(1));
      expect(prefs.getInt('pom_remaining'), 57);
      expect(prefs.getDouble('ruler_scale'), 1.12);
      final keys = prefs.getKeys();
      await reload.migrateRetiredTools();
      expect(prefs.getKeys(), keys);
      expect(prefs.getStringList('favorites'), ['P01', 'C01']);
    },
  );
  testWidgets(
    'retired tools disappear from search and upgraded app shows 60 tools',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorites': ['N02', 'N06', 'N07', 'EC21'],
        'recent': ['N02', 'N06', 'N07', 'EC21'],
      });
      await tester.pumpWidget(
        SaiApp(state: AppState(await SharedPreferences.getInstance())),
      );
      await tester.pumpAndSettle();
      expect(find.text('浏览 ${tools.length} 个工具'), findsOneWidget);
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      for (final name in ['循环数据分析', '锂金属测试分析', '电流积分与容量', '梯度配方']) {
        await tester.enterText(find.byType(TextField), name);
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的工具，试试其他关键词'), findsOneWidget);
        expect(
          find.text(name),
          findsOneWidget,
        ); // Only the search input remains.
      }
      await tester.enterText(find.byType(TextField), '电解液配方');
      await tester.pumpAndSettle();
      expect(find.byTooltip('收藏 电解液配方'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
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
      find.text('=').hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('='));
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
      find.text('=').hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('='));
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
    await tester.ensureVisible(find.text('生成二维码'));
    await tester.tap(find.text('生成二维码'));
    await tester.pumpAndSettle();
    expect(find.text('结果'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'a' * 3500);
    await tester.ensureVisible(find.text('生成二维码'));
    await tester.tap(find.text('生成二维码'));
    await tester.pumpAndSettle();
    expect(find.textContaining('内容超过二维码容量'), findsOneWidget);
    expect(find.text('结果'), findsNothing);
  });
}
