import 'dart:io';

import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

import 'eval_runner.dart';
import 'ledger_expect.dart';

void main() {
  test('fixture folder scores without echoing the manifest', () async {
    final root = await Directory.systemTemp.createTemp('kyc_ledger_');
    final scanner = KycScanner.fixture();
    const manifest = '''
{
  "cases": [
    {
      "id": "lock-a",
      "file": "card-a.png",
      "expect": "lock",
      "documentNumber": "L898902C3",
      "birthDate": "1974-08-12",
      "expiryDate": "2012-04-15",
      "surname": "ERIKSSON",
      "givenNames": "ANNA MARIA"
    },
    {
      "id": "reject-b",
      "file": "card-b.png",
      "expect": "reject"
    },
    {
      "id": "thin-c",
      "file": "missing.jpg",
      "expect": "lock",
      "surname": "ERIKSSON"
    }
  ]
}
''';
    try {
      File('${root.path}/manifest.json').writeAsStringSync(manifest);
      final png = _png(SyntheticCardSpec.image());
      File('${root.path}/card-a.png').writeAsBytesSync(png);
      File('${root.path}/card-b.png').writeAsBytesSync(png);

      final report = await measureFolder(root: root, scan: scanner.scanStill);
      expect(report.correctLocks, 1);
      expect(report.falseLocks, 1);
      expect(report.unscored, 1);
      expect(report.lockRate, 1);
      expect(report.falseLockRate, 0.5);
      expect(report.p95Ms, isNotNull);

      writeLedger(root, report, model: 'fixture');
      final text = File('${root.path}/ledger.txt').readAsStringSync();
      expect(text.startsWith('model: fixture\n'), isTrue);
      expect(text.contains('lockRate: 1.000 (1/1)'), isTrue);
      expect(text.contains('falseLockRate: 0.500 (1/2)'), isTrue);
      expect(text.contains('thin-c unscored'), isTrue);
      expect(text.contains('reject-b falseLock unexpected'), isTrue);
      expectLedgerHidesManifest(text, manifest);
    } finally {
      await scanner.dispose();
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });
}

List<int> _png(RgbImage source) {
  final image = im.Image(width: source.width, height: source.height);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      image.setPixelRgb(
        x,
        y,
        source.red(x, y),
        source.green(x, y),
        source.blue(x, y),
      );
    }
  }
  return im.encodePng(image);
}
