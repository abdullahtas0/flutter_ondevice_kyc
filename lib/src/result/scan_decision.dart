import '../pipeline/detection.dart';
import '../pipeline/quad.dart';
import 'kyc_capture.dart';

enum RejectReason { noCard, badQuad, checksum, unreadable }

/// One processed frame. Skipped frames are not failures.
sealed class ScanDecision {
  const ScanDecision();
}

class ScanSkipped extends ScanDecision {
  const ScanSkipped();
}

class ScanRejected extends ScanDecision {
  const ScanRejected(
    this.reason,
    this.elapsedMs, {
    this.detections = const [],
    this.quad,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
  });

  final RejectReason reason;
  final int elapsedMs;
  final List<Detection> detections;
  final Quad? quad;
  final int sourceWidth;
  final int sourceHeight;
}

class ScanLocked extends ScanDecision {
  const ScanLocked({
    required this.capture,
    required this.quad,
    required this.detections,
    required this.elapsedMs,
    required this.fixture,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
  });

  final KycCapture capture;
  final Quad quad;
  final List<Detection> detections;
  final int elapsedMs;
  final int sourceWidth;
  final int sourceHeight;

  /// True when the recognizer is the built-in specimen, not an ONNX model.
  final bool fixture;
}

/// Timing note safe to log. It never carries a PAN or an MRZ line.
class ScanObservation {
  const ScanObservation({
    required this.elapsedMs,
    required this.status,
    this.detail,
  });

  final int elapsedMs;
  final String status;
  final String? detail;
}

String rejectLabel(RejectReason reason) {
  return switch (reason) {
    RejectReason.checksum =>
      'MRZ okundu, hane tutmadı. Kartı düz ve sabit tut.',
    RejectReason.badQuad => 'Köşeler çerçevede değil. Kartı düz tut.',
    RejectReason.noCard => 'Kimlik çerçevede görünmüyor.',
    RejectReason.unreadable =>
      'Alt üç satır net değil. Çerçeveyi doldurup sabit tut.',
  };
}
