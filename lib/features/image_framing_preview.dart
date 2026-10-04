import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/image_framing.dart';
import 'canvas_gestures.dart';

class ImageFramingPreview extends StatefulWidget {
  const ImageFramingPreview({
    super.key,
    required this.image,
    required this.value,
    required this.onChanged,
    this.sourceSize,
    this.ratio = 1,
    this.grid = false,
  });
  final ui.Image image;
  final ImageFrame value;
  final ValueChanged<ImageFrame>? onChanged;
  final Size? sourceSize;
  final double ratio;
  final bool grid;
  @override
  State<ImageFramingPreview> createState() => _ImageFramingPreviewState();
}

class _ImageFramingPreviewState extends State<ImageFramingPreview> {
  Offset anchor = Offset.zero;
  double baseZoom = 1;
  Size get source =>
      widget.sourceSize ??
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());
  double get maxZoom =>
      widget.grid ? (source.shortestSide / 3).clamp(1.0, 8.0) : 8;
  ImageCrop crop(ImageFrame frame, Size size) => imageCrop(
    source.width,
    source.height,
    size.width,
    size.height,
    frame,
    grid: widget.grid,
  );
  void begin(Offset focal, Size size) {
    final r = crop(widget.value, size);
    baseZoom = widget.value.zoom;
    anchor = Offset(
      r.left + focal.dx / size.width * r.width,
      r.top + focal.dy / size.height * r.height,
    );
  }

  void move(Offset focal, double zoom, Size size) {
    final r = crop(ImageFrame(zoom: zoom), size);
    final left = (anchor.dx - focal.dx / size.width * r.width).clamp(
      0.0,
      source.width - r.width,
    );
    final top = (anchor.dy - focal.dy / size.height * r.height).clamp(
      0.0,
      source.height - r.height,
    );
    widget.onChanged?.call(
      ImageFrame(
        zoom: zoom,
        x: (left + r.width / 2) / source.width,
        y: (top + r.height / 2) / source.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = Size(box.maxWidth, box.maxWidth / widget.ratio);
      return AspectRatio(
        aspectRatio: widget.ratio,
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && widget.onChanged != null) {
              begin(event.localPosition, size);
              move(
                event.localPosition,
                (baseZoom * (event.scrollDelta.dy > 0 ? .9 : 1.1)).clamp(
                  1.0,
                  maxZoom,
                ),
                size,
              );
            }
          },
          child: CanvasGestures(
            onStart: widget.onChanged == null
                ? null
                : (d) => begin(d.localFocalPoint, size),
            onUpdate: widget.onChanged == null
                ? null
                : (d) => move(
                    d.localFocalPoint,
                    (baseZoom * d.scale).clamp(1.0, maxZoom),
                    size,
                  ),
            child: ClipRect(
              child: CustomPaint(
                painter: ImageFramePainter(
                  widget.image,
                  source,
                  widget.value,
                  grid: widget.grid,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ImageFramePainter extends CustomPainter {
  ImageFramePainter(
    this.image,
    this.sourceSize,
    this.frame, {
    this.grid = false,
  });
  final ui.Image image;
  final Size sourceSize;
  final ImageFrame frame;
  final bool grid;
  @override
  void paint(Canvas canvas, Size size) {
    final r = imageCrop(
      sourceSize.width,
      sourceSize.height,
      size.width,
      size.height,
      frame,
      grid: grid,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        r.left / sourceSize.width * image.width,
        r.top / sourceSize.height * image.height,
        r.width / sourceSize.width * image.width,
        r.height / sourceSize.height * image.height,
      ),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
    if (!grid) return;
    for (var i = 1; i < 3; i++) {
      for (final color in [Colors.black38, Colors.white]) {
        final p = Paint()
          ..color = color
          ..strokeWidth = color == Colors.white ? 1 : 3;
        canvas.drawLine(
          Offset(size.width * i / 3, 0),
          Offset(size.width * i / 3, size.height),
          p,
        );
        canvas.drawLine(
          Offset(0, size.height * i / 3),
          Offset(size.width, size.height * i / 3),
          p,
        );
      }
    }
    for (var i = 0; i < 9; i++) {
      final p = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(
        canvas,
        Offset(
          (i % 3 + .5) * size.width / 3 - p.width / 2,
          (i ~/ 3 + .5) * size.height / 3 - p.height / 2,
        ),
      );
      p.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant ImageFramePainter old) => true;
}
