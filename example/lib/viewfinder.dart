import 'dart:math' as math;
import 'dart:ui';

/// ISO/IEC 7810 ID-1, the size of a national identity card.
const id1Aspect = 85.60 / 53.98;

/// Clockwise quarter turns that stand a back-camera buffer upright in portrait.
int portraitQuarterTurns(int sensorOrientation) {
  final degrees = sensorOrientation % 360;
  return (degrees ~/ 90) % 4;
}

/// CameraX sometimes delivers an already-portrait buffer. Rotating that again
/// lays the MRZ on its side, so the three lines never separate.
int analysisTurns({
  required int bufferWidth,
  required int bufferHeight,
  required int sensorOrientation,
}) {
  final sensorTurns = portraitQuarterTurns(sensorOrientation);
  if (sensorTurns.isOdd && bufferHeight > bufferWidth) return 0;
  return sensorTurns;
}

/// Size of the preview widget that fills [view] without stretching.
///
/// [cameraAspectRatio] is [CameraController.value.aspectRatio], which is the
/// landscape buffer width/height. The portrait preview uses the inverse.
Size previewCoverSize({
  required double viewWidth,
  required double viewHeight,
  required double cameraAspectRatio,
}) {
  final widthOverHeight = cameraAspectRatio == 0 ? 0.75 : 1 / cameraAspectRatio;
  var width = viewWidth;
  var height = width / widthOverHeight;
  if (height < viewHeight) {
    height = viewHeight;
    width = height * widthOverHeight;
  }
  return Size(width, height);
}

/// Where autofocus should sit: the MRZ band inside the on-screen guide.
Offset mrzFocusPoint(Size view) {
  if (view.width <= 0 || view.height <= 0) return const Offset(0.5, 0.62);
  final guide = idGuideRect(view);
  return Offset(
    (guide.center.dx / view.width).clamp(0.08, 0.92),
    ((guide.top + guide.height * 0.78) / view.height).clamp(0.08, 0.92),
  );
}

/// Sensor buffers are landscape. Odd sensor angles swap the displayed axes.
Size uprightPreviewSize({
  required double previewWidth,
  required double previewHeight,
  required int sensorOrientation,
}) {
  final swap = sensorOrientation % 180 != 0;
  if (swap) return Size(previewHeight, previewWidth);
  return Size(previewWidth, previewHeight);
}

/// Horizontal ID-1 window, centered in the viewfinder.
Rect idGuideRect(Size view) {
  final maxWidth = view.width * 0.9;
  final maxHeight = view.height * 0.7;
  var width = maxWidth;
  var height = width / id1Aspect;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * id1Aspect;
  }
  return Rect.fromLTWH(
    (view.width - width) / 2,
    (view.height - height) / 2,
    width,
    height,
  );
}

typedef GuideCrop = ({double left, double top, double right, double bottom});

/// Maps the on-screen guide back into an upright camera image, in 0–1 space.
GuideCrop guideCrop(Size view, Size image) {
  const full = (left: 0.0, top: 0.0, right: 1.0, bottom: 1.0);
  if (view.width <= 0 ||
      view.height <= 0 ||
      image.width <= 0 ||
      image.height <= 0) {
    return full;
  }
  final guide = idGuideRect(view);
  final scale = math.max(view.width / image.width, view.height / image.height);
  final dx = (view.width - image.width * scale) / 2;
  final dy = (view.height - image.height * scale) / 2;
  double nx(double x) => ((x - dx) / scale / image.width).clamp(0.0, 1.0);
  double ny(double y) => ((y - dy) / scale / image.height).clamp(0.0, 1.0);
  final left = nx(guide.left);
  final top = ny(guide.top);
  final right = nx(guide.right);
  final bottom = ny(guide.bottom);
  if (right - left < 0.2 || bottom - top < 0.12) return full;
  return (left: left, top: top, right: right, bottom: bottom);
}

/// Focus and exposure point for a tap on the covered preview.
Offset coveredFocusPoint(Offset local, Size view, Size image) {
  if (view.width <= 0 ||
      view.height <= 0 ||
      image.width <= 0 ||
      image.height <= 0) {
    return const Offset(0.5, 0.5);
  }
  final scale = math.max(view.width / image.width, view.height / image.height);
  final dx = (view.width - image.width * scale) / 2;
  final dy = (view.height - image.height * scale) / 2;
  final x = ((local.dx - dx) / scale / image.width).clamp(0.0, 1.0);
  final y = ((local.dy - dy) / scale / image.height).clamp(0.0, 1.0);
  return Offset(x, y);
}
