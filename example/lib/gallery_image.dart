import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:image_picker/image_picker.dart';

import 'rgb_codec.dart';

Future<RgbImage?> rgbFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  return rgbFromEncoded(bytes);
}
