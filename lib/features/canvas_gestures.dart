import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A canvas owns pointers that start inside it. Otherwise the ancestor's
/// vertical scroll recognizer can win before the scale recognizer's pan slop.
class CanvasScaleRecognizer extends ScaleGestureRecognizer {
  CanvasScaleRecognizer() : super(dragStartBehavior: DragStartBehavior.down);
  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent || event is PointerPanZoomStartEvent) {
      resolve(GestureDisposition.accepted);
    }
  }
}

class CanvasGestures extends StatelessWidget {
  const CanvasGestures({
    super.key,
    required this.child,
    this.onStart,
    this.onUpdate,
  });
  final Widget child;
  final GestureScaleStartCallback? onStart;
  final GestureScaleUpdateCallback? onUpdate;
  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      if (onUpdate != null)
        CanvasScaleRecognizer:
            GestureRecognizerFactoryWithHandlers<CanvasScaleRecognizer>(
              CanvasScaleRecognizer.new,
              (recognizer) => recognizer
                ..onStart = onStart
                ..onUpdate = onUpdate,
            ),
    },
    child: child,
  );
}
