import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:archive/archive.dart';

img.Image readCreativeImage(Uint8List bytes, {bool animation = false}) {
  if (bytes.length > 30 * 1024 * 1024) {
    throw const FormatException('图片超过 30 MB');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null) throw const FormatException('无法识别图片格式');
  if (info.width * info.height > 16000000 ||
      (animation &&
          (info.numFrames > 120 ||
              info.width * info.height * info.numFrames > 32000000))) {
    throw const FormatException('图片超过 1600 万像素，或动画超过 120 帧／3200 万总像素');
  }
  final decoded = animation ? decoder!.decode(bytes) : decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('无法解码图片');
  return img.bakeOrientation(decoded);
}

Map<String, dynamic> creativeImageJob(Map<String, dynamic> a) {
  final action = a['action'] as String;
  Uint8List png(img.Image image) => img.encodePng(image);
  if (action == 'gradient') {
    final width = a['width'] as int, height = a['height'] as int;
    if (width < 32 ||
        height < 32 ||
        width > 4096 ||
        height > 4096 ||
        width * height > 8000000) {
      throw const FormatException('尺寸须为 32—4096，总像素不超过 800 万');
    }
    final colors = (a['colors'] as List).cast<int>();
    final angle = (a['angle'] as num).toDouble() * math.pi / 180;
    final dx = math.cos(angle), dy = math.sin(angle);
    final span = dx.abs() * width + dy.abs() * height;
    final noise = (a['noise'] as num).toDouble();
    final random = math.Random(31);
    final image = img.Image(width: width, height: height);
    for (final p in image) {
      final t =
          (((p.x - width / 2) * dx + (p.y - height / 2) * dy) / span + .5)
              .clamp(0.0, 1.0) *
          (colors.length - 1);
      final index = t.floor().clamp(0, colors.length - 2), u = t - index;
      final jitter = (random.nextDouble() - .5) * noise;
      int component(int shift) =>
          ((((colors[index] >> shift) & 255) * (1 - u) +
                      ((colors[index + 1] >> shift) & 255) * u) +
                  jitter)
              .round()
              .clamp(0, 255);
      p
        ..r = component(16)
        ..g = component(8)
        ..b = component(0);
    }
    return {'bytes': png(image), 'width': width, 'height': height};
  }
  if (action == 'gifMake') {
    final sources = (a['images'] as List).cast<Uint8List>();
    if (sources.length < 2 || sources.length > 60) {
      throw const FormatException('请选择 2—60 张图片');
    }
    final durations = (a['durations'] as List).cast<int>();
    final edge = a['edge'] as int;
    if (edge < 64 ||
        edge > 640 ||
        durations.length != sources.length ||
        durations.any((d) => d < 20 || d > 10000)) {
      throw const FormatException('每帧时长须为 20—10000 ms，边长 64—640');
    }
    img.Image? animation;
    for (var i = 0; i < sources.length; i++) {
      final original = readCreativeImage(sources[i]);
      final fitted = img.copyResize(
        original,
        width: edge,
        height: edge,
        maintainAspect: true,
        backgroundColor: img.ColorRgba8(255, 255, 255, 255),
      );
      fitted.frameDuration = durations[i];
      if (animation == null) {
        animation = fitted;
      } else {
        animation.addFrame(fitted);
      }
    }
    animation!.loopCount = 0;
    final encoded = img.encodeGif(animation);
    if (a['loop'] != true) {
      // Omitting the Netscape looping extension is the portable one-shot format.
      final marker = 'NETSCAPE2.0'.codeUnits;
      for (var i = 3; i < encoded.length - marker.length - 5; i++) {
        if (encoded[i - 3] == 0x21 &&
            encoded[i - 2] == 0xff &&
            List.generate(marker.length, (j) => encoded[i + j]).join(',') ==
                marker.join(',')) {
          return {
            'bytes': Uint8List.fromList([
              ...encoded.sublist(0, i - 3),
              ...encoded.sublist(i + 16),
            ]),
          };
        }
      }
      throw const FormatException('无法设置 GIF 播放次数');
    }
    return {'bytes': encoded};
  }
  final source = readCreativeImage(
    a['bytes'] as Uint8List,
    animation: action == 'gifSplit',
  );
  if (action == 'normalize') {
    final scale = math.min(
      1.0,
      (a['edge'] as int? ?? 3000) / math.max(source.width, source.height),
    );
    final image = scale < 1
        ? img.copyResize(
            source,
            width: (source.width * scale).round(),
            height: (source.height * scale).round(),
          )
        : source;
    return {'bytes': png(image), 'width': image.width, 'height': image.height};
  }
  if (action == 'crop') {
    final x = (a['left'] as int).clamp(0, source.width - 1),
        y = (a['top'] as int).clamp(0, source.height - 1);
    final width = (a['width'] as int).clamp(1, source.width - x),
        height = (a['height'] as int).clamp(1, source.height - y);
    return {
      'bytes': png(
        img.copyCrop(source, x: x, y: y, width: width, height: height),
      ),
    };
  }
  if (action == 'grid') {
    final tile = math.min(source.width, source.height) ~/ 3;
    if (tile < 1) throw const FormatException('图片尺寸太小');
    final side = tile * 3;
    final x = ((source.width - side) * (a['x'] as num)).round();
    final y = ((source.height - side) * (a['y'] as num)).round();
    final cropped = img.copyCrop(source, x: x, y: y, width: side, height: side);
    final archive = Archive();
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final bytes = png(
          img.copyCrop(
            cropped,
            x: col * tile,
            y: row * tile,
            width: tile,
            height: tile,
          ),
        );
        archive.add(
          ArchiveFile('九格_${row * 3 + col + 1}.png', bytes.length, bytes),
        );
      }
    }
    return {
      'bytes': ZipEncoder().encode(archive),
      'preview': png(cropped),
      'tile': tile,
    };
  }
  if (action == 'gifSplit') {
    final header = a['bytes'] as Uint8List;
    if (header.length < 6 ||
        String.fromCharCodes(header.sublist(0, 6)) != 'GIF87a' &&
            String.fromCharCodes(header.sublist(0, 6)) != 'GIF89a') {
      throw const FormatException('请选择 GIF 动画文件');
    }
    final archive = Archive();
    final durations = <int>[];
    for (var i = 0; i < source.numFrames; i++) {
      final frame = source.frames[i];
      final bytes = png(frame);
      archive.add(
        ArchiveFile(
          '帧_${(i + 1).toString().padLeft(3, '0')}.png',
          bytes.length,
          bytes,
        ),
      );
      durations.add(frame.frameDuration);
    }
    final timing = Uint8List.fromList(
      durations
          .asMap()
          .entries
          .map((e) => '${e.key + 1},${e.value}')
          .join('\n')
          .codeUnits,
    );
    archive.add(ArchiveFile('frame-timing-ms.txt', timing.length, timing));
    return {
      'bytes': ZipEncoder().encode(archive),
      'preview': png(source.frames.first),
      'frames': source.numFrames,
    };
  }
  if (action == 'phantom') {
    final other = readCreativeImage(a['other'] as Uint8List);
    final width = math.min(source.width, 1600),
        height = (source.height * width / source.width).round();
    final light = img.copyResize(source, width: width, height: height);
    final dark = img.copyResize(
      other,
      width: width,
      height: height,
      maintainAspect: true,
      backgroundColor: img.ColorRgb8(0, 0, 0),
    );
    final result = img.Image(width: width, height: height, numChannels: 4);
    for (final p in result) {
      final w = 127.5 + img.getLuminance(light.getPixel(p.x, p.y)) / 2;
      final b = img.getLuminance(dark.getPixel(p.x, p.y)) / 2;
      final alpha = (255 - w + b).round().clamp(0, 255);
      final color = alpha == 0 ? 0 : (b * 255 / alpha).round().clamp(0, 255);
      p
        ..r = color
        ..g = color
        ..b = color
        ..a = alpha;
    }
    return {'bytes': png(result), 'width': width, 'height': height};
  }
  if (action == 'count') {
    final scale = math.min(1.0, 720 / math.max(source.width, source.height));
    final image = img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
    );
    final w = image.width, h = image.height;
    final foreground = Uint8List(w * h);
    final threshold = a['threshold'] as int;
    final dark = a['dark'] == true;
    for (final p in image) {
      final lum = img.getLuminance(p);
      foreground[p.y * w + p.x] = (dark ? lum < threshold : lum > threshold)
          ? 1
          : 0;
    }
    final seen = Uint8List(w * h), points = <List<double>>[];
    final minimum = a['minArea'] as int;
    for (var start = 0; start < w * h; start++) {
      if (foreground[start] == 0 || seen[start] != 0) continue;
      final queue = <int>[start];
      seen[start] = 1;
      var sx = 0, sy = 0, left = w, right = 0, top = h, bottom = 0;
      for (var q = 0; q < queue.length; q++) {
        final pos = queue[q], x = pos % w, y = pos ~/ w;
        sx += x;
        sy += y;
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
        for (var yy = math.max(0, y - 1); yy <= math.min(h - 1, y + 1); yy++) {
          for (
            var xx = math.max(0, x - 1);
            xx <= math.min(w - 1, x + 1);
            xx++
          ) {
            final n = yy * w + xx;
            if (foreground[n] == 1 && seen[n] == 0) {
              seen[n] = 1;
              queue.add(n);
            }
          }
        }
      }
      final ratio = (right - left + 1) / (bottom - top + 1);
      if (queue.length >= minimum &&
          queue.length < w * h * .15 &&
          ratio > .35 &&
          ratio < 2.8 &&
          left > 0 &&
          top > 0 &&
          right < w - 1 &&
          bottom < h - 1) {
        points.add([sx / queue.length / w, sy / queue.length / h]);
        if (points.length > 1000) {
          throw const FormatException('识别超过 1000 个区域，请调整阈值或裁剪图片');
        }
      }
    }
    return {'points': points};
  }
  throw const FormatException('不支持的图片操作');
}
