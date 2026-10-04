import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';

class DrawingStroke {
  DrawingStroke(this.color, this.width, this.eraser, this.points);
  final Color color;
  final double width;
  final bool eraser;
  final List<Offset> points;
}

class DrawingPainter extends CustomPainter {
  DrawingPainter(this.strokes);
  final List<DrawingStroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = (stroke.eraser ? Colors.white : stroke.color)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          stroke.width / 2,
          Paint()..color = paint.color,
        );
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final p in stroke.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}

class DrawingPage extends StatefulWidget {
  const DrawingPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {
  final strokes = <DrawingStroke>[], redo = <DrawingStroke>[];
  Color color = Colors.black;
  double width = 6;
  bool eraser = false, dirty = false, busy = false, drawingAccepted = false;
  int? drawingPointer;
  // Fixed export coordinates keep the drawing stable across rotation.
  static const canvasSize = Size(900, 900);
  Future<void> export() async {
    setState(() => busy = true);
    try {
      final recorder = ui.PictureRecorder();
      DrawingPainter(strokes).paint(Canvas(recorder), canvasSize);
      final picture = recorder.endRecording(),
          image = await picture.toImage(900, 900);
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final path = await Files.saveBytes(bytes, 'saisuite-drawing.png');
        if (path != null && mounted) {
          setState(() => dirty = false);
          message(context, '已导出 PNG');
        }
      } finally {
        image.dispose();
        picture.dispose();
      }
    } catch (e) {
      if (mounted) message(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void begin(Offset p, double scale) {
    drawingAccepted = false;
    if (strokes.length >= 1000) {
      message(context, '最多 1000 笔，请导出后清空');
      return;
    }
    setState(() {
      drawingAccepted = true;
      strokes.add(DrawingStroke(color, width, eraser, [p / scale]));
      redo.clear();
      dirty = true;
    });
  }

  void move(Offset p, double scale) {
    if (!drawingAccepted ||
        strokes.isEmpty ||
        strokes.last.points.length >= 10000) {
      return;
    }
    final point = p / scale;
    if (point.dx < 0 || point.dy < 0 || point.dx > 900 || point.dy > 900) {
      return;
    }
    setState(() => strokes.last.points.add(point));
  }

  Future<void> clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空画布？'),
        content: const Text('清空后无法恢复，请先导出需要保留的内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (yes == true) {
      setState(() {
        strokes.clear();
        redo.clear();
        dirty = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    dirty: dirty,
    onExport: export,
    children: [
      const Text('画布不会自动保存。需要保留时请导出 PNG。'),
      Wrap(
        spacing: 8,
        children: [
          for (final c in [
            Colors.black,
            Colors.red,
            Colors.orange,
            Colors.green,
            Colors.blue,
            Colors.purple,
          ])
            IconButton(
              tooltip: '画笔颜色 ${c.toARGB32().toRadixString(16)}',
              onPressed: () => setState(() {
                color = c;
                eraser = false;
              }),
              icon: Icon(
                color == c && !eraser ? Icons.check_circle : Icons.circle,
                color: c,
              ),
            ),
          IconButton(
            tooltip: '橡皮',
            onPressed: () => setState(() => eraser = !eraser),
            icon: Icon(
              Icons.cleaning_services,
              color: eraser ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          IconButton(
            tooltip: '撤销',
            onPressed: strokes.isEmpty
                ? null
                : () => setState(() {
                    redo.add(strokes.removeLast());
                    dirty = true;
                  }),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: '重做',
            onPressed: redo.isEmpty
                ? null
                : () => setState(() {
                    strokes.add(redo.removeLast());
                    dirty = true;
                  }),
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: '清空画布',
            onPressed: clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      Text('${eraser ? '橡皮' : '画笔'}粗细 ${width.round()}'),
      Slider(
        value: width,
        min: 1,
        max: 60,
        onChanged: (v) => setState(() => width = v),
      ),
      LayoutBuilder(
        builder: (c, b) {
          final scale = b.maxWidth / 900;
          return AspectRatio(
            aspectRatio: 1,
            child: ClipRect(
              child: RawGestureDetector(
                // Claim canvas touches before the surrounding vertical list.
                gestures: {
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        EagerGestureRecognizer
                      >(EagerGestureRecognizer.new, (_) {}),
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (d) {
                    if (drawingPointer != null) return;
                    drawingPointer = d.pointer;
                    begin(d.localPosition, scale);
                  },
                  onPointerMove: (d) {
                    if (drawingPointer == d.pointer) {
                      move(d.localPosition, scale);
                    }
                  },
                  onPointerUp: (d) {
                    if (drawingPointer == d.pointer) {
                      drawingPointer = null;
                      drawingAccepted = false;
                    }
                  },
                  onPointerCancel: (d) {
                    if (drawingPointer == d.pointer) {
                      drawingPointer = null;
                      drawingAccepted = false;
                    }
                  },
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: 900,
                      height: 900,
                      child: CustomPaint(painter: DrawingPainter(strokes)),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : export,
        icon: const Icon(Icons.save_alt),
        label: Text(busy ? '导出中…' : '导出 PNG'),
      ),
    ],
  );
}
