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
  String kind = '互补色', format = 'HEX';
  Color color = const Color(0xff147d73);
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void update() {
    try {
      final output = runTool('T08', {'格式': format, '颜色': input.text});
      // Use the same conversion engine as the existing color tool.
      setState(() {
        color = parseHex(output.split('\n').first);
        error = null;
      });
    } catch (e) {
      setState(() => error = e is FormatException ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorPalette(color, kind), h = HSLColor.fromColor(color);
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      children: [
        const Text('输入颜色生成配色。点按色块复制，组合建议不等同于文字可读性检查。'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: format,
          items: [
            'HEX',
            'RGB',
            'HSL',
          ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (s) {
            setState(() {
              format = s!;
              input.text = s == 'HEX'
                  ? hexColor(color)
                  : s == 'RGB'
                  ? '${(color.r * 255).round()},${(color.g * 255).round()},${(color.b * 255).round()}'
                  : '${h.hue.toStringAsFixed(1)},${(h.saturation * 100).toStringAsFixed(1)},${(h.lightness * 100).toStringAsFixed(1)}';
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: input,
          decoration: const InputDecoration(labelText: '颜色'),
          onChanged: (_) => update(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: kind,
          items: [
            '互补色',
            '类似色',
            '三色组合',
          ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (s) => setState(() => kind = s!),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        ...colors.map(
          (c) => Card(
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey),
                ),
              ),
              title: Text(hexColor(c)),
              subtitle: Text(
                'RGB ${(c.r * 255).round()}, ${(c.g * 255).round()}, ${(c.b * 255).round()}',
              ),
              trailing: const Icon(Icons.copy),
              onTap: () => copyResult(context, hexColor(c)),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => copyResult(context, colors.map(hexColor).join('\n')),
          icon: const Icon(Icons.copy),
          label: const Text('复制整组配色'),
        ),
        const SizedBox(height: 16),
        Text(
          '基色与白色对比度 ${contrastRatio(color, Colors.white).toStringAsFixed(2)}:1；与黑色 ${contrastRatio(color, Colors.black).toStringAsFixed(2)}:1',
        ),
      ],
    );
  }
}
