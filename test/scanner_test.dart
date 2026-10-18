import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fixture scanner locks the specimen and a broken digit does not',
    () async {
      final image = SyntheticCardSpec.image();
      final notes = <ScanObservation>[];
      final scanner = KycScanner.fixture(onTrace: notes.add);
      final locked = await scanner.scanStill(image);
      expect(locked, isA<ScanLocked>());
      final capture = (locked as ScanLocked).capture;
      expect(capture.isValid, isTrue);
      expect(capture.mrz!.surname, 'ERIKSSON');
      expect(locked.fixture, isTrue);
      expect(notes.single.status, 'locked');
      expect(notes.single.detail, isNull);

      final rejected = await KycScanner.fixture(passChecksum: false)
          .scanStill(image);
      expect(rejected, isA<ScanRejected>());
      expect((rejected as ScanRejected).reason, RejectReason.checksum);
      expect(rejected, isNot(isA<ScanLocked>()));
    },
  );

  test('a Luhn miss does not emit a card capture', () async {
    final scanner = KycScanner(
      detector: FixtureDetector(),
      recognizer: LogitRecognizer('4242424242424243', const ['4', '2', '3']),
      fixture: true,
    );
    final decision = await scanner.scanStill(SyntheticCardSpec.image());
    expect(decision, isA<ScanRejected>());
    expect((decision as ScanRejected).reason, RejectReason.checksum);
  });

  test('a valid PAN locks and the trace omits the number', () async {
    final notes = <ScanObservation>[];
    const alphabet = ['4', '2', '1', '0', '3', '/', ' '];
    final scanner = KycScanner(
      detector: FixtureDetector(),
      recognizer: LogitRecognizer('4242424242424242 12/30', alphabet),
      onTrace: notes.add,
    );
    final decision = await scanner.scanStill(SyntheticCardSpec.image());
    expect(decision, isA<ScanLocked>());
    final capture = (decision as ScanLocked).capture;
    expect(capture.cardNumber, '4242424242424242');
    expect(capture.expiry, '12/30');
    final trace = notes
        .map((note) => '${note.status} ${note.detail}')
        .join(' ');
    expect(trace.contains('4242'), isFalse);
  });

  test('a detector box is used when the card has no brightness edge', () async {
    final scanner = KycScanner(
      detector: _BoxDetector(),
      recognizer: LogitRecognizer(IcaoSamples.erikssonTd3, [
        for (final rune in mrzAlphabet.runes) String.fromCharCode(rune),
      ]),
    );
    final image = RgbImage(220, 160, Uint8List(220 * 160 * 3));
    for (var i = 0; i < image.bytes.length; i++) {
      image.bytes[i] = 128;
    }
    final decision = await scanner.scanStill(image);
    expect(decision, isA<ScanLocked>());
    expect((decision as ScanLocked).capture.mrz!.surname, 'ERIKSSON');
    expect(decision.quad.tl.x, closeTo(30, 1));
    expect(decision.quad.tl.y, closeTo(24, 1));
  });

  test('a second frame during inference is skipped', () async {
    final detector = _HoldDetector();
    final scanner = KycScanner(
      detector: detector,
      recognizer: LogitRecognizer('A', const ['A']),
    );
    final frame = RawCameraFrame(
      width: 16,
      height: 16,
      layout: RawFrameLayout.rgba8888,
      planes: [
        RawPlane(
          bytes: Uint8List(16 * 16 * 4),
          bytesPerRow: 64,
          bytesPerPixel: 4,
        ),
      ],
    );
    final first = scanner.scanFrame(frame);
    await detector.started.future;
    final second = await scanner.scanFrame(frame);
    expect(second, isA<ScanSkipped>());
    expect(detector.calls, 1);
    detector.release.complete();
    await first;
  });

  test('scan sources do not import dart:io or http', () {
    final lib = Directory('lib');
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      expect(text.contains("import 'dart:io'"), isFalse, reason: entity.path);
      expect(text.contains('package:http'), isFalse, reason: entity.path);
      expect(text.contains('HttpClient'), isFalse, reason: entity.path);
      expect(text.contains('File('), isFalse, reason: entity.path);
    }
  });

  test('bundled onnx and dictionaries stay within 15 MB', () {
    final dir = Directory('assets/models');
    if (!dir.existsSync()) return;
    var bytes = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (path.endsWith('.onnx') || path.endsWith('.txt')) {
        bytes += entity.lengthSync();
      }
    }
    expect(bytes <= 15 * 1024 * 1024, isTrue);
  });
}

class _BoxDetector extends CardDetector {
  @override
  Future<List<Detection>> detect(RgbImage image) async {
    return const [
      Detection(
        x1: 30,
        y1: 24,
        x2: 180,
        y2: 118,
        score: 0.9,
        classId: DetectionClass.idCard,
        label: DetectionLabels.idCard,
      ),
    ];
  }
}

class _HoldDetector extends CardDetector {
  final started = Completer<void>();
  final release = Completer<void>();
  var calls = 0;

  @override
  Future<List<Detection>> detect(RgbImage image) async {
    calls += 1;
    if (!started.isCompleted) started.complete();
    await release.future;
    return [
      Detection(
        x1: 0,
        y1: 0,
        x2: image.width.toDouble(),
        y2: image.height.toDouble(),
        score: 1,
        classId: DetectionClass.idCard,
        label: DetectionLabels.idCard,
      ),
    ];
  }
}
