import 'dart:math' as math;

import 'detection.dart';

/// Decodes a YOLOX head that already applies sigmoid to objectness and class
/// scores. Box deltas are still raw: center is `(delta + grid) * stride` and
/// size is `exp(delta) * stride`.
///
/// Grid order matches the official export: stride 8, then 16, then 32,
/// row-major. Official preprocessing pads on the bottom and right, so [padX]
/// and [padY] stay 0 and boxes are divided by [ratio].
List<Detection> decodeYolox({
  required List<double> output,
  required int inputSize,
  required int numClasses,
  required List<String> labels,
  double scoreThreshold = 0.25,
  double ratio = 1,
  double padX = 0,
  double padY = 0,
}) {
  const strides = [8, 16, 32];
  final channels = 5 + numClasses;
  final predictions = yoloxPredictionCount(inputSize);
  if (output.length != predictions * channels) {
    final actual = output.length % predictions == 0
        ? output.length ~/ predictions
        : output.length;
    throw StateError(
      'YOLOX head has $actual channels, expected $channels for $numClasses classes',
    );
  }

  final detections = <Detection>[];
  var index = 0;
  for (final stride in strides) {
    final grid = inputSize ~/ stride;
    for (var gy = 0; gy < grid; gy++) {
      for (var gx = 0; gx < grid; gx++) {
        final base = index * channels;
        final objectness = output[base + 4];
        var bestClass = 0;
        var bestScore = output[base + 5];
        for (var c = 1; c < numClasses; c++) {
          final score = output[base + 5 + c];
          if (score > bestScore) {
            bestScore = score;
            bestClass = c;
          }
        }
        final score = objectness * bestScore;
        if (score >= scoreThreshold) {
          final cx = (output[base] + gx) * stride;
          final cy = (output[base + 1] + gy) * stride;
          final w = math.exp(output[base + 2]) * stride;
          final h = math.exp(output[base + 3]) * stride;
          final scale = ratio == 0 ? 1.0 : ratio;
          final label = bestClass < labels.length
              ? labels[bestClass]
              : '$bestClass';
          detections.add(
            Detection(
              x1: (cx - w / 2 - padX) / scale,
              y1: (cy - h / 2 - padY) / scale,
              x2: (cx + w / 2 - padX) / scale,
              y2: (cy + h / 2 - padY) / scale,
              score: score,
              classId: bestClass,
              label: label,
            ),
          );
        }
        index++;
      }
    }
  }
  return detections;
}

int yoloxPredictionCount(int inputSize) {
  var count = 0;
  for (final stride in [8, 16, 32]) {
    final grid = inputSize ~/ stride;
    count += grid * grid;
  }
  return count;
}
