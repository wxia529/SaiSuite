import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/core/compass.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/drawing_page.dart';
import 'package:saisuite/features/media_page.dart';
import 'package:saisuite/features/pomodoro_page.dart';
import 'package:saisuite/features/sensor_page.dart';
import 'package:saisuite/features/tool_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppState> state() async =>
      AppState(await SharedPreferences.getInstance());
  test('compass crosses north by the shortest path in both directions', () {
    expect(unwrapHeading(359, 1), 361);
    expect(unwrapHeading(1, 359), -1);
    expect(unwrapHeading(721, 359), 719);
    expect(compassDirection(359), '北');
    expect(compassDirection(-90), '西');
    expect(compassDirection(405), '东北');
  });
  for (final size in [const Size(320, 700), const Size(844, 390)]) {
    for (final id in ['C01', 'C02', 'C04', 'C06', 'A03', 'A10']) {
      testWidgets('$id studio fits $size', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('saisuite/device'),
          (_) async => false,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('saisuite/media'),
          (_) async => null,
        );
        final appState = await state(),
            tool = tools.firstWhere((t) => t.id == id);
        final page = id == 'A03'
            ? PomodoroPage(tool: tool, state: appState)
            : id == 'A10'
            ? MediaPage(tool: tool, state: appState)
            : ToolPage(tool: tool, state: appState);
        await tester.pumpWidget(MaterialApp(home: page));
        await tester.pumpAndSettle();
        if (id == 'C06') {
          await tester.scrollUntilVisible(
            find.text('生成二维码').hitTestable(),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('生成二维码'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(QrImageView));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'unit category filters compatible units and swap preserves amount',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ToolPage(
            tool: tools.firstWhere((t) => t.id == 'C02'),
            state: await state(),
          ),
        ),
      );
      await tester.tap(find.text('长度'));
      await tester.pumpAndSettle();
      final amount = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '数值',
      );
      await tester.enterText(amount, '2');
      final dropdowns = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      final options = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .first
          .items!
          .map((i) => i.value)
          .toList();
      expect(options, contains('m'));
      expect(options, isNot(contains('°C')));
      final source = dropdowns.first.initialValue,
          target = dropdowns.last.initialValue;
      await tester.tap(find.byTooltip('交换单位'));
      await tester.pumpAndSettle();
      final swapped = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      expect(swapped.first.initialValue, target);
      expect(swapped.last.initialValue, source);
      expect(tester.widget<TextField>(amount).controller!.text, '2');
      await tester.tap(find.text('换算'));
      await tester.pumpAndSettle();
      expect(find.text('结果'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('random, QR and video modes expose only relevant inputs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appState = await state();
    Future<void> open(String id) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: ToolPage(
            tool: tools.firstWhere((t) => t.id == id),
            state: appState,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder input(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await open('C04');
    expect(input('选项'), findsOneWidget);
    expect(input('最小值'), findsNothing);
    await tester.tap(find.text('随机整数'));
    await tester.pumpAndSettle();
    expect(input('选项'), findsNothing);
    expect(input('最小值'), findsOneWidget);
    await open('C06');
    expect(input('内容'), findsOneWidget);
    expect(input('SSID'), findsNothing);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    expect(input('内容'), findsNothing);
    expect(input('SSID'), findsOneWidget);
    expect(input('密码'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('saisuite/media'),
      (_) async => null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaPage(
          tool: tools.firstWhere((t) => t.id == 'A10'),
          state: appState,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(input('开始时间 s'), findsOneWidget);
    expect(input('截帧时间 s'), findsNothing);
    await tester.tap(find.text('截取画面'));
    await tester.pumpAndSettle();
    expect(input('开始时间 s'), findsNothing);
    expect(input('截帧时间 s'), findsOneWidget);
    expect(find.text('画质与声音'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('changing Wi-Fi visibility clears the generated QR payload', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ToolPage(
          tool: tools.firstWhere((t) => t.id == 'C06'),
          state: await state(),
        ),
      ),
    );
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'SSID',
      ),
      'Lab',
    );
    await tester.tap(find.text('生成二维码'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    await tester.tap(find.text('隐藏网络'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    await tester.tap(find.text('生成二维码'));
    await tester.pumpAndSettle();
    expect(find.textContaining('H:true'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('portrait drawing area fills the available height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingPage(
          tool: tools.firstWhere((t) => t.id == 'A04'),
          state: await state(),
        ),
      ),
    );
    final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DrawingPainter,
    );
    expect(tester.getSize(canvas).height, greaterThan(600));
    expect(tester.getSize(canvas).width, greaterThan(380));
    await tester.dragFrom(
      tester.getBottomLeft(canvas) + const Offset(30, -80),
      const Offset(80, 40),
    );
    await tester.pump();
    final painter =
        tester.widget<CustomPaint>(canvas).painter! as DrawingPainter;
    expect(painter.strokes.single.points.last.dy, greaterThan(900));
    await tester.tap(find.byTooltip('撤销'));
    await tester.pump();
    expect(painter.strokes, isEmpty);
    await tester.tap(find.byTooltip('重做'));
    await tester.pump();
    expect(painter.strokes, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'compass animation follows wraparound samples and cancels its stream',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const codec = StandardMethodCodec();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('saisuite/device'),
        (_) async => [
          {'type': 2, 'available': true},
          {'type': 11, 'available': true},
        ],
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('saisuite/sensors'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SensorPage(
            tool: tools.firstWhere((t) => t.id == 'A05'),
            state: await state(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.first.arguments, {'mode': 'compass'});
      Future<void> sample(double heading) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'saisuite/sensors',
          codec.encodeSuccessEnvelope({
            'azimuth': heading,
            'accuracy': {'2': 3},
          }),
          (_) {},
        );
        await tester.pump();
      }

      await sample(359);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.textContaining('359°'), findsOneWidget);
      await sample(1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('000°'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('001°'), findsOneWidget);
      await sample(1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(calls.last.method, 'cancel');
    },
  );
}
