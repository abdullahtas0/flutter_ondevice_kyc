import 'dart:math' as math;
import 'dart:typed_data';

import '../image/rgb_image.dart';

class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;
}

class Quad {
  const Quad({
    required this.tl,
    required this.tr,
    required this.br,
    required this.bl,
  });

  factory Quad.fromFlat(List<double> values) {
    return Quad(
      tl: Point2(values[0], values[1]),
      tr: Point2(values[2], values[3]),
      br: Point2(values[4], values[5]),
      bl: Point2(values[6], values[7]),
    );
  }

  final Point2 tl;
  final Point2 tr;
  final Point2 br;
  final Point2 bl;

  double get aspect {
    final width = (distance(tl, tr) + distance(bl, br)) / 2;
    final height = (distance(tl, bl) + distance(tr, br)) / 2;
    if (height == 0) return 0;
    return width / height;
  }

  Float64List toFlat() {
    return Float64List.fromList([
      tl.x,
      tl.y,
      tr.x,
      tr.y,
      br.x,
      br.y,
      bl.x,
      bl.y,
    ]);
  }
}

double distance(Point2 a, Point2 b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Finds a document quad by scanning inward from the ROI edges.
///
/// A light card on a dark table is tried first. A dark card on a light table
/// is the fallback. ID-1 is about 1.586, so quads outside [minAspect]–[maxAspect]
/// are rejected. A hit that only traces the ROI border loses to an inset hit.
Quad? findCardQuad(
  RgbImage image, {
  int left = 0,
  int top = 0,
  int? width,
  int? height,
  double minAspect = 1.2,
  double maxAspect = 1.95,
}) {
  final roiLeft = left.clamp(0, image.width - 1);
  final roiTop = top.clamp(0, image.height - 1);
  final roiWidth = (width ?? image.width - roiLeft).clamp(
    1,
    image.width - roiLeft,
  );
  final roiHeight = (height ?? image.height - roiTop).clamp(
    1,
    image.height - roiTop,
  );
  if (roiWidth < 24 || roiHeight < 24) return null;

  final gray = Uint8List(roiWidth * roiHeight);
  for (var y = 0; y < roiHeight; y++) {
    for (var x = 0; x < roiWidth; x++) {
      final index = ((roiTop + y) * image.width + roiLeft + x) * 3;
      final r = image.bytes[index];
      final g = image.bytes[index + 1];
      final b = image.bytes[index + 2];
      gray[y * roiWidth + x] = (r * 77 + g * 150 + b * 29) >> 8;
    }
  }
  final bright = _quadFromEdges(
    gray,
    roiLeft: roiLeft,
    roiTop: roiTop,
    roiWidth: roiWidth,
    roiHeight: roiHeight,
    minAspect: minAspect,
    maxAspect: maxAspect,
    dark: false,
  );
  final dark = _quadFromEdges(
    gray,
    roiLeft: roiLeft,
    roiTop: roiTop,
    roiWidth: roiWidth,
    roiHeight: roiHeight,
    minAspect: minAspect,
    maxAspect: maxAspect,
    dark: true,
  );
  final brightFills =
      bright != null && _fillsRoi(bright, roiLeft, roiTop, roiWidth, roiHeight);
  final darkFills =
      dark != null && _fillsRoi(dark, roiLeft, roiTop, roiWidth, roiHeight);
  if (bright != null && !brightFills) return bright;
  if (dark != null && !darkFills) return dark;
  return bright ?? dark;
}

Quad? _quadFromEdges(
  Uint8List gray, {
  required int roiLeft,
  required int roiTop,
  required int roiWidth,
  required int roiHeight,
  required double minAspect,
  required double maxAspect,
  required bool dark,
}) {
  final threshold = _otsu(gray);
  final topEdge = _scanHorizontal(
    gray,
    roiWidth,
    roiHeight,
    threshold,
    fromTop: true,
    dark: dark,
  );
  final bottomEdge = _scanHorizontal(
    gray,
    roiWidth,
    roiHeight,
    threshold,
    fromTop: false,
    dark: dark,
  );
  final leftEdge = _scanVertical(
    gray,
    roiWidth,
    roiHeight,
    threshold,
    fromLeft: true,
    dark: dark,
  );
  final rightEdge = _scanVertical(
    gray,
    roiWidth,
    roiHeight,
    threshold,
    fromLeft: false,
    dark: dark,
  );
  if (topEdge.length < 6 ||
      bottomEdge.length < 6 ||
      leftEdge.length < 6 ||
      rightEdge.length < 6) {
    return null;
  }

  final tl = Point2(
    _median(_tail(leftEdge, low: true, axis: _Axis.y).map((p) => p.x)),
    _median(_tail(topEdge, low: true, axis: _Axis.x).map((p) => p.y)),
  );
  final tr = Point2(
    _median(_tail(rightEdge, low: true, axis: _Axis.y).map((p) => p.x)),
    _median(_tail(topEdge, low: false, axis: _Axis.x).map((p) => p.y)),
  );
  final br = Point2(
    _median(_tail(rightEdge, low: false, axis: _Axis.y).map((p) => p.x)),
    _median(_tail(bottomEdge, low: false, axis: _Axis.x).map((p) => p.y)),
  );
  final bl = Point2(
    _median(_tail(leftEdge, low: false, axis: _Axis.y).map((p) => p.x)),
    _median(_tail(bottomEdge, low: true, axis: _Axis.x).map((p) => p.y)),
  );
  final quad = Quad(
    tl: Point2(tl.x + roiLeft, tl.y + roiTop),
    tr: Point2(tr.x + roiLeft, tr.y + roiTop),
    br: Point2(br.x + roiLeft, br.y + roiTop),
    bl: Point2(bl.x + roiLeft, bl.y + roiTop),
  );
  if (!_convex(quad)) return null;
  final aspect = quad.aspect;
  if (aspect < minAspect || aspect > maxAspect) return null;
  if (_area(quad) < roiWidth * roiHeight * 0.02) return null;
  return quad;
}

bool _fillsRoi(Quad quad, int left, int top, int width, int height) {
  const edge = 3.0;
  return quad.tl.x <= left + edge &&
      quad.tl.y <= top + edge &&
      quad.tr.x >= left + width - 1 - edge &&
      quad.bl.y >= top + height - 1 - edge;
}

enum _Axis { x, y }

List<Point2> _scanHorizontal(
  Uint8List gray,
  int width,
  int height,
  int threshold, {
  required bool fromTop,
  required bool dark,
}) {
  final points = <Point2>[];
  for (var x = 0; x < width; x += 2) {
    if (fromTop) {
      for (var y = 0; y < height; y++) {
        if (_isCard(gray[y * width + x], threshold, dark: dark)) {
          points.add(Point2(x.toDouble(), y.toDouble()));
          break;
        }
      }
    } else {
      for (var y = height - 1; y >= 0; y--) {
        if (_isCard(gray[y * width + x], threshold, dark: dark)) {
          points.add(Point2(x.toDouble(), y.toDouble()));
          break;
        }
      }
    }
  }
  return points;
}

List<Point2> _scanVertical(
  Uint8List gray,
  int width,
  int height,
  int threshold, {
  required bool fromLeft,
  required bool dark,
}) {
  final points = <Point2>[];
  for (var y = 0; y < height; y += 2) {
    if (fromLeft) {
      for (var x = 0; x < width; x++) {
        if (_isCard(gray[y * width + x], threshold, dark: dark)) {
          points.add(Point2(x.toDouble(), y.toDouble()));
          break;
        }
      }
    } else {
      for (var x = width - 1; x >= 0; x--) {
        if (_isCard(gray[y * width + x], threshold, dark: dark)) {
          points.add(Point2(x.toDouble(), y.toDouble()));
          break;
        }
      }
    }
  }
  return points;
}

bool _isCard(int value, int threshold, {required bool dark}) {
  if (dark) return value < threshold;
  return value > threshold;
}

List<Point2> _tail(
  List<Point2> points, {
  required bool low,
  required _Axis axis,
}) {
  final sorted = [...points]
    ..sort((a, b) {
      final av = axis == _Axis.x ? a.x : a.y;
      final bv = axis == _Axis.x ? b.x : b.y;
      return av.compareTo(bv);
    });
  final count = math.max(3, (sorted.length * 0.2).round());
  if (low) return sorted.take(count).toList();
  return sorted.skip(sorted.length - count).toList();
}

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  return sorted[sorted.length ~/ 2];
}

int _otsu(Uint8List gray) {
  final hist = List<int>.filled(256, 0);
  for (final value in gray) {
    hist[value]++;
  }
  final total = gray.length;
  var sum = 0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumBackground = 0;
  var weightBackground = 0;
  var best = -1.0;
  var threshold = 128;
  for (var t = 0; t < 256; t++) {
    weightBackground += hist[t];
    if (weightBackground == 0) continue;
    final weightForeground = total - weightBackground;
    if (weightForeground == 0) break;
    sumBackground += t * hist[t];
    final meanBackground = sumBackground / weightBackground;
    final meanForeground = (sum - sumBackground) / weightForeground;
    final variance =
        weightBackground *
        weightForeground *
        (meanBackground - meanForeground) *
        (meanBackground - meanForeground);
    if (variance >= best) {
      best = variance;
      threshold = t;
    }
  }
  return threshold;
}

bool _convex(Quad quad) {
  final points = [quad.tl, quad.tr, quad.br, quad.bl];
  double? sign;
  for (var i = 0; i < 4; i++) {
    final a = points[i];
    final b = points[(i + 1) % 4];
    final c = points[(i + 2) % 4];
    final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (cross.abs() < 1e-6) continue;
    final positive = cross > 0;
    if (sign == null) {
      sign = positive ? 1 : -1;
    } else if ((positive ? 1 : -1) != sign) {
      return false;
    }
  }
  return sign != null;
}

double _area(Quad quad) {
  final points = [quad.tl, quad.tr, quad.br, quad.bl];
  var sum = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = points[i];
    final b = points[(i + 1) % 4];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2;
}
