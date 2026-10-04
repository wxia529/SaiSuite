import 'dart:convert';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as tz;

import 'atomic_weights.dart';

const faraday = 96485.33212;
const gasConstant = 8.314462618;
String fmt(num x) {
  if (!x.isFinite) throw const FormatException('结果超出有效数值范围');
  if (x == 0) return '0';
  if (x.abs() >= 1e10 || x.abs() < 1e-7) return x.toStringAsExponential(8);
  return x.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
}

double number(
  Map<String, String> p,
  String key, {
  bool positive = false,
  bool nonnegative = false,
}) {
  final v = double.tryParse(p[key]?.trim() ?? '');
  if (v == null ||
      !v.isFinite ||
      (positive && v <= 0) ||
      (nonnegative && v < 0)) {
    throw FormatException(
      '$key：请输入${positive
          ? '大于零的'
          : nonnegative
          ? '非负'
          : '有效'}数值',
    );
  }
  return v;
}

int integer(
  Map<String, String> p,
  String key, {
  int min = 0,
  int max = 1000000,
}) {
  final v = int.tryParse(p[key]?.trim() ?? '');
  if (v == null || v < min || v > max) {
    throw FormatException('$key：请输入 $min—$max 范围内的整数');
  }
  return v;
}

DateTime date(String text) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (m == null) throw const FormatException('日期格式应为 YYYY-MM-DD');
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final result = DateTime.utc(y, mo, d);
  if (y < 1 || result.year != y || result.month != mo || result.day != d) {
    throw const FormatException('日期不存在');
  }
  return result;
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class ExpressionParser {
  ExpressionParser(String input, {this.degrees = true})
    : source = input
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('π', 'pi')
          .replaceAll(RegExp(r'\s'), '');
  final String source;
  final bool degrees;
  int i = 0, depth = 0;
  bool eat(String c) {
    if (source.startsWith(c, i)) {
      i += c.length;
      return true;
    }
    return false;
  }

  double evaluate() {
    if (source.isEmpty || source.length > 1024) {
      throw const FormatException('请输入不超过 1024 字符的表达式');
    }
    final v = sum();
    if (i != source.length) throw FormatException('第 ${i + 1} 个字符无法解析；乘法请写 *');
    if (!v.isFinite) throw const FormatException('表达式无实数结果，或结果超出范围');
    return v;
  }

  double sum() {
    var v = product();
    while (true) {
      if (eat('+')) {
        v += product();
      } else if (eat('-')) {
        v -= product();
      } else {
        return v;
      }
    }
  }

  double product() {
    var v = unary();
    while (true) {
      if (eat('*')) {
        v *= unary();
      } else if (eat('/')) {
        final d = unary();
        if (d == 0) throw const FormatException('不能除以零');
        v /= d;
      } else if (eat('%')) {
        final d = unary();
        if (d == 0) throw const FormatException('不能对零取余');
        v %= d;
      } else {
        return v;
      }
    }
  }

  double unary() {
    if (++depth > 128) throw const FormatException('表达式嵌套过深');
    try {
      if (eat('+')) return unary();
      if (eat('-')) return -unary();
      return power();
    } finally {
      depth--;
    }
  }

  double power() {
    final v = atom();
    return eat('^') ? math.pow(v, unary()).toDouble() : v;
  }

  double atom() {
    if (eat('(')) {
      final v = sum();
      if (!eat(')')) throw const FormatException('缺少右括号');
      return v;
    }
    final m = RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')
        .firstMatch(source.substring(i));
    if (m != null) {
      i += m[0]!.length;
      return double.parse(m[0]!);
    }
    final name = RegExp(r'^[a-zA-Z]+').firstMatch(source.substring(i))?[0];
    if (name == null) throw FormatException('第 ${i + 1} 个字符处缺少数字');
    i += name.length;
    if (name == 'pi') return math.pi;
    if (name == 'e') return math.e;
    if (!eat('(')) throw const FormatException('函数参数请使用括号');
    final x = sum();
    if (!eat(')')) throw const FormatException('缺少右括号');
    final a = degrees ? x * math.pi / 180 : x;
    final inverse = degrees ? 180 / math.pi : 1.0;
    return switch (name.toLowerCase()) {
      'sin' => math.sin(a),
      'cos' => math.cos(a),
      'tan' => math.tan(a),
      'asin' => math.asin(x) * inverse,
      'acos' => math.acos(x) * inverse,
      'atan' => math.atan(x) * inverse,
      'sqrt' => math.sqrt(x),
      'ln' => math.log(x),
      'log' => math.log(x) / math.ln10,
      'abs' => x.abs(),
      'exp' => math.exp(x),
      'floor' => x.floorToDouble(),
      'ceil' => x.ceilToDouble(),
      _ => throw FormatException('不支持的函数：$name'),
    };
  }
}

typedef UnitDef = ({String category, double factor, double offset});
const units = <String, UnitDef>{
  'm': (category: '长度', factor: 1, offset: 0),
  'mm': (category: '长度', factor: .001, offset: 0),
  'cm': (category: '长度', factor: .01, offset: 0),
  'km': (category: '长度', factor: 1000, offset: 0),
  'in': (category: '长度', factor: .0254, offset: 0),
  'ft': (category: '长度', factor: .3048, offset: 0),
  'm²': (category: '面积', factor: 1, offset: 0),
  'cm²': (category: '面积', factor: .0001, offset: 0),
  'mm²': (category: '面积', factor: .000001, offset: 0),
  'ha': (category: '面积', factor: 10000, offset: 0),
  'm³': (category: '体积', factor: 1, offset: 0),
  'L': (category: '体积', factor: .001, offset: 0),
  'mL': (category: '体积', factor: .000001, offset: 0),
  'µL': (category: '体积', factor: 1e-9, offset: 0),
  'kg': (category: '质量', factor: 1, offset: 0),
  'g': (category: '质量', factor: .001, offset: 0),
  'mg': (category: '质量', factor: .000001, offset: 0),
  'lb': (category: '质量', factor: .45359237, offset: 0),
  'K': (category: '温度', factor: 1, offset: 0),
  '°C': (category: '温度', factor: 1, offset: 273.15),
  '°F': (category: '温度', factor: 5 / 9, offset: 255.3722222222222),
  'Pa': (category: '压力', factor: 1, offset: 0),
  'kPa': (category: '压力', factor: 1000, offset: 0),
  'MPa': (category: '压力', factor: 1e6, offset: 0),
  'bar': (category: '压力', factor: 1e5, offset: 0),
  'atm': (category: '压力', factor: 101325, offset: 0),
  'psi': (category: '压力', factor: 6894.757293, offset: 0),
  'J': (category: '能量', factor: 1, offset: 0),
  'kJ': (category: '能量', factor: 1000, offset: 0),
  'cal': (category: '能量', factor: 4.184, offset: 0),
  'kcal': (category: '能量', factor: 4184, offset: 0),
  'Wh': (category: '能量', factor: 3600, offset: 0),
  'eV': (category: '能量', factor: 1.602176634e-19, offset: 0),
  'B': (category: '数据容量', factor: 1, offset: 0),
  'bit': (category: '数据容量', factor: .125, offset: 0),
  'kB': (category: '数据容量', factor: 1000, offset: 0),
  'MB': (category: '数据容量', factor: 1e6, offset: 0),
  'GB': (category: '数据容量', factor: 1e9, offset: 0),
  'KiB': (category: '数据容量', factor: 1024, offset: 0),
  'MiB': (category: '数据容量', factor: 1048576, offset: 0),
  'GiB': (category: '数据容量', factor: 1073741824, offset: 0),
};
double convertUnit(double value, String from, String to) {
  final a = units[from], b = units[to];
  if (a == null || b == null || a.category != b.category) {
    throw const FormatException('请选择同一类别的单位');
  }
  final base = value * a.factor + a.offset;
  if (a.category == '温度' && base < 0) throw const FormatException('温度不能低于绝对零度');
  return (base - b.offset) / b.factor;
}

class Molecule {
  Molecule(this.atoms);
  final Map<String, double> atoms;
  double get mass =>
      atoms.entries.fold(0, (v, e) => v + atomicWeights[e.key]! * e.value);
  String describe() =>
      '${fmt(mass)} g/mol\n\n${atoms.entries.map((e) => '${e.key}：${fmt(e.value)} 个，${fmt(atomicWeights[e.key]! * e.value / mass * 100)} wt%\n原子量 ${atomicWeights[e.key]}${atomicWeightUncertainties.containsKey(e.key) ? ' ± ${atomicWeightUncertainties[e.key]}' : '（参考同位素质量数）'}').join('\n')}\n\n原子量：CIAAW 2024 约化标准表；无标准原子量者采用 PubChem 参考质量数。显示小数位不代表数据精度；未进行不确定度传播。';
}

Molecule parseFormula(String input) {
  final source = input.trim().replaceAll(' ', '');
  if (source.isEmpty || source.length > 256) {
    throw const FormatException('请输入不超过 256 字符的化学式');
  }
  final atoms = <String, double>{};
  for (var part in source.split('·')) {
    var multiplier = 1.0;
    final m = RegExp(r'^\d+(?:\.\d+)?').firstMatch(part);
    if (m != null) {
      multiplier = double.parse(m[0]!);
      part = part.substring(m[0]!.length);
    }
    final parser = _FormulaParser(part);
    final values = parser.group();
    if (parser.i != part.length || values.isEmpty || multiplier <= 0) {
      throw const FormatException('化学式或水合物系数无效');
    }
    for (final e in values.entries) {
      atoms.update(
        e.key,
        (v) => v + e.value * multiplier,
        ifAbsent: () => e.value * multiplier,
      );
    }
  }
  final result = Molecule(atoms);
  if (!result.mass.isFinite || result.mass <= 0) {
    throw const FormatException('化学式质量无效');
  }
  return result;
}

class _FormulaParser {
  _FormulaParser(this.source);
  final String source;
  int i = 0, depth = 0;
  double count() {
    final m = RegExp(r'^\d+(?:\.\d+)?').firstMatch(source.substring(i));
    if (m == null) return 1;
    i += m[0]!.length;
    final v = double.parse(m[0]!);
    if (v <= 0 || !v.isFinite) throw const FormatException('原子计数必须大于零');
    return v;
  }

  Map<String, double> group({String? end}) {
    if (++depth > 16) throw const FormatException('化学式嵌套过深');
    final out = <String, double>{};
    while (i < source.length && source[i] != end) {
      Map<String, double> current;
      if (source[i] == '(' || source[i] == '[') {
        final close = source[i++] == '(' ? ')' : ']';
        current = group(end: close);
        if (current.isEmpty || i >= source.length || source[i] != close) {
          throw const FormatException('化学式括号不匹配');
        }
        i++;
      } else {
        final m = RegExp(r'^[A-Z][a-z]?').firstMatch(source.substring(i));
        if (m == null || !atomicWeights.containsKey(m[0])) {
          throw FormatException('无法识别 ${source.substring(i)}；水合物请用 · 分隔');
        }
        i += m[0]!.length;
        current = {m[0]!: 1};
      }
      final n = count();
      for (final e in current.entries) {
        out.update(e.key, (v) => v + e.value * n, ifAbsent: () => e.value * n);
      }
    }
    depth--;
    return out;
  }
}

String textDiff(String a, String b) {
  final x = a.split('\n'), y = b.split('\n');
  if (x.length * y.length > 1000000) {
    throw const FormatException('逐行对比最多支持约 1000×1000 行，请缩小文本');
  }
  final dp = List.generate(x.length + 1, (_) => List.filled(y.length + 1, 0));
  for (var i = x.length - 1; i >= 0; i--) {
    for (var j = y.length - 1; j >= 0; j--) {
      dp[i][j] = x[i] == y[j]
          ? dp[i + 1][j + 1] + 1
          : math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  var i = 0, j = 0;
  final result = <String>[];
  while (i < x.length || j < y.length) {
    if (i < x.length && j < y.length && x[i] == y[j]) {
      result.add('  ${x[i++]}');
      j++;
    } else if (j < y.length &&
        (i == x.length || dp[i][j + 1] >= dp[i + 1][j])) {
      result.add('+ ${y[j++]}');
    } else {
      result.add('- ${x[i++]}');
    }
  }
  return result.join('\n');
}

String hashText(String text, String algorithm) => switch (algorithm) {
  'MD5' => md5.convert(utf8.encode(text)).toString(),
  'SHA-1' => sha1.convert(utf8.encode(text)).toString(),
  _ => sha256.convert(utf8.encode(text)).toString(),
};

String runTool(String id, Map<String, String> p) {
  double n(String k, {bool positive = false, bool nonnegative = false}) =>
      number(p, k, positive: positive, nonnegative: nonnegative);
  String s(String k) => p[k] ?? '';
  String f(num v) => fmt(v);
  switch (id) {
    case 'C01':
      return f(
        ExpressionParser(s('表达式'), degrees: s('角度模式') == '度').evaluate(),
      );
    case 'C02':
      return '${f(convertUnit(n('数值'), s('原单位'), s('目标单位')))} ${s('目标单位')}';
    case 'C03':
      final a = n('A'), b = n('B');
      return switch (s('模式')) {
        '占比' =>
          b == 0
              ? throw const FormatException('总量不能为零')
              : '${f(a / b * 100)}%（A/B）',
        '变化率' =>
          a == 0
              ? throw const FormatException('原值不能为零')
              : '${f((b - a) / a * 100)}%（B 相对 A）',
        '折扣' => '折后 ${f(a * b / 100)}；节省 ${f(a * (1 - b / 100))}',
        _ =>
          a == 0
              ? throw const FormatException('比例中的 A 不能为零')
              : '${f(b * n('C') / a)}（A:B=C:X）',
      };
    case 'C04':
      final count = integer(p, '抽取数量', min: 1, max: 1000),
          rng = math.Random.secure();
      if (s('模式') == '整数' &&
          integer(p, '最大值', min: -100000, max: 100000) <
              integer(p, '最小值', min: -100000, max: 100000)) {
        throw const FormatException('最大值不能小于最小值');
      }
      final options = s('模式') == '选项'
          ? const LineSplitter()
                .convert(s('选项'))
                .where((e) => e.trim().isNotEmpty)
                .map((e) => e.trim())
                .toList()
          : List.generate(
              integer(p, '最大值', min: -100000, max: 100000) -
                  integer(p, '最小值', min: -100000, max: 100000) +
                  1,
              (i) =>
                  (i + integer(p, '最小值', min: -100000, max: 100000)).toString(),
            );
      if (options.isEmpty) throw const FormatException('请输入选项，或确保最大值不小于最小值');
      if (s('允许重复') == 'false') {
        final pool = options.toSet().toList();
        if (count > pool.length) throw const FormatException('抽取数量超过可用选项');
        pool.shuffle(rng);
        return pool.take(count).join('\n');
      }
      return List.generate(
        count,
        (_) => options[rng.nextInt(options.length)],
      ).join('\n');
    case 'C05':
      final len = integer(p, '长度', min: 4, max: 256),
          rng = math.Random.secure();
      final groups = <String>[
        if (s('小写') == 'true') 'abcdefghijklmnopqrstuvwxyz',
        if (s('大写') == 'true') 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        if (s('数字') == 'true') '0123456789',
        if (s('符号') == 'true') '!@#\$%^&*()-_=+[]{}:,.?',
      ];
      if (groups.isEmpty) throw const FormatException('至少选择一种字符类型');
      final pool = groups.join(),
          chars = groups.map((g) => g[rng.nextInt(g.length)]).toList();
      while (chars.length < len) {
        chars.add(pool[rng.nextInt(pool.length)]);
      }
      chars.shuffle(rng);
      return chars.join();
    case 'C06':
      if (s('类型') != 'Wi-Fi') {
        if (s('内容').trim().isEmpty) throw const FormatException('请输入二维码内容');
        return s('内容');
      }
      String escape(String v) =>
          v.replaceAllMapped(RegExp(r'[\\;,:\"]'), (m) => '\\${m[0]}');
      if (s('SSID').isEmpty) throw const FormatException('请输入 Wi-Fi 名称');
      return 'WIFI:T:${s('加密')};S:${escape(s('SSID'))};P:${escape(s('密码'))};H:${s('隐藏网络')};;';
    case 'T01':
      final text = s('文本');
      return '字符（用户可见）：${text.characters.length}\nUnicode 码点：${text.runes.length}\n中文字数：${RegExp(r'[\u3400-\u9fff]').allMatches(text).length}\n非空白字符：${text.replaceAll(RegExp(r'\s'), '').characters.length}\n行数：${text.isEmpty ? 0 : text.split('\n').length}\n段落：${text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\n\s*\n')).length}';
    case 'T02':
      var lines = s('文本').split('\n');
      if (s('去首尾空格') == 'true') lines = lines.map((e) => e.trim()).toList();
      if (s('去空行') == 'true') {
        lines = lines.where((e) => e.trim().isNotEmpty).toList();
      }
      if (s('去重复行') == 'true') lines = lines.toSet().toList();
      if (s('排序') != '不排序') {
        lines.sort();
        if (s('排序') == '降序') lines = lines.reversed.toList();
      }
      return lines.join('\n');
    case 'T09':
      return removeCjkBoundarySpaces(s('文本'));
    case 'T03':
      return textDiff(s('原文本'), s('新文本'));
    case 'T04':
      final value = jsonDecode(s('JSON'));
      return s('模式') == '压缩'
          ? jsonEncode(value)
          : const JsonEncoder.withIndent('  ').convert(value);
    case 'T05':
      return s('模式') == '编码'
          ? base64.encode(utf8.encode(s('文本')))
          : utf8.decode(base64.decode(s('文本').replaceAll(RegExp(r'\s'), '')));
    case 'T06':
      if (s('模式') == '查看参数') {
        final u = Uri.tryParse(s('文本'));
        if (u == null || !u.hasScheme) {
          throw const FormatException('请输入包含协议的 URL');
        }
        return '协议：${u.scheme}\n主机：${u.host}\n路径：${u.path}\n\n${u.queryParametersAll.entries.map((e) => '${e.key} = ${e.value.join(', ')}').join('\n')}';
      }
      try {
        return s('模式') == '编码'
            ? Uri.encodeComponent(s('文本'))
            : Uri.decodeComponent(s('文本'));
      } on ArgumentError {
        throw const FormatException('URL 编码无效，请检查百分号后的十六进制字符和 UTF-8 编码');
      }
    case 'T07':
      final h = hashText(s('文本'), s('算法'));
      return '$h${s('预期校验值').isEmpty ? '' : '\n\n${h.toLowerCase() == s('预期校验值').trim().toLowerCase() ? '校验一致' : '校验不一致'}'}';
    case 'T08':
      return colorConvert(s('格式'), s('颜色'));
    case 'S01':
      return parseFormula(s('化学式')).describe();
    case 'S02':
      final m = n('摩尔质量', positive: true);
      if (s('求解') == '浓度') {
        final amount = n('称量质量 g', nonnegative: true) / m,
            volume = n('最终体积 mL', positive: true) / 1000;
        return '浓度：${f(amount / volume)} mol/L\n物质的量：${f(amount)} mol\n\nc=m/(MV)；V 为最终溶液体积。';
      }
      if (s('求解') == '最终体积') {
        final amount = n('称量质量 g', nonnegative: true) / m,
            concentration = n('浓度 mol/L', positive: true);
        return '最终体积：${f(amount / concentration * 1000)} mL\n物质的量：${f(amount)} mol\n\nV=m/(Mc)；使用定容后的溶液体积。';
      }
      final c = n('浓度 mol/L', nonnegative: true),
          v = n('最终体积 mL', positive: true);
      return '物质的量：${f(c * v / 1000)} mol\n称量质量：${f(c * v * m / 1000)} g\n\nm=c×V×M；使用定容后的溶液体积。';
    case 'S03':
      final c1 = n('原液浓度', positive: true),
          c2 = n('目标浓度', nonnegative: true),
          v = n('目标体积 mL', positive: true);
      if (c2 > c1) throw const FormatException('稀释不能得到更高浓度');
      return '取原液：${f(c2 * v / c1)} mL\n定容至：${f(v)} mL\n\nc₁V₁=c₂V₂；同一种浓度单位。';
    case 'S04':
      final q = n('容量 mAh', positive: true);
      if (s('求解') == '电流') {
        return '${f(q * n('倍率 C', positive: true))} mA\n\nI=倍率×参考容量';
      }
      return '${f(n('电流 mA', positive: true) / q)} C';
    case 'S05':
      final a = n('面积 cm²', positive: true),
          m = n('活性物质质量 mg', positive: true),
          q = n('比容量 mAh/g', nonnegative: true);
      return '载量：${f(m / a)} mg/cm²\n容量：${f(m * q / 1000)} mAh\n面容量：${f(m * q / (1000 * a))} mAh/cm²\n\n质量仅指活性物质，已扣除集流体和其他组分。';
    case 'S06':
      final value = n('数值', positive: true),
          ev = s('输入单位') == 'eV'
              ? value
              : s('输入单位') == 'kJ/mol'
              ? value / 96.4853321233
              : s('输入单位') == 'kcal/mol'
              ? value * 4.184 / 96.4853321233
              : 1239.841984332 / value;
      return '${f(ev)} eV\n${f(ev * 96.4853321233)} kJ/mol\n${f(ev * 96.4853321233 / 4.184)} kcal/mol\n${f(1239.841984332 / ev)} nm（光子）\n${f(ev * 241.7989242085)} THz（光子）';
    case 'D01':
      final a = date(s('起始日期')),
          b = date(s('结束日期')),
          d = b.difference(a).inDays;
      return '${s('含起止日') == 'true' ? (d >= 0 ? d + 1 : d - 1) : d} 天\n\n按日历日期计算，不受夏令时影响。';
    case 'D02':
      final computed = date(s('日期'))
          .add(Duration(days: integer(p, '天数', min: -100000, max: 100000)));
      if (computed.year < 1 || computed.year > 9999) {
        throw const FormatException('推算后的年份需在 1—9999 内');
      }
      return isoDate(computed);
    case 'D03':
      if (s('方向') == '时间戳 → 日期') {
        final t = integer(
              p,
              '时间戳',
              min: -8640000000000000,
              max: 8640000000000000,
            ),
            ms = s('精度') == '秒' ? t * 1000 : t;
        final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
        return '${d.toIso8601String()}\n本地：${d.toLocal()}';
      }
      final text = s('ISO 日期');
      if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text)) {
        throw const FormatException('ISO 日期必须带 Z 或时区偏移，例如 +08:00');
      }
      final isoParts = RegExp(
        r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$',
      ).firstMatch(text);
      if (isoParts == null) {
        throw const FormatException('格式应为 YYYY-MM-DDTHH:mm:ss，加 Z 或时区偏移');
      }
      date(isoParts[1]!);
      if (int.parse(isoParts[2]!) > 23 ||
          int.parse(isoParts[3]!) > 59 ||
          int.parse(isoParts[4] ?? '0') > 59) {
        throw const FormatException('时、分、秒超出有效范围');
      }
      final offset = isoParts[5]!;
      if (offset != 'Z') {
        final digits = offset.substring(1).replaceAll(':', '');
        if (int.parse(digits.substring(0, 2)) > 23 ||
            int.parse(digits.substring(2)) > 59) {
          throw const FormatException('时区偏移超出有效范围');
        }
      }
      final d = DateTime.parse(text);
      return (s('精度') == '秒'
              ? (d.millisecondsSinceEpoch / 1000).floor()
              : d.millisecondsSinceEpoch)
          .toString();
    case 'D04':
      final text = s('当地日期时间').replaceAll(' ', 'T'),
          d = DateTime.tryParse(text);
      final parts = RegExp(
        r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$',
      ).firstMatch(text);
      if (d == null || parts == null) {
        throw const FormatException('请输入不带偏移的当地时间，如 2026-10-04 12:00:00');
      }
      date(parts[1]!);
      if (int.parse(parts[2]!) > 23 ||
          int.parse(parts[3]!) > 59 ||
          int.parse(parts[4] ?? '0') > 59) {
        throw const FormatException('时、分、秒超出有效范围');
      }
      final loc = tz.getLocation(s('原时区')),
          local = tz.TZDateTime(
            loc,
            d.year,
            d.month,
            d.day,
            d.hour,
            d.minute,
            d.second,
          );
      if (local.year != d.year ||
          local.month != d.month ||
          local.day != d.day ||
          local.hour != d.hour ||
          local.minute != d.minute) {
        throw const FormatException('该当地时间处于夏令时跳跃区间，不存在');
      }
      for (final offset in [-120, -60, -30, 30, 60, 120]) {
        final alternate = tz.TZDateTime.from(
          local.add(Duration(minutes: offset)),
          loc,
        );
        if (alternate.year == local.year &&
            alternate.month == local.month &&
            alternate.day == local.day &&
            alternate.hour == local.hour &&
            alternate.minute == local.minute) {
          throw const FormatException('该当地时间因夏令时回拨重复，请用带明确偏移的时间戳转换工具');
        }
      }
      return '${tz.TZDateTime.from(local, tz.getLocation(s('目标时区')))}\nUTC：${local.toUtc().toIso8601String()}\n原时区：${local.timeZoneName}\n\n使用 IANA 时区数据。夏令时回拨重复时间请用时间戳工具明确偏移。';
    case 'EC01':
      final shape = s('形状');
      final area = shape == '圆片'
          ? math.pi * math.pow(n('直径 mm', positive: true) / 20, 2)
          : shape == '矩形'
          ? n('长 mm', positive: true) * n('宽 mm', positive: true) / 100
          : math.pi *
                (math.pow(n('外径 mm', positive: true), 2) -
                    math.pow(n('内径 mm', nonnegative: true), 2)) /
                400;
      if (area <= 0) throw const FormatException('外径必须大于内径');
      return '${f(area)} cm²\n${f(area * 100)} mm²\n\n单面几何面积；暴露面积和 ECSA 请单独确定。';
    case 'EC02':
      final i = n('电流 mA'),
          q = n('容量 mAh', nonnegative: true),
          m = n('活性物质质量 mg', positive: true) / 1000,
          a = n('面积 cm²', positive: true);
      return '${f(i / a)} mA/cm²\n${f(i / m)} mA/g\n${f(q / m)} mAh/g\n${f(q / a)} mAh/cm²';
    case 'EC03':
      final m = parseFormula(s('化学式')).mass;
      return '${f(n('电子转移数', positive: true) * faraday / (3.6 * m))} mAh/g\n摩尔质量：${f(m)} g/mol\n\nq=nF/(3.6M)；电子转移数由配平反应确定。';
    case 'EC04':
      final qp =
              n('正极载量 mg/cm²', positive: true) *
              n('正极比容量 mAh/g', positive: true) /
              1000,
          qn =
              n('负极载量 mg/cm²', positive: true) *
              n('负极比容量 mAh/g', positive: true) /
              1000,
          ap = n('正极有效面积 cm²', positive: true),
          an = n('负极有效面积 cm²', positive: true),
          target = n('目标 N/P', positive: true);
      return '面容量比：${f(qn / qp)}\n有效总容量比：${f(qn * an / (qp * ap))}\n正极：${f(qp * ap)} mAh；负极：${f(qn * an)} mAh\n目标负极活性质量：${f(qp * ap * target / n('负极比容量 mAh/g', positive: true) * 1000)} mg\n\n两侧使用相同测试条件的可逆容量。';
    case 'EC05':
      final mass = n('干固体 g', positive: true),
          a = n('活性物质 wt%', nonnegative: true),
          c = n('导电剂 wt%', nonnegative: true),
          b = n('粘结剂 wt%', nonnegative: true),
          solid = n('浆料固含量 wt%', positive: true),
          solution = n('粘结剂溶液 wt%', positive: true);
      if ((a + b + c - 100).abs() > 1e-6 || solid > 100 || solution > 100) {
        throw const FormatException('干固体比例应合计 100%，浓度应在 0—100%');
      }
      final binder = mass * b / 100,
          sol = binder * 100 / solution,
          solvent = mass * (100 / solid - 1),
          additional = solvent - (sol - binder);
      if (additional < -1e-9) {
        throw const FormatException('粘结剂溶液已带入过多溶剂，请降低目标固含量或提高粘结剂溶液浓度');
      }
      return '活性物质：${f(mass * a / 100)} g\n导电剂：${f(mass * c / 100)} g\n干粘结剂：${f(binder)} g\n粘结剂溶液：${f(sol)} g\n另加溶剂：${f(math.max(0, additional))} g\n最终浆料：${f(mass * 100 / solid)} g';
    case 'EC08':
      final v = n('电解液 µL', nonnegative: true),
          density = n('密度 g/mL', positive: true),
          q = n('容量 mAh', positive: true),
          sulfur = n('硫质量 mg', positive: true);
      return 'E/C：${f(v / q)} µL/mAh\nE/C：${f(v * density / q)} g/Ah\nE/S：${f(v / sulfur)} µL/mg\n目标容量下加液量：${f(n('目标 E/C µL/mAh', nonnegative: true) * q)} µL\n\nE/S 仅针对硫活性质量。';
    case 'EC09':
      final rows = s('组分：名称,比例,密度')
          .split('\n')
          .where((e) => e.trim().isNotEmpty)
          .map((line) {
            final c = line.split(RegExp(r'[,，]'));
            if (c.length != 3) {
              throw const FormatException('每行填写：名称,比例,密度(g/mL)');
            }
            final r = double.tryParse(c[1]), d = double.tryParse(c[2]);
            if (r == null ||
                d == null ||
                !r.isFinite ||
                !d.isFinite ||
                r <= 0 ||
                d <= 0) {
              throw const FormatException('比例和密度必须为正数');
            }
            return (c[0].trim(), r, d);
          })
          .toList();
      if (rows.isEmpty) throw const FormatException('请添加组分');
      final total = n('目标总量', positive: true),
          sum = rows.fold(0.0, (v, e) => v + e.$2),
          mass = s('配比基准') == '质量比';
      return '${rows.map((e) {
        final amount = total * e.$2 / sum;
        return '${e.$1}：${f(mass ? amount : amount * e.$3)} g，${f(mass ? amount / e.$3 : amount)} mL';
      }).join('\n')}\n\n${mass ? '按质量比计算。' : '按组分体积可加近似计算；混合后最终体积需实测。'}';
    case 'EC14':
      final e = n('原电位 V'),
          old = n('原参比 vs SHE V'),
          target = n('目标参比 vs SHE V'),
          temp = n('温度 °C') + 273.15;
      if (temp <= 0) throw const FormatException('温度必须高于绝对零度');
      final converted = e + old - target;
      return '${f(s('目标基准') == 'RHE' ? e + old + gasConstant * temp / faraday * math.ln10 * n('pH') : converted)} V vs ${s('目标基准')}\n\n参比偏移须为相同温度、填充液条件下的来源值或实测值；RHE 假定标准氢气压力。';
    case 'EC16':
      final proportion = n('已补偿 %', nonnegative: true);
      if (proportion > 100) throw const FormatException('已补偿比例不能超过 100%');
      final loss =
          n('电流 mA') /
          1000 *
          n('未补偿电阻 Ω', nonnegative: true) *
          (1 - proportion / 100);
      return '剩余电压损失：${f(loss)} V\n校正电位：${f(n('测得电位 V') - loss)} V\n\n氧化电流为正；仅扣除尚未补偿部分。';
    default:
      throw FormatException('未知工具：$id');
  }
}

String colorConvert(String format, String input) {
  double r, g, b;
  if (format == 'HEX') {
    final h = input.trim().replaceFirst('#', '');
    final expanded = h.length == 3 ? h.split('').map((c) => c + c).join() : h;
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(expanded)) {
      throw const FormatException('请输入 #RGB 或 #RRGGBB');
    }
    final v = int.parse(expanded, radix: 16);
    r = ((v >> 16) & 255) / 255;
    g = ((v >> 8) & 255) / 255;
    b = (v & 255) / 255;
  } else {
    final v = input
        .split(RegExp(r'[,，\s]+'))
        .where((e) => e.isNotEmpty)
        .map(double.parse)
        .toList();
    if (v.length != 3 || v.any((e) => !e.isFinite)) {
      throw const FormatException('请输入三个数值');
    }
    if (format == 'RGB') {
      if (v.any((e) => e < 0 || e > 255)) {
        throw const FormatException('RGB 范围为 0—255');
      }
      r = v[0] / 255;
      g = v[1] / 255;
      b = v[2] / 255;
    } else {
      if (v[1] < 0 || v[1] > 100 || v[2] < 0 || v[2] > 100) {
        throw const FormatException('饱和度和亮度范围为 0—100');
      }
      final h = (v[0] % 360) / 60,
          s = v[1] / 100,
          l = v[2] / 100,
          c = (1 - (2 * l - 1).abs()) * s,
          x = c * (1 - (h % 2 - 1).abs()),
          m = l - c / 2;
      final channels = switch (h.floor()) {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
      };
      r = channels.$1 + m;
      g = channels.$2 + m;
      b = channels.$3 + m;
    }
  }
  final max = math.max(r, math.max(g, b)),
      min = math.min(r, math.min(g, b)),
      d = max - min,
      l = (max + min) / 2;
  var h = 0.0;
  if (d != 0) {
    h =
        (max == r
            ? ((g - b) / d) % 6
            : max == g
            ? (b - r) / d + 2
            : (r - g) / d + 4) *
        60;
  }
  final saturation = d == 0 ? 0 : d / (1 - (2 * l - 1).abs());
  String hex(double x) =>
      (x * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${hex(r)}${hex(g)}${hex(b)}\nRGB ${(r * 255).round()}, ${(g * 255).round()}, ${(b * 255).round()}\nHSL ${fmt(h)}, ${fmt(saturation * 100)}%, ${fmt(l * 100)}%';
}

String removeCjkBoundarySpaces(String text) {
  const han = r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\u{20000}-\u{323af}]';
  const latinOrDigit = r'[A-Za-z0-9Ａ-Ｚａ-ｚ０-９]';
  const gap = r'[ \t\u00a0\u3000]+';
  return text
      .replaceAllMapped(
        RegExp('($han)$gap(?=$latinOrDigit)', unicode: true),
        (m) => m[1]!,
      )
      .replaceAllMapped(
        RegExp('($latinOrDigit)$gap(?=$han)', unicode: true),
        (m) => m[1]!,
      );
}
