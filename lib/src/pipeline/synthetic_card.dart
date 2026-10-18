import 'dart:typed_data';

import '../image/rgb_image.dart';

/// Bright card on a black field. Aspect is 240/152 ≈ 1.58, inside the ID-1 range.
abstract final class SyntheticCardSpec {
  static const imageWidth = 320;
  static const imageHeight = 220;
  static const left = 40;
  static const top = 34;
  static const cardWidth = 240;
  static const cardHeight = 152;

  static RgbImage image() {
    final bytes = Uint8List(imageWidth * imageHeight * 3);
    for (var y = top; y < top + cardHeight; y++) {
      for (var x = left; x < left + cardWidth; x++) {
        final index = (y * imageWidth + x) * 3;
        bytes[index] = 236;
        bytes[index + 1] = 232;
        bytes[index + 2] = 220;
      }
    }
    return RgbImage(imageWidth, imageHeight, bytes);
  }
}
