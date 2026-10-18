import 'dart:math' as math;

import 'detection.dart';

double iou(Detection a, Detection b) {
  final x1 = math.max(a.x1, b.x1);
  final y1 = math.max(a.y1, b.y1);
  final x2 = math.min(a.x2, b.x2);
  final y2 = math.min(a.y2, b.y2);
  final w = math.max(0.0, x2 - x1);
  final h = math.max(0.0, y2 - y1);
  final intersection = w * h;
  final union = a.area + b.area - intersection;
  if (union <= 0) return 0;
  return intersection / union;
}

/// Per-class non-maximum suppression. Different classes are kept even when
/// their boxes overlap.
List<Detection> nms(List<Detection> detections, {double iouThreshold = 0.45}) {
  final sorted = [...detections]..sort((a, b) => b.score.compareTo(a.score));
  final removed = List<bool>.filled(sorted.length, false);
  final kept = <Detection>[];
  for (var i = 0; i < sorted.length; i++) {
    if (removed[i]) continue;
    kept.add(sorted[i]);
    for (var j = i + 1; j < sorted.length; j++) {
      if (removed[j]) continue;
      if (sorted[i].classId != sorted[j].classId) continue;
      if (iou(sorted[i], sorted[j]) >= iouThreshold) removed[j] = true;
    }
  }
  return kept;
}
