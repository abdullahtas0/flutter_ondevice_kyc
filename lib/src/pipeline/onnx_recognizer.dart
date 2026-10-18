import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../image/rgb_image.dart';
import 'ctc_decoder.dart';
import 'detection.dart';

class OnnxTextRecognizer extends TextRecognizer {
  OnnxTextRecognizer({
    required this._session,
    required this.inputName,
    required this.outputName,
    required this.alphabet,
    this.bgr = true,
  });

  final OrtSession _session;
  final String inputName;
  final String outputName;
  final List<String> alphabet;
  final bool bgr;

  static Future<OnnxTextRecognizer> fromAssets({
    required String modelAsset,
    required String dictionaryAsset,
    List<OrtProvider> providers = const [OrtProvider.CPU],
    bool bgr = true,
  }) async {
    final session = await OnnxRuntime().createSessionFromAsset(
      modelAsset,
      options: OrtSessionOptions(providers: providers, intraOpNumThreads: 2),
    );
    final dictionary = await rootBundle.loadString(dictionaryAsset);
    return OnnxTextRecognizer(
      session: session,
      inputName: session.inputNames.first,
      outputName: session.outputNames.first,
      alphabet: alphabetFromDictionary(dictionary),
      bgr: bgr,
    );
  }

  @override
  Future<String> recognize(RgbImage line) async {
    try {
      return await _recognize(line, _tensorWidth(line));
    } on Object {
      return _recognize(line, 320);
    }
  }

  Future<String> _recognize(RgbImage line, int tensorWidth) async {
    final tensor = recognitionTensor(line, bgr: bgr, imageWidth: tensorWidth);
    final width = tensor.width;
    final input = await OrtValue.fromList(tensor.values, [1, 3, 48, width]);
    late final Map<String, OrtValue> outputs;
    try {
      outputs = await _session.run({inputName: input});
    } finally {
      await input.dispose();
    }
    try {
      final value = outputs[outputName] ?? outputs.values.first;
      final flat = await value.asFlattenedList();
      final data = [for (final item in flat) (item as num).toDouble()];
      return decodeRecognition(data, value.shape, alphabet);
    } finally {
      for (final tensor in outputs.values) {
        await tensor.dispose();
      }
    }
  }

  @override
  Future<void> close() => _session.close();
}

class RecognitionTensor {
  const RecognitionTensor(this.values, this.width);

  final Float32List values;
  final int width;
}

List<String> alphabetFromDictionary(String dictionary) {
  return [
    for (final line in dictionary.split('\n'))
      if (line.replaceAll('\r', '').isNotEmpty) line.replaceAll('\r', ''),
  ];
}

/// Official PP-OCRv4 rec preprocess: BGR, height 48, width capped at 320,
/// right side padded with normalized zeros.
RecognitionTensor recognitionTensor(
  RgbImage image, {
  bool bgr = true,
  int imageHeight = 48,
  int imageWidth = 320,
}) {
  final ratio = image.width / math.max(1, image.height);
  var resizedW = (imageHeight * ratio).ceil();
  if (resizedW > imageWidth) resizedW = imageWidth;
  if (resizedW < 1) resizedW = 1;
  final values = Float32List(3 * imageHeight * imageWidth);
  final plane = imageHeight * imageWidth;
  for (var y = 0; y < imageHeight; y++) {
    final srcY = (y + 0.5) * image.height / imageHeight - 0.5;
    for (var x = 0; x < resizedW; x++) {
      final srcX = (x + 0.5) * image.width / resizedW - 0.5;
      final sample = _bilinear(image, srcX, srcY);
      final red = (sample.$1 / 255.0 - 0.5) / 0.5;
      final green = (sample.$2 / 255.0 - 0.5) / 0.5;
      final blue = (sample.$3 / 255.0 - 0.5) / 0.5;
      final offset = y * imageWidth + x;
      if (bgr) {
        values[offset] = blue;
        values[plane + offset] = green;
        values[2 * plane + offset] = red;
      } else {
        values[offset] = red;
        values[plane + offset] = green;
        values[2 * plane + offset] = blue;
      }
    }
  }
  return RecognitionTensor(values, imageWidth);
}

/// Width of one MRZ line at height 48, capped so 30–44 characters are not crushed.
int _tensorWidth(RgbImage image) {
  final ratio = image.width / math.max(1, image.height);
  var width = (48 * ratio).ceil();
  if (width < 8) width = 8;
  if (width > 960) width = 960;
  final snapped = (width + 7) & ~7;
  if (snapped > 960) return 960;
  return snapped;
}

(int, int, int) _bilinear(RgbImage image, double x, double y) {
  if (x < 0 || y < 0 || x > image.width - 1 || y > image.height - 1) {
    final cx = x.clamp(0, image.width - 1).floor();
    final cy = y.clamp(0, image.height - 1).floor();
    return (image.red(cx, cy), image.green(cx, cy), image.blue(cx, cy));
  }
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, image.width - 1);
  final y1 = math.min(y0 + 1, image.height - 1);
  final dx = x - x0;
  final dy = y - y0;
  int mix(int c00, int c10, int c01, int c11) {
    final value =
        c00 * (1 - dx) * (1 - dy) +
        c10 * dx * (1 - dy) +
        c01 * (1 - dx) * dy +
        c11 * dx * dy;
    return value.round().clamp(0, 255);
  }

  return (
    mix(
      image.red(x0, y0),
      image.red(x1, y0),
      image.red(x0, y1),
      image.red(x1, y1),
    ),
    mix(
      image.green(x0, y0),
      image.green(x1, y0),
      image.green(x0, y1),
      image.green(x1, y1),
    ),
    mix(
      image.blue(x0, y0),
      image.blue(x1, y0),
      image.blue(x0, y1),
      image.blue(x1, y1),
    ),
  );
}

String decodeRecognition(
  List<double> flat,
  List<int> shape,
  List<String> alphabet,
) {
  if (alphabet.isEmpty || flat.isEmpty) return '';
  var classes = alphabet.length + 1;
  var channelLast = true;
  if (shape.length >= 2 && shape.last > alphabet.length) {
    classes = shape.last;
  } else if (shape.length >= 2 && shape[shape.length - 2] > alphabet.length) {
    classes = shape[shape.length - 2];
    channelLast = false;
  }
  if (classes <= 1 || flat.length % classes != 0) return '';
  final timesteps = channelLast ? flat.length ~/ classes : shape.last;
  if (timesteps <= 0 || (channelLast && flat.length != timesteps * classes)) {
    return '';
  }
  final logits = <List<double>>[];
  if (channelLast) {
    for (var t = 0; t < timesteps; t++) {
      logits.add(flat.sublist(t * classes, (t + 1) * classes));
    }
  } else {
    for (var t = 0; t < timesteps; t++) {
      final step = List<double>.filled(classes, 0);
      for (var c = 0; c < classes; c++) {
        step[c] = flat[c * timesteps + t];
      }
      logits.add(step);
    }
  }
  return ctcGreedyDecode(logits, alphabet);
}
