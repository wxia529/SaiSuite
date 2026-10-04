import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/compass.dart';
import 'catalog.dart';
import 'workbench.dart';

class SensorPage extends StatefulWidget {
  const SensorPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  StreamSubscription<dynamic>? subscription;
  List<dynamic> inventory = [];
  Map data = {};
  double zeroX = 0, zeroY = 0;
  String? error;
  late final AnimationController headingAnimation;
  Tween<double> heading = Tween(begin: 0, end: 0);
  bool receivedHeading = false;
  bool get isCompass => widget.tool.id == 'A05';
  static const names = {
    1: '加速度 · m/s²',
    2: '磁场 · µT',
    4: '角速度 · rad/s',
    5: '照度 · lx',
    6: '气压 · hPa',
    9: '重力 · m/s²',
    11: '旋转向量 · 无量纲',
  };
  @override
  void initState() {
    super.initState();
    headingAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    try {
      final list = await const MethodChannel('saisuite/device')
          .invokeMethod<List<dynamic>>('sensors');
      if (mounted) {
        setState(() => inventory = list ?? []);
        listen();
      }
    } catch (e) {
      if (mounted) setState(() => error = '无法读取设备传感器：$e');
    }
  }

  void listen() {
    if (subscription != null) return;
    subscription = const EventChannel('saisuite/sensors')
        .receiveBroadcastStream({
          'mode': isCompass
              ? 'compass'
              : widget.tool.id == 'A06'
              ? 'level'
              : 'all',
        })
        .listen(
          (event) {
            if (!mounted) return;
            final next = event as Map;
            if (!isCompass) {
              setState(() => data = next);
              return;
            }
            final raw = (next['azimuth'] as num?)?.toDouble();
            final accuracyChanged =
                (data['accuracy'] as Map?)?['2'] !=
                (next['accuracy'] as Map?)?['2'];
            data = next;
            if (raw != null && raw.isFinite) {
              final current = heading.evaluate(headingAnimation);
              final target = receivedHeading
                  ? unwrapHeading(current, raw)
                  : raw;
              // Identical sensor samples must not keep the GPU animation alive.
              if (receivedHeading &&
                  !accuracyChanged &&
                  (target - heading.end!).abs() < .05) {
                return;
              }
              heading = Tween(
                begin: receivedHeading ? current : target,
                end: target,
              );
              if (!receivedHeading || accuracyChanged) {
                setState(() => receivedHeading = true);
              }
              headingAnimation.forward(from: 0);
            } else if (accuracyChanged) {
              setState(() {});
            }
          },
          onError: (Object e) {
            if (mounted) setState(() => error = '$e');
          },
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      listen();
    } else {
      subscription?.cancel();
      subscription = null;
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    headingAnimation.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool has(int type) =>
      inventory.any((s) => s['type'] == type && s['available'] == true);
  double? value(String key) => (data[key] as num?)?.toDouble();
  @override
  Widget build(BuildContext context) {
    final compass = widget.tool.id == 'A05', level = widget.tool.id == 'A06';
    final supported = compass
        ? has(2) && (has(11) || has(1))
        : level
        ? has(9) || has(1)
        : inventory.any((s) => s['available'] == true);
    final x = value('tiltX'), y = value('tiltY');
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      children: [
        if (error != null) Text(error!),
        if (inventory.isEmpty && error == null) const LinearProgressIndicator(),
        if (inventory.isNotEmpty && !supported)
          const Text('设备缺少此工具所需的传感器，无法测量。'),
        if (compass && supported) ...[
          Text(
            'MAGNETIC COMPASS',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          Text('找到你的方向', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: headingAnimation,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: CompassRosePainter(
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.onSurface,
                  Theme.of(context).colorScheme.surfaceContainerLow,
                ),
              ),
            ),
            builder: (context, face) {
              final angle = heading.evaluate(headingAnimation),
                  degrees = angle % 360;
              return Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Transform.rotate(
                              angle: -angle * math.pi / 180,
                              child: face,
                            ),
                            const IgnorePointer(
                              child: CustomPaint(
                                painter: CompassPointerPainter(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    receivedHeading
                        ? '${compassDirection(degrees)} · ${(degrees.round() % 360).toString().padLeft(3, '0')}°'
                        : '等待方向读数…',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(
                '磁场精度：${switch ((data['accuracy'] as Map?)?['2']) {
                  3 => '高',
                  2 => '中',
                  1 => '低，请校准',
                  _ => '未知或不可靠，请校准',
                }}',
              ),
              subtitle: const Text('可缓慢以“8”字形移动手机后重新观察。'),
            ),
          ),
          const SizedBox(height: 18),
          const Text('以磁北为参考。远离磁铁、电池夹具和金属干扰，读数不作为精密测量依据。'),
        ],
        if (level && supported) ...[
          const Text('将手机放在待测面上。归零以当前姿态为参考，测量精度受手机外壳与传感器影响。'),
          SizedBox(
            height: 250,
            child: CustomPaint(
              painter: LevelPainter(
                (x ?? 0) - zeroX,
                (y ?? 0) - zeroY,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Text(
            x == null || y == null
                ? '等待读数…'
                : 'X ${(x - zeroX).toStringAsFixed(2)}°   Y ${(y - zeroY).toStringAsFixed(2)}°',
            textAlign: TextAlign.center,
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: x == null
                    ? null
                    : () => setState(() {
                        zeroX = x;
                        zeroY = y ?? 0;
                      }),
                child: const Text('当前姿态归零'),
              ),
              OutlinedButton(
                onPressed: () => setState(() {
                  zeroX = 0;
                  zeroY = 0;
                }),
                child: const Text('重置校准'),
              ),
            ],
          ),
        ],
        if (!compass && !level) ...[
          const Text('显示设备实时读数，不保存采样记录。没有的传感器会标明不可用。'),
          ...inventory.map((sensor) {
            final type = sensor['type'] as int,
                raw = (data['values'] as Map?)?['$type'] as List?;
            return Card(
              child: ListTile(
                title: Text(names[type] ?? '传感器 $type'),
                subtitle: Text(
                  sensor['available'] != true
                      ? '设备未提供'
                      : '${sensor['name']}\n${raw == null ? '等待读数…' : raw.map((n) => (n as num).toStringAsFixed(3)).join('  ')}',
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class LevelPainter extends CustomPainter {
  LevelPainter(this.x, this.y, this.color);
  final double x, y;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2),
        radius = math.min(s.width, s.height) / 2 - 20;
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawCircle(center, radius, border);
    c.drawCircle(center, 22, border);
    c.drawLine(center - Offset(radius, 0), center + Offset(radius, 0), border);
    c.drawLine(center - Offset(0, radius), center + Offset(0, radius), border);
    final dx = x.clamp(-45, 45) / 45 * (radius - 20),
        dy = y.clamp(-45, 45) / 45 * (radius - 20);
    c.drawCircle(
      center + Offset(dx, -dy),
      16,
      Paint()..color = color.withValues(alpha: .7),
    );
  }

  @override
  bool shouldRepaint(LevelPainter old) =>
      old.x != x || old.y != y || old.color != color;
}

class CompassRosePainter extends CustomPainter {
  const CompassRosePainter(this.accent, this.foreground, this.surface);
  final Color accent, foreground, surface;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        radius = math.min(size.width, size.height) * .44;
    canvas.drawCircle(center, radius, Paint()..color = surface);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accent.withValues(alpha: .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      center,
      radius * .63,
      Paint()..color = accent.withValues(alpha: .07),
    );
    Offset at(double angle, double r) =>
        center + Offset(math.sin(angle) * r, -math.cos(angle) * r);
    for (int i = 0; i < 72; i++) {
      final major = i % 6 == 0, angle = i * math.pi / 36;
      canvas.drawLine(
        at(angle, radius * .96),
        at(angle, radius * (major ? .83 : .9)),
        Paint()
          ..color = foreground.withValues(alpha: major ? .6 : .2)
          ..strokeWidth = major ? 2 : 1,
      );
    }
    const letters = ['北 N', '东 E', '南 S', '西 W'];
    for (int i = 0; i < 4; i++) {
      final text = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            color: i == 0 ? const Color(0xffd66a56) : foreground,
            fontSize: radius * .11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final spot = at(i * math.pi / 2, radius * .72);
      text.paint(canvas, spot - Offset(text.width / 2, text.height / 2));
    }
    final north = Path()
      ..moveTo(center.dx, center.dy - radius * .52)
      ..lineTo(center.dx - radius * .08, center.dy)
      ..lineTo(center.dx + radius * .08, center.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = const Color(0xffd66a56));
    final south = Path()
      ..moveTo(center.dx, center.dy + radius * .52)
      ..lineTo(center.dx - radius * .08, center.dy)
      ..lineTo(center.dx + radius * .08, center.dy)
      ..close();
    canvas.drawPath(south, Paint()..color = accent.withValues(alpha: .45));
    canvas.drawCircle(center, 7, Paint()..color = surface);
    canvas.drawCircle(center, 4, Paint()..color = foreground);
  }

  @override
  bool shouldRepaint(CompassRosePainter old) =>
      old.accent != accent ||
      old.foreground != foreground ||
      old.surface != surface;
}

class CompassPointerPainter extends CustomPainter {
  const CompassPointerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2, y = math.min(size.width, size.height) * .015;
    canvas.drawPath(
      Path()
        ..moveTo(x - 6, y)
        ..lineTo(x + 6, y)
        ..lineTo(x, y + 12)
        ..close(),
      Paint()..color = const Color(0xffd66a56),
    );
  }

  @override
  bool shouldRepaint(CompassPointerPainter old) => false;
}
