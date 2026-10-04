import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';
import 'design_widgets.dart';

enum ImageAction { transform, resize, watermark, collage }

class MediaPage extends StatefulWidget {
  const MediaPage({
    super.key,
    required this.tool,
    required this.state,
    this.imageAction = ImageAction.transform,
  });
  final ToolSpec tool;
  final AppState state;
  final ImageAction imageAction;
  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  static const channel = MethodChannel('saisuite/media');
  final fields = <String, TextEditingController>{
    for (final entry in {
      '输出宽度 px': '1024',
      '裁剪 X%': '0',
      '裁剪 Y%': '0',
      '裁剪宽度%': '100',
      '裁剪高度%': '100',
      '文字水印': '',
      '开始时间 s': '0',
      '结束时间 s': '10',
      '截帧时间 s': '0',
      '目标码率 kbps': '2000',
    }.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  final paths = <String>[];
  final outputs = <String>{};
  List<String> names = [];
  Map? info, result;
  bool busy = false, dirty = false, mute = false, flip = false;
  bool frameMode = false;
  String? error;
  String format = 'JPEG', layout = '网格', resolution = '720';
  double quality = 85;
  int rotation = 0, progress = -1;
  Timer? poll;
  bool get video => widget.tool.id == 'A10';
  bool get collage => widget.imageAction == ImageAction.collage;
  @override
  void dispose() {
    poll?.cancel();
    for (final c in fields.values) {
      c.dispose();
    }
    channel.invokeMethod('mediaCleanup', {'paths': outputs.toList()});
    super.dispose();
  }

  Future<void> guard(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : e is PlatformException
              ? e.message ?? e.code
              : '$e',
        );
      }
    } finally {
      poll?.cancel();
      if (mounted) setState(() => busy = false);
    }
  }

  double numeric(String key, {double min = 0, double max = 1e8}) {
    final n = double.tryParse(fields[key]!.text);
    if (n == null || !n.isFinite || n < min || n > max) {
      throw FormatException('$key：请输入 $min—$max 的有效数值');
    }
    return n;
  }

  Future<bool> replaceResult() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('当前结果尚未导出'),
            content: const Text('继续会替换当前结果，请先导出需要保留的文件。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('继续并放弃当前结果'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> pick() async {
    if (!await replaceResult()) return;
    await guard(() async {
      final files = video
          ? [?await FilePicker.pickFile(type: FileType.video)]
          : collage
          ? await FilePicker.pickFiles(type: FileType.image)
          : [?await FilePicker.pickFile(type: FileType.image)];
      if (files.isEmpty) return;
      if (files.length > 9) throw const FormatException('拼图最多 9 张图片');
      if (collage && files.length < 2) {
        throw const FormatException('拼图请选择 2—9 张图片');
      }
      final next = <String>[];
      for (final file in files) {
        next.add(
          await Files.localCopy(
            file,
            maxBytes: video ? 500 * 1024 * 1024 : 30 * 1024 * 1024,
          ),
        );
      }
      Map? metadata;
      if (video) {
        metadata = await channel.invokeMapMethod('videoInfo', {
          'path': next.first,
        });
        fields['结束时间 s']!.text = '${metadata?['duration'] ?? 10}';
      } else {
        metadata = await channel.invokeMapMethod('imageInfo', {
          'path': next.first,
        });
        if (widget.imageAction != ImageAction.resize && !collage) {
          final orientation = metadata?['orientation'];
          final width =
              metadata?[orientation is num && orientation >= 5
                  ? 'height'
                  : 'width'];
          if (width is num) {
            fields['输出宽度 px']!.text = '${width.clamp(16, 4096).toInt()}';
          }
        }
      }
      if (mounted) {
        setState(() {
          paths.clear();
          paths.addAll(next);
          names = files.map((f) => f.name).toList();
          info = metadata;
          result = null;
          dirty = false;
        });
      }
    });
  }

  Future<void> process({bool frame = false}) async {
    if (!await replaceResult()) return;
    await guard(() async {
      if (paths.isEmpty) throw const FormatException('请先选择文件');
      Map? next;
      if (video) {
        if (frame) {
          final seconds = numeric('截帧时间 s');
          if (seconds >= (info?['duration'] as num? ?? 0)) {
            throw const FormatException('截帧时间须小于视频时长');
          }
          next = await channel.invokeMapMethod('videoFrame', {
            'path': paths.first,
            'seconds': seconds,
          });
        } else {
          final start = numeric('开始时间 s'), end = numeric('结束时间 s');
          if (end <= start || end > (info?['duration'] as num? ?? 0)) {
            throw const FormatException('结束时间须大于开始时间且不超过视频时长');
          }
          poll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
            try {
              final p = await channel.invokeMethod<int>('videoProgress');
              if (mounted) setState(() => progress = p ?? -1);
            } catch (_) {}
          });
          next = await channel.invokeMapMethod('videoProcess', {
            'path': paths.first,
            'start': start,
            'end': end,
            'mute': mute,
            'height': int.parse(resolution),
            'bitrate': (numeric('目标码率 kbps', min: 128, max: 20000) * 1000)
                .round(),
          });
        }
      } else {
        if (widget.imageAction == ImageAction.watermark &&
            fields['文字水印']!.text.trim().isEmpty) {
          throw const FormatException('请输入水印文字');
        }
        next = await channel.invokeMapMethod('imageProcess', {
          'paths': paths,
          'width': numeric('输出宽度 px', min: 16, max: 4096).round(),
          'crop': [
            if (widget.imageAction == ImageAction.transform) ...[
              numeric('裁剪 X%', max: 100),
              numeric('裁剪 Y%', max: 100),
              numeric('裁剪宽度%', min: .01, max: 100),
              numeric('裁剪高度%', min: .01, max: 100),
            ] else ...[
              0,
              0,
              100,
              100,
            ],
          ],
          'rotation': widget.imageAction == ImageAction.transform
              ? rotation
              : 0,
          'flip': widget.imageAction == ImageAction.transform && flip,
          'layout': layout,
          'format': format,
          'quality': quality.round(),
          'watermark': widget.imageAction == ImageAction.watermark
              ? fields['文字水印']!.text
              : '',
        });
      }
      if (next == null) throw const FormatException('处理没有产生文件');
      if (mounted) {
        setState(() {
          result = next;
          outputs.add(next!['path'] as String);
          dirty = true;
        });
      }
    });
  }

  Future<void> save() async => guard(() async {
    if (result == null) return;
    final path = result!['path'] as String, extension = path.split('.').last;
    final uri = await channel.invokeMethod<String>('saveOutput', {
      'path': path,
      'name': 'saisuite-result.$extension',
      'mime': extension == 'mp4'
          ? 'video/mp4'
          : extension == 'png'
          ? 'image/png'
          : 'image/jpeg',
    });
    if (uri != null && mounted) {
      setState(() => dirty = false);
      message(context, '已另存为新文件');
    }
  });
  Widget input(String name, {bool text = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: fields[name],
      enabled: !busy,
      maxLength: text ? 128 : null,
      keyboardType: text
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      onChanged: video ? (_) => setState(() {}) : null,
      decoration: InputDecoration(labelText: name),
    ),
  );
  Widget select(
    String label,
    String value,
    List<String> options,
    void Function(String) changed,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: busy ? null : (s) => setState(() => changed(s!)),
    ),
  );
  Future<void> preview(String path) async {
    try {
      await channel.invokeMethod('videoPreview', {'path': path});
    } catch (e) {
      if (mounted) message(context, '预览失败：$e');
    }
  }

  Widget videoWorkbench() {
    final duration = (info?['duration'] as num?)?.toDouble() ?? 0;
    final start = (double.tryParse(fields['开始时间 s']!.text) ?? 0)
        .clamp(0.0, duration)
        .toDouble();
    final end = (double.tryParse(fields['结束时间 s']!.text) ?? duration)
        .clamp(start, duration)
        .toDouble();
    final frame = (double.tryParse(fields['截帧时间 s']!.text) ?? 0)
        .clamp(0.0, duration)
        .toDouble();
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      dirty: dirty,
      blocked: busy,
      onExport: save,
      children: [
        const StudioHeader(
          label: 'VIDEO STUDIO',
          title: '留住精彩的片段',
          subtitle: '剪一段视频，或把一个瞬间变成图片。',
          icon: Icons.movie_outlined,
        ),
        const SizedBox(height: 18),
        StudioPanel(
          title: paths.isEmpty ? '添加你的素材' : names.first,
          icon: Icons.video_library_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (info != null) ...[
                Text(
                  '${duration.toStringAsFixed(1)} 秒 · ${info!['width']} × ${info!['height']} px',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => preview(paths.first),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('预览原视频'),
                ),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Icon(Icons.movie_creation_outlined, size: 56),
                ),
                const Text('选择视频后，可拖动时间轴确定范围。', textAlign: TextAlign.center),
                const SizedBox(height: 16),
              ],
              FilledButton.tonalIcon(
                onPressed: busy ? null : pick,
                icon: const Icon(Icons.add_rounded),
                label: Text(paths.isEmpty ? '选择视频' : '更换视频'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.content_cut),
              label: Text('剪辑导出'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.photo_outlined),
              label: Text('截取画面'),
            ),
          ],
          selected: {frameMode},
          onSelectionChanged: busy
              ? null
              : (v) => setState(() => frameMode = v.first),
        ),
        const SizedBox(height: 18),
        StudioPanel(
          title: frameMode ? '选择一个瞬间' : '选择片段范围',
          icon: frameMode ? Icons.image_search : Icons.timeline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (duration > 0) ...[
                if (frameMode)
                  Slider(
                    value: frame,
                    max: duration,
                    label: '${frame.toStringAsFixed(2)} s',
                    onChanged: busy
                        ? null
                        : (v) => setState(
                            () => fields['截帧时间 s']!.text = v.toStringAsFixed(2),
                          ),
                  )
                else
                  RangeSlider(
                    values: RangeValues(start, end),
                    max: duration,
                    labels: RangeLabels(
                      '${start.toStringAsFixed(2)} s',
                      '${end.toStringAsFixed(2)} s',
                    ),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            fields['开始时间 s']!.text = v.start.toStringAsFixed(2);
                            fields['结束时间 s']!.text = v.end.toStringAsFixed(2);
                          }),
                  ),
                Text(
                  frameMode
                      ? '当前 ${frame.toStringAsFixed(2)} 秒'
                      : '片段 ${(end - start).toStringAsFixed(2)} 秒 / 总长 ${duration.toStringAsFixed(2)} 秒',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              if (frameMode)
                input('截帧时间 s')
              else
                Row(
                  children: [
                    Expanded(child: input('开始时间 s')),
                    const SizedBox(width: 12),
                    Expanded(child: input('结束时间 s')),
                  ],
                ),
            ],
          ),
        ),
        if (!frameMode) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              title: const Text('画质与声音'),
              subtitle: Text(
                '${resolution == '0' ? '原尺寸' : '${resolution}p'} · ${fields['目标码率 kbps']!.text} kbps · ${mute ? '静音' : '保留声音'}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                select('输出高度 px（0 保持原尺寸）', resolution, [
                  '0',
                  '360',
                  '480',
                  '720',
                  '1080',
                ], (s) => resolution = s),
                input('目标码率 kbps'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('静音'),
                  value: mute,
                  onChanged: busy ? null : (v) => setState(() => mute = v),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: busy || paths.isEmpty
              ? null
              : () => process(frame: frameMode),
          icon: Icon(
            frameMode
                ? Icons.photo_camera_outlined
                : Icons.movie_filter_outlined,
          ),
          label: Text(frameMode ? '截取这一帧为 PNG' : '生成视频片段'),
        ),
        if (busy) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress >= 0 && !frameMode ? progress / 100 : null,
          ),
          if (!frameMode)
            TextButton(
              onPressed: () => channel.invokeMethod('videoCancel'),
              child: const Text('取消视频处理'),
            ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (result != null) ...[
          const SizedBox(height: 18),
          StudioPanel(
            title: '片段已准备好',
            icon: Icons.check_circle_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!(result!['path'] as String).endsWith('.mp4'))
                  Image.file(
                    File(result!['path'] as String),
                    height: 240,
                    cacheWidth: 800,
                  ),
                Text(
                  '${((result!['bytes'] as num) / 1024 / 1024).toStringAsFixed(2)} MB${result!['width'] == null ? '' : ' · ${result!['width']} × ${result!['height']} px'}',
                ),
                if ((result!['path'] as String).endsWith('.mp4'))
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => preview(result!['path'] as String),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('预览处理后视频'),
                  ),
                FilledButton.icon(
                  onPressed: busy ? null : save,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('另存为新文件'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('格式与处理说明'),
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                '视频输出 MP4（H.264/AAC），截图输出 PNG。单文件上限 500 MB。编码支持取决于设备；码率是目标值，输出不保证比原件更小。原文件保持不变。',
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => video
      ? videoWorkbench()
      : Workbench(
          tool: widget.tool,
          state: widget.state,
          dirty: dirty,
          blocked: busy,
          onExport: save,
          children: [
            Text(
              video
                  ? '视频处理，原件只读。输出 MP4（H.264/AAC），编码支持取决于设备；码率是目标值，输出不保证比原件更小。单文件上限 500 MB。'
                  : switch (widget.imageAction) {
                      ImageAction.transform => '调整画面范围和方向。裁剪基于原图比例，处理后先预览，再另存。',
                      ImageAction.resize =>
                        '设置输出宽度和文件格式，按比例缩放。单张上限 30 MB，输出长宽最多 4096 px。',
                      ImageAction.watermark => '选择一张图片，为它添加文字标记。原文件保持不变。',
                      ImageAction.collage =>
                        '选择 2—9 张图片，再选择排列方式。每张居中放入等大格子，可调整输出宽度。',
                    },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.file_open),
              label: Text(
                video
                    ? '选择视频'
                    : collage
                    ? '选择 2—9 张图片'
                    : '选择一张图片',
              ),
            ),
            ...names.map((n) => Text(n)),
            if (paths.isNotEmpty && !video)
              Image.file(
                File(paths.first),
                height: 200,
                cacheWidth: 600,
                errorBuilder: (c, e, s) => const Text('输入预览失败，可尝试处理'),
              ),
            if (info != null && !video)
              SelectableText(
                '原图 ${info!["width"]} × ${info!["height"]} px · ${info!["mime"]}\n${info!["bytes"]} 字节 · EXIF 方向码 ${info!["orientation"]}',
              ),
            const SizedBox(height: 16),
            if (!video) ...[
              if (widget.imageAction == ImageAction.transform) ...[
                for (final key in ['裁剪 X%', '裁剪 Y%', '裁剪宽度%', '裁剪高度%'])
                  input(key),
                select('顺时针旋转', '$rotation', [
                  '0',
                  '90',
                  '180',
                  '270',
                ], (s) => rotation = int.parse(s)),
                SwitchListTile(
                  title: const Text('水平翻转'),
                  value: flip,
                  onChanged: busy ? null : (v) => setState(() => flip = v),
                ),
              ],
              if (collage)
                select('拼图排列', layout, ['网格', '横向', '竖向'], (s) => layout = s),
              if (widget.imageAction == ImageAction.watermark)
                input('文字水印', text: true),
              if (widget.imageAction == ImageAction.resize || collage)
                input('输出宽度 px'),
              Card(
                child: ExpansionTile(
                  initiallyExpanded: widget.imageAction == ImageAction.resize,
                  title: const Text('导出设置'),
                  subtitle: Text(
                    '$format · ${format == 'JPEG' ? '质量 ${quality.round()}' : '无损输出'}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    select('输出格式', format, ['JPEG', 'PNG'], (s) => format = s),
                    if (format == 'JPEG') ...[
                      Text('JPEG 质量 ${quality.round()}；透明区域填白'),
                      Slider(
                        value: quality,
                        min: 1,
                        max: 100,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => quality = v),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            FilledButton(
              onPressed: busy || paths.isEmpty ? null : () => process(),
              child: const Text('处理并预览'),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (result != null) ...[
              const SizedBox(height: 20),
              const Text('处理结果'),
              if (!(result!['path'] as String).endsWith('.mp4'))
                Image.file(
                  File(result!['path'] as String),
                  height: 240,
                  cacheWidth: 800,
                ),
              Text(
                '${result!['bytes']} 字节${result!['width'] == null ? '' : ' · ${result!['width']} × ${result!['height']} px'}',
              ),
              if ((result!['path'] as String).endsWith('.mp4'))
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => preview(result!['path'] as String),
                  child: const Text('预览处理后视频'),
                ),
              FilledButton.icon(
                onPressed: busy ? null : save,
                icon: const Icon(Icons.save_alt),
                label: const Text('另存为新文件'),
              ),
            ],
          ],
        );
}
