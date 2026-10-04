import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import '../core/creative_images.dart';
import 'catalog.dart';
import 'workbench.dart';
import 'extra_widgets.dart';

class PosterPage extends StatefulWidget {
  const PosterPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<PosterPage> createState() => _PosterPageState();
}

class _PosterPageState extends State<PosterPage> {
  final text = TextEditingController(text: '今天也要开心'),
      width = TextEditingController(text: '1080'),
      height = TextEditingController(text: '1080');
  ui.Image? photo;
  bool transparent = false, busy = false, dirty = false;
  double fontSize = 88, stroke = 5;
  Color foreground = Colors.white, background = const Color(0xff147d73);
  Offset position = const Offset(.5, .65);
  final stickers = <({String text, Offset position})>[];
  int? selected;
  String template = '正方形', font = '粗体', error = '';
  @override
  void dispose() {
    photo?.dispose();
    text.dispose();
    width.dispose();
    height.dispose();
    super.dispose();
  }

  void change(VoidCallback action) => setState(() {
    action();
    dirty = true;
    error = '';
  });
  Future<void> pick() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final path = await Files.localCopy(file, maxBytes: 30 * 1024 * 1024);
      final result = await compute(creativeImageJob, {
        'action': 'normalize',
        'bytes': await File(path).readAsBytes(),
        'edge': 3000,
      });
      final codec = await ui.instantiateImageCodec(
        result['bytes'] as Uint8List,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      change(() {
        photo?.dispose();
        photo = frame.image;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Size canvasSize() {
    final w = int.tryParse(width.text) ?? 0, h = int.tryParse(height.text) ?? 0;
    if (w < 64 || h < 64 || w > 4096 || h > 4096 || w * h > 8000000) {
      throw const FormatException('宽高须为 64—4096，总像素不超过 800 万');
    }
    return Size(w.toDouble(), h.toDouble());
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final size = canvasSize();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter().paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final path = await Files.saveBytes(
        data!.buffer.asUint8List(),
        '${widget.tool.name}.png',
      );
      if (mounted && path != null) {
        setState(() => dirty = false);
        message(context, '已导出 PNG');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message.toString() : '$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  _PosterPainter painter() => _PosterPainter(
    text: text.text,
    photo: photo,
    foreground: foreground,
    background: background,
    transparent: transparent,
    font: font,
    fontSize: fontSize,
    stroke: stroke,
    position: position,
    stickers: stickers.toList(),
    referenceWidth: double.tryParse(width.text) ?? 1080,
  );
  @override
  Widget build(BuildContext context) {
    final ratio =
        (double.tryParse(width.text) ?? 1080) /
        (double.tryParse(height.text) ?? 1080).clamp(64, 4096);
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      dirty: dirty,
      blocked: busy,
      onExport: save,
      children: [
        StudioBanner(
          'TYPE & STICKER',
          widget.tool.name,
          '拖动文字与贴纸，让画面表达你的意思。',
          color: const Color(0xffbc6a63),
          icon: widget.tool.icon,
        ),
        const SizedBox(height: 18),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420 * math.min(1.0, ratio.clamp(.2, 5)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: LayoutBuilder(
                builder: (context, box) => AspectRatio(
                  aspectRatio: ratio.clamp(.2, 5),
                  child: GestureDetector(
                    onPanStart: (d) {
                      final p = Offset(
                        d.localPosition.dx / box.maxWidth,
                        d.localPosition.dy /
                            (box.maxWidth / ratio.clamp(.2, 5)),
                      );
                      selected = null;
                      for (var i = stickers.length - 1; i >= 0; i--) {
                        if ((stickers[i].position - p).distance < .13) {
                          selected = i;
                          break;
                        }
                      }
                    },
                    onPanUpdate: (d) => change(() {
                      final delta = Offset(
                        d.delta.dx / box.maxWidth,
                        d.delta.dy / (box.maxWidth / ratio.clamp(.2, 5)),
                      );
                      if (selected == null) {
                        position = clampPosition(position + delta);
                      } else {
                        final old = stickers[selected!];
                        stickers[selected!] = (
                          text: old.text,
                          position: clampPosition(old.position + delta),
                        );
                      }
                    }),
                    child: CustomPaint(
                      painter: transparent ? _CheckerPainter() : null,
                      foregroundPainter: painter(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('在预览中拖动文字或贴纸；透明画布以棋盘格显示，导出时不带棋盘格。'),
        StudioPanel(
          title: '文字与样式',
          children: [
            TextField(
              controller: text,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(labelText: '画面文字'),
              onChanged: (_) => change(() {}),
            ),
            studioChoices(
              ['粗体', '常规', '等宽'],
              font,
              (v) => change(() => font = v),
            ),
            studioSlider(
              '字号',
              fontSize,
              20,
              240,
              (v) => change(() => fontSize = v),
            ),
            studioSlider('描边', stroke, 0, 12, (v) => change(() => stroke = v)),
            const Text('文字颜色'),
            colorChoices(foreground, (c) => change(() => foreground = c)),
            const SizedBox(height: 12),
            const Text('画布颜色'),
            colorChoices(background, (c) => change(() => background = c)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('透明画布'),
              value: transparent,
              onChanged: (v) => change(() => transparent = v),
            ),
          ],
        ),
        StudioPanel(
          title: '画布与图片',
          children: [
            studioChoices(
              ['正方形', '竖卡片', '横卡片'],
              template,
              (v) => change(() {
                template = v;
                width.text = v == '横卡片' ? '1600' : '1080';
                height.text = v == '竖卡片'
                    ? '1440'
                    : v == '横卡片'
                    ? '900'
                    : '1080';
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: width,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '宽度 px'),
                    onChanged: (_) => change(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '高度 px'),
                    onChanged: (_) => change(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : pick,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('添加背景图片'),
                ),
                if (photo != null)
                  TextButton(
                    onPressed: () => change(() {
                      photo?.dispose();
                      photo = null;
                    }),
                    child: const Text('移除图片'),
                  ),
              ],
            ),
          ],
        ),
        StudioPanel(
          title: '贴纸',
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children:
                  ['❤️', '✨', '🎉', '😎', '🥰', '🧪', '🔋', '🌿', '👍', '💯']
                      .map(
                        (s) => ActionChip(
                          label: Text(s, style: const TextStyle(fontSize: 24)),
                          onPressed: stickers.length >= 20
                              ? null
                              : () => change(
                                  () => stickers.add((
                                    text: s,
                                    position: const Offset(.5, .3),
                                  )),
                                ),
                        ),
                      )
                      .toList(),
            ),
            TextButton(
              onPressed: () => change(stickers.clear),
              child: const Text('清空贴纸'),
            ),
          ],
        ),
        if (error.isNotEmpty)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton.icon(
          onPressed: busy ? null : save,
          icon: const Icon(Icons.save_alt),
          label: Text(busy ? '正在导出…' : '导出 PNG'),
        ),
      ],
    );
  }

  Offset clampPosition(Offset p) =>
      Offset(p.dx.clamp(.02, .98), p.dy.clamp(.02, .98));
  Widget colorChoices(Color current, void Function(Color) change) => Wrap(
    spacing: 9,
    runSpacing: 9,
    children:
        [
              Colors.white,
              Colors.black,
              const Color(0xff147d73),
              const Color(0xfff6bd73),
              const Color(0xffe38097),
              const Color(0xff6478cb),
            ]
            .map(
              (c) => InkWell(
                onTap: () => change(c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: current == c
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                      width: current == c ? 3 : 1,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
  );
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0.0; y < size.height; y += 16) {
      for (var x = 0.0; x < size.width; x += 16) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, 16, 16),
          Paint()
            ..color = (x ~/ 16 + y ~/ 16) % 2 == 0
                ? const Color(0xffdddddd)
                : const Color(0xfffafafa),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _PosterPainter extends CustomPainter {
  _PosterPainter({
    required this.text,
    required this.photo,
    required this.foreground,
    required this.background,
    required this.transparent,
    required this.font,
    required this.fontSize,
    required this.stroke,
    required this.position,
    required this.stickers,
    required this.referenceWidth,
  });
  final String text, font;
  final ui.Image? photo;
  final Color foreground, background;
  final bool transparent;
  final double fontSize, stroke, referenceWidth;
  final Offset position;
  final List<({String text, Offset position})> stickers;
  @override
  void paint(Canvas canvas, Size size) {
    if (!transparent) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background);
    }
    if (photo != null) {
      final image = photo!;
      final scale = math.max(
        size.width / image.width,
        size.height / image.height,
      );
      final sw = size.width / scale, sh = size.height / scale;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH((image.width - sw) / 2, (image.height - sh) / 2, sw, sh),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    final scale = size.width / referenceWidth.clamp(64, 4096);
    void draw(
      String content,
      Offset p,
      double fontsize, {
      bool outline = false,
    }) {
      final style = TextStyle(
        fontSize: fontsize,
        fontWeight: font == '粗体' ? FontWeight.w900 : FontWeight.normal,
        fontFamily: font == '等宽' ? 'monospace' : null,
        height: 1.25,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: content,
          style: style.copyWith(color: foreground),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: size.width * .94);
      final offset = Offset(
        p.dx * size.width - painter.width / 2,
        p.dy * size.height - painter.height / 2,
      );
      if (outline && stroke > 0) {
        final edge = TextPainter(
          text: TextSpan(
            text: content,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = stroke * scale
                ..color = foreground.computeLuminance() > .5
                    ? Colors.black
                    : Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout(maxWidth: size.width * .94);
        edge.paint(canvas, offset);
      }
      painter.paint(canvas, offset);
    }

    draw(text, position, fontSize * scale, outline: true);
    for (final sticker in stickers) {
      draw(sticker.text, sticker.position, 110 * scale);
    }
  }

  @override
  bool shouldRepaint(covariant _PosterPainter old) => true;
}
