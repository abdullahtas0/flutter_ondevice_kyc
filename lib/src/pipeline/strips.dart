import 'dart:math' as math;
import 'dart:typed_data';

import '../image/rgb_image.dart';
import 'detection.dart';
import 'mrz_lines.dart';
import 'quad.dart';
import 'warp.dart';

typedef StripPayload = ({
  Uint8List mrz,
  int mrzWidth,
  int mrzHeight,
  Uint8List pan,
  int panWidth,
  int panHeight,
  Float64List quad,
  List<LineImage> mrzLines,
  List<LineImage> flippedLines,
});

Float64List encodeDetections(List<Detection> detections) {
  final out = Float64List(detections.length * 6);
  for (var i = 0; i < detections.length; i++) {
    final box = detections[i];
    final offset = i * 6;
    out[offset] = box.x1;
    out[offset + 1] = box.y1;
    out[offset + 2] = box.x2;
    out[offset + 3] = box.y2;
    out[offset + 4] = box.score;
    out[offset + 5] = box.classId.toDouble();
  }
  return out;
}

/// Runs on a worker isolate. Returns null when the card quad is not usable.
///
/// [framed] means the buffer is already the on-screen guide. A detector box
/// or the guide itself is then enough; a missed brightness edge is not fatal.
StripPayload? prepareStrips({
  required Uint8List rgb,
  required int width,
  required int height,
  required Float64List boxes,
  bool framed = false,
}) {
  final image = RgbImage(width, height, rgb);
  final quad = _resolveQuad(image, boxes, framed: framed);
  if (quad == null) return null;
  final card = warpQuad(image, quad);
  if (card == null) return null;
  final mrz = _band(card, 0.50, 1);
  final pan = _band(card, 0.30, 0.58);
  return (
    mrz: mrz.bytes,
    mrzWidth: mrz.width,
    mrzHeight: mrz.height,
    pan: pan.bytes,
    panWidth: pan.width,
    panHeight: pan.height,
    quad: quad.toFlat(),
    mrzLines: _preferLines(card, mrz),
    flippedLines: _preferLines(
      rotate180(card),
      _band(rotate180(card), 0.50, 1),
    ),
  );
}

Quad? _resolveQuad(RgbImage image, Float64List boxes, {required bool framed}) {
  final roi = _roi(boxes, image.width, image.height);
  if (roi != null) {
    final box = _boxQuad(boxes, image.width, image.height);
    final scanned = findCardQuad(
      image,
      left: roi.$1,
      top: roi.$2,
      width: roi.$3,
      height: roi.$4,
    );
    if (scanned != null && (box == null || _coversBox(scanned, box))) {
      return scanned;
    }
    if (box != null) return box;
  }
  final full = findCardQuad(image);
  if (full != null && _coversEnough(full, image)) return full;
  if (framed && _lumaSpread(image) >= 16) {
    final right = (image.width - 1).toDouble();
    final bottom = (image.height - 1).toDouble();
    return Quad(
      tl: const Point2(0, 0),
      tr: Point2(right, 0),
      br: Point2(right, bottom),
      bl: Point2(0, bottom),
    );
  }
  return null;
}

Quad? _boxQuad(Float64List boxes, int width, int height) {
  final index = _bestBox(boxes);
  if (index == null) return null;
  final left = math.min(boxes[index], boxes[index + 2]);
  final top = math.min(boxes[index + 1], boxes[index + 3]);
  final right = math.max(boxes[index], boxes[index + 2]);
  final bottom = math.max(boxes[index + 1], boxes[index + 3]);
  final boxWidth = right - left;
  final boxHeight = bottom - top;
  if (boxWidth < 24 || boxHeight < 24) return null;
  final area = boxWidth * boxHeight;
  final frame = width * height;
  if (area < frame * 0.05 || area > frame * 0.94) return null;
  return Quad(
    tl: Point2(left, top),
    tr: Point2(right, top),
    br: Point2(right, bottom),
    bl: Point2(left, bottom),
  );
}

bool _coversBox(Quad scanned, Quad box) {
  final scannedSpan =
      distance(scanned.tl, scanned.tr) * distance(scanned.tl, scanned.bl);
  final boxSpan = distance(box.tl, box.tr) * distance(box.tl, box.bl);
  if (boxSpan < 1) return false;
  return scannedSpan >= boxSpan * 0.55;
}

bool _coversEnough(Quad quad, RgbImage image) {
  final span = distance(quad.tl, quad.tr) * distance(quad.tl, quad.bl);
  return span >= image.width * image.height * 0.08;
}

double _lumaSpread(RgbImage image) {
  var count = 0;
  var sum = 0.0;
  var sumSq = 0.0;
  for (var y = 0; y < image.height; y += 8) {
    for (var x = 0; x < image.width; x += 8) {
      final index = (y * image.width + x) * 3;
      final luma =
          (image.bytes[index] * 77 +
              image.bytes[index + 1] * 150 +
              image.bytes[index + 2] * 29) >>
          8;
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

int? _bestBox(Float64List boxes) {
  if (boxes.length < 6) return null;
  var bestId = -1;
  var bestScore = -1.0;
  var bestAny = 0;
  var bestArea = -1.0;
  for (var i = 0; i + 5 < boxes.length; i += 6) {
    final score = boxes[i + 4];
    final classId = boxes[i + 5].round();
    final area =
        (boxes[i + 2] - boxes[i]).abs() * (boxes[i + 3] - boxes[i + 1]).abs();
    if (classId == DetectionClass.idCard && score > bestScore) {
      bestScore = score;
      bestId = i;
    }
    if (area > bestArea) {
      bestArea = area;
      bestAny = i;
    }
  }
  return bestId >= 0 ? bestId : bestAny;
}

(int, int, int, int)? _roi(Float64List boxes, int width, int height) {
  final index = _bestBox(boxes);
  if (index == null) return null;
  final x1 = boxes[index];
  final y1 = boxes[index + 1];
  final x2 = boxes[index + 2];
  final y2 = boxes[index + 3];
  final padX = (x2 - x1).abs() * 0.12;
  final padY = (y2 - y1).abs() * 0.12;
  final left = (x1 - padX).floor().clamp(0, width - 1);
  final top = (y1 - padY).floor().clamp(0, height - 1);
  final right = (x2 + padX).ceil().clamp(left + 1, width);
  final bottom = (y2 + padY).ceil().clamp(top + 1, height);
  return (left, top, right - left, bottom - top);
}

List<LineImage> _preferLines(RgbImage card, RgbImage band) {
  final full = segmentMrzLines(card);
  final lower = segmentMrzLines(band);
  if (lower.length >= 2 && lower.length >= full.length) return lower;
  return full;
}

RgbImage _band(RgbImage card, double start, double end) {
  final y0 = (card.height * start).round().clamp(0, card.height - 1);
  final y1 = (card.height * end).round().clamp(y0 + 1, card.height);
  return card.crop(0, y0, card.width, y1 - y0);
}
