import 'dart:math' as math;
import 'dart:typed_data';

import '../image/rgb_image.dart';

class Letterbox {
  const Letterbox({
    required this.tensor,
    required this.ratio,
    required this.size,
  });

  /// CHW, BGR, values 0–255. YOLOX pads the bottom and right with 114.
  final Float32List tensor;
  final double ratio;
  final int size;
}

Letterbox letterboxBgr(RgbImage image, {int size = 416}) {
  final ratio = math.min(size / image.width, size / image.height);
  final resizedW = math.max(1, (image.width * ratio).round());
  final resizedH = math.max(1, (image.height * ratio).round());
  final tensor = Float32List(3 * size * size);
  for (var i = 0; i < tensor.length; i++) {
    tensor[i] = 114;
  }
  final plane = size * size;
  for (var y = 0; y < resizedH; y++) {
    final srcY = math.min(image.height - 1, (y / ratio).floor());
    for (var x = 0; x < resizedW; x++) {
      final srcX = math.min(image.width - 1, (x / ratio).floor());
      final pixel = (srcY * image.width + srcX) * 3;
      final offset = y * size + x;
      tensor[offset] = image.bytes[pixel + 2].toDouble();
      tensor[plane + offset] = image.bytes[pixel + 1].toDouble();
      tensor[2 * plane + offset] = image.bytes[pixel].toDouble();
    }
  }
  return Letterbox(tensor: tensor, ratio: ratio, size: size);
}
