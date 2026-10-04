import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/creative_images.dart';
import '../core/image_framing.dart';
import '../core/files.dart';
import '../core/platform_channel.dart';
import 'catalog.dart';
import 'workbench.dart';
import 'extra_widgets.dart';
import 'image_framing_preview.dart';

const creativeChannel = SaiChannel('saisuite/creative');

class ImageStudioPage extends StatefulWidget {
  const ImageStudioPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<ImageStudioPage> createState() => _ImageStudioPageState();
}

class _ImageStudioPageState extends State<ImageStudioPage> {
  final width = TextEditingController(text: '1080'),
      height = TextEditingController(text: '1080');
  final hex = TextEditingController(text: '#F9B77E');
  final fields = {
    for (final s in ['拍摄时间', '作者', '版权', '描述']) s: TextEditingController(),
  };
  final images = <String>[], durations = <int>[], owned = <String>[];
  final frames = <ImageFrame?>[];
  ui.Image? framingImage, otherImage;
  Size? framingSize, otherSize;
  ImageFrame framing = const ImageFrame(), otherFraming = const ImageFrame();
  List<int> colors = [0xff147d73, 0xff7595d8, 0xffe5adbc];
  String? source, other;
  String mode = '合成 GIF', error = '', note = '', outputName = '';
  Map<String, dynamic> metadata = {};
  Uint8List? output, preview;
  bool busy = false, saved = false, loop = true, white = true;
  double angle = 45, noise = 0, edge = 480, frameTime = 200;
  Timer? debounce;
  int revision = 0, timingVersion = 0;
  String get id => widget.tool.id;
  @override
  void initState() {
    super.initState();
    if (id == 'B07') mode = '修改信息';
    if (id == 'B01') Future.microtask(generate);
  }

  @override
  void dispose() {
    debounce?.cancel();
    framingImage?.dispose();
    otherImage?.dispose();
    width.dispose();
    height.dispose();
    hex.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    for (final p in owned) {
      File(p).delete().catchError((_) => File(p));
    }
    super.dispose();
  }

  void invalidate(void Function() change, {bool live = false}) {
    setState(() {
      revision++;
      change();
      output = null;
      error = '';
      saved = false;
    });
    if (live) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted && !busy) generate();
      });
    }
  }

  Future<void> guarded(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is FormatException ? e.message.toString() : '$e';
          output = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick({bool second = false, bool multi = false}) =>
      guarded(() async {
        if (multi) {
          final picked = await FilePicker.pickFiles(type: FileType.image);
          if (picked.isEmpty || !mounted) return;
          if (images.length + picked.length > 60) {
            throw const FormatException('最多 60 帧');
          }
          for (final file in picked) {
            images.add(await Files.localCopy(file, maxBytes: 30 * 1024 * 1024));
            durations.add(frameTime.round());
            frames.add(null);
          }
          setState(() {
            output = null;
            preview = null;
          });
          return;
        }
        final picked = await FilePicker.pickFile(
          type: id == 'B10' ? FileType.video : FileType.image,
        );
        if (picked == null || !mounted) return;
        final path = await Files.localCopy(
          picked,
          maxBytes: id == 'B10' ? 100 * 1024 * 1024 : 30 * 1024 * 1024,
        );
        final loaded = id == 'B02' || id == 'B06'
            ? await loadFraming(path)
            : null;
        if (loaded != null && id == 'B02' && loaded.size.shortestSide < 3) {
          loaded.image.dispose();
          throw const FormatException('图片至少需要 3 × 3 像素');
        }
        if (!mounted) {
          loaded?.image.dispose();
          return;
        }
        setState(() {
          second ? other = path : source = path;
          output = null;
          preview = null;
          metadata = {};
          saved = false;
          if (loaded != null) {
            if (second) {
              otherImage?.dispose();
              otherImage = loaded.image;
              otherSize = loaded.size;
              otherFraming = const ImageFrame();
            } else {
              framingImage?.dispose();
              framingImage = loaded.image;
              framingSize = loaded.size;
              framing = const ImageFrame();
            }
          }
        });
        if (id == 'B07') {
          final result = await creativeChannel.invokeMapMethod<String, dynamic>(
            'exifRead',
            {'path': path},
          );
          if (mounted) {
            setState(() {
              metadata = result ?? {};
              for (final e in fields.entries) {
                e.value.text = '${metadata[e.key] ?? ''}';
              }
            });
          }
        }
        if (id == 'B02') await doGenerate();
      });
  Future<void> generate() => guarded(doGenerate);
  Future<({ui.Image image, Size size})> loadFraming(String path) async {
    final result = await compute(creativeImageJob, {
      'action': 'normalize',
      'bytes': await File(path).readAsBytes(),
      'edge': 1400,
    });
    final codec = await ui.instantiateImageCodec(result['bytes'] as Uint8List);
    try {
      return (
        image: (await codec.getNextFrame()).image,
        size: Size(
          (result['sourceWidth'] as int).toDouble(),
          (result['sourceHeight'] as int).toDouble(),
        ),
      );
    } finally {
      codec.dispose();
    }
  }

  Widget framingPanel(
    String title,
    ui.Image image,
    Size sourceSize,
    ImageFrame frame,
    ValueChanged<ImageFrame> changed, {
    double ratio = 1,
    bool grid = false,
  }) => StudioPanel(
    title: title,
    children: [
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420 * math.min(1.0, ratio)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ImageFramingPreview(
              key: ValueKey('framing-$title'),
              image: image,
              sourceSize: sourceSize,
              value: frame,
              ratio: ratio,
              grid: grid,
              onChanged: busy ? null : changed,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text('单指拖动、双指缩放；鼠标拖动，滚轮缩放。保持原比例，边缘不留空。'),
      studioSlider(
        '取景缩放',
        frame.zoom,
        1,
        grid ? (sourceSize.shortestSide / 3).clamp(1.0, 8.0) : 8,
        (v) => changed(ImageFrame(zoom: v, x: frame.x, y: frame.y)),
        display: '${frame.zoom.toStringAsFixed(2)}×',
      ),
      TextButton(
        onPressed: busy ? null : () => changed(const ImageFrame()),
        child: const Text('重置取景'),
      ),
      if (grid) const Text('1—9 为导出顺序。取景后点击生成预览，导出位置与这里一致。'),
    ],
  );
  Future<void> adjustFrame(int index) => guarded(() async {
    final loaded = await loadFraming(images[index]);
    try {
      if (!mounted) return;
      var frame = frames[index] ?? const ImageFrame();
      var crop = frames[index] != null;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: Text('第 ${index + 1} 帧取景'),
            scrollable: true,
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  studioChoices(
                    ['完整保留', '填满裁切'],
                    crop ? '填满裁切' : '完整保留',
                    (v) => refresh(() => crop = v == '填满裁切'),
                  ),
                  const SizedBox(height: 12),
                  if (crop)
                    ImageFramingPreview(
                      image: loaded.image,
                      sourceSize: loaded.size,
                      value: frame,
                      onChanged: (f) => refresh(() => frame = f),
                    )
                  else
                    AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(
                        color: Colors.white,
                        child: RawImage(
                          image: loaded.image,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  if (crop)
                    studioSlider(
                      '缩放',
                      frame.zoom,
                      1,
                      8,
                      (v) => refresh(
                        () =>
                            frame = ImageFrame(zoom: v, x: frame.x, y: frame.y),
                      ),
                    ),
                  const Text('拖动图片调整内容，双指或滚轮缩放；完整保留不会裁掉横图或竖图。'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => refresh(() => frame = const ImageFrame()),
                child: const Text('重置'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('应用'),
              ),
            ],
          ),
        ),
      );
      if (accepted == true && mounted) {
        invalidate(() => frames[index] = crop ? frame : null);
      }
    } finally {
      loaded.image.dispose();
    }
  });
  Future<void> doGenerate() async {
    final requestedRevision = revision;
    Map<String, dynamic> result;
    if (id == 'B07' || id == 'B10') {
      if (source == null) throw const FormatException('请先选择文件');
      final value = await creativeChannel.invokeMapMethod<String, dynamic>(
        id == 'B07' ? 'exifWrite' : 'extractAudio',
        {
          'path': source,
          'clear': mode == '清除 EXIF',
          'fields': {for (final e in fields.entries) e.key: e.value.text},
        },
      );
      final path = value?['path'] as String?;
      if (path == null) throw const FormatException('没有生成输出文件');
      owned.add(path);
      if (await File(path).length() > 64 * 1024 * 1024) {
        throw const FormatException('结果超过 64 MB 导出上限');
      }
      result = {'bytes': await File(path).readAsBytes()};
      outputName = id == 'B07' ? '照片信息.jpg' : '提取音频.m4a';
    } else {
      final a = <String, dynamic>{};
      if (id == 'B01') {
        a.addAll({
          'action': 'gradient',
          'width': int.tryParse(width.text) ?? 0,
          'height': int.tryParse(height.text) ?? 0,
          'colors': colors,
          'angle': angle,
          'noise': noise,
        });
        outputName = '渐变图.png';
      } else if (id == 'B03' && mode == '合成 GIF') {
        if (images.length < 2) throw const FormatException('请选择至少两张图片');
        var total = 0;
        final bytes = <Uint8List>[];
        for (final path in images) {
          total += await File(path).length();
          if (total > 60 * 1024 * 1024) {
            throw const FormatException('合成素材合计不能超过 60 MB');
          }
          bytes.add(await File(path).readAsBytes());
        }
        a.addAll({
          'action': 'gifMake',
          'images': bytes,
          'durations': durations,
          'edge': edge.round(),
          'loop': loop,
          'frames': frames.map((f) => f?.toMap()).toList(),
        });
        outputName = '合成动画.gif';
      } else {
        if (source == null) throw const FormatException('请先选择图片');
        a['bytes'] = await File(source!).readAsBytes();
        if (id == 'B02') {
          a.addAll({'action': 'grid', 'frame': framing.toMap()});
          outputName = '九格切图.zip';
        }
        if (id == 'B03') {
          a['action'] = 'gifSplit';
          outputName = 'GIF拆帧.zip';
        }
        if (id == 'B06') {
          if (other == null) throw const FormatException('请再选择暗背景显示的图片');
          a.addAll({
            'action': 'phantom',
            'other': await File(other!).readAsBytes(),
            'frame': framing.toMap(),
            'otherFrame': otherFraming.toMap(),
          });
          outputName = '幻影坦克.png';
        }
      }
      result = await compute(creativeImageJob, a);
    }
    if (mounted && requestedRevision == revision) {
      setState(() {
        output = result['bytes'] as Uint8List;
        preview =
            (result['preview'] ??
                    (outputName.endsWith('.png') || outputName.endsWith('.gif')
                        ? output
                        : null))
                as Uint8List?;
        note = result.containsKey('tile')
            ? '每格 ${result['tile']} × ${result['tile']} px · 1—9 顺序编号'
            : result.containsKey('frames')
            ? '${result['frames']} 帧 · 附每帧时长文件'
            : '';
        saved = false;
      });
    }
  }

  Future<void> save() async {
    if (output == null) return;
    try {
      final path = await Files.saveBytes(output!, outputName);
      if (mounted && path != null) {
        setState(() => saved = true);
        message(context, '已导出新文件');
      }
    } catch (e) {
      if (mounted) message(context, '$e');
    }
  }

  Widget sourceCard(String title, String? path, VoidCallback action) => Card(
    child: InkWell(
      onTap: busy ? null : action,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (path != null && id != 'B10')
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(path),
                  width: 65,
                  height: 65,
                  fit: BoxFit.contain,
                  cacheWidth: 160,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image_not_supported),
                ),
              )
            else
              Icon(
                id == 'B10'
                    ? Icons.music_video
                    : Icons.add_photo_alternate_outlined,
                size: 36,
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    path?.split(RegExp(r'[/\\]')).last ?? '点击选择',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    blocked: busy,
    dirty: output != null && !saved,
    onExport: save,
    children: [
      StudioBanner(
        'IMAGE STUDIO',
        widget.tool.name,
        widget.tool.description,
        color: const Color(0xff75618b),
        icon: widget.tool.icon,
      ),
      const SizedBox(height: 16),
      if (id == 'B03')
        studioChoices(
          ['合成 GIF', '分解 GIF'],
          mode,
          (s) => invalidate(() {
            mode = s;
            preview = null;
          }),
        ),
      if (id != 'B01' && !(id == 'B03' && mode == '合成 GIF'))
        sourceCard(
          id == 'B06'
              ? '亮背景显示的图片'
              : id == 'B10'
              ? '选择含音轨的视频'
              : '选择图片',
          source,
          () => pick(),
        ),
      if (id == 'B06') sourceCard('暗背景显示的图片', other, () => pick(second: true)),
      if (id == 'B01')
        StudioPanel(
          title: '颜色与画布',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors
                  .asMap()
                  .entries
                  .map(
                    (e) => InputChip(
                      label: Text(
                        '#${e.value.toRadixString(16).substring(2).toUpperCase()}',
                        style: TextStyle(
                          color: Color(e.value).computeLuminance() > .4
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                      backgroundColor: Color(e.value),
                      onDeleted: colors.length > 2
                          ? () => invalidate(
                              () => colors.removeAt(e.key),
                              live: true,
                            )
                          : null,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: hex,
                    decoration: const InputDecoration(
                      labelText: '添加颜色 #RRGGBB',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: colors.length >= 8
                      ? null
                      : () {
                          final value = hex.text.replaceAll('#', '');
                          if (!RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(value)) {
                            message(context, '请输入六位 HEX 色值');
                            return;
                          }
                          invalidate(
                            () => colors.add(
                              0xff000000 | int.parse(value, radix: 16),
                            ),
                            live: true,
                          );
                        },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            studioSlider(
              '角度',
              angle,
              0,
              360,
              (v) => invalidate(() => angle = v, live: true),
              display: '${angle.round()}°',
            ),
            studioSlider(
              '颗粒噪点',
              noise,
              0,
              60,
              (v) => invalidate(() => noise = v, live: true),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: width,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '宽度 px'),
                    onChanged: (_) => invalidate(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '高度 px'),
                    onChanged: (_) => invalidate(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            studioChoices(
              ['正方形', '手机壁纸', '横向'],
              width.text == height.text
                  ? '正方形'
                  : (int.tryParse(width.text) ?? 0) <
                        (int.tryParse(height.text) ?? 0)
                  ? '手机壁纸'
                  : '横向',
              (s) => invalidate(() {
                width.text = s == '横向' ? '1920' : '1080';
                height.text = s == '手机壁纸' ? '1920' : '1080';
              }, live: true),
            ),
          ],
        ),
      if (id == 'B02' && framingImage != null)
        framingPanel(
          '拖动调整九格画面',
          framingImage!,
          framingSize!,
          framing,
          (f) => invalidate(() => framing = f),
          grid: true,
        ),
      if (id == 'B06' && framingImage != null)
        framingPanel(
          '亮图取景',
          framingImage!,
          framingSize!,
          framing,
          (f) => invalidate(() => framing = f),
          ratio: framingSize!.aspectRatio,
        ),
      if (id == 'B06' && otherImage != null && framingSize != null)
        framingPanel(
          '暗图取景 · 与亮图比例一致',
          otherImage!,
          otherSize!,
          otherFraming,
          (f) => invalidate(() => otherFraming = f),
          ratio: framingSize!.aspectRatio,
        ),
      if (id == 'B03' && mode == '合成 GIF')
        StudioPanel(
          title: '动画帧 · ${images.length}/60',
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : () => pick(multi: true),
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('添加图片'),
            ),
            ...images.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Image.file(
                          File(e.value),
                          width: 42,
                          height: 42,
                          fit: BoxFit.contain,
                          cacheWidth: 100,
                        ),
                        const SizedBox(width: 10),
                        Text('${e.key + 1}'),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('${e.value}-${e.key}-$timingVersion'),
                            initialValue: '${durations[e.key]}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '时长 ms',
                            ),
                            onChanged: (s) => invalidate(
                              () => durations[e.key] = int.tryParse(s) ?? 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: '调整帧画面',
                          onPressed: busy ? null : () => adjustFrame(e.key),
                          icon: const Icon(Icons.crop),
                        ),
                        IconButton(
                          tooltip: '向前移动',
                          onPressed: busy || e.key == 0
                              ? null
                              : () => invalidate(() {
                                  final p = images.removeAt(e.key),
                                      d = durations.removeAt(e.key);
                                  images.insert(e.key - 1, p);
                                  durations.insert(e.key - 1, d);
                                  final f = frames.removeAt(e.key);
                                  frames.insert(e.key - 1, f);
                                }),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: '移除',
                          onPressed: busy
                              ? null
                              : () => invalidate(() {
                                  images.removeAt(e.key);
                                  durations.removeAt(e.key);
                                  frames.removeAt(e.key);
                                }),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            studioSlider(
              '统一帧时长',
              frameTime,
              20,
              1000,
              (v) => setState(() => frameTime = v),
              display: '${frameTime.round()} ms',
            ),
            TextButton(
              onPressed: () => invalidate(() {
                for (var i = 0; i < durations.length; i++) {
                  durations[i] = frameTime.round();
                }
                timingVersion++;
              }),
              child: const Text('应用到全部帧'),
            ),
            studioSlider(
              '输出边长',
              edge,
              64,
              640,
              (v) => invalidate(() => edge = v),
              display: '${edge.round()} px',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('循环播放'),
              value: loop,
              onChanged: (v) => invalidate(() => loop = v),
            ),
            const Text('默认完整保留图片比例、空白填白；点击每帧裁切按钮可拖动、缩放取景。每帧 20—10000 ms。'),
          ],
        ),
      if (id == 'B07' && source != null) ...[
        StudioPanel(
          title: '照片信息',
          children: [
            ...metadata.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${e.key}：${e.value.toString().isEmpty ? '未记录' : e.value}',
                ),
              ),
            ),
          ],
        ),
        StudioPanel(
          title: '编辑副本',
          children: [
            studioChoices(
              ['修改信息', '清除 EXIF'],
              mode,
              (v) => invalidate(() => mode = v),
            ),
            const SizedBox(height: 12),
            if (mode != '清除 EXIF')
              ...fields.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: e.value,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: e.key,
                      hintText: e.key == '拍摄时间' ? 'YYYY:MM:DD HH:MM:SS' : null,
                    ),
                    onChanged: (_) => invalidate(() {}),
                  ),
                ),
              ),
            const Text(
              '仅支持 JPEG。文字字段使用英文、数字与半角符号。清除 EXIF 会保留显示方向；其他元数据（如 XMP）不在此操作范围内。原件不会被修改。',
            ),
          ],
        ),
      ],
      if (id == 'B10')
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '导出 M4A。Android 直接提取 AAC 音轨；其他音轨可先用视频工具转换为 MP4。Windows 会转换音轨为 AAC。无音轨的视频会明确提示。',
          ),
        ),
      if (id == 'B06')
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('输出透明灰度 PNG，亮背景与暗背景呈现不同内容。部分聊天软件会改变透明度，保存后请用两种背景查看。'),
        ),
      FilledButton.icon(
        onPressed: busy ? null : generate,
        icon: const Icon(Icons.auto_awesome_outlined),
        label: Text(
          busy
              ? '正在处理…'
              : id == 'B10'
              ? '提取音轨'
              : '生成预览',
        ),
      ),
      if (busy)
        const Padding(
          padding: EdgeInsets.all(20),
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
      if (preview != null)
        StudioPanel(
          title: '实际输出预览',
          children: [
            if (id == 'B06')
              studioChoices(
                ['白背景', '黑背景'],
                white ? '白背景' : '黑背景',
                (v) => setState(() => white = v == '白背景'),
              ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: id == 'B06'
                    ? (white ? Colors.white : Colors.black)
                    : const Color(0xffe8e8e8),
                child: Stack(
                  children: [
                    Image.memory(
                      preview!,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                    if (id == 'B02')
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(note),
              ),
          ],
        ),
      if (output != null)
        OutlinedButton.icon(
          onPressed: busy ? null : save,
          icon: const Icon(Icons.save_alt),
          label: Text(
            '导出 $outputName · ${(output!.length / 1048576).toStringAsFixed(2)} MB',
          ),
        ),
    ],
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    for (var i = 1; i < 3; i++) {
      c.drawLine(
        Offset(s.width * i / 3, 0),
        Offset(s.width * i / 3, s.height),
        paint,
      );
      c.drawLine(
        Offset(0, s.height * i / 3),
        Offset(s.width, s.height * i / 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
