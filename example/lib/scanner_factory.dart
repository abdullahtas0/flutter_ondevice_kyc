import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';

class OpenedScanner {
  const OpenedScanner({
    required this.scanner,
    required this.fixture,
    required this.label,
  });

  final KycScanner scanner;
  final bool fixture;
  final String label;
}

Future<OpenedScanner> openScanner() async {
  void trace(ScanObservation observation) {
    debugPrint('kyc ${observation.elapsedMs}ms ${observation.status}');
  }

  final detector = await _assetReady(KycScanner.suggestedDetectorAsset);
  final recognizer = await _assetReady(KycScanner.suggestedRecognizerAsset);
  final dictionary = await _assetReady(KycScanner.suggestedDictionaryAsset);
  if (!detector) {
    return OpenedScanner(
      scanner: KycScanner.fixture(onTrace: trace),
      fixture: true,
      label: 'Fikstür',
    );
  }
  try {
    if (recognizer && dictionary) {
      final scanner = await KycScanner.onnx(
        detectorAsset: KycScanner.suggestedDetectorAsset,
        recognizerAsset: KycScanner.suggestedRecognizerAsset,
        dictionaryAsset: KycScanner.suggestedDictionaryAsset,
        onTrace: trace,
      );
      return OpenedScanner(
        scanner: scanner,
        fixture: false,
        label: 'Cihaz modeli',
      );
    }
    final scanner = await KycScanner.detectorOnly(
      detectorAsset: KycScanner.suggestedDetectorAsset,
      onTrace: trace,
    );
    return OpenedScanner(
      scanner: scanner,
      fixture: false,
      label: 'Tespit modeli',
    );
  } on Object {
    return OpenedScanner(
      scanner: KycScanner.fixture(onTrace: trace),
      fixture: true,
      label: 'Model açılamadı',
    );
  }
}

Future<bool> _assetReady(String key) async {
  try {
    await rootBundle.load(key);
    return true;
  } on Object {
    return false;
  }
}
