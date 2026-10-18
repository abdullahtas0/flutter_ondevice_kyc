import 'dart:typed_data';

import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:image/image.dart' as im;
import 'package:image_picker/image_picker.dart';

Future<RgbImage?> rgbFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  final decoded = im.decodeImage(bytes);
  if (decoded == null) return null;
  final out = Uint8List(decoded.width * decoded.height * 3);
  var index = 0;
  for (final pixel in decoded) {
    out[index++] = pixel.r.toInt().clamp(0, 255);
    out[index++] = pixel.g.toInt().clamp(0, 255);
    out[index++] = pixel.b.toInt().clamp(0, 255);
  }
  return RgbImage(decoded.width, decoded.height, out);
}
