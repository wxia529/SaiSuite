import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import '../core/app_state.dart';
import '../core/files.dart';
import '../core/cycle_analysis.dart';
import 'catalog.dart';
import 'workbench.dart';

AnalysisResult analyzeData(Map<String, dynamic> r) {
  final table = CsvTable.parse(
        r['text'] as String,
        r['delimiter'] as String,
        hasHeader: r['hasHeader'] as bool? ?? true,
      ),
      columns = Map<String, int>.from(r['columns'] as Map);
  return r['mode'] == 'Li‖Li极化'
      ? analyzeSymmetric(table, columns, excludeSeconds: r['exclude'] as double)
      : analyzeCycles(
          table,
          columns,
          baseline: r['baseline'] as int,
          firstCycle: r['first'] as int,
          compareCycle: r['compare'] as int,
          lithium: r['mode'] == 'Li‖Cu效率',
        );
}

CsvTable parseData(Map<String, dynamic> r) => CsvTable.parse(
  r['text'] as String,
  r['delimiter'] as String,
  hasHeader: r['hasHeader'] as bool? ?? true,
);

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key, required this.tool, required this.state});
  final ToolSpec tool;
  final AppState state;
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  final text = TextEditingController(),
      first = TextEditingController(text: '1'),
      baseline = TextEditingController(text: '1'),
      compare = TextEditingController(text: '3'),
      exclude = TextEditingController(text: '0');
  final columns = <String, int>{};
  CsvTable? table;
  AnalysisResult? result;
  bool busy = false, dirty = false;
  bool hasHeader = true;
  String delimiter = 'CSV', mode = '循环汇总', filename = '手工数据';
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.tool.id == 'N07') mode = 'Li‖Cu效率';
  }

  @override
  void dispose() {
    for (final c in [text, first, baseline, compare, exclude]) {
      c.dispose();
    }
    super.dispose();
  }

  String get separator => delimiter == 'TSV'
      ? '\t'
      : delimiter == '分号'
      ? ';'
      : ',';
  List<String> get requiredColumns => mode == 'Li‖Li极化'
      ? ['样品', '循环', '步骤', '时间', '电压']
      : ['样品', '循环', '充电/沉积容量', '放电/剥离容量'];
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
        setState(() => error = e is FormatException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> discard() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('当前结果尚未导出'),
            content: const Text('继续会替换当前分析，请先导出需要保留的结果。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> parse() async {
    if (!await discard()) return;
    await guard(() async {
      final next = await compute(parseData, {
        'text': text.text,
        'delimiter': separator,
        'hasHeader': hasHeader,
      });
      final defaults = {
        '样品': ['sample', '样品'],
        '循环': ['cycle', '循环'],
        '步骤': ['step', '步骤'],
        '时间': ['time', '时间'],
        '电压': ['voltage', '电压'],
        '充电/沉积容量': ['charge', 'plated', '充电容量', '沉积容量'],
        '放电/剥离容量': ['discharge', 'stripped', '放电容量', '剥离容量'],
      };
      if (mounted) {
        setState(() {
          table = next;
          result = null;
          dirty = false;
          columns.clear();
          for (final key in requiredColumns) {
            columns[key] = hasHeader
                ? next.headers.indexWhere(
                    (s) => defaults[key]!.contains(s.toLowerCase()),
                  )
                : -1;
          }
        });
      }
    });
  }

  Future<void> changeHeader(bool value) async {
    if (!await discard() || !mounted) return;
    setState(() {
      hasHeader = value;
      table = null;
      columns.clear();
      result = null;
      dirty = false;
      error = null;
    });
  }

  Future<void> pick() async {
    if (!await discard()) return;
    await guard(() async {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final path = await Files.localCopy(file, maxBytes: 2 * 1024 * 1024),
          content = await File(path).readAsString();
      if (mounted) {
        setState(() {
          text.text = content;
          filename = file.name;
          table = null;
          result = null;
          dirty = false;
        });
      }
    });
    if (error == null && text.text.isNotEmpty) await parse();
  }

  int positive(TextEditingController c) {
    final n = int.tryParse(c.text);
    if (n == null || n < 1) throw const FormatException('循环参数须为正整数');
    return n;
  }

  Future<void> analyze() async {
    if (!await discard()) return;
    await guard(() async {
      if (table == null) throw const FormatException('请先解析数据并映射列');
      final seconds = double.tryParse(exclude.text);
      if (seconds == null || !seconds.isFinite || seconds < 0) {
        throw const FormatException('排除时间须为非负数');
      }
      final next = await compute(analyzeData, {
        'text': text.text,
        'delimiter': separator,
        'hasHeader': hasHeader,
        'columns': columns,
        'mode': mode,
        'first': positive(first),
        'baseline': positive(baseline),
        'compare': positive(compare),
        'exclude': seconds,
      });
      if (mounted) {
        setState(() {
          result = next;
          dirty = true;
        });
      }
    });
  }

  Future<void> exportCsv() async => guard(() async {
    if (result == null) return;
    final path = await Files.saveText(result!.csv, 'saisuite-analysis.csv');
    if (path != null && mounted) {
      setState(() => dirty = false);
      message(context, '已导出 CSV');
    }
  });
  Future<void> exportChart() async => guard(() async {
    if (result == null) return;
    final recorder = ui.PictureRecorder();
    AnalysisPainter(result!).paint(Canvas(recorder), const Size(1200, 800));
    final picture = recorder.endRecording(),
        image = await picture.toImage(1200, 800);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      final path = await Files.saveBytes(bytes, 'saisuite-analysis.png');
      if (path != null && mounted) message(context, '已导出曲线 PNG；数值请另导出 CSV');
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
  Future<void> example() async {
    if (!await discard()) return;
    setState(() {
      filename = '合成示例';
      result = null;
      dirty = false;
      table = null;
      delimiter = 'CSV';
      hasHeader = true;
      text.text = mode == 'Li‖Li极化'
          ? 'sample,cycle,step,time,voltage\nA,1,1,0,0.06\nA,1,1,10,0.05\nA,1,2,0,-0.06\nA,1,2,10,-0.05\nA,2,1,0,0.055\nA,2,1,10,0.045\nA,2,2,0,-0.055\nA,2,2,10,-0.045'
          : 'sample,cycle,charge,discharge\nA,1,1,0.9\nA,2,1,0.95\nA,3,1,0.94\nB,1,1,0.91\nB,2,1,0.96\nB,3,1,0.95';
    });
    await parse();
  }

  Widget parameter(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: c,
      enabled: !busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    ),
  );
  @override
  Widget build(BuildContext context) => Workbench(
    tool: widget.tool,
    state: widget.state,
    dirty: dirty,
    blocked: busy,
    onExport: exportCsv,
    children: [
      const Text(
        '只分析当前数据，不保存实验记录。UTF-8 文件上限 2 MB、50000 行，可选择有无表头。容量 mAh，电压 V，时间 s；容量须来自确认配对的步骤。',
      ),
      if (widget.tool.id == 'N07')
        DropdownButtonFormField<String>(
          initialValue: mode,
          items: [
            'Li‖Cu效率',
            'Li‖Li极化',
          ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: busy
              ? null
              : (s) async {
                  if (!await discard()) return;
                  if (mounted) {
                    setState(() {
                      mode = s!;
                      table = null;
                      result = null;
                      dirty = false;
                    });
                  }
                },
        ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('delimiter:$delimiter'),
        initialValue: delimiter,
        items: [
          'CSV',
          'TSV',
          '分号',
        ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: busy
            ? null
            : (s) => setState(() {
                delimiter = s!;
                table = null;
                columns.clear();
              }),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('文件包含表头'),
        subtitle: Text(
          hasHeader
              ? '第一行为列名，其余行为数据；列名可以自行命名。'
              : '第一行也作为数据；解析后按第 1 列、第 2 列等手动映射。',
        ),
        value: hasHeader,
        onChanged: busy ? null : changeHeader,
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: busy ? null : pick,
            child: const Text('选择数据文件'),
          ),
          TextButton(
            onPressed: busy ? null : example,
            child: const Text('填入合成示例'),
          ),
        ],
      ),
      Text(filename),
      TextField(
        controller: text,
        enabled: !busy,
        minLines: 4,
        maxLines: 7,
        decoration: InputDecoration(labelText: hasHeader ? '表头与数据' : '数据（无表头）'),
        onChanged: (_) => setState(() => table = null),
      ),
      FilledButton(onPressed: busy ? null : parse, child: const Text('解析并映射列')),
      if (table != null) ...[
        Text('${table!.rows.length} 行 · ${table!.headers.length} 列'),
        Text('预览：${table!.rows.take(3).map((r) => r.join(' | ')).join('\n')}'),
        for (final key in requiredColumns)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: DropdownButtonFormField<int>(
              key: ValueKey('$key:${columns[key]}:${table!.headers.join()}'),
              initialValue: columns[key],
              decoration: InputDecoration(labelText: key),
              items: [
                DropdownMenuItem(
                  value: -1,
                  child: Text(key == '样品' ? '未提供（单一样品）' : '未映射'),
                ),
                for (var i = 0; i < table!.headers.length; i++)
                  DropdownMenuItem(value: i, child: Text(table!.headers[i])),
              ],
              onChanged: busy ? null : (v) => setState(() => columns[key] = v!),
            ),
          ),
      ],
      if (mode == 'Li‖Li极化')
        parameter('排除每步骤起始时间 s', exclude)
      else ...[
        parameter('起始循环（可排除形成圈）', first),
        if (mode == '循环汇总') parameter('保持率基准循环', baseline),
        parameter('平行样对比循环', compare),
      ],
      FilledButton(
        onPressed: busy || table == null ? null : analyze,
        child: const Text('分析当前数据'),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (result != null) ...[
        const SizedBox(height: 16),
        SelectableText(result!.summary),
        SizedBox(
          height: 360,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: CustomPaint(
              size: const Size(700, 360),
              painter: AnalysisPainter(result!),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : exportCsv,
              icon: const Icon(Icons.save_alt),
              label: const Text('导出 CSV'),
            ),
            OutlinedButton(
              onPressed: busy ? null : exportChart,
              child: const Text('导出曲线 PNG'),
            ),
            TextButton(
              onPressed: () => copyResult(context, result!.summary),
              child: const Text('复制摘要'),
            ),
          ],
        ),
      ],
    ],
  );
}

class AnalysisPainter extends CustomPainter {
  AnalysisPainter(this.result);
  final AnalysisResult result;
  static const colors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
  ];
  void label(
    Canvas c,
    String text,
    Offset position, {
    Color color = Colors.black,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(c, position);
  }

  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = Colors.white);
    final points = result.curves.expand((v) => v.points).toList();
    if (points.isEmpty) return;
    var xmin = points.first.$1,
        xmax = xmin,
        ymin = points.first.$2,
        ymax = ymin;
    for (final p in points) {
      if (p.$1 < xmin) xmin = p.$1;
      if (p.$1 > xmax) xmax = p.$1;
      if (p.$2 < ymin) ymin = p.$2;
      if (p.$2 > ymax) ymax = p.$2;
    }
    if (xmin == xmax) xmax = xmin + 1;
    if (ymin == ymax) ymax = ymin + 1;
    final plot = Rect.fromLTRB(
      65,
      25,
      s.width - 20,
      s.height - 55 - ((result.curves.length + 2) ~/ 3) * 20,
    );
    Offset point((double, double) p) => Offset(
      plot.left + (p.$1 - xmin) / (xmax - xmin) * plot.width,
      plot.bottom - (p.$2 - ymin) / (ymax - ymin) * plot.height,
    );
    final axis = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;
    c.drawLine(plot.bottomLeft, plot.topLeft, axis);
    c.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    for (var i = 0; i <= 4; i++) {
      label(
        c,
        (xmin + (xmax - xmin) * i / 4).toStringAsPrecision(3),
        Offset(plot.left + plot.width * i / 4 - 10, plot.bottom + 4),
      );
      label(
        c,
        (ymin + (ymax - ymin) * i / 4).toStringAsPrecision(3),
        Offset(2, plot.bottom - plot.height * i / 4 - 6),
      );
    }
    c.save();
    c.clipRect(plot.inflate(3));
    for (var i = 0; i < result.curves.length; i++) {
      final series = result.curves[i],
          paint = Paint()
            ..color = colors[i % colors.length]
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;
      final path = Path();
      for (var j = 0; j < series.points.length; j++) {
        final p = point(series.points[j]);
        if (j == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
        c.drawCircle(p, 2, Paint()..color = paint.color);
      }
      c.drawPath(path, paint);
    }
    c.restore();
    label(c, result.yLabel, const Offset(65, 5));
    label(c, result.xLabel, Offset(s.width / 2, plot.bottom + 24));
    for (var i = 0; i < result.curves.length; i++) {
      label(
        c,
        result.curves[i].name,
        Offset(
          65 + (i % 3) * (s.width - 85) / 3,
          plot.bottom + 44 + (i ~/ 3) * 20,
        ),
        color: colors[i % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(AnalysisPainter old) => old.result != result;
}
