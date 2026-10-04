import 'dart:math' as math;

class ImageFrame {
  const ImageFrame({this.zoom = 1, this.x = .5, this.y = .5});
  final double zoom, x, y;
  Map<String, double> toMap() => {'zoom': zoom, 'x': x, 'y': y};
  factory ImageFrame.fromMap(Map<dynamic, dynamic>? value) {
    double read(String key, double fallback) {
      final v = value?[key] ?? fallback;
      if (v is! num || !v.isFinite) throw const FormatException('取景参数无效');
      return v.toDouble();
    }

    return ImageFrame(
      zoom: read('zoom', 1).clamp(1, 8),
      x: read('x', .5).clamp(0, 1),
      y: read('y', .5).clamp(0, 1),
    );
  }
}

class ImageCrop {
  const ImageCrop(this.left, this.top, this.width, this.height);
  final double left, top, width, height;
}

/// Source-pixel geometry shared by the gesture preview and image export.
ImageCrop imageCrop(
  double sourceWidth,
  double sourceHeight,
  double width,
  double height,
  ImageFrame frame, {
  bool grid = false,
}) {
  if ([
    sourceWidth,
    sourceHeight,
    width,
    height,
  ].any((v) => !v.isFinite || v <= 0)) {
    throw const FormatException('图片尺寸无效');
  }
  final safe = ImageFrame.fromMap(frame.toMap());
  final scale =
      math.max(width / sourceWidth, height / sourceHeight) * safe.zoom;
  var sw = width / scale, sh = height / scale;
  if (grid) {
    sw = sh = (math.min(sw, sh) / 3).floor() * 3.0;
    if (sw < 3) throw const FormatException('当前裁切范围太小，无法切成九格');
  }
  var left = (safe.x * sourceWidth - sw / 2).clamp(
    0.0,
    math.max(0.0, sourceWidth - sw),
  );
  var top = (safe.y * sourceHeight - sh / 2).clamp(
    0.0,
    math.max(0.0, sourceHeight - sh),
  );
  if (grid) {
    left = left.roundToDouble();
    top = top.roundToDouble();
  }
  return ImageCrop(left.toDouble(), top.toDouble(), sw, sh);
}
