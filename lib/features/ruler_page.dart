import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/platform_channel.dart';
import 'catalog.dart';
import 'workbench.dart';

class RulerPage extends StatefulWidget {
  const RulerPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<RulerPage> createState() => _RulerPageState();
}

class _RulerPageState extends State<RulerPage> {
  final calibration = TextEditingController();
  double scale = 3.78;
  bool calibrated = false, vertical = false, inches = false;
  RangeValues marks = const RangeValues(0, 100);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final stored = widget.state.prefs.getDouble('ruler_px_mm');
    if (stored != null && stored.isFinite && stored > 0) {
      setState(() {
        scale = stored;
        calibrated = true;
      });
      return;
    }
    try {
      final metrics = await const SaiChannel('saisuite/device')
          .invokeMapMethod<String, dynamic>('displayMetrics');
      if (mounted && metrics != null) {
        setState(
          () => scale =
              (metrics['xdpi'] as num) / 25.4 / (metrics['density'] as num),
        );
      }
    } catch (_) {
      /* A manual calibration remains available. */
    }
  }

  @override
  void dispose() {
    calibration.dispose();
    super.dispose();
  }

  Future<void> calibrate() async {
    final mm = double.tryParse(calibration.text);
    if (mm == null || !mm.isFinite || mm < 5 || mm > 200) {
      message(context, '实测长度须为 5—200 mm');
      return;
    }
    final next = 200 / mm;
    await widget.state.prefs.setDouble('ruler_px_mm', next);
    if (mounted) {
      setState(() {
        scale = next;
        calibrated = true;
        marks = const RangeValues(0, 100);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    children: [
      Text(calibrated ? '已按实体长度校准；屏幕标尺用于日常估测。' : '尚未校准：请用实体尺测量下方校准线，再输入其实际长度。'),
      const SizedBox(height: 12),
      Center(
        child: SizedBox(
          width: 200,
          height: 30,
          child: CustomPaint(
            painter: CalibrationPainter(Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
      TextField(
        controller: calibration,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '校准线的实测长度 mm'),
      ),
      FilledButton(onPressed: calibrate, child: const Text('应用校准')),
      Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('竖向标尺'),
            selected: vertical,
            onSelected: (v) => setState(() => vertical = v),
          ),
          FilterChip(
            label: const Text('英寸'),
            selected: inches,
            onSelected: (v) => setState(() => inches = v),
          ),
        ],
      ),
      LayoutBuilder(
        builder: (c, b) {
          final length = vertical ? 400.0 : b.maxWidth, maxMm = length / scale;
          final a = marks.start.clamp(0.0, length),
              end = marks.end.clamp(a, length);
          return Column(
            children: [
              SizedBox(
                width: b.maxWidth,
                height: vertical ? 400 : 120,
                child: CustomPaint(
                  painter: RulerPainter(
                    scale,
                    vertical,
                    inches,
                    RangeValues(a, end),
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              RangeSlider(
                values: RangeValues(a, end),
                max: length,
                onChanged: (v) => setState(() => marks = v),
              ),
              Text(
                '两点距离 ${((end - a) / scale).toStringAsFixed(2)} mm / ${((end - a) / scale / 25.4).toStringAsFixed(3)} in\n屏幕有效范围 ${maxMm.toStringAsFixed(1)} mm',
              ),
            ],
          );
        },
      ),
    ],
  );
}

class CalibrationPainter extends CustomPainter {
  CalibrationPainter(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    c.drawLine(const Offset(0, 15), const Offset(200, 15), p);
    c.drawLine(const Offset(1, 4), const Offset(1, 26), p);
    c.drawLine(const Offset(199, 4), const Offset(199, 26), p);
  }

  @override
  bool shouldRepaint(CalibrationPainter old) => old.color != color;
}

class RulerPainter extends CustomPainter {
  RulerPainter(this.scale, this.vertical, this.inches, this.marks, this.color);
  final double scale;
  final bool vertical, inches;
  final RangeValues marks;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    if (vertical) {
      c.translate(s.width, 0);
      c.rotate(1.5707963267948966);
    }
    final length = vertical ? s.height : s.width,
        breadth = vertical ? s.width : s.height;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final step = inches ? scale * 25.4 / 16 : scale;
    if (step <= 0) return;
    for (var i = 0; i * step <= length && i < 10000; i++) {
      final major = i % (inches ? 16 : 10) == 0,
          mid = i % (inches ? 8 : 5) == 0,
          x = i * step;
      c.drawLine(
        Offset(x, 0),
        Offset(
          x,
          major
              ? 36
              : mid
              ? 26
              : 16,
        ),
        p,
      );
      if (major) {
        final t = TextPainter(
          text: TextSpan(
            text: '${i ~/ (inches ? 16 : 10)}',
            style: TextStyle(color: color, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        t.paint(c, Offset(x + 3, 40));
      }
    }
    for (final mark in [marks.start, marks.end]) {
      c.drawLine(
        Offset(mark, 0),
        Offset(mark, breadth),
        Paint()
          ..color = Colors.red
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(RulerPainter old) => true;
}
