import 'dart:math' as math;

import 'engine.dart' show fmt;

class CsvTable {
  CsvTable(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
  factory CsvTable.parse(
    String source,
    String delimiter, {
    bool hasHeader = true,
  }) {
    if (source.length > 2 * 1024 * 1024) {
      throw const FormatException('数据上限 2 MB');
    }
    if (source.startsWith('\ufeff')) source = source.substring(1);
    final records = <List<String>>[], row = <String>[];
    var value = StringBuffer(), quoted = false;
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (c == '"') {
        if (quoted && i + 1 < source.length && source[i + 1] == '"') {
          value.write('"');
          i++;
        } else if (quoted || value.isEmpty) {
          quoted = !quoted;
        } else {
          throw const FormatException('引号位置无效');
        }
      } else if (c == delimiter && !quoted) {
        row.add(value.toString().trim());
        value = StringBuffer();
      } else if ((c == '\n' || c == '\r') && !quoted) {
        if (c == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
        row.add(value.toString().trim());
        value = StringBuffer();
        if (row.any((v) => v.isNotEmpty)) records.add(List.of(row));
        row.clear();
      } else {
        value.write(c);
      }
    }
    if (quoted) throw const FormatException('CSV 引号没有闭合');
    row.add(value.toString().trim());
    if (row.any((v) => v.isNotEmpty)) records.add(row);
    final dataCount = records.length - (hasHeader ? 1 : 0);
    if (dataCount < 1 || dataCount > 50000) {
      throw FormatException(hasHeader ? '需要表头和 1—50000 行数据' : '需要 1—50000 行数据');
    }
    final headers = hasHeader
        ? records.removeAt(0)
        : List.generate(records.first.length, (i) => '第 ${i + 1} 列');
    if (headers.any((h) => h.isEmpty) ||
        headers.toSet().length != headers.length ||
        records.any((r) => r.length != headers.length)) {
      throw const FormatException('表头须非空且不重复，每行列数须一致');
    }
    return CsvTable(headers, records);
  }
  String cell(List<String> row, int column) {
    if (column < 0 || column >= headers.length) {
      throw const FormatException('请映射必需的数据列');
    }
    return row[column];
  }

  double numeric(
    List<String> row,
    int column, {
    bool positive = false,
    bool nonnegative = false,
  }) {
    final n = double.tryParse(cell(row, column));
    if (n == null ||
        !n.isFinite ||
        (positive && n <= 0) ||
        (nonnegative && n < 0)) {
      throw const FormatException('数据列包含空值、非法数值或不符合范围的值');
    }
    return n;
  }
}

class CurveSeries {
  CurveSeries(this.name, this.points);
  final String name;
  final List<(double, double)> points;
}

class AnalysisResult {
  AnalysisResult(this.csv, this.summary, this.curves, this.xLabel, this.yLabel);
  final String csv, summary, xLabel, yLabel;
  final List<CurveSeries> curves;
}

String csvCell(String s) => '"${s.replaceAll('"', '""')}"';
({double mean, double? sd}) sampleStats(List<double> values) {
  if (values.isEmpty) throw const FormatException('没有可用于统计的数据');
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.length > 1
      ? values.fold(0.0, (sum, v) => sum + math.pow(v - mean, 2)) /
            (values.length - 1)
      : null;
  return (mean: mean, sd: variance == null ? null : math.sqrt(variance));
}

AnalysisResult analyzeCycles(
  CsvTable table,
  Map<String, int> columns, {
  required int baseline,
  required int firstCycle,
  required int compareCycle,
  bool lithium = false,
}) {
  if (baseline < firstCycle || firstCycle < 1 || compareCycle < firstCycle) {
    throw const FormatException('基准圈和对比圈须不小于起始圈，圈数从 1 开始');
  }
  final groups = <String, List<(int, double, double)>>{};
  final seen = <String>{};
  for (final row in table.rows) {
    final sample = (columns['样品'] ?? -1) < 0
        ? '样品'
        : table.cell(row, columns['样品']!);
    if (sample.isEmpty) throw const FormatException('样品名称不能为空');
    final cycle = table.numeric(row, columns['循环']!, positive: true);
    if (cycle != cycle.roundToDouble()) {
      throw const FormatException('循环编号须为正整数');
    }
    final charge = table.numeric(row, columns['充电/沉积容量']!, positive: true),
        discharge = table.numeric(row, columns['放电/剥离容量']!, nonnegative: true);
    final entries = groups.putIfAbsent(sample, () => []);
    if (!seen.add('$sample\u0000${cycle.toInt()}')) {
      throw const FormatException('同一样品同一循环有重复汇总行，请先核对配对');
    }
    entries.add((cycle.toInt(), charge, discharge));
  }
  if (groups.length > 20) throw const FormatException('最多比较 20 个样品');
  final csv = [
    lithium
        ? 'sample,cycle,plated_mAh,stripped_mAh,CE_percent'
        : 'sample,cycle,charge_mAh,discharge_mAh,CE_percent,retention_percent',
  ];
  final curves = <CurveSeries>[], selected = <double>[];
  var unusual = 0;
  for (final group in groups.entries) {
    final entries = group.value..sort((a, b) => a.$1.compareTo(b.$1));
    final base = entries.where((v) => v.$1 == baseline).firstOrNull;
    if (!lithium && (base == null || base.$3 <= 0)) {
      throw FormatException('${group.key} 缺少有效的基准循环 $baseline');
    }
    final points = <(double, double)>[];
    for (final row in entries.where((v) => v.$1 >= firstCycle)) {
      final efficiency = row.$3 / row.$2 * 100;
      if (efficiency > 100) unusual++;
      csv.add(
        '${csvCell(group.key)},${row.$1},${fmt(row.$2)},${fmt(row.$3)},${fmt(efficiency)}${lithium ? '' : ',${fmt(row.$3 / base!.$3 * 100)}'}',
      );
      points.add((row.$1.toDouble(), lithium ? efficiency : row.$3));
      if (row.$1 == compareCycle) selected.add(lithium ? efficiency : row.$3);
    }
    if (points.isEmpty) throw FormatException('${group.key} 在选定范围内没有数据');
    curves.add(CurveSeries(group.key, points));
  }
  final stats = sampleStats(selected);
  return AnalysisResult(
    csv.join('\n'),
    '${groups.length} 个样品；起始圈 $firstCycle${lithium ? '' : '；保持率基准圈 $baseline'}。\n对比圈 $compareCycle：n=${selected.length}，${lithium ? 'CE' : '放电容量'}均值 ${fmt(stats.mean)} ${lithium ? '%' : 'mAh'}；样本标准差 ${stats.sd == null ? '单样品不计算' : fmt(stats.sd!)}。\n${groups.length - selected.length} 个样品没有对比圈数据，未纳入这一圈的统计。\n$unusual 行 CE 超过 100%，保留原结果，请核对测试步骤与容量配对。${lithium ? '\n采用逐圈剥离容量/沉积容量，不等同于储锂库等其他测试协议。' : ''}',
    curves,
    '循环',
    lithium ? 'CE %' : '放电容量 mAh',
  );
}

AnalysisResult analyzeSymmetric(
  CsvTable table,
  Map<String, int> columns, {
  required double excludeSeconds,
}) {
  if (!excludeSeconds.isFinite || excludeSeconds < 0) {
    throw const FormatException('排除时间须为非负数');
  }
  final groups = <String, List<(double, double)>>{},
      labels = <String, (String, int, String)>{};
  for (final row in table.rows) {
    final sample = (columns['样品'] ?? -1) < 0
        ? '样品'
        : table.cell(row, columns['样品']!);
    final cycle = table.numeric(row, columns['循环']!, positive: true);
    if (cycle != cycle.roundToDouble()) {
      throw const FormatException('循环编号须为正整数');
    }
    final step = table.cell(row, columns['步骤']!);
    if (sample.isEmpty || step.isEmpty) {
      throw const FormatException('样品与步骤名称不能为空');
    }
    final t = table.numeric(row, columns['时间']!, nonnegative: true),
        v = table.numeric(row, columns['电压']!);
    final key = '$sample\u0000${cycle.toInt()}\u0000$step',
        series = groups.putIfAbsent(key, () => []);
    if (series.isNotEmpty && t <= series.last.$1) {
      throw const FormatException('同一样品/循环/步骤的时间须严格递增；时间重置请使用不同步骤编号');
    }
    series.add((t, v));
    labels[key] = (sample, cycle.toInt(), step);
  }
  final curves = <String, List<(double, double)>>{},
      csv = ['sample,cycle,step,points,mean_abs_voltage_V,duration_s'];
  for (final group in groups.entries) {
    final label = labels[group.key]!, start = group.value.first.$1;
    final retained = group.value
        .where((v) => v.$1 - start >= excludeSeconds)
        .toList();
    if (retained.isEmpty) {
      throw FormatException('${label.$1}/${label.$2}/${label.$3} 排除起始区间后无数据');
    }
    final mean = sampleStats(retained.map((v) => v.$2.abs()).toList()).mean;
    csv.add(
      '${csvCell(label.$1)},${label.$2},${csvCell(label.$3)},${retained.length},${fmt(mean)},${fmt(group.value.last.$1 - start)}',
    );
    curves.putIfAbsent('${label.$1} · ${label.$3}', () => []).add((
      label.$2.toDouble(),
      mean,
    ));
  }
  if (curves.length > 20) throw const FormatException('最多显示 20 组样品/步骤曲线');
  return AnalysisResult(
    csv.join('\n'),
    '${groups.length} 个步骤段；每段排除起始 $excludeSeconds s。\n统计剩余采样点的 |电压| 算术均值，采样间隔不均匀时不代表时间加权平均。\n这是 Li‖Li 双电极电池的电压差，不是单电极过电位；不能由长循环时长单独判定是否短路。',
    curves.entries
        .map(
          (g) =>
              CurveSeries(g.key, g.value..sort((a, b) => a.$1.compareTo(b.$1))),
        )
        .toList(),
    '循环',
    '平均 |电压| V',
  );
}
