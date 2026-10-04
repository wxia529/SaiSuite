import 'package:flutter_test/flutter_test.dart';
import 'package:saisuite/core/electrolyte.dart';
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
}
