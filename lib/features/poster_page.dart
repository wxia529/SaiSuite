import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import '../core/creative_images.dart';
import '../core/image_framing.dart';
import 'catalog.dart';
import 'workbench.dart';
import 'extra_widgets.dart';
import 'canvas_gestures.dart';

const emojiFallback = ['SaiEmoji'];

class PosterSticker {
  PosterSticker(
    this.text, {
    this.position = const Offset(.5, .3),
    this.size = 110,
  });
  String text;
  Offset position;
  double size;
  PosterSticker copy() => PosterSticker(text, position: position, size: size);
}

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
      height = TextEditingController(text: '1080'),
      customSticker = TextEditingController();
  ui.Image? photo;
  bool transparent = false, busy = false, dirty = false;
  double fontSize = 88, stroke = 5, baseSize = 88;
  Color foreground = Colors.white, background = const Color(0xff147d73);
  Offset position = const Offset(.5, .65),
      basePosition = Offset.zero,
      startFocal = Offset.zero,
      photoAnchor = Offset.zero;
  ImageFrame photoFrame = const ImageFrame(), baseFrame = const ImageFrame();
  final stickers = <PosterSticker>[];
  int? selected;
  String template = '正方形', font = '粗体', error = '', editing = '文字';
  @override
  void dispose() {
    photo?.dispose();
    for (final c in [text, width, height, customSticker]) {
      c.dispose();
    }
    super.dispose();
  }

  void change(VoidCallback action) => setState(() {
    action();
    dirty = true;
    error = '';
  });
  void imageSize() {
    if (photo == null) return;
    final image = photo!;
    final scale = math.min(
      1.0,
      math.sqrt(8000000 / (image.width * image.height)),
    );
    width.text = (image.width * scale).floor().clamp(64, 4096).toString();
    height.text = (image.height * scale).floor().clamp(64, 4096).toString();
    template = '按图片尺寸';
    photoFrame = const ImageFrame();
  }

  Future<void> loadPhoto(String path) async {
    final result = await compute(creativeImageJob, {
      'action': 'normalize',
      'bytes': await File(path).readAsBytes(),
      'edge': 2800,
    });
    final codec = await ui.instantiateImageCodec(result['bytes'] as Uint8List);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    change(() {
      final adopt =
          photo == null &&
          template == '正方形' &&
          width.text == '1080' &&
          height.text == '1080';
      photo?.dispose();
      photo = frame.image;
      photoFrame = const ImageFrame();
      if (adopt) imageSize();
      editing = '图片';
      selected = null;
    });
  }

  Future<void> pick() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      await loadPhoto(await Files.localCopy(file, maxBytes: 30 * 1024 * 1024));
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

  Future<Uint8List> renderPng() async {
    final size = canvasSize();
    final recorder = ui.PictureRecorder();
    painter().paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final path = await Files.saveBytes(await renderPng(), '图文制作.png');
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

  PosterPainter painter({bool selection = false}) => PosterPainter(
    text: text.text,
    photo: photo,
    photoFrame: photoFrame,
    foreground: foreground,
    background: background,
    transparent: transparent,
    font: font,
    fontSize: fontSize,
    stroke: stroke,
    position: position,
    stickers: stickers.map((s) => s.copy()).toList(),
    referenceWidth: (double.tryParse(width.text) ?? 1080).clamp(64, 4096),
    editing: selection ? editing : null,
    selected: selected,
  );
  void selectAt(Offset p, Size size) {
    // Selecting "图片" explicitly keeps a text-covered photo easy to reposition.
    if (editing == '图片' && photo != null) return;
    final paint = painter();
    for (var i = stickers.length - 1; i >= 0; i--) {
      if (paint
          .bounds(
            stickers[i].text,
            stickers[i].position,
            stickers[i].size,
            size,
          )
          .inflate(12)
          .contains(p)) {
        setState(() {
          selected = i;
          editing = '贴纸';
        });
        return;
      }
    }
    if (paint
        .bounds(text.text, position, fontSize, size)
        .inflate(12)
        .contains(p)) {
      setState(() {
        editing = '文字';
        selected = null;
      });
    }
  }

  void begin(ScaleStartDetails d, Size size) {
    selectAt(d.localFocalPoint, size);
    startFocal = d.localFocalPoint;
    basePosition = editing == '贴纸' && selected != null
        ? stickers[selected!].position
        : position;
    baseSize = editing == '贴纸' && selected != null
        ? stickers[selected!].size
        : fontSize;
    baseFrame = photoFrame;
    if (editing == '图片' && photo != null) {
      final r = imageCrop(
        photo!.width.toDouble(),
        photo!.height.toDouble(),
        size.width,
        size.height,
        photoFrame,
      );
      photoAnchor = Offset(
        r.left + startFocal.dx / size.width * r.width,
        r.top + startFocal.dy / size.height * r.height,
      );
    }
  }

  void move(ScaleUpdateDetails d, Size size) => change(() {
    if (editing == '图片' && photo != null) {
      final zoom = (baseFrame.zoom * d.scale).clamp(1.0, 8.0);
      final r = imageCrop(
        photo!.width.toDouble(),
        photo!.height.toDouble(),
        size.width,
        size.height,
        ImageFrame(zoom: zoom),
      );
      final left =
          (photoAnchor.dx - d.localFocalPoint.dx / size.width * r.width).clamp(
            0.0,
            photo!.width - r.width,
          );
      final top =
          (photoAnchor.dy - d.localFocalPoint.dy / size.height * r.height)
              .clamp(0.0, photo!.height - r.height);
      photoFrame = ImageFrame(
        zoom: zoom,
        x: (left + r.width / 2) / photo!.width,
        y: (top + r.height / 2) / photo!.height,
      );
      return;
    }
    final delta = d.localFocalPoint - startFocal;
    final p = Offset(
      (basePosition.dx + delta.dx / size.width).clamp(.02, .98),
      (basePosition.dy + delta.dy / size.height).clamp(.02, .98),
    );
    if (editing == '贴纸' && selected != null) {
      stickers[selected!].position = p;
      stickers[selected!].size = (baseSize * d.scale).clamp(20, 360);
    } else {
      position = p;
      fontSize = (baseSize * d.scale).clamp(20, 240);
    }
  });
  void addSticker(String value) {
    value = value.trim();
    if (value.isEmpty) {
      message(context, '请输入 emoji、符号或短文字');
      return;
    }
    if (value.characters.length > 24) {
      message(context, '贴纸最多 24 个字符');
      return;
    }
    if (stickers.length >= 20) {
      message(context, '最多添加 20 个贴纸');
      return;
    }
    final next = value;
    change(() {
      stickers.add(PosterSticker(next));
      selected = stickers.length - 1;
      editing = '贴纸';
    });
    customSticker.clear();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final ratio =
        (double.tryParse(width.text) ?? 1080).clamp(64, 4096) /
        (double.tryParse(height.text) ?? 1080).clamp(64, 4096);
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      dirty: dirty,
      blocked: busy,
      onExport: save,
      children: [
        StudioBanner(
          'TEXT & STICKER',
          '图文制作',
          '照片加字、文字卡片与个性表情，在一张画布上完成。',
          color: const Color(0xffbc6a63),
          icon: widget.tool.icon,
        ),
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420 * math.min(1.0, ratio)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = Size(box.maxWidth, box.maxWidth / ratio);
                  return AspectRatio(
                    aspectRatio: ratio,
                    child: CanvasGestures(
                      key: const ValueKey('poster-canvas'),
                      onStart: busy ? null : (d) => begin(d, size),
                      onUpdate: busy ? null : (d) => move(d, size),
                      child: CustomPaint(
                        painter: transparent ? CheckerPainter() : null,
                        foregroundPainter: painter(selection: true),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in [
              '文字',
              if (photo != null) '图片',
              if (stickers.isNotEmpty) '贴纸',
            ])
              ChoiceChip(
                label: Text('编辑$kind'),
                selected: editing == kind,
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                        editing = kind;
                        if (kind == '贴纸') selected ??= stickers.length - 1;
                      }),
              ),
            if (editing == '图片')
              TextButton(
                onPressed: busy
                    ? null
                    : () => change(() => photoFrame = const ImageFrame()),
                child: const Text('重置取景'),
              ),
            if (editing == '贴纸' && selected != null)
              IconButton(
                tooltip: '删除选中贴纸',
                onPressed: busy
                    ? null
                    : () => change(() {
                        stickers.removeAt(selected!);
                        selected = stickers.isEmpty
                            ? null
                            : stickers.length - 1;
                        if (stickers.isEmpty) editing = '文字';
                      }),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        const Text('单指拖动当前对象，双指缩放；鼠标拖动，大小可用下方滑块调节。选中框与棋盘格不会导出。'),
        if (editing == '图片')
          studioSlider(
            '图片缩放',
            photoFrame.zoom,
            1,
            8,
            (v) => change(
              () => photoFrame = ImageFrame(
                zoom: v,
                x: photoFrame.x,
                y: photoFrame.y,
              ),
            ),
            display: '${photoFrame.zoom.toStringAsFixed(2)}×',
          ),
        if (editing == '贴纸' && selected != null)
          studioSlider(
            '贴纸大小',
            stickers[selected!].size,
            20,
            360,
            (v) => change(() => stickers[selected!].size = v),
          ),
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
              ['正方形', '竖卡片', '横卡片', if (photo != null) '按图片尺寸'],
              template,
              (v) => change(() {
                if (v == '按图片尺寸') {
                  imageSize();
                  return;
                }
                template = v;
                width.text = v == '横卡片' ? '1600' : '1080';
                height.text = v == '竖卡片'
                    ? '1440'
                    : v == '横卡片'
                    ? '900'
                    : '1080';
                photoFrame = const ImageFrame();
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
                    onPressed: busy
                        ? null
                        : () => change(() {
                            photo?.dispose();
                            photo = null;
                            editing = '文字';
                          }),
                    child: const Text('移除图片'),
                  ),
              ],
            ),
          ],
        ),
        StudioPanel(
          title: '自定义贴纸',
          children: [
            TextField(
              key: const ValueKey('poster-custom-sticker'),
              controller: customSticker,
              maxLength: 24,
              style: const TextStyle(fontFamilyFallback: emojiFallback),
              decoration: const InputDecoration(
                labelText: '输入 emoji、符号或短文字',
                hintText: '使用键盘表情，也可以粘贴组合 emoji',
              ),
              onSubmitted: addSticker,
            ),
            FilledButton.tonalIcon(
              onPressed: busy ? null : () => addSticker(customSticker.text),
              icon: const Icon(Icons.add),
              label: const Text('添加自定义贴纸'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final s in [
                  '❤️',
                  '✨',
                  '🎉',
                  '😎',
                  '🥰',
                  '🧪',
                  '🔋',
                  '🌿',
                  '👍',
                  '💯',
                ])
                  ActionChip(
                    label: Text(
                      s,
                      style: const TextStyle(
                        fontSize: 24,
                        fontFamilyFallback: emojiFallback,
                      ),
                    ),
                    onPressed: busy ? null : () => addSticker(s),
                  ),
              ],
            ),
            if (stickers.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('点选要编辑的贴纸'),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < stickers.length; i++)
                    ChoiceChip(
                      label: Text(
                        stickers[i].text,
                        style: const TextStyle(
                          fontFamilyFallback: emojiFallback,
                        ),
                      ),
                      selected: editing == '贴纸' && selected == i,
                      onSelected: (_) => setState(() {
                        selected = i;
                        editing = '贴纸';
                      }),
                    ),
                ],
              ),
              TextButton(
                onPressed: () => change(() {
                  stickers.clear();
                  selected = null;
                  editing = '文字';
                }),
                child: const Text('清空贴纸'),
              ),
            ],
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

  Widget colorChoices(Color current, ValueChanged<Color> change) => Wrap(
    spacing: 9,
    runSpacing: 9,
    children: [
      for (final c in [
        Colors.white,
        Colors.black,
        const Color(0xff147d73),
        const Color(0xfff6bd73),
        const Color(0xffe38097),
        const Color(0xff6478cb),
      ])
        InkWell(
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
    ],
  );
}

class CheckerPainter extends CustomPainter {
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

class PosterPainter extends CustomPainter {
  PosterPainter({
    required this.text,
    required this.photo,
    required this.photoFrame,
    required this.foreground,
    required this.background,
    required this.transparent,
    required this.font,
    required this.fontSize,
    required this.stroke,
    required this.position,
    required this.stickers,
    required this.referenceWidth,
    this.editing,
    this.selected,
  });
  final String text, font;
  final ui.Image? photo;
  final ImageFrame photoFrame;
  final Color foreground, background;
  final bool transparent;
  final double fontSize, stroke, referenceWidth;
  final Offset position;
  final List<PosterSticker> stickers;
  final String? editing;
  final int? selected;
  TextStyle style(double size) => TextStyle(
    fontSize: size,
    fontFamilyFallback: emojiFallback,
    fontWeight: font == '粗体' ? FontWeight.w900 : FontWeight.normal,
    fontFamily: font == '等宽' ? 'monospace' : null,
    height: 1.25,
    color: foreground,
  );
  TextPainter layout(
    String content,
    double fontsize,
    Size size, {
    bool outline = false,
  }) => TextPainter(
    text: TextSpan(
      text: content,
      style: outline
          ? style(fontsize).copyWith(
              color: null,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = stroke * size.width / referenceWidth
                ..color = foreground.computeLuminance() > .5
                    ? Colors.black
                    : Colors.white,
            )
          : style(fontsize),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: size.width * .94);
  Rect bounds(String content, Offset p, double fontsize, Size size) {
    final paint = layout(content, fontsize * size.width / referenceWidth, size);
    final result = Rect.fromCenter(
      center: Offset(p.dx * size.width, p.dy * size.height),
      width: paint.width,
      height: paint.height,
    );
    paint.dispose();
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (!transparent) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background);
    }
    if (photo != null) {
      final image = photo!;
      final r = imageCrop(
        image.width.toDouble(),
        image.height.toDouble(),
        size.width,
        size.height,
        photoFrame,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(r.left, r.top, r.width, r.height),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    void draw(
      String content,
      Offset p,
      double fontsize, {
      bool outline = false,
      bool active = false,
    }) {
      final painter = layout(
        content,
        fontsize * size.width / referenceWidth,
        size,
      );
      final offset = Offset(
        p.dx * size.width - painter.width / 2,
        p.dy * size.height - painter.height / 2,
      );
      if (outline && stroke > 0) {
        final edge = layout(
          content,
          fontsize * size.width / referenceWidth,
          size,
          outline: true,
        );
        edge.paint(canvas, offset);
        edge.dispose();
      }
      painter.paint(canvas, offset);
      if (active && content.isNotEmpty) {
        final r = (offset & painter.size).inflate(6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(5)),
          Paint()
            ..color = const Color(0xfff6bd73)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
          canvas.drawCircle(p, 3, Paint()..color = const Color(0xfff6bd73));
        }
      }
      painter.dispose();
    }

    draw(text, position, fontSize, outline: true, active: editing == '文字');
    for (var i = 0; i < stickers.length; i++) {
      final s = stickers[i];
      draw(
        s.text,
        s.position,
        s.size,
        active: editing == '贴纸' && selected == i,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PosterPainter old) => true;
}
