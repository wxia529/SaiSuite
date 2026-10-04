import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import 'catalog.dart';
import 'workbench.dart';

class SensorPage extends StatefulWidget {
  const SensorPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> with WidgetsBindingObserver {
  StreamSubscription<dynamic>? subscription;
  List<dynamic> inventory = [];
  Map data = {};
  double zeroX = 0, zeroY = 0;
  String? error;
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
        .receiveBroadcastStream()
        .listen(
          (event) {
            if (mounted) setState(() => data = event as Map);
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
    final azimuth = value('azimuth'), x = value('tiltX'), y = value('tiltY');
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      children: [
        if (error != null) Text(error!),
        if (inventory.isEmpty && error == null) const LinearProgressIndicator(),
        if (inventory.isNotEmpty && !supported)
          const Text('设备缺少此工具所需的传感器，无法测量。'),
        if (compass && supported) ...[
          const Text('磁北指南针；远离磁铁、电池测试夹具和金属干扰。读数不作为精密测量依据。'),
          SizedBox(
            height: 240,
            child: Center(
              child: Transform.rotate(
                angle: -(azimuth ?? 0) * math.pi / 180,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('N · 磁北'), Icon(Icons.navigation, size: 140)],
                ),
              ),
            ),
          ),
          Text(
            azimuth == null ? '等待方向读数…' : '方位角 ${azimuth.toStringAsFixed(1)}°',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            '磁场精度：${switch ((data['accuracy'] as Map?)?['2']) {
              3 => '高',
              2 => '中',
              1 => '低，请校准',
              _ => '未知或不可靠，请校准',
            }}',
          ),
          const Text('可缓慢以“8”字形移动手机后重新观察读数。'),
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
