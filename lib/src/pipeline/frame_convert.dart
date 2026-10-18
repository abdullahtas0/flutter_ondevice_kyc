import 'dart:math' as math;
import 'dart:typed_data';

import '../image/rgb_image.dart';

/// Longest edge kept for detection and OCR. The preview stays full resolution.
const analysisMaxLongEdge = 1280;

enum RawFrameLayout { yuv420, nv21, bgra8888, rgba8888 }

class RawPlane {
  const RawPlane({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class RawCameraFrame {
  const RawCameraFrame({
    required this.width,
    required this.height,
    required this.layout,
    required this.planes,
    this.quarterTurns = 0,
    this.framed = false,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 1,
    this.cropBottom = 1,
  });

  final int width;
  final int height;
  final RawFrameLayout layout;
  final List<RawPlane> planes;

  /// Clockwise quarter turns that make a portrait-held back camera upright.
  final int quarterTurns;

  /// The crop is the on-screen document guide, so the guide itself is a quad.
  final bool framed;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
}

typedef PackedRgb = ({Uint8List bytes, int width, int height});

PackedRgb yuv420ToPacked({
  required int width,
  required int height,
  required Uint8List y,
  required Uint8List u,
  required Uint8List v,
  required int yRow,
  required int uRow,
  required int vRow,
  required int yPix,
  required int uPix,
  required int vPix,
}) {
  final out = Uint8List(width * height * 3);
  for (var row = 0; row < height; row++) {
    for (var col = 0; col < width; col++) {
      final yIndex = row * yRow + col * yPix;
      final uvRow = (row >> 1) * uRow;
      final uvCol = (col >> 1);
      final uIndex = uvRow + uvCol * uPix;
      final vIndex = (row >> 1) * vRow + uvCol * vPix;
      final rgb = _yuvToRgb(_at(y, yIndex), _at(u, uIndex), _at(v, vIndex));
      final dst = (row * width + col) * 3;
      out[dst] = rgb.$1;
      out[dst + 1] = rgb.$2;
      out[dst + 2] = rgb.$3;
    }
  }
  return (bytes: out, width: width, height: height);
}

PackedRgb nv21ToPacked({
  required int width,
  required int height,
  required Uint8List y,
  required Uint8List vu,
  required int yRow,
  required int vuRow,
  required int yPix,
  required int vuPix,
}) {
  final out = Uint8List(width * height * 3);
  for (var row = 0; row < height; row++) {
    for (var col = 0; col < width; col++) {
      final yIndex = row * yRow + col * yPix;
      final uvIndex = (row >> 1) * vuRow + (col >> 1) * vuPix;
      final rgb = _yuvToRgb(
        _at(y, yIndex),
        _at(vu, uvIndex + 1),
        _at(vu, uvIndex),
      );
      final dst = (row * width + col) * 3;
      out[dst] = rgb.$1;
      out[dst + 1] = rgb.$2;
      out[dst + 2] = rgb.$3;
    }
  }
  return (bytes: out, width: width, height: height);
}

PackedRgb bgraToPacked({
  required int width,
  required int height,
  required Uint8List bytes,
  required int bytesPerRow,
}) {
  final out = Uint8List(width * height * 3);
  for (var row = 0; row < height; row++) {
    for (var col = 0; col < width; col++) {
      final src = row * bytesPerRow + col * 4;
      final dst = (row * width + col) * 3;
      out[dst] = _at(bytes, src + 2);
      out[dst + 1] = _at(bytes, src + 1);
      out[dst + 2] = _at(bytes, src);
    }
  }
  return (bytes: out, width: width, height: height);
}

PackedRgb rgbaToPacked({
  required int width,
  required int height,
  required Uint8List bytes,
  required int bytesPerRow,
}) {
  final out = Uint8List(width * height * 3);
  for (var row = 0; row < height; row++) {
    for (var col = 0; col < width; col++) {
      final src = row * bytesPerRow + col * 4;
      final dst = (row * width + col) * 3;
      out[dst] = _at(bytes, src);
      out[dst + 1] = _at(bytes, src + 1);
      out[dst + 2] = _at(bytes, src + 2);
    }
  }
  return (bytes: out, width: width, height: height);
}

RgbImage packedToImage(PackedRgb packed) {
  return RgbImage(packed.width, packed.height, packed.bytes);
}

/// Rotates, crops to the guide, then limits the long edge.
PackedRgb alignCameraPacked(
  PackedRgb packed, {
  int quarterTurns = 0,
  double cropLeft = 0,
  double cropTop = 0,
  double cropRight = 1,
  double cropBottom = 1,
  int maxLongEdge = analysisMaxLongEdge,
}) {
  final turned = rotatePacked(packed, quarterTurns);
  final cropped = cropPackedNormalized(
    turned,
    left: cropLeft,
    top: cropTop,
    right: cropRight,
    bottom: cropBottom,
  );
  return limitLongEdge(cropped, maxLongEdge);
}

/// Clockwise quarter turns. 1 is 90°, 2 is 180°, 3 is 270°.
PackedRgb rotatePacked(PackedRgb packed, int quarterTurns) {
  final turns = quarterTurns % 4;
  if (turns == 0) return packed;
  final width = packed.width;
  final height = packed.height;
  final outWidth = turns.isOdd ? height : width;
  final outHeight = turns.isOdd ? width : height;
  final out = Uint8List(outWidth * outHeight * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final src = (y * width + x) * 3;
      final (dx, dy) = switch (turns) {
        1 => (height - 1 - y, x),
        2 => (width - 1 - x, height - 1 - y),
        _ => (y, width - 1 - x),
      };
      final dst = (dy * outWidth + dx) * 3;
      out[dst] = packed.bytes[src];
      out[dst + 1] = packed.bytes[src + 1];
      out[dst + 2] = packed.bytes[src + 2];
    }
  }
  return (bytes: out, width: outWidth, height: outHeight);
}

PackedRgb cropPackedNormalized(
  PackedRgb packed, {
  required double left,
  required double top,
  required double right,
  required double bottom,
}) {
  final x0 = (left.clamp(0.0, 1.0) * packed.width).floor().clamp(
    0,
    packed.width - 1,
  );
  final y0 = (top.clamp(0.0, 1.0) * packed.height).floor().clamp(
    0,
    packed.height - 1,
  );
  final x1 = (right.clamp(0.0, 1.0) * packed.width).ceil().clamp(
    x0 + 1,
    packed.width,
  );
  final y1 = (bottom.clamp(0.0, 1.0) * packed.height).ceil().clamp(
    y0 + 1,
    packed.height,
  );
  if (x0 == 0 && y0 == 0 && x1 == packed.width && y1 == packed.height) {
    return packed;
  }
  final outWidth = x1 - x0;
  final outHeight = y1 - y0;
  final out = Uint8List(outWidth * outHeight * 3);
  for (var y = 0; y < outHeight; y++) {
    final src = ((y0 + y) * packed.width + x0) * 3;
    final dst = y * outWidth * 3;
    out.setRange(dst, dst + outWidth * 3, packed.bytes, src);
  }
  return (bytes: out, width: outWidth, height: outHeight);
}

PackedRgb limitLongEdge(PackedRgb packed, int maxLongEdge) {
  final long = math.max(packed.width, packed.height);
  if (long <= maxLongEdge || maxLongEdge < 2) return packed;
  final scale = maxLongEdge / long;
  final width = math.max(2, (packed.width * scale).round());
  final height = math.max(2, (packed.height * scale).round());
  final out = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    final sy0 = (y * packed.height / height).floor();
    final sy1 = math.min(
      packed.height,
      ((y + 1) * packed.height / height).ceil(),
    );
    for (var x = 0; x < width; x++) {
      final sx0 = (x * packed.width / width).floor();
      final sx1 = math.min(
        packed.width,
        ((x + 1) * packed.width / width).ceil(),
      );
      var red = 0;
      var green = 0;
      var blue = 0;
      var count = 0;
      for (var sy = sy0; sy < sy1; sy++) {
        for (var sx = sx0; sx < sx1; sx++) {
          final index = (sy * packed.width + sx) * 3;
          red += packed.bytes[index];
          green += packed.bytes[index + 1];
          blue += packed.bytes[index + 2];
          count++;
        }
      }
      final dst = (y * width + x) * 3;
      out[dst] = red ~/ count;
      out[dst + 1] = green ~/ count;
      out[dst + 2] = blue ~/ count;
    }
  }
  return (bytes: out, width: width, height: height);
}

int _at(Uint8List bytes, int index) {
  if (index < 0 || index >= bytes.length) return 128;
  return bytes[index];
}

(int, int, int) _yuvToRgb(int y, int u, int v) {
  final c = y - 16;
  final d = u - 128;
  final e = v - 128;
  final red = (298 * c + 409 * e + 128) >> 8;
  final green = (298 * c - 100 * d - 208 * e + 128) >> 8;
  final blue = (298 * c + 516 * d + 128) >> 8;
  return (red.clamp(0, 255), green.clamp(0, 255), blue.clamp(0, 255));
}
