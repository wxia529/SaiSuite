import 'package:flutter_test/flutter_test.dart';
import 'package:saisuite/core/electrolyte.dart';
import 'package:saisuite/core/cycle_analysis.dart';
import 'package:saisuite/features/catalog.dart';

void main() {
  Map<String, String> recipe() => {
    '目标量基准': '溶剂质量 g',
    '目标量': '10',
    '盐浓度单位': 'mol/kg溶剂',
    '实测溶液密度 g/mL': '0',
    '溶剂：名称,质量比': 'A,1\nB,3',
    '盐：名称,摩尔质量,目标浓度,纯度%': 'S,100,1,100',
    '添加剂：名称,最终电解液wt%': 'X,10',
  };
  for (final tool in tools.where(
    (t) => t.id.startsWith('N') && t.fields.isNotEmpty,
  )) {
    test(
      '${tool.id} default demonstration calculates',
      () => expect(runLabTool(tool.id, tool.defaults), isNotEmpty),
    );
  }
  test('molality accounts for additive fraction of final mass', () {
    final r = electrolyteRecipe(recipe());
    expect(r.solvent, 10);
    expect(r.total, closeTo(110 / 9, 1e-10));
    expect(r.rows[0].$2, 2.5);
    expect(r.rows[1].$2, 7.5);
    expect(r.rows[2].$2, 1);
    expect(r.rows[3].$2 / r.total, closeTo(.1, 1e-12));
    expect(
      r.rows.fold(0.0, (sum, row) => sum + row.$2),
      closeTo(r.total, 1e-10),
    );
  });
  test('molarity uses final volume and measured solution density', () {
    final r = electrolyteRecipe({
      ...recipe(),
      '目标量基准': '最终体积 mL',
      '盐浓度单位': 'mol/L',
      '实测溶液密度 g/mL': '1.2',
    });
    expect(r.total, 12);
    expect(r.volume, 10);
    expect(r.rows[2].$2, 1);
    expect(r.solvent, closeTo(9.8, 1e-10));
    expect(
      () => electrolyteRecipe({...recipe(), '盐浓度单位': 'mol/L'}),
      throwsFormatException,
    );
  });
  test('purity changes weighing mass without changing effective salt', () {
    final r = electrolyteRecipe({
      ...recipe(),
      '盐：名称,摩尔质量,目标浓度,纯度%': 'S,100,1,50',
      '添加剂：名称,最终电解液wt%': '',
    });
    expect(r.rows.last.$2, 2);
    expect(r.total, 12);
    expect(
      () => electrolyteRecipe({...recipe(), '添加剂：名称,最终电解液wt%': 'A,60\nB,40'}),
      throwsFormatException,
    );
  });
  test('actual weighing does not invent final volume', () {
    final s = reverseRecipe({
      '实际溶剂：名称,质量g': 'A,10',
      '实际盐：名称,摩尔质量,质量g,纯度%': 'S,100,1,100',
      '实际添加剂：名称,质量g': 'X,1',
      '实测最终体积 mL': '0',
    });
    expect(s, contains('1 mol/kg溶剂'));
    expect(s, contains('不计算 mol/L'));
  });
  test('quoted CSV and resets within different steps work', () {
    final table = CsvTable.parse(
      'sample,cycle,step,time,voltage\n"A,1",1,1,0,0.1\n"A,1",1,1,10,0.05\n"A,1",1,2,0,-0.1\n"A,1",1,2,10,-0.05',
      ',',
    );
    final r = analyzeSymmetric(table, {
      '样品': 0,
      '循环': 1,
      '步骤': 2,
      '时间': 3,
      '电压': 4,
    }, excludeSeconds: 5);
    expect(r.curves.length, 2);
    expect(r.curves.first.points.first.$2, .05);
    expect(r.summary, contains('不是单电极过电位'));
    expect(() => CsvTable.parse('a,b\n"open,1', ','), throwsFormatException);
  });
  test('headerless input keeps the first row, BOM, quotes and single rows', () {
    final table = CsvTable.parse(
      '\ufeff"A,1",1,1,.9\r\n"A,1",2,1,.8',
      ',',
      hasHeader: false,
    );
    expect(table.headers, ['第 1 列', '第 2 列', '第 3 列', '第 4 列']);
    expect(table.rows.length, 2);
    expect(table.rows.first, ['A,1', '1', '1', '.9']);
    expect(CsvTable.parse('1,1,.9', ',', hasHeader: false).rows.length, 1);
    // Repeated values in the first row are data, not duplicate column names.
    expect(CsvTable.parse('1,1', ',', hasHeader: false).rows.single, [
      '1',
      '1',
    ]);
    expect(CsvTable.parse('\ufeff"电池",圈数\nA,1', ',').headers, ['电池', '圈数']);
  });
  test('headerless TSV and semicolon data still validate row widths', () {
    for (final delimiter in ['\t', ';']) {
      final table = CsvTable.parse(
        '1$delimiter.9\n2$delimiter.8',
        delimiter,
        hasHeader: false,
      );
      expect(table.rows.length, 2);
      expect(table.rows.first, ['1', '.9']);
      expect(
        () => CsvTable.parse('1$delimiter.9\n2', delimiter, hasHeader: false),
        throwsFormatException,
      );
    }
    expect(
      () => CsvTable.parse('', ',', hasHeader: false),
      throwsFormatException,
    );
    expect(
      () => CsvTable.parse('cycle,charge,discharge', ','),
      throwsFormatException,
    );
  });
  test('headerless data has the same 50000 data row limit', () {
    final rows = List.filled(50000, '1,1,.9').join('\n');
    expect(CsvTable.parse(rows, ',', hasHeader: false).rows.length, 50000);
    expect(
      CsvTable.parse('cycle,charge,discharge\n$rows', ',').rows.length,
      50000,
    );
    expect(
      () => CsvTable.parse('$rows\n1,1,.9', ',', hasHeader: false),
      throwsFormatException,
    );
  });
  test('cycle pairing uses selected baseline and sample deviation', () {
    final table = CsvTable.parse(
      'sample,cycle,charge,discharge\nA,1,1,0.5\nA,2,1,0.8\nB,1,1,0.6\nB,2,1,1.2',
      ',',
    );
    final r = analyzeCycles(
      table,
      {'样品': 0, '循环': 1, '充电/沉积容量': 2, '放电/剥离容量': 3},
      baseline: 1,
      firstCycle: 1,
      compareCycle: 2,
    );
    expect(r.csv, contains('160'));
    expect(r.csv, contains('200'));
    expect(r.summary, contains('1 行 CE 超过 100%'));
    final stats = sampleStats([.8, 1.2]);
    expect(stats.mean, 1);
    expect(stats.sd, closeTo(.28284271247, 1e-10));
  });
  test('duplicate cycles and reversed step time are rejected', () {
    final t = CsvTable.parse('cycle,charge,discharge\n1,1,.9\n1,1,.8', ',');
    expect(
      () => analyzeCycles(
        t,
        {'循环': 0, '充电/沉积容量': 1, '放电/剥离容量': 2},
        baseline: 1,
        firstCycle: 1,
        compareCycle: 1,
      ),
      throwsFormatException,
    );
    final s = CsvTable.parse(
      'cycle,step,time,voltage\n1,1,10,.1\n1,1,0,.05',
      ',',
    );
    expect(
      () => analyzeSymmetric(s, {
        '循环': 0,
        '步骤': 1,
        '时间': 2,
        '电压': 3,
      }, excludeSeconds: 0),
      throwsFormatException,
    );
  });
}
