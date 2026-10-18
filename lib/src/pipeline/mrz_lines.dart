import 'dart:math' as math;
import 'dart:typed_data';

import '../image/rgb_image.dart';

typedef LineImage = ({Uint8List bytes, int width, int height});

/// Splits a card photo into the full-width MRZ lines, top to bottom.
///
/// The recognizer reads one text line. A Turkish identity card has three,
/// so the whole bottom band must not be sent as a single image.
List<LineImage> segmentMrzLines(RgbImage image) {
  final straight = _straighten(image);
  final strict = _segment(straight, darkFraction: 0.72);
  if (strict.length >= 2) return strict;
  final loose = _segment(straight, darkFraction: 0.9);
  if (loose.length >= 2) return loose;
  return _fixedTd1Lines(straight);
}

RgbImage rotate180(RgbImage image) {
  final count = image.width * image.height;
  final out = Uint8List(image.bytes.length);
  for (var i = 0; i < count; i++) {
    final src = i * 3;
    final dst = (count - 1 - i) * 3;
    out[dst] = image.bytes[src];
    out[dst + 1] = image.bytes[src + 1];
    out[dst + 2] = image.bytes[src + 2];
  }
  return RgbImage(image.width, image.height, out);
}

LineImage lineFromImage(RgbImage image) {
  return (bytes: image.bytes, width: image.width, height: image.height);
}

List<LineImage> _segment(RgbImage image, {required double darkFraction}) {
  final width = image.width;
  final height = image.height;
  if (width < 40 || height < 40) return const [];

  final samples = <int>[];
  for (var y = height ~/ 3; y < height; y += 2) {
    for (var x = 0; x < width; x += 4) {
      samples.add(_lumaAt(image, x, y));
    }
  }
  if (samples.isEmpty) return const [];
  samples.sort();
  final median = samples[samples.length ~/ 2];
  final threshold = (median * darkFraction).round().clamp(30, 200);
  final ink = List<int>.filled(height, 0);
  for (var y = 0; y < height; y++) {
    var count = 0;
    for (var x = 0; x < width; x++) {
      if (_lumaAt(image, x, y) < threshold) count++;
    }
    ink[y] = count;
  }

  final minInk = width * 0.045;
  final bands = <({int top, int bottom})>[];
  var start = -1;
  for (var y = 0; y < height; y++) {
    final on = ink[y] >= minInk;
    if (on && start < 0) start = y;
    if (!on && start >= 0) {
      bands.add((top: start, bottom: y));
      start = -1;
    }
  }
  if (start >= 0) bands.add((top: start, bottom: height));

  final usable = <({int top, int bottom, int span})>[];
  for (final band in bands) {
    final bandHeight = band.bottom - band.top;
    if (bandHeight < height * 0.01 || bandHeight > height * 0.24) continue;
    final span = _inkSpan(image, band.top, band.bottom, threshold);
    if (span < width * 0.35) continue;
    usable.add((top: band.top, bottom: band.bottom, span: span));
  }
  final group = _lowestGroup(usable);
  if (group.length < 2) return const [];

  return [
    for (final band in group)
      lineFromImage(_stretch(_padded(image, band.top, band.bottom))),
  ];
}

List<({int top, int bottom, int span})> _lowestGroup(
  List<({int top, int bottom, int span})> bands,
) {
  if (bands.length < 2) return const [];
  for (var end = bands.length; end >= 2; end--) {
    for (final count in const [3, 2]) {
      if (end < count) continue;
      final group = bands.sublist(end - count, end);
      if (_consistent(group)) return group;
    }
  }
  return const [];
}

bool _consistent(List<({int top, int bottom, int span})> group) {
  final heights = [for (final band in group) band.bottom - band.top];
  final tallest = heights.reduce(math.max);
  final shortest = heights.reduce(math.min);
  if (shortest == 0 || tallest / shortest > 2.4) return false;
  for (var i = 1; i < group.length; i++) {
    final gap = group[i].top - group[i - 1].bottom;
    if (gap < 0 || gap > tallest * 2.4) return false;
  }
  return true;
}

RgbImage _padded(RgbImage image, int top, int bottom) {
  final bandHeight = math.max(1, bottom - top);
  final pad = math.max(1, (bandHeight * 0.28).round());
  final y0 = math.max(0, top - pad);
  final y1 = math.min(image.height, bottom + pad);
  return image.crop(0, y0, image.width, y1 - y0);
}

int _inkSpan(RgbImage image, int top, int bottom, int threshold) {
  var left = image.width;
  var right = -1;
  for (var y = top; y < bottom; y++) {
    for (var x = 0; x < image.width; x++) {
      if (_lumaAt(image, x, y) >= threshold) continue;
      if (x < left) left = x;
      if (x > right) right = x;
    }
  }
  if (right < left) return 0;
  return right - left + 1;
}

int _lumaAt(RgbImage image, int x, int y) {
  final index = (y * image.width + x) * 3;
  return (image.bytes[index] * 77 +
          image.bytes[index + 1] * 150 +
          image.bytes[index + 2] * 29) >>
      8;
}

RgbImage _stretch(RgbImage image) {
  if (image.width < 2 || image.height < 2) return image;
  final samples = <int>[];
  final step = math.max(1, (image.width * image.height) ~/ 800);
  for (var i = 0; i < image.width * image.height; i += step) {
    final index = i * 3;
    samples.add(
      (image.bytes[index] * 77 +
              image.bytes[index + 1] * 150 +
              image.bytes[index + 2] * 29) >>
          8,
    );
  }
  if (samples.length < 8) return image;
  samples.sort();
  final low = samples[(samples.length * 0.06).floor()];
  final high = samples[(samples.length * 0.94).floor()];
  if (high - low < 28) return image;
  final out = Uint8List(image.bytes.length);
  final scale = 255 / (high - low);
  for (var i = 0; i < image.bytes.length; i++) {
    out[i] = ((image.bytes[i] - low) * scale).round().clamp(0, 255);
  }
  return RgbImage(image.width, image.height, out);
}

RgbImage _straighten(RgbImage image) {
  final angle = _mrzAngle(image);
  if (angle.abs() < 0.02 || angle.abs() > 0.18) return image;
  return _rotate(image, -angle);
}

double _mrzAngle(RgbImage image) {
  final top = (image.height * 0.5).round();
  if (image.height - top < 16 || image.width < 48) return 0;
  final left = _inkRow(image, top, 0, image.width ~/ 4);
  final right = _inkRow(image, top, image.width * 3 ~/ 4, image.width);
  return math.atan2((right - left).toDouble(), image.width * 0.75);
}

int _inkRow(RgbImage image, int top, int x0, int x1) {
  var best = top;
  var bestCount = -1;
  for (var y = top; y < image.height; y++) {
    var count = 0;
    for (var x = x0; x < x1; x += 2) {
      if (_lumaAt(image, x, y) < 120) count++;
    }
    if (count > bestCount) {
      bestCount = count;
      best = y;
    }
  }
  return best;
}

RgbImage _rotate(RgbImage image, double angle) {
  final cosine = math.cos(angle);
  final sine = math.sin(angle);
  final cx = (image.width - 1) / 2;
  final cy = (image.height - 1) / 2;
  final out = Uint8List(image.bytes.length);
  for (var i = 0; i < out.length; i++) {
    out[i] = 236;
  }
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final sx = cosine * dx + sine * dy + cx;
      final sy = -sine * dx + cosine * dy + cy;
      final ix = sx.round();
      final iy = sy.round();
      if (ix < 0 || iy < 0 || ix >= image.width || iy >= image.height) continue;
      final src = (iy * image.width + ix) * 3;
      final dst = (y * image.width + x) * 3;
      out[dst] = image.bytes[src];
      out[dst + 1] = image.bytes[src + 1];
      out[dst + 2] = image.bytes[src + 2];
    }
  }
  return RgbImage(image.width, image.height, out);
}

/// Three equal slices of the bottom band. Used when the lines are present but
/// too close or too tilted for the projection to split them.
List<LineImage> _fixedTd1Lines(RgbImage image) {
  final top = (image.height * 0.58).round();
  final span = image.height - top;
  if (span < 24 || _bandSpread(image, top, image.height) < 16) return const [];
  final slice = span ~/ 3;
  if (slice < 8) return const [];
  return [
    for (var i = 0; i < 3; i++)
      lineFromImage(
        _stretch(image.crop(0, top + i * slice, image.width, slice)),
      ),
  ];
}

double _bandSpread(RgbImage image, int top, int bottom) {
  var count = 0;
  var sum = 0.0;
  var sumSq = 0.0;
  for (var y = top; y < bottom; y += 2) {
    for (var x = 0; x < image.width; x += 4) {
      final luma = _lumaAt(image, x, y).toDouble();
      sum += luma;
      sumSq += luma * luma;
      count++;
    }
  }
  if (count == 0) return 0;
  final mean = sum / count;
  final variance = sumSq / count - mean * mean;
  if (variance <= 0) return 0;
  return math.sqrt(variance);
}
