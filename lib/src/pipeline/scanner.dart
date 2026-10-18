import 'dart:isolate';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../image/rgb_image.dart';
import '../result/kyc_capture.dart';
import '../result/scan_decision.dart';
import '../validation/expiry.dart';
import '../validation/icao_mrz.dart';
import '../validation/luhn.dart';
import 'ctc_decoder.dart';
import 'detection.dart';
import 'frame_convert.dart';
import 'frame_gate.dart';
import 'onnx_detector.dart';
import 'mrz_lines.dart';
import 'mrz_repair.dart';
import 'onnx_recognizer.dart';
import 'quad.dart';
import 'strips.dart';
import 'synthetic_card.dart';

enum KycExecutionProvider { cpu, xnnpack, coreMl }

/// Two-stage scan. A checksum miss is [ScanRejected], never an exception.
class KycScanner {
  KycScanner({
    required this._detector,
    required this._recognizer,
    FrameGate? frameGate,
    DateTime Function()? clock,
    this.fixture = false,
    this.onTrace,
  }) : _gate = frameGate ?? FrameGate(),
       _clock = clock ?? DateTime.now;

  /// Conventional asset keys. The host app lists these files in its own
  /// `pubspec.yaml`. This package does not ship the weights.
  static const suggestedDetectorAsset = 'assets/models/card_detector.onnx';
  static const suggestedRecognizerAsset = 'assets/models/text_rec.onnx';
  static const suggestedDictionaryAsset = 'assets/models/en_dict.txt';

  final bool fixture;
  final void Function(ScanObservation observation)? onTrace;
  final CardDetector _detector;
  final TextRecognizer _recognizer;
  final FrameGate _gate;
  final DateTime Function() _clock;
  RejectReason _readReason = RejectReason.unreadable;

  factory KycScanner.fixture({
    bool passChecksum = true,
    FrameGate? frameGate,
    void Function(ScanObservation observation)? onTrace,
  }) {
    final text = passChecksum ? IcaoSamples.erikssonTd3 : brokenErikssonMrz();
    return KycScanner(
      detector: FixtureDetector(),
      recognizer: LogitRecognizer(text, _chars(mrzAlphabet)),
      frameGate: frameGate,
      fixture: true,
      onTrace: onTrace,
    );
  }

  /// Loads the card detector only. Text is not invented, so a frame cannot lock
  /// until a recognizer is supplied.
  static Future<KycScanner> detectorOnly({
    required String detectorAsset,
    List<KycExecutionProvider> providers = const [KycExecutionProvider.cpu],
    void Function(ScanObservation observation)? onTrace,
  }) async {
    final detector = await OnnxCardDetector.fromAsset(
      detectorAsset,
      providers: _mapProviders(providers),
    );
    return KycScanner(
      detector: detector,
      recognizer: _SilentRecognizer(),
      onTrace: onTrace,
    );
  }

  static Future<KycScanner> onnx({
    required String detectorAsset,
    required String recognizerAsset,
    required String dictionaryAsset,
    List<KycExecutionProvider> providers = const [KycExecutionProvider.cpu],
    void Function(ScanObservation observation)? onTrace,
  }) async {
    final mapped = _mapProviders(providers);
    final detector = await OnnxCardDetector.fromAsset(
      detectorAsset,
      providers: mapped,
    );
    try {
      final recognizer = await OnnxTextRecognizer.fromAssets(
        modelAsset: recognizerAsset,
        dictionaryAsset: dictionaryAsset,
        providers: mapped,
      );
      return KycScanner(
        detector: detector,
        recognizer: recognizer,
        onTrace: onTrace,
      );
    } on Object {
      await detector.close();
      rethrow;
    }
  }

  /// One gallery frame. Geometry stays on this isolate so a single tap can
  /// finish without a worker. Camera frames still warp on a worker isolate.
  Future<ScanDecision> scanStill(RgbImage image) {
    final watch = Stopwatch()..start();
    return _finish(image, watch, offloadGeometry: false, framed: false);
  }

  Future<ScanDecision> scanFrame(RawCameraFrame frame, {DateTime? now}) async {
    final stamp = now ?? _clock();
    if (!_gate.tryAcquire(stamp)) return const ScanSkipped();
    final watch = Stopwatch()..start();
    try {
      final packed = await _decode(frame);
      return await _finish(
        packedToImage(packed),
        watch,
        offloadGeometry: true,
        framed: frame.framed,
      );
    } catch (error) {
      return _reject(RejectReason.unreadable, watch, error: error);
    } finally {
      _gate.release();
    }
  }

  Future<void> dispose() async {
    await _detector.close();
    await _recognizer.close();
  }

  Future<ScanDecision> _finish(
    RgbImage image,
    Stopwatch watch, {
    required bool offloadGeometry,
    required bool framed,
  }) async {
    final sourceWidth = image.width;
    final sourceHeight = image.height;
    late final List<Detection> detections;
    try {
      detections = await _detector.detect(image);
    } catch (error) {
      return _reject(
        RejectReason.unreadable,
        watch,
        error: error,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
    }
    if (detections.isEmpty && !framed) {
      return _reject(
        RejectReason.noCard,
        watch,
        detections: detections,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
    }

    final bytes = image.bytes;
    final width = image.width;
    final height = image.height;
    final encoded = encodeDetections(detections);
    late final StripPayload? payload;
    try {
      payload = offloadGeometry
          ? await Isolate.run(
              () => prepareStrips(
                rgb: bytes,
                width: width,
                height: height,
                boxes: encoded,
                framed: framed,
              ),
            )
          : prepareStrips(
              rgb: bytes,
              width: width,
              height: height,
              boxes: encoded,
              framed: framed,
            );
    } catch (error) {
      return _reject(
        RejectReason.unreadable,
        watch,
        error: error,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
    }
    if (payload == null) {
      return _reject(
        detections.isEmpty ? RejectReason.noCard : RejectReason.badQuad,
        watch,
        detections: detections,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
    }

    final KycCapture? capture;
    try {
      capture = await _read(payload);
    } catch (error) {
      return _reject(
        RejectReason.unreadable,
        watch,
        error: error,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
    }
    final elapsed = watch.elapsedMilliseconds;
    if (capture == null || !capture.isValid) {
      return _reject(
        _readReason,
        watch,
        detections: detections,
        quad: Quad.fromFlat(payload.quad),
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
    }
    _observe(elapsed, 'locked', null);
    return ScanLocked(
      capture: capture,
      quad: Quad.fromFlat(payload.quad),
      detections: detections,
      elapsedMs: elapsed,
      fixture: fixture,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  Future<KycCapture?> _read(StripPayload payload) async {
    _readReason = RejectReason.unreadable;
    final lined = await _readLines(payload.mrzLines);
    if (lined != null) return lined;
    if (_readReason != RejectReason.checksum) {
      final flipped = await _readLines(payload.flippedLines);
      if (flipped != null) return flipped;
    }
    if (payload.mrzLines.isEmpty &&
        payload.flippedLines.isEmpty &&
        payload.mrzWidth >= 8 &&
        payload.mrzHeight >= 8) {
      final text = await _recognizer.recognize(
        RgbImage(payload.mrzWidth, payload.mrzHeight, payload.mrz),
      );
      final mrz = parseMrz(repairMrz(text));
      if (mrz != null) {
        if (mrz.isValid) return KycCapture.fromMrz(mrz);
        _readReason = RejectReason.checksum;
        return null;
      }
    } else if (payload.mrzLines.isNotEmpty || payload.flippedLines.isNotEmpty) {
      return null;
    }
    if (payload.panWidth >= 8 && payload.panHeight >= 8) {
      final text = await _recognizer.recognize(
        RgbImage(payload.panWidth, payload.panHeight, payload.pan),
      );
      final pan = extractPan(text);
      if (pan != null) {
        return KycCapture.fromCard(
          cardNumber: pan,
          expiry: extractExpiry(text),
        );
      }
      if (hasPanCandidate(text)) {
        _readReason = RejectReason.checksum;
        return null;
      }
    }
    _readReason = RejectReason.unreadable;
    return null;
  }

  /// Reads each MRZ line on its own. Returns null and sets [_readReason]
  /// when the lines were seen but did not lock.
  Future<KycCapture?> _readLines(List<LineImage> lines) async {
    if (lines.length < 2) return null;
    final texts = <String>[];
    for (final line in lines) {
      if (line.width < 8 || line.height < 8) return null;
      final text = _mrzToken(
        await _recognizer.recognize(
          RgbImage(line.width, line.height, line.bytes),
        ),
      );
      if (text.isEmpty) {
        _readReason = RejectReason.unreadable;
        return null;
      }
      texts.add(text);
    }
    final mrz = parseMrz(repairMrz(texts.join('\n')));
    if (mrz != null && mrz.isValid) return KycCapture.fromMrz(mrz);
    _readReason = mrz == null ? RejectReason.unreadable : RejectReason.checksum;
    return null;
  }

  String _mrzToken(String raw) {
    return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9<]'), '');
  }

  ScanRejected _reject(
    RejectReason reason,
    Stopwatch watch, {
    Object? error,
    List<Detection> detections = const [],
    Quad? quad,
    int sourceWidth = 0,
    int sourceHeight = 0,
  }) {
    final elapsed = watch.elapsedMilliseconds;
    _observe(elapsed, 'rejected', error?.runtimeType.toString());
    return ScanRejected(
      reason,
      elapsed,
      detections: detections,
      quad: quad,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  void _observe(int elapsedMs, String status, String? detail) {
    onTrace?.call(
      ScanObservation(elapsedMs: elapsedMs, status: status, detail: detail),
    );
  }

  Future<PackedRgb> _decode(RawCameraFrame frame) {
    final turns = frame.quarterTurns;
    final cropLeft = frame.cropLeft;
    final cropTop = frame.cropTop;
    final cropRight = frame.cropRight;
    final cropBottom = frame.cropBottom;
    switch (frame.layout) {
      case RawFrameLayout.yuv420:
        final y = frame.planes[0];
        final u = frame.planes[1];
        final v = frame.planes[2];
        final width = frame.width;
        final height = frame.height;
        final yBytes = y.bytes;
        final uBytes = u.bytes;
        final vBytes = v.bytes;
        final yRow = y.bytesPerRow;
        final uRow = u.bytesPerRow;
        final vRow = v.bytesPerRow;
        final yPix = y.bytesPerPixel;
        final uPix = u.bytesPerPixel;
        final vPix = v.bytesPerPixel;
        return Isolate.run(
          () => alignCameraPacked(
            yuv420ToPacked(
              width: width,
              height: height,
              y: yBytes,
              u: uBytes,
              v: vBytes,
              yRow: yRow,
              uRow: uRow,
              vRow: vRow,
              yPix: yPix,
              uPix: uPix,
              vPix: vPix,
            ),
            quarterTurns: turns,
            cropLeft: cropLeft,
            cropTop: cropTop,
            cropRight: cropRight,
            cropBottom: cropBottom,
          ),
        );
      case RawFrameLayout.nv21:
        final y = frame.planes[0];
        final vu = frame.planes[1];
        final width = frame.width;
        final height = frame.height;
        final yBytes = y.bytes;
        final vuBytes = vu.bytes;
        final yRow = y.bytesPerRow;
        final vuRow = vu.bytesPerRow;
        final yPix = y.bytesPerPixel;
        final vuPix = vu.bytesPerPixel;
        return Isolate.run(
          () => alignCameraPacked(
            nv21ToPacked(
              width: width,
              height: height,
              y: yBytes,
              vu: vuBytes,
              yRow: yRow,
              vuRow: vuRow,
              yPix: yPix,
              vuPix: vuPix,
            ),
            quarterTurns: turns,
            cropLeft: cropLeft,
            cropTop: cropTop,
            cropRight: cropRight,
            cropBottom: cropBottom,
          ),
        );
      case RawFrameLayout.bgra8888:
        final plane = frame.planes[0];
        final width = frame.width;
        final height = frame.height;
        final bytes = plane.bytes;
        final row = plane.bytesPerRow;
        return Isolate.run(
          () => alignCameraPacked(
            bgraToPacked(
              width: width,
              height: height,
              bytes: bytes,
              bytesPerRow: row,
            ),
            quarterTurns: turns,
            cropLeft: cropLeft,
            cropTop: cropTop,
            cropRight: cropRight,
            cropBottom: cropBottom,
          ),
        );
      case RawFrameLayout.rgba8888:
        final plane = frame.planes[0];
        final width = frame.width;
        final height = frame.height;
        final bytes = plane.bytes;
        final row = plane.bytesPerRow;
        return Isolate.run(
          () => alignCameraPacked(
            rgbaToPacked(
              width: width,
              height: height,
              bytes: bytes,
              bytesPerRow: row,
            ),
            quarterTurns: turns,
            cropLeft: cropLeft,
            cropTop: cropTop,
            cropRight: cropRight,
            cropBottom: cropBottom,
          ),
        );
    }
  }
}

class FixtureDetector extends CardDetector {
  FixtureDetector();

  @override
  Future<List<Detection>> detect(RgbImage image) async {
    if (image.width == SyntheticCardSpec.imageWidth &&
        image.height == SyntheticCardSpec.imageHeight) {
      return [
        Detection(
          x1: SyntheticCardSpec.left.toDouble(),
          y1: SyntheticCardSpec.top.toDouble(),
          x2: (SyntheticCardSpec.left + SyntheticCardSpec.cardWidth).toDouble(),
          y2: (SyntheticCardSpec.top + SyntheticCardSpec.cardHeight).toDouble(),
          score: 0.95,
          classId: DetectionClass.idCard,
          label: DetectionLabels.idCard,
        ),
      ];
    }
    return [
      Detection(
        x1: 0,
        y1: 0,
        x2: image.width.toDouble(),
        y2: image.height.toDouble(),
        score: 0.5,
        classId: DetectionClass.idCard,
        label: DetectionLabels.idCard,
      ),
    ];
  }
}

class _SilentRecognizer extends TextRecognizer {
  @override
  Future<String> recognize(RgbImage line) async => '';
}

class LogitRecognizer extends TextRecognizer {
  LogitRecognizer(String text, List<String> alphabet)
    : _logits = logitsForText(text, alphabet),
      _alphabet = alphabet;

  final List<List<double>> _logits;
  final List<String> _alphabet;

  @override
  Future<String> recognize(RgbImage line) async {
    return ctcGreedyDecode(_logits, _alphabet);
  }
}

String brokenErikssonMrz() {
  final raw = IcaoSamples.erikssonTd3;
  return '${raw.substring(0, raw.length - 1)}1';
}

List<String> _chars(String alphabet) => [
  for (final rune in alphabet.runes) String.fromCharCode(rune),
];

List<OrtProvider> _mapProviders(List<KycExecutionProvider> providers) {
  if (providers.isEmpty) return const [OrtProvider.CPU];
  return [
    for (final provider in providers)
      switch (provider) {
        KycExecutionProvider.cpu => OrtProvider.CPU,
        KycExecutionProvider.xnnpack => OrtProvider.XNNPACK,
        KycExecutionProvider.coreMl => OrtProvider.CORE_ML,
      },
  ];
}
