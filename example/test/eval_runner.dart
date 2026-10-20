import 'dart:io';

import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
// ignore: implementation_imports
import 'package:flutter_ondevice_kyc/src/eval/ledger.dart';
import 'package:kyc_example/rgb_codec.dart';

/// Loads the ONNX models. A missing weight fails this future. The fixture
/// scanner is not a stand-in for a measurement.
Future<KycScanner> openEvalScanner() {
  return KycScanner.onnx(
    detectorAsset: KycScanner.suggestedDetectorAsset,
    recognizerAsset: KycScanner.suggestedRecognizerAsset,
    dictionaryAsset: KycScanner.suggestedDictionaryAsset,
  );
}

/// Scores `manifest.json` inside [root]. Unscored rows are not read.
Future<LedgerReport> measureFolder({
  required Directory root,
  required Future<ScanDecision> Function(RgbImage image) scan,
}) async {
  final manifest = File('${root.path}/manifest.json');
  if (!manifest.existsSync()) {
    throw const LedgerException('manifest.json is missing');
  }
  final frames = parseLedgerManifest(manifest.readAsStringSync());
  final observations = <LedgerObservation>[];
  for (final frame in frames) {
    if (frame.truth.expectLock && !frame.truth.canScoreLock) {
      observations.add(LedgerObservation(frame.truth, null));
      continue;
    }
    final image = _load(root, frame);
    observations.add(LedgerObservation(frame.truth, await scan(image)));
  }
  return scoreLedger(observations);
}

/// Writes `ledger.txt` next to the manifest. The text is the return value of
/// [renderLedger].
void writeLedger(Directory root, LedgerReport report, {required String model}) {
  File('${root.path}/ledger.txt')
      .writeAsStringSync(renderLedger(report, model: model));
}

RgbImage _load(Directory root, LedgerFrame frame) {
  final id = frame.truth.id;
  checkLedgerPath(id, frame.relativePath);
  final file = File(_join(root.path, frame.relativePath));
  if (!file.existsSync()) {
    throw LedgerException('case $id image is missing');
  }
  final resolved = file.resolveSymbolicLinksSync();
  final rootResolved = root.resolveSymbolicLinksSync();
  final prefix = rootResolved.endsWith('/') ? rootResolved : '$rootResolved/';
  if (!resolved.startsWith(prefix)) {
    throw LedgerException('case $id file is not inside the folder');
  }
  final decoded = rgbFromEncoded(file.readAsBytesSync());
  if (decoded == null) {
    throw LedgerException('case $id image is undecodable');
  }
  return decoded;
}

String _join(String root, String relative) {
  final separator = root.contains('\\') ? '\\' : '/';
  final tail = relative.replaceAll('\\', separator).replaceAll('/', separator);
  final base = root.endsWith(separator)
      ? root.substring(0, root.length - 1)
      : root;
  return '$base$separator$tail';
}
