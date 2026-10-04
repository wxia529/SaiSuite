import 'engine.dart' show fmt, number, integer;

List<List<String>> tableRows(
  String text,
  int columns, {
  bool optional = false,
}) {
  final rows = text
      .split('\n')
      .where((s) => s.trim().isNotEmpty)
      .map(
        (s) => s.trim().split(RegExp(r'[,，;\t]')).map((v) => v.trim()).toList(),
      )
      .toList();
  if (rows.isEmpty && !optional) throw const FormatException('组分表不能为空');
  if (rows.length > 10 ||
      rows.any((r) => r.length != columns || r.first.isEmpty)) {
    throw FormatException('组分表最多 10 行，每行需要 $columns 列；组分名称不能为空');
  }
  if (rows.map((r) => r.first).toSet().length != rows.length) {
    throw const FormatException('组分名称不能重复');
  }
  return rows;
}

double rowNumber(String text, {bool positive = false, double? max}) {
  final value = double.tryParse(text);
  if (value == null ||
      !value.isFinite ||
      value < 0 ||
      (positive && value <= 0) ||
      (max != null && value > max)) {
    throw const FormatException('组分表数值无效，请核对单位、范围与纯度');
  }
  return value;
}

class ElectrolyteRecipe {
  ElectrolyteRecipe(
    this.total,
    this.solvent,
    this.volume,
    this.rows,
    this.notes,
  );
  final double total, solvent;
  final double? volume;
  final List<(String, double)> rows;
  final String notes;
  String describe() =>
      '${rows.map((r) => '${r.$1}：${fmt(r.$2)} g').join('\n')}\n\n总质量：${fmt(total)} g\n溶剂质量：${fmt(solvent)} g${volume == null ? '' : '\n最终溶液体积：${fmt(volume!)} mL'}\n$notes';
}

ElectrolyteRecipe electrolyteRecipe(Map<String, String> p) {
  final solvents = tableRows(p['溶剂：名称,质量比']!, 2);
  final salts = tableRows(p['盐：名称,摩尔质量,目标浓度,纯度%']!, 4);
  final additives = tableRows(p['添加剂：名称,最终电解液wt%'] ?? '', 2, optional: true);
  final ratios = solvents.map((r) => rowNumber(r[1], positive: true)).toList();
  final molar = salts.map((r) => rowNumber(r[1], positive: true)).toList();
  final concentrations = salts.map((r) => rowNumber(r[2])).toList();
  final purity = salts
      .map((r) => rowNumber(r[3], positive: true, max: 100) / 100)
      .toList();
  final fractions = additives
      .map((r) => rowNumber(r[1], max: 100) / 100)
      .toList();
  final additiveFraction = fractions.fold(0.0, (a, b) => a + b);
  if (additiveFraction >= 1) throw const FormatException('添加剂质量分数总和须小于 100%');
  final amount = number(p, '目标量', positive: true),
      density = number(p, '实测溶液密度 g/mL', nonnegative: true);
  final basis = p['目标量基准'], unit = p['盐浓度单位'];
  if ((basis == '最终体积 mL' || unit == 'mol/L') && density <= 0) {
    throw const FormatException('体积基准或 mol/L 配方需要实测最终溶液密度；不能用溶剂体积代替最终溶液体积');
  }
  final coefficient = List.generate(
    salts.length,
    (i) => switch (unit) {
      'mol/kg溶剂' => concentrations[i] * molar[i] / 1000 / purity[i],
      'mol/L' => concentrations[i] * molar[i] / 1000 / density / purity[i],
      'wt%有效盐' => concentrations[i] / 100 / purity[i],
      _ => throw const FormatException('请选择盐浓度单位'),
    },
  );
  final saltCoefficient = coefficient.fold(0.0, (a, b) => a + b);
  double total, solvent;
  if (basis == '溶剂质量 g') {
    solvent = amount;
    final numerator = unit == 'mol/kg溶剂'
        ? solvent * (1 + saltCoefficient)
        : solvent;
    final denominator = unit == 'mol/kg溶剂'
        ? 1 - additiveFraction
        : 1 - additiveFraction - saltCoefficient;
    if (denominator <= 0) throw const FormatException('盐和添加剂用量超过可用总质量，请核对配方');
    total = numerator / denominator;
  } else {
    total = basis == '最终体积 mL' ? amount * density : amount;
    solvent = unit == 'mol/kg溶剂'
        ? total * (1 - additiveFraction) / (1 + saltCoefficient)
        : total * (1 - additiveFraction - saltCoefficient);
  }
  if (!total.isFinite || solvent <= 0 || !solvent.isFinite) {
    throw const FormatException('配方不能得到正的溶剂质量，请核对输入');
  }
  final ratioSum = ratios.fold(0.0, (a, b) => a + b);
  final rows = <(String, double)>[];
  for (var i = 0; i < solvents.length; i++) {
    rows.add(('溶剂 ${solvents[i][0]}', solvent * ratios[i] / ratioSum));
  }
  for (var i = 0; i < salts.length; i++) {
    rows.add((
      '盐 ${salts[i][0]}（纯度修正称量）',
      coefficient[i] * (unit == 'mol/kg溶剂' ? solvent : total),
    ));
  }
  for (var i = 0; i < additives.length; i++) {
    rows.add(('添加剂 ${additives[i][0]}', fractions[i] * total));
  }
  return ElectrolyteRecipe(
    total,
    solvent,
    density > 0 ? total / density : null,
    rows,
    '溶剂按质量比分配；添加剂 wt% 以最终电解液总质量为分母。密度由用户提供；盐摩尔质量须对应实际试剂形态，纯度修正不推断杂质成分。',
  );
}

String reverseRecipe(Map<String, String> p) {
  final solventRows = tableRows(p['实际溶剂：名称,质量g']!, 2);
  final saltRows = tableRows(p['实际盐：名称,摩尔质量,质量g,纯度%']!, 4);
  final addRows = tableRows(p['实际添加剂：名称,质量g'] ?? '', 2, optional: true);
  final solvent = solventRows.fold(0.0, (sum, r) => sum + rowNumber(r[1]));
  if (solvent <= 0) throw const FormatException('实际溶剂总质量须大于零');
  final saltMass = saltRows.map((r) => rowNumber(r[2])).toList(),
      addMass = addRows.map((r) => rowNumber(r[1])).toList();
  final total =
      solvent +
      saltMass.fold(0.0, (a, b) => a + b) +
      addMass.fold(0.0, (a, b) => a + b);
  final volume = number(p, '实测最终体积 mL', nonnegative: true);
  final out = ['总质量：${fmt(total)} g', '溶剂质量：${fmt(solvent)} g'];
  for (var i = 0; i < saltRows.length; i++) {
    final r = saltRows[i],
        moles =
            saltMass[i] *
            rowNumber(r[3], positive: true, max: 100) /
            100 /
            rowNumber(r[1], positive: true);
    out.add(
      '${r[0]}：${fmt(moles / (solvent / 1000))} mol/kg溶剂；${fmt(moles * rowNumber(r[1]) / total * 100)} wt%有效盐${volume > 0 ? '；${fmt(moles / (volume / 1000))} mol/L' : ''}',
    );
  }
  for (var i = 0; i < addRows.length; i++) {
    out.add('${addRows[i][0]}：${fmt(addMass[i] / total * 100)} wt%（最终电解液）');
  }
  out.add(volume > 0 ? 'mol/L 使用实测最终溶液体积。' : '未填写最终溶液体积，不计算 mol/L；0 表示未提供。');
  return out.join('\n');
}

String runLabTool(String id, Map<String, String> p) {
  switch (id) {
    case 'N01':
      return p['模式'] == '实际称量反算'
          ? reverseRecipe(p)
          : electrolyteRecipe(p).describe();
    case 'N03':
      final count = integer(p, '电池数量', min: 1, max: 10000),
          volume = number(p, '单颗加液量 µL', nonnegative: true),
          extra = number(p, '余量', nonnegative: true);
      final total =
          count * volume +
          (p['余量单位'] == '%' ? count * volume * extra / 100 : extra);
      final electrode = integer(p, '每颗电极片数', min: 1, max: 20),
          separator = integer(p, '每颗隔膜片数', min: 1, max: 20),
          pad = integer(p, '每颗垫片数', max: 20),
          spring = integer(p, '每颗弹片数', max: 20);
      return '电解液：${fmt(total)} µL / ${fmt(total / 1000)} mL\n电极：${count * electrode} 片\n隔膜：${count * separator} 片\n垫片：${count * pad} 个\n弹片：${count * spring} 个\n壳体套数：$count\n用量由你的实验方案指定，不按电池型号推荐加液量。';
    case 'N04':
      final area = number(p, '有效面积 cm²', positive: true),
          j = number(p, '电流密度 mA/cm²', positive: true),
          q = number(p, '面容量 mAh/cm²', positive: true),
          ref = number(p, '参考容量 mAh', positive: true);
      return '仪器电流：${fmt(j * area)} mA\n单段容量：${fmt(q * area)} mAh\n恒流预计时长：${fmt(q / j)} h / ${fmt(q / j * 60)} min\n相对参考容量的倍率：${fmt(j * area / ref)} C\nI=jA；Q=qA；t=Q/I，仅计算恒流段，不包含静置与恒压时间。';
    case 'N05':
      final r = number(p, '实测体相电阻 Ω', positive: true),
          temp = number(p, '温度 °C');
      if (temp <= -273.15) throw const FormatException('温度须高于绝对零度');
      final constant = p['口径'] == '电导池常数'
          ? number(p, '电导池常数 cm⁻¹', positive: true)
          : number(p, '样品厚度 mm', positive: true) /
                10 /
                number(p, '有效面积 cm²', positive: true);
      final sigma = constant / r;
      return '电导率：${fmt(sigma)} S/cm / ${fmt(sigma * 1000)} mS/cm\n电导池常数：${fmt(constant)} cm⁻¹\n温度：${fmt(temp)} °C\nσ=K/R；几何口径 K=L/A。使用体相电阻，不能直接代入整电池总阻抗；几何口径仅适用于对应测试结构。';
    default:
      throw const FormatException('未知实验计算工具');
  }
}
