import 'dart:typed_data';

/// Tightly packed RGB image. Three bytes per pixel, row-major, no padding.
class RgbImage {
  RgbImage(this.width, this.height, Uint8List bytes) : bytes = bytes {
    final expected = width * height * 3;
    if (width <= 0 || height <= 0 || bytes.length != expected) {
      throw ArgumentError(
        'RGB buffer length ${bytes.length} != $expected for ${width}x$height',
      );
    }
  }

  final int width;
  final int height;
  final Uint8List bytes;

  int _index(int x, int y) => (y * width + x) * 3;

  int red(int x, int y) => bytes[_index(x, y)];

  int green(int x, int y) => bytes[_index(x, y) + 1];

  int blue(int x, int y) => bytes[_index(x, y) + 2];

  void setRgb(int x, int y, int red, int green, int blue) {
    final index = _index(x, y);
    bytes[index] = red;
    bytes[index + 1] = green;
    bytes[index + 2] = blue;
  }

  RgbImage crop(int left, int top, int cropWidth, int cropHeight) {
    final x0 = left.clamp(0, width - 1);
    final y0 = top.clamp(0, height - 1);
    final x1 = (left + cropWidth).clamp(x0 + 1, width);
    final y1 = (top + cropHeight).clamp(y0 + 1, height);
    final outWidth = x1 - x0;
    final outHeight = y1 - y0;
    final out = Uint8List(outWidth * outHeight * 3);
    for (var y = 0; y < outHeight; y++) {
      final src = ((y0 + y) * width + x0) * 3;
      final dst = y * outWidth * 3;
      out.setRange(dst, dst + outWidth * 3, bytes, src);
    }
    return RgbImage(outWidth, outHeight, out);
  }
}
