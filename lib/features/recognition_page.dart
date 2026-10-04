import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../core/app_state.dart';
import '../core/creative_images.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';
import 'extra_widgets.dart';
import 'image_studio_page.dart' show creativeChannel;

class RecognitionPage extends StatefulWidget {
  const RecognitionPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<RecognitionPage> createState() => _RecognitionPageState();
}

class _RecognitionPageState extends State<RecognitionPage> {
  Uint8List? bytes;
  ui.Image? image;
  int width = 1, height = 1;
  final output = TextEditingController();
  final points = <Offset>[];
  final lines = <Map<String, dynamic>>[];
  bool busy = false, dark = true, selecting = false, dirty = false;
  double threshold = 160, minArea = 80;
  Rect? crop;
  Offset? start;
  String error = '', mode = '增删标记';
  bool get counting => widget.tool.id == 'B09';
  @override
  void dispose() {
    image?.dispose();
    output.dispose();
    super.dispose();
  }

  Future<void> guarded(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message.toString()
              : e is PlatformException
              ? e.message ?? e.code
              : '$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick({bool camera = false}) => guarded(() async {
    String? path;
    if (camera) {
      final value = await creativeChannel.invokeMapMethod<String, dynamic>(
        'camera',
      );
      path = value?['path'] as String?;
    } else {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      path = await Files.localCopy(file, maxBytes: 30 * 1024 * 1024);
    }
    if (path == null) return;
    final normalized = await compute(creativeImageJob, {
      'action': 'normalize',
      'bytes': await File(path).readAsBytes(),
      'edge': 3000,
    });
    final png = normalized['bytes'] as Uint8List;
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (camera) await File(path).delete();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() {
      image?.dispose();
      image = frame.image;
      bytes = png;
      width = normalized['width'] as int;
      height = normalized['height'] as int;
      crop = null;
      points.clear();
      lines.clear();
      output.clear();
      dirty = false;
    });
  });
  Future<void> recognize() => guarded(() async {
    if (bytes == null) throw const FormatException('请先选择图片');
    if (counting) {
      final result = await compute(creativeImageJob, {
        'action': 'count',
        'bytes': bytes!,
        'threshold': threshold.round(),
        'dark': dark,
        'minArea': minArea.round(),
      });
      if (mounted) {
        setState(() {
          points.clear();
          points.addAll(
            (result['points'] as List).map(
              (p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
            ),
          );
          dirty = true;
        });
      }
    } else {
      var input = bytes!;
      final area = crop ?? const Rect.fromLTWH(0, 0, 1, 1);
      final left = (area.left * width).floor(),
          top = (area.top * height).floor();
      if (crop != null) {
        final result = await compute(creativeImageJob, {
          'action': 'crop',
          'bytes': bytes!,
          'left': left,
          'top': top,
          'width': math.max(1, (area.width * width).round()),
          'height': math.max(1, (area.height * height).round()),
        });
        input = result['bytes'] as Uint8List;
      }
      final directory = await Files.temporaryDirectory(),
          file = File(
            '${directory.path}/saisuite_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
          );
      try {
        await file.writeAsBytes(input);
        final result = await creativeChannel.invokeMapMethod<String, dynamic>(
          'ocr',
          {'path': file.path},
        );
        if (mounted) {
          setState(() {
            output.text = (result?['text'] ?? '').toString();
            lines.clear();
            for (final value in result?['lines'] as List? ?? []) {
              final entry = Map<String, dynamic>.from(value as Map);
              final box = (entry['box'] as List).cast<num>();
              entry['box'] = [
                box[0] + left,
                box[1] + top,
                box[2] + left,
                box[3] + top,
              ];
              lines.add(entry);
            }
            dirty = output.text.isNotEmpty;
            if (output.text.isEmpty) error = '没有识别到文字，可调整框选区域或换一张清晰图片。';
          });
        }
      } finally {
        if (await file.exists()) await file.delete();
      }
    }
  });
  Future<void> save() async {
    if (counting) {
      if (image == null) return;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image!, Offset.zero, Paint());
      _RecognitionPainter(
        points: points,
        lines: const [],
        crop: null,
        counting: true,
        imageWidth: width,
        imageHeight: height,
      ).paint(canvas, Size(width.toDouble(), height.toDouble()));
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(width, height);
      picture.dispose();
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      final path = await Files.saveBytes(
        png!.buffer.asUint8List(),
        '计数_${points.length}.png',
      );
      if (mounted && path != null) setState(() => dirty = false);
    } else {
      final path = await Files.saveText(output.text, '识别文字.txt');
      if (mounted && path != null) setState(() => dirty = false);
    }
  }

  void addOrRemove(Offset p) {
    var nearest = -1;
    var distance = .035;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i] - p).distance;
      if (d < distance) {
        nearest = i;
        distance = d;
      }
    }
    setState(() {
      if (nearest >= 0) {
        points.removeAt(nearest);
      } else if (points.length < 1000) {
        points.add(p);
      }
      dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    blocked: busy,
    dirty: dirty,
    onExport: save,
    children: [
      StudioBanner(
        counting ? 'COUNT & CHECK' : 'READ & EDIT',
        widget.tool.name,
        counting ? '自动找出分散区域，再逐个核对标记。' : '框选你需要的文字，识别后继续修改。',
        color: const Color(0xff496f8e),
        icon: widget.tool.icon,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : () => pick(),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('选择图片'),
          ),
          if (defaultTargetPlatform == TargetPlatform.android)
            OutlinedButton.icon(
              onPressed: busy ? null : () => pick(camera: true),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('拍照'),
            ),
        ],
      ),
      if (bytes != null) ...[
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LayoutBuilder(
            builder: (context, box) {
              final h = box.maxWidth * height / width;
              Offset normalized(Offset p) => Offset(
                (p.dx / box.maxWidth).clamp(0, 1),
                (p.dy / h).clamp(0, 1),
              );
              return AspectRatio(
                aspectRatio: width / height,
                child: GestureDetector(
                  onTapDown: counting && !busy
                      ? (d) => addOrRemove(normalized(d.localPosition))
                      : null,
                  onPanStart: !counting && selecting && !busy
                      ? (d) {
                          start = normalized(d.localPosition);
                          setState(() {
                            crop = null;
                            lines.clear();
                          });
                        }
                      : null,
                  onPanUpdate: !counting && selecting && !busy
                      ? (d) {
                          final end = normalized(d.localPosition);
                          setState(() => crop = Rect.fromPoints(start!, end));
                        }
                      : null,
                  onPanEnd: !counting && selecting && !busy
                      ? (_) {
                          if (crop != null &&
                              (crop!.width < .01 || crop!.height < .01)) {
                            setState(() => crop = null);
                          }
                        }
                      : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(bytes!, fit: BoxFit.fill),
                      CustomPaint(
                        painter: _RecognitionPainter(
                          points: points,
                          lines: lines,
                          crop: crop,
                          counting: counting,
                          imageWidth: width,
                          imageHeight: height,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (counting) ...[
          StudioPanel(
            title: '识别设置',
            children: [
              studioChoices(
                ['深色物体', '浅色物体'],
                dark ? '深色物体' : '浅色物体',
                (v) => setState(() => dark = v == '深色物体'),
              ),
              studioSlider(
                '明暗阈值',
                threshold,
                1,
                254,
                (v) => setState(() => threshold = v),
              ),
              studioSlider(
                '过滤小区域',
                minArea,
                10,
                600,
                (v) => setState(() => minArea = v),
                display: '${minArea.round()} px',
              ),
              const Text('适合纯色背景上分散、反差明显的圆片、硬币和颗粒。接触、遮挡或复杂背景可能误计；结果需人工核对。'),
            ],
          ),
          StudioPanel(
            title: '核对结果',
            children: [
              Text(
                '${points.length}',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Text('个标记 · 点空白处添加，点已有标记删除'),
              TextButton(
                onPressed: () => setState(() {
                  points.clear();
                  dirty = true;
                }),
                child: const Text('清空标记'),
              ),
            ],
          ),
        ] else ...[
          SwitchListTile(
            title: const Text('框选文字区域'),
            subtitle: const Text('在图片上拖动；关闭开关后可以查看识别框'),
            value: selecting,
            onChanged: (v) => setState(() => selecting = v),
          ),
          TextButton(
            onPressed: () => setState(() => crop = null),
            child: const Text('恢复整张识别'),
          ),
        ],
        FilledButton.icon(
          onPressed: busy ? null : recognize,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(
            busy
                ? '正在识别…'
                : counting
                ? '自动标记'
                : '识别文字',
          ),
        ),
      ],
      if (busy)
        const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (!counting && bytes != null)
        StudioPanel(
          title: '文字结果 · 可修改',
          children: [
            TextField(
              controller: output,
              minLines: 5,
              maxLines: 14,
              decoration: const InputDecoration(hintText: '识别结果会显示在这里'),
              onChanged: (_) => setState(() => dirty = true),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: output.text.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: output.text),
                          );
                          if (context.mounted) message(context, '已复制');
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('复制'),
                ),
                OutlinedButton.icon(
                  onPressed: output.text.isEmpty ? null : save,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('导出 TXT'),
                ),
              ],
            ),
          ],
        ),
      if (counting && bytes != null)
        OutlinedButton.icon(
          onPressed: busy ? null : save,
          icon: const Icon(Icons.save_alt),
          label: const Text('导出带标记的图片'),
        ),
    ],
  );
}

class _RecognitionPainter extends CustomPainter {
  _RecognitionPainter({
    required this.points,
    required this.lines,
    required this.crop,
    required this.counting,
    required this.imageWidth,
    required this.imageHeight,
  });
  final List<Offset> points;
  final List<Map<String, dynamic>> lines;
  final Rect? crop;
  final bool counting;
  final int imageWidth, imageHeight;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xff43d9b0);
    if (crop != null) {
      canvas.drawRect(
        Rect.fromLTWH(
          crop!.left * size.width,
          crop!.top * size.height,
          crop!.width * size.width,
          crop!.height * size.height,
        ),
        paint,
      );
    }
    for (final line in lines) {
      final b = (line['box'] as List).cast<num>();
      canvas.drawRect(
        Rect.fromLTRB(
          b[0] * size.width / imageWidth,
          b[1] * size.height / imageHeight,
          b[2] * size.width / imageWidth,
          b[3] * size.height / imageHeight,
        ),
        paint,
      );
    }
    final radius = (size.width * .025).clamp(10.0, 36.0);
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      canvas.drawCircle(p, radius, Paint()..color = const Color(0xdd147d73));
      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(color: Colors.white, fontSize: radius),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, p - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RecognitionPainter old) => true;
}
