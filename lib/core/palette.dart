import 'dart:math' as math;

import 'package:flutter/material.dart';

Color parseHex(String text) {
  final t = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(t)) {
    throw const FormatException('请输入六位 HEX，例如 #147D73');
  }
  return Color(0xff000000 | int.parse(t, radix: 16));
}

String hexColor(Color c) =>
    '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
List<Color> colorPalette(Color color, String kind) {
  final hsl = HSLColor.fromColor(color);
  final shifts = switch (kind) {
    '互补色' => [0.0, 180.0],
    '三色组合' => [0.0, 120.0, 240.0],
    _ => [-30.0, 0.0, 30.0],
  };
  return shifts
      .map((shift) => hsl.withHue((hsl.hue + shift + 360) % 360).toColor())
      .toList();
}

double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
}

class PalettePreset {
  const PalettePreset(this.name, this.colors);
  final String name;
  final List<Color> colors;
}

const palettePresets = [
  PalettePreset('海岸微风', [
    Color(0xff194759),
    Color(0xff398c9c),
    Color(0xff8dc5c2),
    Color(0xffe7e6d6),
    Color(0xffd6aa7e),
  ]),
  PalettePreset('森林薄雾', [
    Color(0xff203b32),
    Color(0xff56765d),
    Color(0xffa7bba0),
    Color(0xffe5e9dc),
    Color(0xffc9a77f),
  ]),
  PalettePreset('日落橘光', [
    Color(0xff642e3b),
    Color(0xffb65353),
    Color(0xffe99362),
    Color(0xffffd5a0),
    Color(0xfffff0dc),
  ]),
  PalettePreset('莓果奶油', [
    Color(0xff512d50),
    Color(0xff945777),
    Color(0xffc690a7),
    Color(0xffead1d9),
    Color(0xfffff6e9),
  ]),
  PalettePreset('鸢尾花园', [
    Color(0xff333959),
    Color(0xff6968a3),
    Color(0xffa19fca),
    Color(0xffd7d4ec),
    Color(0xfff4e9d8),
  ]),
  PalettePreset('薄荷汽水', [
    Color(0xff164a46),
    Color(0xff3c9c8a),
    Color(0xff8cdbc4),
    Color(0xffd6f4df),
    Color(0xffe8e2a8),
  ]),
  PalettePreset('沙丘日记', [
    Color(0xff51453a),
    Color(0xff9b7860),
    Color(0xffc9a982),
    Color(0xffe1d0b5),
    Color(0xfff6f0e4),
  ]),
  PalettePreset('午夜霓虹', [
    Color(0xff1b213f),
    Color(0xff575fa7),
    Color(0xffae6bcc),
    Color(0xffe992b2),
    Color(0xff73d6d0),
  ]),
  PalettePreset('青瓷茶室', [
    Color(0xff2d4e4f),
    Color(0xff618882),
    Color(0xffa9c5b5),
    Color(0xffe2e6cc),
    Color(0xffb89c6d),
  ]),
  PalettePreset('雨后蓝调', [
    Color(0xff233952),
    Color(0xff517793),
    Color(0xff88adc0),
    Color(0xffc6dae0),
    Color(0xffe9e5df),
  ]),
  PalettePreset('柠檬花开', [
    Color(0xff435445),
    Color(0xff86a76b),
    Color(0xffd4df8c),
    Color(0xffffe698),
    Color(0xfffff7db),
  ]),
  PalettePreset('暖调纸页', [
    Color(0xff463e38),
    Color(0xff8e7464),
    Color(0xffc5a58d),
    Color(0xffe7d4bf),
    Color(0xfffff9ee),
  ]),
];

const paletteStyles = ['互补色', '类似色', '三色组合', '分裂互补', '四色组合', '单色层次'];
List<Color> designPalette(Color color, String kind) {
  final h = HSLColor.fromColor(color);
  Color shifted(double shift, [double? lightness, double? saturation]) => h
      .withHue((h.hue + shift + 360) % 360)
      .withLightness(lightness ?? h.lightness)
      .withSaturation(saturation ?? h.saturation)
      .toColor();
  return switch (kind) {
    '互补色' => [
      color,
      shifted(180),
      shifted(0, .88, h.saturation * .6),
      shifted(180, .3),
      shifted(0, .16),
    ],
    '三色组合' => [
      color,
      shifted(120),
      shifted(240),
      shifted(0, .9, h.saturation * .35),
      shifted(0, .18),
    ],
    '分裂互补' => [
      color,
      shifted(150),
      shifted(210),
      shifted(0, .9, h.saturation * .4),
      shifted(0, .2),
    ],
    '四色组合' => [
      color,
      shifted(90),
      shifted(180),
      shifted(270),
      shifted(0, .92, h.saturation * .3),
    ],
    '单色层次' => [
      color,
      shifted(0, .18),
      shifted(0, .35),
      shifted(0, .7),
      shifted(0, .9, h.saturation * .55),
    ],
    _ => [color, shifted(-30), shifted(30), shifted(0, .85), shifted(0, .2)],
  };
}

PalettePreset randomPalette(math.Random random) {
  final base = HSLColor.fromAHSL(
    1,
    random.nextDouble() * 360,
    .45 + random.nextDouble() * .35,
    .35 + random.nextDouble() * .3,
  ).toColor();
  final style = paletteStyles[random.nextInt(paletteStyles.length)];
  return PalettePreset(style, designPalette(base, style));
}
