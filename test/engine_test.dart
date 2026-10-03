import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saisuite/core/engine.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/pdf_page.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('catalog contains 46 unique implemented tools', () {
    expect(tools.length, 46);
    expect(tools.map((e) => e.id).toSet().length, 46);
  });
  for (final tool in tools.where((t) => !t.pdf)) {
    test('${tool.id} example completes with a genuine result', () {
      final output = runTool(tool.id, tool.defaults);
      expect(output, isNotEmpty);
      expect(output, isNot(contains('NaN')));
      expect(output, isNot(contains('Infinity')));
    });
  }
  test('calculator precedence, degrees and powers', () {
    expect(ExpressionParser('-2^2').evaluate(), -4);
    expect(ExpressionParser('2^3^2').evaluate(), 512);
    expect(ExpressionParser('sin(30)+sqrt(9)').evaluate(), closeTo(3.5, 1e-12));
    expect(ExpressionParser('1/0').evaluate, throwsFormatException);
    expect(ExpressionParser('sqrt(-1)').evaluate, throwsFormatException);
  });
  test('units preserve offsets and binary data capacities', () {
    expect(convertUnit(25, '°C', 'K'), closeTo(298.15, 1e-12));
    expect(convertUnit(32, '°F', '°C'), closeTo(0, 1e-12));
    expect(convertUnit(1024, 'MiB', 'GiB'), 1);
    expect(() => convertUnit(1, 'g', 'm'), throwsFormatException);
    expect(() => convertUnit(-1, 'K', '°C'), throwsFormatException);
  });
  test('molecule parser supports nested groups, decimal stoichiometry and hydrates', () {
    expect(parseFormula('H2O').mass, closeTo(18.015, 0.01));
    expect(parseFormula('Ca(OH)2').atoms, {'Ca': 1.0, 'O': 2.0, 'H': 2.0});
    expect(parseFormula('CuSO4·5H2O').atoms['H'], 10);
    expect(parseFormula('LiNi0.8Co0.1Mn0.1O2').atoms['Ni'], .8);
    expect(() => parseFormula('Unknown'), throwsFormatException);
    expect(() => parseFormula('Ca(OH2'), throwsFormatException);
    expect(() => parseFormula('H0'), throwsFormatException);
  });
  test('validates leap days and uses calendar dates', () {
    expect(() => date('2025-02-29'), throwsFormatException);
    expect(
      isoDate(date('2024-02-29').add(const Duration(days: 1))),
      '2024-03-01',
    );
    expect(
      runTool('D01', {
        '起始日期': '2024-02-28',
        '结束日期': '2024-03-01',
        '含起止日': 'false',
      }),
      startsWith('2 天'),
    );
  });
  test('Unicode Base64 round trip and invalid input', () {
    final input = '中文 🧪';
    final encoded = runTool('T05', {'模式': '编码', '文本': input});
    expect(runTool('T05', {'模式': '解码', '文本': encoded}), input);
    expect(
      () => runTool('T05', {'模式': '解码', '文本': '!!!'}),
      throwsFormatException,
    );
  });
  test('JSON errors retain source offset', () {
    expect(
      () => runTool('T04', {'模式': '格式化', 'JSON': '{"x":}'}),
      throwsFormatException,
    );
    expect(jsonDecode(runTool('T04', {'模式': '压缩', 'JSON': ' { "n": 1 } '})), {
      'n': 1,
    });
  });
  test('password includes every selected group', () {
    final defaults = tools.firstWhere((t) => t.id == 'C05').defaults;
    for (var i = 0; i < 30; i++) {
      final password = runTool('C05', defaults);
      expect(password.length, 20);
      for (final regex in [r'[a-z]', r'[A-Z]', r'[0-9]', r'[^a-zA-Z0-9]']) {
        expect(RegExp(regex).hasMatch(password), isTrue);
      }
    }
  });
  test('random sampling is unique and rejects impossible ranges', () {
    final p = tools.firstWhere((t) => t.id == 'C04').defaults;
    expect(runTool('C04', {...p, '抽取数量': '3'}).split('\n').toSet().length, 3);
    expect(() => runTool('C04', {...p, '抽取数量': '4'}), throwsFormatException);
    expect(
      () => runTool('C04', {...p, '模式': '整数', '最小值': '9', '最大值': '1'}),
      throwsFormatException,
    );
  });
  test('hash and textual differences', () {
    expect(
      hashText('abc', 'SHA-256'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(textDiff('a\nb', 'a\nc'), allOf(contains('- b'), contains('+ c')));
  });
  test('colors round trip between spaces', () {
    expect(colorConvert('RGB', '255,0,0'), startsWith('#FF0000'));
    expect(colorConvert('HSL', '120,100,50'), startsWith('#00FF00'));
    expect(() => colorConvert('RGB', '256,0,0'), throwsFormatException);
  });
  test('current integration splits zero crossings and rejects time reset', () {
    final result = integrateCurrent([(0, 1), (3600, 1)]);
    expect(result.positive, 1);
    final crossed = integrateCurrent([(0, 1), (3600, -1)]);
    expect(crossed.positive, .25);
    expect(crossed.negative, .25);
    expect(() => currentSeries('0,1\n0,2'), throwsFormatException);
    expect(() => currentSeries('0,1\n1,NaN'), throwsFormatException);
  });
  test('electrochemistry unit and capacity conventions', () {
    expect(
      runTool('EC01', tools.firstWhere((t) => t.id == 'EC01').defaults),
      startsWith('1.13097336'),
    );
    expect(
      runTool('EC04', tools.firstWhere((t) => t.id == 'EC04').defaults),
      contains('1.09375'),
    );
    expect(
      runTool('EC16', tools.firstWhere((t) => t.id == 'EC16').defaults),
      contains('0.45 V'),
    );
    expect(
      runTool('EC21', tools.firstWhere((t) => t.id == 'EC21').defaults),
      contains('1 mAh'),
    );
  });
  test('slurry rejects impossible solvent amount and ratios', () {
    final p = tools.firstWhere((t) => t.id == 'EC05').defaults;
    expect(
      () => runTool('EC05', {...p, '活性物质 wt%': '90'}),
      throwsFormatException,
    );
    expect(
      () => runTool('EC05', {...p, '浆料固含量 wt%': '90'}),
      throwsFormatException,
    );
  });
  test('PDF page ranges validate bounds and keep requested order', () {
    expect(parsePages('3,1-2,3', 3), [2, 0, 1]);
    expect(parsePages('', 2), [0, 1]);
    expect(() => parsePages('0', 3), throwsFormatException);
    expect(() => parsePages('2-4', 3), throwsFormatException);
  });
  test('timezones account for DST seasons', () {
    final p = tools.firstWhere((t) => t.id == 'D04').defaults;
    expect(
      runTool('D04', {...p, '当地日期时间': '2026-07-01 12:00:00'}),
      contains('00:00:00'),
    );
    expect(
      () => runTool('D04', {
        ...p,
        '原时区': 'America/New_York',
        '当地日期时间': '2026-03-08 02:30:00',
      }),
      throwsFormatException,
    );
    expect(
      () => runTool('D04', {
        ...p,
        '原时区': 'America/New_York',
        '当地日期时间': '2026-11-01 01:30:00',
      }),
      throwsFormatException,
    );
    expect(
      () => runTool('D04', {...p, '当地日期时间': '2026-02-30 12:00:00'}),
      throwsFormatException,
    );
  });
  test('dates handle pre-epoch fractions and bounded calendar years', () {
    final p = tools.firstWhere((t) => t.id == 'D03').defaults;
    expect(
      runTool('D03', {
        ...p,
        '方向': '日期 → 时间戳',
        '精度': '秒',
        'ISO 日期': '1969-12-31T23:59:59.500Z',
      }),
      '-1',
    );
    expect(
      () => runTool('D02', {'日期': '0001-01-01', '天数': '-1'}),
      throwsFormatException,
    );
  });
  test('solution preparation solves mass, concentration and volume', () {
    final p = tools.firstWhere((t) => t.id == 'S02').defaults;
    expect(runTool('S02', p), contains('1.519 g'));
    expect(runTool('S02', {...p, '求解': '浓度'}), contains('1 mol/L'));
    expect(runTool('S02', {...p, '求解': '最终体积'}), contains('10 mL'));
    expect(
      () => runTool('S02', {...p, '求解': '最终体积', '浓度 mol/L': '0'}),
      throwsFormatException,
    );
  });
  test('percentages and proportions use the stated operand order', () {
    final p = tools.firstWhere((t) => t.id == 'C03').defaults;
    expect(
      runTool('C03', {...p, '模式': '比例求解', 'A': '2', 'B': '3', 'C': '10'}),
      startsWith('15'),
    );
    expect(
      runTool('C03', {...p, '模式': '变化率', 'A': '80', 'B': '100'}),
      startsWith('25%'),
    );
    expect(
      runTool('C03', {...p, '模式': '折扣', 'A': '100', 'B': '80'}),
      contains('节省 20'),
    );
    expect(
      () => runTool('C03', {...p, '模式': '比例求解', 'A': '0'}),
      throwsFormatException,
    );
  });
  test('text cleanup, Unicode counts and URL decoding have known outputs', () {
    expect(runTool('T01', {'文本': '中🧪'}), contains('字符（用户可见）：2'));
    expect(
      runTool('T02', {
        '文本': ' b \n\na\nb',
        '去首尾空格': 'true',
        '去空行': 'true',
        '去重复行': 'true',
        '排序': '升序',
      }),
      'a\nb',
    );
    expect(runTool('T06', {'模式': '解码', '文本': '%E4%B8%AD%E6%96%87'}), '中文');
    expect(
      () => runTool('T06', {'模式': '解码', '文本': '%ZZ'}),
      throwsFormatException,
    );
  });
  test('science examples preserve physical units', () {
    String calc(String id, Map<String, String> inputs) => runTool(id, {
      ...tools.firstWhere((t) => t.id == id).defaults,
      ...inputs,
    });
    expect(calc('S03', {}), contains('取原液：10 mL'));
    expect(calc('S04', {}), startsWith('1 mA'));
    expect(
      calc('S05', {'面积 cm²': '1', '活性物质质量 mg': '2'}),
      contains('面容量：0.32 mAh/cm²'),
    );
    expect(
      calc('S06', {'数值': '1', '输入单位': 'eV'}),
      contains('96.48533212 kJ/mol'),
    );
    expect(
      calc('EC02', {'活性物质质量 mg': '2', '容量 mAh': '0.32'}),
      contains('160 mAh/g'),
    );
    expect(calc('EC03', {}), startsWith('169.89'));
    expect(
      calc('EC05', {
        '干固体 g': '1',
        '活性物质 wt%': '90',
        '导电剂 wt%': '5',
        '粘结剂 wt%': '5',
        '浆料固含量 wt%': '40',
        '粘结剂溶液 wt%': '5',
      }),
      contains('另加溶剂：0.55 g'),
    );
    expect(
      calc('EC08', {'电解液 µL': '20', '密度 g/mL': '1.2', '容量 mAh': '2'}),
      contains('E/C：12 g/Ah'),
    );
    expect(
      calc('EC09', {
        '配比基准': '体积比',
        '目标总量': '10',
        '组分：名称,比例,密度': 'A,1,1\nB,1,2',
      }),
      contains('B：10 g，5 mL'),
    );
    expect(
      double.parse(
        calc('EC14', {'原电位 V': '0', '目标基准': 'RHE'}).split(' ').first,
      ),
      closeTo(.414115, .00001),
    );
    expect(calc('EC16', {'电流 mA': '-10', '已补偿 %': '50'}), contains('0.525 V'));
  });
  test('timestamp input rejects invalid calendar dates and clock overflow', () {
    final p = tools.firstWhere((t) => t.id == 'D03').defaults;
    for (final iso in [
      '2026-02-30T12:00:00Z',
      '2026-01-01T25:00:00Z',
      '2026-01-01T12:00:00+08:99',
    ]) {
      expect(
        () => runTool('D03', {...p, '方向': '日期 → 时间戳', 'ISO 日期': iso}),
        throwsFormatException,
      );
    }
  });
}
