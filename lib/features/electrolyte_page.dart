import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/electrolyte.dart';
import '../core/files.dart';
import 'catalog.dart';
import 'workbench.dart';

/// Components stay in memory; no experiment history is created.
class ElectrolytePage extends StatefulWidget {
  const ElectrolytePage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<ElectrolytePage> createState() => _ElectrolytePageState();
}

class _ElectrolytePageState extends State<ElectrolytePage> {
  late final values = widget.tool.defaults;
  late final fields = {
    for (final f in widget.tool.fields.where(
      (f) => f.kind != FieldKind.multiline && f.kind != FieldKind.choice,
    ))
      f.name: TextEditingController(text: f.value),
  };
  late final groups = {
    for (final f in widget.tool.fields.where(
      (f) => f.kind == FieldKind.multiline,
    ))
      f.name: f.value
          .split('\n')
          .map(
            (r) => r
                .split(',')
                .map((v) => TextEditingController(text: v))
                .toList(),
          )
          .toList(),
  };
  final retired = <TextEditingController>[];
  bool dirty = false, exporting = false;
  bool get reverse => values['模式'] == '实际称量反算';
  @override
  void dispose() {
    for (final c in [
      ...fields.values,
      ...groups.values.expand((r) => r.expand((r) => r)),
      ...retired,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? fieldError(String text, String name, {bool component = false}) {
    if (name == '名称') {
      if (text.trim().isEmpty) return '请填写名称';
      if (RegExp(r'[,，;；\t\n]').hasMatch(text)) return '名称不能含分隔符';
      return null;
    }
    final n = double.tryParse(text);
    if (n == null || !n.isFinite || n < 0) return '请输入非负有限数值';
    if ((name == '目标量' ||
            name.contains('摩尔质量') ||
            name.contains('质量比') ||
            name.contains('纯度')) &&
        n == 0) {
      return '须大于 0';
    }
    if ((name.contains('纯度') || name.contains('wt%')) && n > 100) {
      return '不能超过 100%';
    }
    if (name.contains('密度') &&
        !reverse &&
        n == 0 &&
        (values['目标量基准'] == '最终体积 mL' || values['盐浓度单位'] == 'mol/L')) {
      return '此口径需要实测最终溶液密度';
    }
    return null;
  }

  Future<void> exportResult(String output) async {
    setState(() => exporting = true);
    try {
      final saved = await Files.saveText(output, 'saisuite-electrolyte.txt');
      if (saved != null && mounted) setState(() => dirty = false);
    } catch (e) {
      if (mounted) message(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget entry(
    TextEditingController c,
    String label, {
    bool name = false,
    String? specificError,
  }) => TextField(
    controller: c,
    enabled: !exporting,
    keyboardType: name
        ? TextInputType.text
        : const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      errorText: specificError ?? fieldError(c.text, name ? '名称' : label),
    ),
    onChanged: (_) => setState(() => dirty = true),
  );
  @override
  Widget build(BuildContext context) {
    final visible = widget.tool.fields
        .where(
          (f) =>
              f.name == '模式' ||
              (reverse
                  ? f.name.startsWith('实际') || f.name == '实测最终体积 mL'
                  : !f.name.startsWith('实际') && f.name != '实测最终体积 mL'),
        )
        .toList();
    String? result, error;
    try {
      final p = Map<String, String>.of(values);
      for (final f in visible) {
        if (fields.containsKey(f.name)) {
          final text = fields[f.name]!.text;
          if (fieldError(text, f.name) != null) {
            throw const FormatException('请检查标出的输入字段');
          }
          p[f.name] = text;
        }
        if (groups.containsKey(f.name)) {
          final labels = f.name.split('：').last.split(',');
          final rows = groups[f.name]!;
          for (final row in rows) {
            for (var i = 0; i < row.length; i++) {
              if (fieldError(row[i].text, labels[i]) != null) {
                throw const FormatException('请检查标出的组分字段');
              }
            }
          }
          p[f.name] = rows
              .map((r) => r.map((c) => c.text.trim()).join(','))
              .join('\n');
        }
      }
      result = runLabTool('N01', p);
      final solventKey = reverse ? '实际溶剂：名称,质量g' : '溶剂：名称,质量比';
      final solventRows = groups[solventKey]!;
      final weights = solventRows.map((r) => double.parse(r[1].text)).toList();
      final sum = weights.fold(0.0, (a, b) => a + b);
      result +=
          '\n溶剂质量比例：${List.generate(weights.length, (i) => '${solventRows[i][0].text} ${(weights[i] / sum * 100).toStringAsFixed(2)}%').join(' · ')}';
    } on FormatException catch (e) {
      error = e.message.toString();
    }
    return Workbench(
      tool: widget.tool,
      state: widget.state,
      dirty: dirty,
      blocked: exporting,
      onExport: result == null ? null : () => exportResult(result!),
      children: [
        Text('把配方变成清晰的称量清单', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('调整任意参数即可重新计算。密度与体积填写实测值，0 表示未提供。'),
        const SizedBox(height: 20),
        for (final f in visible)
          if (f.kind == FieldKind.choice)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<String>(
                key: ValueKey(f.name),
                initialValue: values[f.name],
                decoration: InputDecoration(labelText: f.name),
                items: f.options
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: exporting
                    ? null
                    : (v) => setState(() {
                        values[f.name] = v!;
                        dirty = true;
                      }),
              ),
            )
          else if (fields.containsKey(f.name))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: entry(fields[f.name]!, f.name),
            )
          else if (groups.containsKey(f.name)) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    f.name.split('：').first,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: exporting || groups[f.name]!.length >= 10
                      ? null
                      : () => setState(() {
                          groups[f.name]!.add(
                            List.generate(
                              f.name.split('：').last.split(',').length,
                              (_) => TextEditingController(),
                            ),
                          );
                          dirty = true;
                        }),
                  icon: const Icon(Icons.add),
                  label: const Text('添加组分'),
                ),
              ],
            ),
            for (final row in groups[f.name]!)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: entry(
                              row.first,
                              '名称',
                              name: true,
                              specificError:
                                  groups[f.name]!
                                          .where(
                                            (r) =>
                                                r.first.text.trim() ==
                                                row.first.text.trim(),
                                          )
                                          .length >
                                      1
                                  ? '组分名称不能重复'
                                  : null,
                            ),
                          ),
                          IconButton(
                            tooltip: '删除组分',
                            onPressed: exporting
                                ? null
                                : () => setState(() {
                                    groups[f.name]!.remove(row);
                                    retired.addAll(row);
                                    dirty = true;
                                  }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                      for (var i = 1; i < row.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: entry(row[i], switch (f.name
                              .split('：')
                              .last
                              .split(',')[i]) {
                            '摩尔质量' => '摩尔质量 g/mol',
                            '目标浓度' => '目标浓度 ${values['盐浓度单位']}',
                            final s => s,
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result == null ? '检查输入后查看结果' : '实时称量结果',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SelectableText(result ?? error ?? ''),
                if (result != null)
                  OutlinedButton.icon(
                    onPressed: exporting ? null : () => exportResult(result!),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('导出称量清单'),
                  ),
                if (result != null)
                  TextButton.icon(
                    onPressed: () => copyResult(context, result!),
                    icon: const Icon(Icons.copy),
                    label: const Text('复制称量清单'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(widget.tool.hint),
      ],
    );
  }
}
