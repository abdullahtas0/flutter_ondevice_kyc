import 'dart:math' as math;
import 'dart:typed_data';

import '../image/rgb_image.dart';
import 'quad.dart';

/// Inverse-maps [quad] onto a top-down card whose aspect matches the quad edges.
RgbImage? warpQuad(RgbImage source, Quad quad) {
  final width = (distance(quad.tl, quad.tr) + distance(quad.bl, quad.br)) / 2;
  final height = (distance(quad.tl, quad.bl) + distance(quad.tr, quad.br)) / 2;
  final outWidth = math.max(2, width.round());
  final outHeight = math.max(2, height.round());
  final homography = _homography(
    destinations: [
      const Point2(0, 0),
      Point2(outWidth - 1, 0),
      Point2(outWidth - 1, outHeight - 1),
      Point2(0, outHeight - 1),
    ],
    sources: [quad.tl, quad.tr, quad.br, quad.bl],
  );
  if (homography == null) return null;

  final out = Uint8List(outWidth * outHeight * 3);
  for (var y = 0; y < outHeight; y++) {
    for (var x = 0; x < outWidth; x++) {
      final denominator = homography[6] * x + homography[7] * y + 1;
      if (denominator.abs() < 1e-8) continue;
      final srcX =
          (homography[0] * x + homography[1] * y + homography[2]) / denominator;
      final srcY =
          (homography[3] * x + homography[4] * y + homography[5]) / denominator;
      final index = (y * outWidth + x) * 3;
      out[index] = _sample(source, srcX, srcY, 0);
      out[index + 1] = _sample(source, srcX, srcY, 1);
      out[index + 2] = _sample(source, srcX, srcY, 2);
    }
  }
  return RgbImage(outWidth, outHeight, out);
}

List<double>? _homography({
  required List<Point2> destinations,
  required List<Point2> sources,
}) {
  final matrix = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final u = destinations[i].x;
    final v = destinations[i].y;
    final x = sources[i].x;
    final y = sources[i].y;
    final row = i * 2;
    matrix[row][0] = u;
    matrix[row][1] = v;
    matrix[row][2] = 1;
    matrix[row][6] = -u * x;
    matrix[row][7] = -v * x;
    matrix[row][8] = x;
    matrix[row + 1][3] = u;
    matrix[row + 1][4] = v;
    matrix[row + 1][5] = 1;
    matrix[row + 1][6] = -u * y;
    matrix[row + 1][7] = -v * y;
    matrix[row + 1][8] = y;
  }
  return _solve(matrix);
}

List<double>? _solve(List<List<double>> matrix) {
  const n = 8;
  for (var col = 0; col < n; col++) {
    var pivot = col;
    var best = matrix[col][col].abs();
    for (var row = col + 1; row < n; row++) {
      final value = matrix[row][col].abs();
      if (value > best) {
        best = value;
        pivot = row;
      }
    }
    if (best < 1e-10) return null;
    if (pivot != col) {
      final swap = matrix[col];
      matrix[col] = matrix[pivot];
      matrix[pivot] = swap;
    }
    final divisor = matrix[col][col];
    for (var c = col; c <= n; c++) {
      matrix[col][c] /= divisor;
    }
    for (var row = 0; row < n; row++) {
      if (row == col) continue;
      final factor = matrix[row][col];
      if (factor == 0) continue;
      for (var c = col; c <= n; c++) {
        matrix[row][c] -= factor * matrix[col][c];
      }
    }
  }
  return [for (var i = 0; i < n; i++) matrix[i][n]];
}

int _sample(RgbImage source, double x, double y, int channel) {
  if (x < 0 || y < 0 || x > source.width - 1 || y > source.height - 1) {
    return 0;
  }
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, source.width - 1);
  final y1 = math.min(y0 + 1, source.height - 1);
  final dx = x - x0;
  final dy = y - y0;
  final c00 = source.bytes[(y0 * source.width + x0) * 3 + channel];
  final c10 = source.bytes[(y0 * source.width + x1) * 3 + channel];
  final c01 = source.bytes[(y1 * source.width + x0) * 3 + channel];
  final c11 = source.bytes[(y1 * source.width + x1) * 3 + channel];
  final value =
      c00 * (1 - dx) * (1 - dy) +
      c10 * dx * (1 - dy) +
      c01 * (1 - dx) * dy +
      c11 * dx * dy;
  return value.round().clamp(0, 255);
}
