import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/palette.dart';
import '../core/engine.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';

class PalettePage extends StatefulWidget {
  const PalettePage({
    super.key,
    required this.tool,
    required this.state,
    this.initialColors,
  });
  final List<Color>? initialColors;
  final ToolSpec tool;
  final AppState state;
  @override
  State<PalettePage> createState() => _PalettePageState();
}

class _PalettePageState extends State<PalettePage> {
  final input = TextEditingController(text: '#147D73');
  final random = math.Random();
  String kind = '互补色', format = 'HEX', title = '你的配色';
  Color color = const Color(0xff147d73);
  List<Color>? preset;
  String? error;
  final locked = List<bool>.filled(8, false);
  int colorCount = 5;
  bool exporting = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialColors != null && widget.initialColors!.isNotEmpty) {
      preset = List.of(widget.initialColors!.take(8));
      colorCount = preset!.length;
      title = '照片主色';
      color = preset!.first;
      input.text = encoded(color);
    }
  }

  List<Color> get currentColors =>
      preset ?? designPalette(color, kind).take(colorCount).toList();
  void randomize() {
    final generated = randomPalette(random);
    final old = currentColors;
    setState(() {
      preset = List.generate(colorCount, (i) {
        if (locked[i] && i < old.length) return old[i];
        final base = generated.colors[i % generated.colors.length];
        if (i < generated.colors.length) return base;
        final hsl = HSLColor.fromColor(base);
        return hsl
            .withHue((hsl.hue + 25) % 360)
            .withLightness((hsl.lightness + .12).clamp(.08, .92))
            .toColor();
      });
      color = preset!.first;
      input.text = encoded(color);
      title = '随机灵感';
      error = null;
    });
  }

  Future<void> editColor(int index) async {
    final controller = TextEditingController(
      text: hexColor(currentColors[index]),
    );
    String? invalid;
    final chosen = await showDialog<Color>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) => AlertDialog(
          title: const Text('调整单色'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'HEX 色值',
              errorText: invalid,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final value = runTool('T08', {
                    '格式': 'HEX',
                    '颜色': controller.text,
                  });
                  Navigator.pop(c, parseHex(value.split('\n').first));
                } on FormatException catch (e) {
                  refresh(() => invalid = e.message.toString());
                }
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    // Wait for the closing animation before disposing the dialog field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (chosen != null && mounted) {
      setState(() {
        preset = List.of(currentColors);
        preset![index] = chosen;
      });
    }
  }

  Future<void> exportCard() async {
    setState(() => exporting = true);
    try {
      final colors = currentColors, recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder), height = colors.length * 160 + 80;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 960, height.toDouble()),
        Paint()..color = Colors.white,
      );
      for (var i = 0; i < colors.length; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(40, 40 + i * 160, 300, 136),
            const Radius.circular(18),
          ),
          Paint()..color = colors[i],
        );
        final c = colors[i];
        final text = TextPainter(
          text: TextSpan(
            text:
                '${hexColor(c)}\nRGB ${(c.r * 255).round()}, ${(c.g * 255).round()}, ${(c.b * 255).round()}',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 30,
              height: 1.6,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 560);
        text.paint(canvas, Offset(380, 60 + i * 160.0));
        text.dispose();
      }
      final picture = recorder.endRecording();
      final output = await picture.toImage(960, height);
      try {
        final data = (await output.toByteData(format: ui.ImageByteFormat.png))!;
        final uri = await Files.saveBytes(
          data.buffer.asUint8List(),
          'saisuite-palette.png',
        );
        if (uri != null && mounted) message(context, '色卡已导出');
      } finally {
        output.dispose();
        picture.dispose();
      }
    } catch (e) {
      if (mounted) message(context, '色卡导出失败：$e');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void update() {
    try {
      final output = runTool('T08', {'格式': format, '颜色': input.text});
      setState(() {
        color = parseHex(output.split('\n').first);
        preset = null;
        colorCount = 5;
        locked.fillRange(0, 8, false);
        title = '你的配色';
        error = null;
      });
    } catch (e) {
      setState(() => error = e is FormatException ? e.message : '$e');
    }
  }

  String encoded(Color c) {
    final h = HSLColor.fromColor(c);
    return format == 'HEX'
        ? hexColor(c)
        : format == 'RGB'
        ? '${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()}'
        : '${h.hue.toStringAsFixed(1)},${(h.saturation * 100).toStringAsFixed(1)},${(h.lightness * 100).toStringAsFixed(1)}';
  }

  void usePreset(PalettePreset p, {bool generated = false}) => setState(() {
    color = p.colors.first;
    preset = List.of(p.colors);
    colorCount = preset!.length;
    locked.fillRange(0, 8, false);
    error = null;
    if (generated) kind = p.name;
    title = generated ? '随机灵感' : p.name;
    input.text = encoded(color);
  });

  Widget strip(List<Color> colors, double height) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      height: height,
      child: Row(
        children: colors
            .map(
              (c) => Expanded(
                child: ColoredBox(color: c, child: const SizedBox.expand()),
              ),
            )
            .toList(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = currentColors;
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COLOR STUDIO',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(letterSpacing: 2),
                  ),
                  const SizedBox(height: 4),
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('random-palette'),
              onPressed: randomize,
              icon: const Icon(Icons.casino_outlined),
              label: const Text('随机灵感'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        strip(colors, 110),
        const SizedBox(height: 12),
        const Text('锁定喜欢的颜色，再随机其余颜色。长按拖动换位，点按色值复制。'),
        Row(
          children: [
            const Text('颜色数量'),
            const Spacer(),
            IconButton(
              tooltip: '减少颜色',
              onPressed: colorCount <= 2
                  ? null
                  : () => setState(() {
                      preset = List.of(colors)..removeLast();
                      colorCount--;
                      locked[colorCount] = false;
                    }),
              icon: const Icon(Icons.remove),
            ),
            Text('$colorCount'),
            IconButton(
              tooltip: '增加颜色',
              onPressed: colorCount >= 8
                  ? null
                  : () => setState(() {
                      preset = [...colors, randomPalette(random).colors.first];
                      colorCount++;
                    }),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (_, box) {
            final count = box.maxWidth >= 540
                ? 5
                : box.maxWidth >= 360
                ? 3
                : 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: colors.indexed.map((entry) {
                final (index, c) = entry;
                return SizedBox(
                  width: (box.maxWidth - (count - 1) * 10) / count,
                  child: DragTarget<int>(
                    onWillAcceptWithDetails: (d) => d.data != index,
                    onAcceptWithDetails: (d) => setState(() {
                      preset = List.of(colors);
                      final old = preset![index];
                      preset![index] = preset![d.data];
                      preset![d.data] = old;
                      final lock = locked[index];
                      locked[index] = locked[d.data];
                      locked[d.data] = lock;
                    }),
                    builder: (context, candidate, rejected) =>
                        LongPressDraggable<int>(
                          data: index,
                          feedback: SizedBox(
                            width: 80,
                            height: 80,
                            child: ColoredBox(color: c),
                          ),
                          child: Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => copyResult(context, hexColor(c)),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 62,
                                    width: double.infinity,
                                    child: ColoredBox(color: c),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      hexColor(c),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        tooltip: '锁定颜色 ${index + 1}',
                                        onPressed: () => setState(
                                          () => locked[index] = !locked[index],
                                        ),
                                        icon: Icon(
                                          locked[index]
                                              ? Icons.lock
                                              : Icons.lock_open,
                                          size: 20,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '调整颜色 ${index + 1}',
                                        onPressed: () => editColor(index),
                                        icon: const Icon(Icons.tune, size: 20),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => copyResult(context, colors.map(hexColor).join('\n')),
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('复制整组配色'),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: exporting ? null : exportCard,
          icon: const Icon(Icons.image_outlined),
          label: const Text('导出带色值的色卡 PNG'),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('调整基色', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('format:$format'),
                  initialValue: format,
                  decoration: const InputDecoration(labelText: '输入格式'),
                  items: ['HEX', 'RGB', 'HSL']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (s) => setState(() {
                    format = s!;
                    input.text = encoded(color);
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: input,
                  decoration: const InputDecoration(labelText: '颜色'),
                  onChanged: (_) => update(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('kind:$kind'),
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '组合方式'),
                  items: paletteStyles
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (s) => setState(() {
                    kind = s!;
                    preset = null;
                    colorCount = 5;
                    locked.fillRange(0, 8, false);
                    title = '你的配色';
                  }),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '基色与白色 ${contrastRatio(color, Colors.white).toStringAsFixed(2)}:1 · 与黑色 ${contrastRatio(color, Colors.black).toStringAsFixed(2)}:1',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text('预设灵感 · 12 组', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('选一张色卡作为起点，也可以随机生成新组合。'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (_, box) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: palettePresets
                .map(
                  (p) => SizedBox(
                    width: (box.maxWidth - 12) / 2,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => usePreset(p),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              strip(p.colors, 48),
                              const SizedBox(height: 10),
                              Text(
                                p.name,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
        const Text('组合用于配色参考；实际文字与背景的对比度需按使用场景核对。'),
      ],
    );
  }
}
