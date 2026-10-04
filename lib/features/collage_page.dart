import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/platform_channel.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';

class CollageCell {
  CollageCell(this.image);
  final ui.Image image;
  double zoom = 1;
  Offset center = const Offset(.5, .5);
}

/// Shared geometry for the editor and the PNG renderer.
List<Rect> collageRects(
  List<double> ratios,
  String layout,
  double width,
  double gap,
  double margin,
) {
  if (ratios.isEmpty) return [];
  if (layout == '长图拼接' || layout == '竖排') {
    var y = margin;
    return ratios.map((ratio) {
      final h = (width - 2 * margin) / (layout == '长图拼接' ? ratio : 1);
      final r = Rect.fromLTWH(margin, y, width - 2 * margin, h);
      y += h + gap;
      return r;
    }).toList();
  }
  final cols = layout == '横排'
      ? ratios.length
      : layout == '三列'
      ? 3
      : 2;
  final side = (width - 2 * margin - gap * (cols - 1)) / cols;
  return List.generate(
    ratios.length,
    (i) => Rect.fromLTWH(
      margin + i % cols * (side + gap),
      margin + i ~/ cols * (side + gap),
      side,
      side,
    ),
  );
}

Rect collageCrop(CollageCell cell, Rect dest) {
  final w = cell.image.width.toDouble(), h = cell.image.height.toDouble();
  final scale = math.max(dest.width / w, dest.height / h) * cell.zoom;
  final sw = dest.width / scale, sh = dest.height / scale;
  return Rect.fromLTWH(
    (cell.center.dx * w - sw / 2).clamp(0, math.max(0, w - sw)),
    (cell.center.dy * h - sh / 2).clamp(0, math.max(0, h - sh)),
    sw,
    sh,
  );
}

class CollagePainter extends CustomPainter {
  CollagePainter(
    this.cells,
    this.rects,
    this.background,
    this.radius,
    this.documentSize, {
    this.long = false,
  });
  final List<CollageCell> cells;
  final List<Rect> rects;
  final Color background;
  final double radius;
  final Size documentSize;
  final bool long;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(
      size.width / documentSize.width,
      size.height / documentSize.height,
    );
    canvas.drawRect(Offset.zero & documentSize, Paint()..color = background);
    for (var i = 0; i < cells.length; i++) {
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(rects[i], Radius.circular(radius)),
      );
      final im = cells[i].image;
      canvas.drawImageRect(
        im,
        long
            ? Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble())
            : collageCrop(cells[i], rects[i]),
        rects[i],
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CollagePainter oldDelegate) => true;
}

class CollagePage extends StatefulWidget {
  const CollagePage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<CollagePage> createState() => _CollagePageState();
}

class _CollagePageState extends State<CollagePage> {
  static const channel = SaiChannel('saisuite/media');
  final cells = <CollageCell>[];
  final temporary = <String>[];
  String layout = '双列';
  double gap = 12, margin = 16, radius = 12;
  Color background = Colors.white;
  bool busy = false, dirty = false;
  String? error;
  @override
  void dispose() {
    for (final c in cells) {
      c.image.dispose();
    }
    channel.invokeMethod<void>('mediaCleanup', {'paths': temporary});
    super.dispose();
  }

  List<Rect> get rects => collageRects(
    cells.map((c) => c.image.width / c.image.height).toList(),
    layout,
    1080,
    gap,
    margin,
  );
  Size get documentSize =>
      Size(1080, rects.isEmpty ? 1080 : rects.last.bottom + margin);
  CollagePainter get painter => CollagePainter(
    cells,
    rects,
    background,
    radius,
    documentSize,
    long: layout == '长图拼接',
  );
  Future<void> pick() async {
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('替换当前拼图？'),
          content: const Text('当前拼图尚未导出。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('替换'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final next = <CollageCell>[];
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      if (files.length < 2 || files.length > 9) {
        throw const FormatException('请选择 2—9 张图片');
      }
      for (final f in files) {
        final source = await Files.localCopy(f, maxBytes: 30 * 1024 * 1024);
        final prepared = (await channel.invokeMapMethod<String, dynamic>(
          'imagePrepareEditor',
          {'path': source},
        ))!;
        final path = prepared['path'] as String;
        temporary.add(path);
        final w = prepared['width'] as int, h = prepared['height'] as int;
        final scale = math.min(1.0, 1536 / math.max(w, h));
        final codec = await ui.instantiateImageCodec(
          await File(path).readAsBytes(),
          targetWidth: (w * scale).round(),
          targetHeight: (h * scale).round(),
        );
        try {
          next.add(CollageCell((await codec.getNextFrame()).image));
        } finally {
          codec.dispose();
        }
      }
      if (!mounted) return;
      setState(() {
        for (final c in cells) {
          c.image.dispose();
        }
        cells.clear();
        cells.addAll(next);
        next.clear();
        dirty = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : '$e');
      }
    } finally {
      for (final c in next) {
        c.image.dispose();
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> crop(int index) async {
    if (layout == '长图拼接') {
      message(context, '长图保留各张图片的完整比例');
      return;
    }
    final cell = cells[index],
        originalCenter = cells[index].center,
        originalZoom = cells[index].zoom;
    var baseZoom = cell.zoom;
    final dest = rects[index];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) => AlertDialog(
          title: Text('调整第 ${index + 1} 格'),
          content: SizedBox(
            width: 320,
            child: AspectRatio(
              aspectRatio: dest.width / dest.height,
              child: GestureDetector(
                onScaleStart: (_) => baseZoom = cell.zoom,
                onScaleUpdate: (d) => refresh(() {
                  cell.zoom = (baseZoom * d.scale).clamp(1, 6);
                  cell.center = Offset(
                    (cell.center.dx - d.focalPointDelta.dx / (320 * cell.zoom))
                        .clamp(0, 1),
                    (cell.center.dy -
                            d.focalPointDelta.dy /
                                (320 * dest.height / dest.width * cell.zoom))
                        .clamp(0, 1),
                  );
                }),
                child: CustomPaint(
                  painter: CollagePainter(
                    [cell],
                    [Rect.fromLTWH(0, 0, dest.width, dest.height)],
                    background,
                    0,
                    dest.size,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => refresh(() {
                cell.zoom = 1;
                cell.center = const Offset(.5, .5);
              }),
              child: const Text('重置'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (accepted != true) {
        cell.center = originalCenter;
        cell.zoom = originalZoom;
      } else {
        dirty = true;
      }
    });
  }

  Future<void> export() async {
    if (cells.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final size = documentSize;
      // Bound GPU allocation; long documents are uniformly scaled, never cut off.
      final scale = math.min(
        1.0,
        math.min(
          8000 / size.height,
          math.sqrt(16000000 / (size.width * size.height)),
        ),
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size * scale);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (size.width * scale).round().clamp(1, 1080),
        (size.height * scale).round().clamp(1, 8000),
      );
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final saved = await Files.saveBytes(
          data.buffer.asUint8List(),
          'saisuite-collage.png',
        );
        if (saved != null && mounted) {
          setState(() => dirty = false);
          message(context, '已导出 ${image.width} × ${image.height} PNG');
        }
      } finally {
        image.dispose();
        picture.dispose();
      }
    } catch (e) {
      if (mounted) setState(() => error = '导出失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget slider(
    String label,
    double value,
    double max,
    ValueChanged<double> update,
  ) => Row(
    children: [
      SizedBox(width: 65, child: Text(label)),
      Expanded(
        child: Slider(
          value: value,
          max: max,
          onChanged: busy
              ? null
              : (v) => setState(() {
                  update(v);
                  dirty = true;
                }),
        ),
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
    children: [
      Text('让画面组合起来', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('长按一格拖动换位，点按调整裁剪。长图拼接保留完整画面。'),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: busy ? null : pick,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('选择 2—9 张图片'),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (cells.isNotEmpty) ...[
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          children: [
            for (final l in ['双列', '三列', '横排', '竖排', '长图拼接'])
              ChoiceChip(
                label: Text(l),
                selected: layout == l,
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                        layout = l;
                        dirty = true;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (c, b) {
            final scale = math.min(
              b.maxWidth / documentSize.width,
              2400 / documentSize.height,
            );
            return Center(
              child: SizedBox(
                width: documentSize.width * scale,
                height: documentSize.height * scale,
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: painter)),
                    for (var i = 0; i < cells.length; i++)
                      Positioned(
                        left: rects[i].left * scale,
                        top: rects[i].top * scale,
                        width: rects[i].width * scale,
                        height: rects[i].height * scale,
                        child: DragTarget<int>(
                          onWillAcceptWithDetails: (d) => !busy && d.data != i,
                          onAcceptWithDetails: (d) => setState(() {
                            final cell = cells[i];
                            cells[i] = cells[d.data];
                            cells[d.data] = cell;
                            dirty = true;
                          }),
                          builder: (c, candidate, rejected) =>
                              LongPressDraggable<int>(
                                data: i,
                                maxSimultaneousDrags: busy ? 0 : 1,
                                feedback: SizedBox(
                                  width: 90,
                                  height: 90,
                                  child: RawImage(
                                    image: cells[i].image,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: GestureDetector(
                                  onTap: busy ? null : () => crop(i),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: candidate.isEmpty
                                          ? null
                                          : Border.all(
                                              color: Colors.tealAccent,
                                              width: 4,
                                            ),
                                    ),
                                    alignment: Alignment.topLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.all(5),
                                      child: CircleAvatar(
                                        radius: 12,
                                        child: Text(
                                          '${i + 1}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        slider('间距', gap, 60, (v) => gap = v),
        slider('边距', margin, 80, (v) => margin = v),
        slider('圆角', radius, 80, (v) => radius = v),
        Wrap(
          spacing: 12,
          children: [
            for (final c in [
              Colors.white,
              Colors.black,
              const Color(0xfff4e6d6),
              const Color(0xffd7ece9),
            ])
              InkWell(
                onTap: busy
                    ? null
                    : () => setState(() {
                        background = c;
                        dirty = true;
                      }),
                child: CircleAvatar(
                  backgroundColor: c,
                  child: background == c
                      ? const Icon(Icons.check, color: Colors.grey)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : export,
          icon: const Icon(Icons.save_alt),
          label: const Text('导出拼图 PNG'),
        ),
        const Text('导出宽度最高 1080 px；长图超过 8000 px 或 1600 万像素时整体等比缩小。'),
      ],
    ],
  );
}
