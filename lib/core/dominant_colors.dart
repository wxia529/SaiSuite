import 'dart:math' as math;
import 'dart:typed_data';

/// Bounded sampling and quantized buckets avoid a model or full image clustering.
/// Returns opaque ARGB values ordered by population; transparent pixels are ignored.
List<int> dominantColors(Uint8List rgba, {int count = 6}) {
  final buckets = <int, List<int>>{};
  final stride = math.max(1, (rgba.length / 4 / 20000).ceil());
  for (var pixel = 0; pixel < rgba.length ~/ 4; pixel += stride) {
    final i = pixel * 4;
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
    final entry = buckets.putIfAbsent(key, () => [0, 0, 0, 0]);
    entry[0]++;
    entry[1] += r;
    entry[2] += g;
    entry[3] += b;
  }
  final ordered = buckets.values.toList()..sort((a, b) => b[0].compareTo(a[0]));
  final selected = <int>[];
  for (final v in ordered) {
    final r = (v[1] / v[0]).round(),
        g = (v[2] / v[0]).round(),
        b = (v[3] / v[0]).round();
    if (selected.any(
      (c) =>
          math.pow(r - ((c >> 16) & 255), 2) +
              math.pow(g - ((c >> 8) & 255), 2) +
              math.pow(b - (c & 255), 2) <
          900,
    )) {
      continue;
    }
    selected.add(0xff000000 | r << 16 | g << 8 | b);
    if (selected.length == count.clamp(1, 8)) break;
  }
  return selected;
}
