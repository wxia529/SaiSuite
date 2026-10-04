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
