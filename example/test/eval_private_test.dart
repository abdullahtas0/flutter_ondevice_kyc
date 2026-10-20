import 'dart:io';

// ignore: implementation_imports
import 'package:flutter_ondevice_kyc/src/eval/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'eval_runner.dart';
import 'ledger_expect.dart';

/// Scores a private folder. Skipped unless KYC_EVAL_DIR points at it.
///
/// ```sh
/// KYC_EVAL_DIR=/path/to/private flutter test test/eval_private_test.dart
/// ```
void main() {
  test('private folder writes a model ledger', () async {
    final dir = Platform.environment['KYC_EVAL_DIR'];
    if (dir == null || dir.isEmpty) {
      markTestSkipped(
        'KYC_EVAL_DIR is unset. A private folder is required for model measurement.',
      );
      return;
    }
    final root = Directory(dir);
    if (!root.existsSync()) {
      fail('KYC_EVAL_DIR does not exist');
    }
    final manifestFile = File('${root.path}/manifest.json');
    if (!manifestFile.existsSync()) {
      fail('manifest.json is missing');
    }
    final manifest = manifestFile.readAsStringSync();
    parseLedgerManifest(manifest);

    TestWidgetsFlutterBinding.ensureInitialized();
    final scanner = await openEvalScanner();
    try {
      expect(scanner.fixture, isFalse);
      final report = await measureFolder(root: root, scan: scanner.scanStill);
      writeLedger(root, report, model: 'onnx');
      final text = File('${root.path}/ledger.txt').readAsStringSync();
      expect(text.startsWith('model: onnx\n'), isTrue);
      expectLedgerHidesManifest(text, manifest);
      stdout.writeln(text);
    } finally {
      await scanner.dispose();
    }
  });
}
