import 'dart:typed_data';

import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:image/image.dart' as im;

/// Decodes an encoded still frame into packed RGB. Returns null when the
/// bytes are not an image.
RgbImage? rgbFromEncoded(Uint8List bytes) {
  final decoded = im.decodeImage(bytes);
  if (decoded == null) return null;
  final out = Uint8List(decoded.width * decoded.height * 3);
  var index = 0;
  for (final pixel in decoded) {
    out[index++] = pixel.r.toInt().clamp(0, 255).toInt();
    out[index++] = pixel.g.toInt().clamp(0, 255).toInt();
    out[index++] = pixel.b.toInt().clamp(0, 255).toInt();
  }
  return RgbImage(decoded.width, decoded.height, out);
}
