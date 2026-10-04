import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/palette.dart';
import '../core/engine.dart';
import 'catalog.dart';
import 'workbench.dart';

class PalettePage extends StatefulWidget {
  const PalettePage({super.key, required this.tool, required this.state});
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
    preset = p.colors;
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
    final colors = preset ?? designPalette(color, kind);
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
              onPressed: () =>
                  usePreset(randomPalette(random), generated: true),
              icon: const Icon(Icons.casino_outlined),
              label: const Text('随机灵感'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        strip(colors, 110),
        const SizedBox(height: 12),
        const Text('一组五色，从主色到点缀与留白。点按下方色卡复制。'),
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
              children: colors
                  .map(
                    (c) => SizedBox(
                      width: (box.maxWidth - (count - 1) * 10) / count,
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
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
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
