import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import '../core/palette.dart';
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
  bool busy = false;
  String? error;
  final transform = TransformationController();
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
      const Text('选择图片后点按取色，双指放大或移动。读取原图像素；透明像素同时显示 Alpha。'),
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
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth,
                height = width * image!.height / image!.width;
            return SizedBox(
              height: 360,
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: transform,
                  maxScale: 12,
                  minScale: .25,
                  constrained: false,
                  child: GestureDetector(
                    onTapUp: (d) => sample(d.localPosition, width, height),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: RawImage(image: image, fit: BoxFit.fill),
                    ),
                  ),
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
