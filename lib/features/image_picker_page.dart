import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:file_picker/file_picker.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import '../core/palette.dart';
import '../core/dominant_colors.dart';
import 'palette_page.dart';
import 'catalog.dart';
import 'workbench.dart';

class ImagePickerPage extends StatefulWidget {
  const ImagePickerPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<ImagePickerPage> createState() => _ImagePickerPageState();
}

class _ImagePickerPageState extends State<ImagePickerPage> {
  ui.Image? image;
  Uint8List? pixels;
  Color? picked;
  Offset? point;
  bool busy = false, picking = true;
  int? samplingPointer;
  String? error;
  final transform = TransformationController();
  List<Color> dominant = [];
  bool extracting = false;
  Future<void> extract() async {
    if (pixels == null) return;
    setState(() => extracting = true);
    try {
      final sampled = pixels!;
      final values = await compute(dominantColors, sampled);
      if (mounted && identical(sampled, pixels)) {
        setState(() => dominant = values.map(Color.new).toList());
      }
      if (values.isEmpty && mounted) message(context, '图片中没有足够的不透明像素');
    } finally {
      if (mounted) setState(() => extracting = false);
    }
  }

  @override
  void dispose() {
    image?.dispose();
    transform.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final path = await Files.localCopy(file, maxBytes: 20 * 1024 * 1024);
      final bytes = await File(path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      ui.Codec? codec;
      try {
        if (descriptor.width * descriptor.height > 16000000) {
          throw const FormatException('精确取色支持最多 1600 万像素，请先缩小图片');
        }
        codec = await descriptor.instantiateCodec();
        final next = (await codec.getNextFrame()).image;
        final rgba = await next.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (rgba == null) {
          next.dispose();
          throw const FormatException('图片像素读取失败');
        }
        if (!mounted) {
          next.dispose();
          return;
        }
        image?.dispose();
        setState(() {
          image = next;
          pixels = rgba.buffer.asUint8List();
          picked = null;
          dominant = [];
          point = null;
          transform.value = Matrix4.identity();
        });
      } finally {
        codec?.dispose();
        descriptor.dispose();
        buffer.dispose();
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : '无法读取图片：$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void sample(Offset p, double width, double height) {
    final im = image!;
    final x = (p.dx / width * im.width).floor().clamp(0, im.width - 1);
    final y = (p.dy / height * im.height).floor().clamp(0, im.height - 1);
    final at = (y * im.width + x) * 4, bytes = pixels!;
    setState(() {
      picked = Color.fromARGB(
        bytes[at + 3],
        bytes[at],
        bytes[at + 1],
        bytes[at + 2],
      );
      point = Offset(x.toDouble(), y.toDouble());
    });
  }

  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    children: [
      if (image != null) ...[
        OutlinedButton.icon(
          onPressed: extracting || busy ? null : extract,
          icon: const Icon(Icons.palette_outlined),
          label: Text(extracting ? '正在提取主色' : '提取照片主色'),
        ),
        if (dominant.isNotEmpty) ...[
          const Text('照片主色 · 按像素分布提取'),
          Wrap(
            spacing: 10,
            children: [
              for (final c in dominant)
                ActionChip(
                  avatar: CircleAvatar(backgroundColor: c),
                  label: Text(hexColor(c)),
                  onPressed: () => copyResult(context, hexColor(c)),
                ),
            ],
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PalettePage(
                  tool: tools.firstWhere((t) => t.id == 'A01'),
                  state: widget.state,
                  initialColors: dominant,
                ),
              ),
            ),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('用这组颜色打开配色助手'),
          ),
        ],
      ],
      const Text('在取色模式中点按或拖动，圆环标出位置，旁边的放大镜显示原图像素。需要调整画面时切换缩放模式。'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : load,
        icon: const Icon(Icons.image_search),
        label: const Text('选择图片'),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      if (image != null) ...[
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              icon: Icon(Icons.colorize),
              label: Text('取色'),
            ),
            ButtonSegment(
              value: false,
              icon: Icon(Icons.zoom_in),
              label: Text('缩放 / 移动'),
            ),
          ],
          selected: {picking},
          onSelectionChanged: (s) => setState(() {
            picking = s.first;
            samplingPointer = null;
          }),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth,
                height = width * image!.height / image!.width;
            void sampleViewport(Offset position) {
              final scene = transform.toScene(position);
              if (scene.dx >= 0 &&
                  scene.dy >= 0 &&
                  scene.dx < width &&
                  scene.dy < height) {
                sample(scene, width, height);
              }
            }

            Widget viewer = InteractiveViewer(
              transformationController: transform,
              maxScale: 12,
              minScale: .25,
              constrained: false,
              panEnabled: !picking,
              scaleEnabled: !picking,
              child: SizedBox(
                width: width,
                height: height,
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
            );
            if (picking) {
              viewer = RawGestureDetector(
                gestures: {
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        EagerGestureRecognizer
                      >(EagerGestureRecognizer.new, (_) {}),
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (d) {
                    if (samplingPointer != null) return;
                    samplingPointer = d.pointer;
                    sampleViewport(d.localPosition);
                  },
                  onPointerMove: (d) {
                    if (samplingPointer == d.pointer) {
                      sampleViewport(d.localPosition);
                    }
                  },
                  onPointerUp: (d) {
                    if (samplingPointer == d.pointer) samplingPointer = null;
                  },
                  onPointerCancel: (d) {
                    if (samplingPointer == d.pointer) samplingPointer = null;
                  },
                  child: viewer,
                ),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 360,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    viewer,
                    if (point != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: transform,
                            builder: (_, _) => CustomPaint(
                              painter: PickerOverlayPainter(
                                image!,
                                point!,
                                MatrixUtils.transformPoint(
                                  transform.value,
                                  Offset(
                                    (point!.dx + .5) / image!.width * width,
                                    (point!.dy + .5) / image!.height * height,
                                  ),
                                ),
                                picked!,
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
        Text('原图 ${image!.width} × ${image!.height} px'),
      ],
      if (picked != null)
        Card(
          child: ListTile(
            leading: Container(width: 48, height: 48, color: picked),
            title: Text(hexColor(picked!)),
            subtitle: Text(
              'RGB ${(picked!.r * 255).round()}, ${(picked!.g * 255).round()}, ${(picked!.b * 255).round()}\nAlpha ${(picked!.a * 255).round()}；坐标 ${point!.dx.toInt()}, ${point!.dy.toInt()}',
            ),
            trailing: const Icon(Icons.copy),
            onTap: () => copyResult(
              context,
              '${hexColor(picked!)}\nRGBA ${(picked!.r * 255).round()}, ${(picked!.g * 255).round()}, ${(picked!.b * 255).round()}, ${(picked!.a * 255).round()}',
            ),
          ),
        ),
    ],
  );
}

class PickerOverlayPainter extends CustomPainter {
  PickerOverlayPainter(this.image, this.pixel, this.location, this.color);
  final ui.Image image;
  final Offset pixel, location;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (!(Offset.zero & size).contains(location)) return;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final dark = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(location, 16, dark..strokeWidth = 5);
    canvas.drawCircle(location, 16, white);
    canvas.drawCircle(location, 11, dark..strokeWidth = 1.5);
    canvas.drawLine(
      location + const Offset(-22, 0),
      location + const Offset(-10, 0),
      white,
    );
    canvas.drawLine(
      location + const Offset(10, 0),
      location + const Offset(22, 0),
      white,
    );
    canvas.drawLine(
      location + const Offset(0, -22),
      location + const Offset(0, -10),
      white,
    );
    canvas.drawLine(
      location + const Offset(0, 10),
      location + const Offset(0, 22),
      white,
    );
    const radius = 46.0;
    final lens = Offset(
      (location.dx + (location.dx < size.width / 2 ? 85 : -85)).clamp(
        52,
        size.width - 52,
      ),
      (location.dy - 80).clamp(52, size.height - 52),
    );
    canvas.drawCircle(
      lens,
      radius + 5,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: lens, radius: radius)),
    );
    canvas.drawColor(Colors.white, BlendMode.srcOver);
    // A checkerboard makes transparent source pixels distinguishable.
    for (var y = -6; y <= 6; y++) {
      for (var x = -6; x <= 6; x++) {
        if ((x + y).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(lens.dx + x * 8, lens.dy + y * 8, 8, 8),
            Paint()..color = const Color(0xffd9d9d9),
          );
        }
      }
    }
    canvas.translate(lens.dx, lens.dy);
    canvas.scale(8);
    canvas.drawImage(
      image,
      Offset(-pixel.dx - .5, -pixel.dy - .5),
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
    canvas.drawCircle(lens, radius, dark..strokeWidth = 5);
    canvas.drawCircle(lens, radius, white);
    canvas.drawRect(
      Rect.fromCenter(center: lens, width: 8, height: 8),
      dark..strokeWidth = 2.5,
    );
    canvas.drawRect(
      Rect.fromCenter(center: lens, width: 8, height: 8),
      white..strokeWidth = 1,
    );
    canvas.drawCircle(lens + const Offset(0, 39), 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(PickerOverlayPainter old) => true;
}
