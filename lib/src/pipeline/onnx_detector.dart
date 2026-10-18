import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../image/rgb_image.dart';
import 'detection.dart';
import 'letterbox.dart';
import 'nms.dart';
import 'yolox_decode.dart';

class OnnxCardDetector extends CardDetector {
  OnnxCardDetector({
    required this._session,
    required this.inputName,
    required this.outputName,
    this.inputSize = 416,
    this.labels = DetectionLabels.kyc,
    this.scoreThreshold = 0.25,
    this.iouThreshold = 0.45,
  });

  final OrtSession _session;
  final String inputName;
  final String outputName;
  final int inputSize;
  final List<String> labels;
  final double scoreThreshold;
  final double iouThreshold;

  static Future<OnnxCardDetector> fromAsset(
    String assetKey, {
    List<OrtProvider> providers = const [OrtProvider.CPU],
    int inputSize = 416,
    List<String> labels = DetectionLabels.kyc,
  }) async {
    final session = await OnnxRuntime().createSessionFromAsset(
      assetKey,
      options: OrtSessionOptions(providers: providers, intraOpNumThreads: 2),
    );
    return OnnxCardDetector(
      session: session,
      inputName: session.inputNames.first,
      outputName: session.outputNames.first,
      inputSize: inputSize,
      labels: labels,
    );
  }

  @override
  Future<List<Detection>> detect(RgbImage image) async {
    final boxed = letterboxBgr(image, size: inputSize);
    final input = await OrtValue.fromList(boxed.tensor, [
      1,
      3,
      inputSize,
      inputSize,
    ]);
    late final Map<String, OrtValue> outputs;
    try {
      outputs = await _session.run({inputName: input});
    } finally {
      await input.dispose();
    }
    try {
      final tensor = outputs[outputName] ?? outputs.values.first;
      final flat = await _doubles(tensor);
      final decoded = decodeYolox(
        output: flat,
        inputSize: inputSize,
        numClasses: labels.length,
        labels: labels,
        scoreThreshold: scoreThreshold,
        ratio: boxed.ratio,
      );
      return nms(decoded, iouThreshold: iouThreshold);
    } finally {
      for (final tensor in outputs.values) {
        await tensor.dispose();
      }
    }
  }

  @override
  Future<void> close() => _session.close();
}

Future<List<double>> _doubles(OrtValue tensor) async {
  final flat = await tensor.asFlattenedList();
  return [for (final value in flat) (value as num).toDouble()];
}
