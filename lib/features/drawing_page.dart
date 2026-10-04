import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';

class DrawingStroke {
  DrawingStroke(
    this.color,
    this.width,
    this.eraser,
    this.points, {
    this.shape = '画笔',
    this.text,
    this.textId,
  });
  final String? text;
  final int? textId;
  final String shape;
  final Color color;
  final double width;
  final bool eraser;
  final List<Offset> points;
}

class DrawingPainter extends CustomPainter {
  DrawingPainter(this.strokes, {this.transparent = false});
  final List<DrawingStroke> strokes;
  final bool transparent;
  static TextPainter textPainter(DrawingStroke stroke) => TextPainter(
    text: TextSpan(
      text: stroke.text,
      style: TextStyle(color: stroke.color, fontSize: stroke.width),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 850);
  @override
  void paint(Canvas canvas, Size size) {
    if (!transparent) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    }
    canvas.saveLayer(Offset.zero & size, Paint());
    final latestText = <int, DrawingStroke>{
      for (final s in strokes)
        if (s.textId != null) s.textId!: s,
    };
    for (final stroke in strokes) {
      if (stroke.textId != null) {
        if (latestText[stroke.textId] != stroke) continue;
        final text = textPainter(stroke);
        text.paint(canvas, stroke.points.first);
        text.dispose();
        continue;
      }
      final paint = Paint()
        ..color = stroke.color
        ..blendMode = stroke.eraser ? BlendMode.clear : BlendMode.srcOver
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          stroke.width / 2,
          Paint()
            ..color = paint.color
            ..blendMode = paint.blendMode,
        );
        continue;
      }
      if (stroke.shape != '画笔') {
        final a = stroke.points.first, b = stroke.points.last;
        final rect = Rect.fromPoints(a, b);
        if (stroke.shape == '矩形') {
          canvas.drawRect(rect, paint);
        } else if (stroke.shape == '圆形') {
          canvas.drawOval(rect, paint);
        } else {
          canvas.drawLine(a, b, paint);
          if (stroke.shape == '箭头' && (b - a).distance > 0) {
            final direction = (b - a) / (b - a).distance;
            final side = Offset(-direction.dy, direction.dx);
            canvas.drawPath(
              Path()
                ..moveTo(
                  (b - direction * 20 + side * 10).dx,
                  (b - direction * 20 + side * 10).dy,
                )
                ..lineTo(b.dx, b.dy)
                ..lineTo(
                  (b - direction * 20 - side * 10).dx,
                  (b - direction * 20 - side * 10).dy,
                ),
              paint,
            );
          }
        }
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length - 1; i++) {
        final p = stroke.points[i], next = stroke.points[i + 1];
        path.quadraticBezierTo(
          p.dx,
          p.dy,
          (p.dx + next.dx) / 2,
          (p.dy + next.dy) / 2,
        );
      }
      path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
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
  bool fullScreen = false;
  bool transparent = false,
      moveMode = false,
      collapsed = false,
      gestureBlocked = false;
  String shape = '画笔';
  int textSequence = 0;
  final transform = TransformationController();
  final pointers = <int>{};
  List<DrawingStroke> previousRedo = [];
  bool previousDirty = false;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Size? drawingSize;
  // Fixed export coordinates keep the drawing stable across rotation.
  Size get canvasSize => drawingSize ?? const Size(900, 900);
  Future<void> export() async {
    setState(() => busy = true);
    try {
      final recorder = ui.PictureRecorder();
      DrawingPainter(
        strokes,
        transparent: transparent,
      ).paint(Canvas(recorder), canvasSize);
      final picture = recorder.endRecording(),
          image = await picture.toImage(
            canvasSize.width.round(),
            canvasSize.height.round(),
          );
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
    DrawingStroke? selectedText;
    if (shape == '文字' && !eraser) {
      final seen = <int>{};
      for (final s in strokes.reversed) {
        if (s.textId == null || !seen.add(s.textId!)) continue;
        final text = DrawingPainter.textPainter(s);
        final hit = (s.points.first & text.size)
            .inflate(10)
            .contains(p / scale);
        text.dispose();
        if (hit) {
          selectedText = s;
          break;
        }
      }
      if (selectedText == null) return;
    }
    setState(() {
      drawingAccepted = true;
      previousRedo = List.of(redo);
      previousDirty = dirty;
      if (selectedText != null) {
        strokes.add(
          DrawingStroke(
            selectedText.color,
            selectedText.width,
            false,
            [selectedText.points.first, p / scale],
            shape: '文字',
            text: selectedText.text,
            textId: selectedText.textId,
          ),
        );
      } else {
        strokes.add(
          DrawingStroke(color, width, eraser, [
            p / scale,
          ], shape: eraser ? '画笔' : shape),
        );
      }
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
    if (point.dx < 0 ||
        point.dy < 0 ||
        point.dx > canvasSize.width ||
        point.dy > canvasSize.height) {
      return;
    }
    setState(() {
      if (strokes.last.textId != null) {
        final last = strokes.last;
        final delta = point - last.points.last;
        last.points[0] = Offset(
          (last.points[0].dx + delta.dx).clamp(0, canvasSize.width - 20),
          (last.points[0].dy + delta.dy).clamp(0, canvasSize.height - 20),
        );
        last.points[1] = point;
        return;
      }
      if (strokes.last.shape != '画笔' && strokes.last.points.length > 1) {
        strokes.last.points.removeLast();
      }
      strokes.last.points.add(point);
    });
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

  Widget drawingCanvas() => LayoutBuilder(
    builder: (c, b) {
      final scale = b.maxWidth / canvasSize.width;
      return AspectRatio(
        aspectRatio: canvasSize.aspectRatio,
        child: ClipRect(
          child: Listener(
            onPointerDown: (d) {
              pointers.add(d.pointer);
              if (pointers.length > 1) {
                if (drawingAccepted && strokes.isNotEmpty) {
                  setState(() {
                    strokes.removeLast();
                    redo
                      ..clear()
                      ..addAll(previousRedo);
                    dirty = previousDirty;
                  });
                }
                drawingAccepted = false;
                gestureBlocked = true;
                drawingPointer = null;
                return;
              }
              if (busy || moveMode || gestureBlocked) return;
              drawingPointer = d.pointer;
              begin(transform.toScene(d.localPosition), scale);
            },
            onPointerMove: (d) {
              if (drawingPointer == d.pointer && !gestureBlocked) {
                move(transform.toScene(d.localPosition), scale);
              }
            },
            onPointerUp: (d) {
              pointers.remove(d.pointer);
              if (pointers.isEmpty) {
                gestureBlocked = false;
                drawingPointer = null;
                drawingAccepted = false;
              }
            },
            onPointerCancel: (d) {
              pointers.remove(d.pointer);
              drawingAccepted = false;
              drawingPointer = null;
              if (pointers.isEmpty) gestureBlocked = false;
            },
            child: InteractiveViewer(
              transformationController: transform,
              panEnabled: moveMode || pointers.length > 1,
              minScale: 1,
              maxScale: 8,
              child: Stack(
                children: [
                  if (transparent)
                    const Positioned.fill(
                      child: CustomPaint(painter: CheckerboardPainter()),
                    ),
                  FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: canvasSize.width,
                      height: canvasSize.height,
                      child: CustomPaint(
                        painter: DrawingPainter(
                          strokes,
                          transparent: transparent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget colorMenu() => PopupMenuButton<Color>(
    tooltip: '画笔颜色',
    enabled: !busy,
    icon: Icon(Icons.circle, color: color),
    onSelected: (c) => setState(() {
      color = c;
      eraser = false;
    }),
    itemBuilder: (_) => [
      for (final c in [
        Colors.black,
        Colors.red,
        Colors.orange,
        Colors.green,
        Colors.blue,
        Colors.purple,
      ])
        PopupMenuItem(
          value: c,
          child: Row(
            children: [
              Icon(Icons.circle, color: c),
              const SizedBox(width: 12),
              Text(
                '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
              ),
            ],
          ),
        ),
    ],
  );
  Future<void> addText() async {
    if (strokes.length >= 1000) return;
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加文字'),
        content: TextField(
          controller: input,
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '输入标注'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(c, input.text.trim());
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (!mounted || value == null) return;
    setState(() {
      shape = '文字';
      eraser = false;
      strokes.add(
        DrawingStroke(
          color,
          36,
          false,
          [Offset(canvasSize.width * .1, canvasSize.height * .3)],
          shape: '文字',
          text: value,
          textId: textSequence++,
        ),
      );
      redo.clear();
      dirty = true;
    });
    message(context, '拖动文字可调整位置，撤销可恢复移动前的位置');
  }

  Widget editingTools() => Wrap(
    alignment: WrapAlignment.center,
    children: [
      colorMenu(),
      IconButton(
        tooltip: '添加文字',
        onPressed: busy ? null : addText,
        icon: const Icon(Icons.text_fields),
      ),
      IconButton(
        tooltip: '缩放移动',
        onPressed: busy ? null : () => setState(() => moveMode = !moveMode),
        icon: Icon(moveMode ? Icons.pan_tool : Icons.gesture),
      ),
      IconButton(
        tooltip: '重置视图',
        onPressed: () => transform.value = Matrix4.identity(),
        icon: const Icon(Icons.center_focus_strong),
      ),
      PopupMenuButton<String>(
        tooltip: '绘图形状',
        icon: const Icon(Icons.category_outlined),
        onSelected: (v) => setState(() {
          shape = v;
          eraser = false;
        }),
        itemBuilder: (_) => [
          for (final s in ['画笔', '直线', '箭头', '矩形', '圆形', '文字'])
            PopupMenuItem(value: s, child: Text(s)),
        ],
      ),
      IconButton(
        tooltip: '透明背景',
        onPressed: busy
            ? null
            : () => setState(() {
                transparent = !transparent;
                dirty = true;
              }),
        icon: Icon(transparent ? Icons.grid_on : Icons.crop_square),
      ),
      IconButton(
        tooltip: '橡皮',
        onPressed: busy ? null : () => setState(() => eraser = !eraser),
        icon: Icon(
          Icons.cleaning_services,
          color: eraser ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      IconButton(
        tooltip: '撤销',
        onPressed: busy || strokes.isEmpty
            ? null
            : () => setState(() {
                redo.add(strokes.removeLast());
                dirty = true;
              }),
        icon: const Icon(Icons.undo),
      ),
      IconButton(
        tooltip: '重做',
        onPressed: busy || redo.isEmpty
            ? null
            : () => setState(() {
                strokes.add(redo.removeLast());
                dirty = true;
              }),
        icon: const Icon(Icons.redo),
      ),
      IconButton(
        tooltip: '清空画布',
        onPressed: busy ? null : clear,
        icon: const Icon(Icons.delete_outline),
      ),
      IconButton(
        tooltip: '导出 PNG',
        onPressed: busy ? null : export,
        icon: const Icon(Icons.save_alt),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    dirty: dirty,
    blocked: busy,
    onExport: export,
    hideAppBar: fullScreen,
    onBack: fullScreen ? () => setState(() => fullScreen = false) : null,
    actions: [
      IconButton(
        tooltip: '全屏画板',
        icon: const Icon(Icons.fullscreen),
        onPressed: busy ? null : () => setState(() => fullScreen = true),
      ),
    ],
    body: SafeArea(
      child: Column(
        children: [
          if (fullScreen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '退出全屏',
                    onPressed: busy
                        ? null
                        : () => setState(() => fullScreen = false),
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                  Text('画板', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: collapsed ? '展开工具栏' : '收起工具栏',
                    onPressed: () => setState(() => collapsed = !collapsed),
                    icon: Icon(
                      collapsed ? Icons.expand_more : Icons.expand_less,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) {
                drawingSize ??= Size(
                  900,
                  (900 * box.maxHeight / box.maxWidth)
                      .clamp(300, 4096)
                      .roundToDouble(),
                );
                final scale =
                    (box.maxWidth / canvasSize.width) <
                        (box.maxHeight / canvasSize.height)
                    ? box.maxWidth / canvasSize.width
                    : box.maxHeight / canvasSize.height;
                return ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Center(
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: canvasSize.width * scale,
                        height: canvasSize.height * scale,
                        child: drawingCanvas(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!fullScreen || !collapsed)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    editingTools(),
                    Row(
                      children: [
                        Text(
                          '${eraser ? '橡皮' : '画笔'} ${width.round()}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Expanded(
                          child: Slider(
                            value: width,
                            min: 1,
                            max: 60,
                            onChanged: busy
                                ? null
                                : (v) => setState(() => width = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
    children: const [],
  );
}

class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter();
  @override
  void paint(Canvas canvas, Size size) {
    for (double y = 0; y < size.height; y += 16) {
      for (double x = 0; x < size.width; x += 16) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, 16, 16),
          Paint()
            ..color = ((x / 16 + y / 16).round().isEven
                ? const Color(0xffeeeeee)
                : const Color(0xffcccccc)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter oldDelegate) => false;
}
