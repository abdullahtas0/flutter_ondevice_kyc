import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_ondevice_kyc/src/eval/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rates ignore the name line and keep field values out of the report',
    () {
      final report = scoreLedger([
        _obs(
          id: 'lock-ok',
          expectLock: true,
          decision: _lock(_specimen(), 100),
        ),
        _obs(
          id: 'lock-name',
          expectLock: true,
          surname: 'OTHERNAME',
          decision: _lock(_specimen(), 200),
        ),
        _obs(
          id: 'lock-wrong',
          expectLock: true,
          documentNumber: 'X12345678',
          decision: _lock(_specimen(), 300),
        ),
        _obs(
          id: 'lock-miss',
          expectLock: true,
          decision: const ScanRejected(RejectReason.checksum, 400),
        ),
        _obs(
          id: 'reject-ok',
          expectLock: false,
          decision: const ScanRejected(RejectReason.noCard, 500),
        ),
        _obs(
          id: 'reject-bad',
          expectLock: false,
          decision: _lock(_specimen(), 600),
        ),
        _obs(id: 'skip-one', expectLock: true, decision: const ScanSkipped()),
        LedgerObservation(
          const LedgerCase(
            id: 'no-gate',
            expectLock: true,
            surname: 'OTHERNAME',
          ),
          _lock(_specimen(raw: 'RAWSENTINEL'), 700),
        ),
      ]);

      expect(report.lockRate, 0.5);
      expect(report.falseLockRate, closeTo(2 / 6, 1e-12));
      expect(report.p95Ms, 575);
      expect(report.correctLocks, 2);
      expect(report.misses, 1);
      expect(report.falseLocks, 2);
      expect(report.nameMismatches, 1);
      expect(report.skipped, 1);
      expect(report.unscored, 1);

      final text = renderLedger(report, model: 'fixture');
      expect(text, '''
model: fixture
# lockRate is correctLocks/expectedLocks
# falseLockRate is falseLocks/processed
# p95Ms interpolates processed elapsed milliseconds
lockRate: 0.500 (2/4)
falseLockRate: 0.333 (2/6)
p95Ms: 575
processed: 6
expectedLocks: 4
correctLocks: 2
misses: 1
falseLocks: 2
correctRejects: 1
skipped: 1
unscored: 1
nameMismatches: 1

lock-miss miss checksum 400ms
lock-name correctLock name 200ms
lock-ok correctLock 100ms
lock-wrong falseLock documentNumber 300ms
no-gate unscored
reject-bad falseLock unexpected 600ms
reject-ok correctReject noCard 500ms
skip-one skipped
''');
      for (final secret in [
        'RAWSENTINEL',
        'L898902C3',
        'ERIKSSON',
        'OTHERNAME',
        'X12345678',
        'ANNA',
        '1974-08-12',
        '2012-04-15',
        'OPTIONALDATA',
      ]) {
        expect(text.contains(secret), isFalse, reason: secret);
      }
    },
  );

  test('a PAN mismatch is a false lock and the digits stay out', () {
    const pan = '4242424242424242';
    const other = '4000000000000002';
    final report = scoreLedger([
      LedgerObservation(
        const LedgerCase(
          id: 'pan-ok',
          expectLock: true,
          cardNumber: pan,
          cardExpiry: '12/30',
        ),
        _card(pan, '12/30', 10),
      ),
      LedgerObservation(
        const LedgerCase(
          id: 'pan-bad',
          expectLock: true,
          cardNumber: other,
          cardExpiry: '12/30',
        ),
        _card(pan, '12/30', 20),
      ),
    ]);
    expect(report.correctLocks, 1);
    expect(report.falseLocks, 1);
    expect(report.rows.firstWhere((row) => row.id == 'pan-bad').fields, [
      'cardNumber',
    ]);
    final text = renderLedger(report, model: 'onnx');
    expect(text.contains(pan), isFalse);
    expect(text.contains(other), isFalse);
    expect(text.contains('12/30'), isFalse);
    expect(text.contains('model: onnx'), isTrue);
  });

  test('a TCKN miss is a false lock and the digits stay out', () {
    const got = '10000000146';
    const expected = '20000000138';
    final report = scoreLedger([
      _obs(
        id: 'tckn-bad',
        expectLock: true,
        tckn: expected,
        decision: _lock(_specimen(tckn: got), 15),
      ),
    ]);
    expect(report.falseLocks, 1);
    expect(report.rows.single.fields, contains('tckn'));
    final text = renderLedger(report, model: 'fixture');
    expect(text.contains(got), isFalse);
    expect(text.contains(expected), isFalse);
  });

  test('surname case does not count as a name miss', () {
    final report = scoreLedger([
      _obs(
        id: 'name-case',
        expectLock: true,
        surname: 'eriksson',
        givenNames: 'anna  maria',
        decision: _lock(_specimen(), 8),
      ),
    ]);
    expect(report.correctLocks, 1);
    expect(report.nameMismatches, 0);
  });

  test('p95 interpolates the sorted elapsed times', () {
    expect(_p95([42]), 42);
    expect(_p95([10, 1000]), 951);
    expect(_p95([for (var i = 1; i <= 10; i++) i * 10]), 96);
    expect(scoreLedger(const []).p95Ms, isNull);
    expect(
      renderLedger(scoreLedger(const []), model: 'fixture'),
      contains('lockRate: n/a (0/0)'),
    );
  });

  test('manifest errors do not echo values', () {
    expect(
      () => parseLedgerManifest('{"4242424242424242":[],"cases":[]}'),
      throwsA(
        isA<LedgerException>().having(
          (error) => '$error',
          'text',
          isNot(contains('4242')),
        ),
      ),
    );

    expect(
      () => parseLedgerManifest(
        '{"cases":[{"id":"case-a","file":"a.jpg","expect":"lock",'
        '"documentNumber":898902,"birthDate":"1974-08-12",'
        '"expiryDate":"2012-04-15"}]}',
      ),
      throwsA(
        isA<LedgerException>().having(
          (error) => '$error',
          'text',
          isNot(contains('898902')),
        ),
      ),
    );

    expect(
      () => parseLedgerManifest(
        '{"cases":[{"id":"L898902C3","file":"a.jpg","expect":"reject"}]}',
      ),
      throwsA(
        isA<LedgerException>().having(
          (error) => '$error',
          'text',
          isNot(contains('L898902C3')),
        ),
      ),
    );

    expect(
      () => parseLedgerManifest(
        '{"cases":[{"id":"case-a","file":"../L898902C3.jpg","expect":"reject"}]}',
      ),
      throwsA(
        isA<LedgerException>().having(
          (error) => '$error',
          'text',
          isNot(contains('L898902C3')),
        ),
      ),
    );
  });

  test(
    'a lock manifest keeps the gated fields and drops a thin case later',
    () {
      final frames = parseLedgerManifest('''
{
  "cases": [
    {
      "id": "td3-01",
      "file": "frames/td3-01.jpg",
      "expect": "lock",
      "documentNumber": "l898902c3",
      "birthDate": "1974-08-12",
      "expiryDate": "2012-04-15",
      "surname": "eriksson"
    }
  ]
}
''');
      final truth = frames.single.truth;
      expect(truth.expectLock, isTrue);
      expect(truth.canScoreLock, isTrue);
      expect(truth.documentNumber, 'L898902C3');
      expect(truth.birthDate, DateTime(1974, 8, 12));
      expect(truth.surname, 'eriksson');
      expect(frames.single.relativePath, 'frames/td3-01.jpg');
    },
  );
}

int? _p95(List<int> samples) {
  return scoreLedger([
    for (var i = 0; i < samples.length; i++)
      LedgerObservation(
        LedgerCase(id: 'p95-${'$i'.padLeft(2, '0')}', expectLock: false),
        ScanRejected(RejectReason.noCard, samples[i]),
      ),
  ]).p95Ms;
}

LedgerObservation _obs({
  required String id,
  required bool expectLock,
  required ScanDecision decision,
  String documentNumber = 'L898902C3',
  DateTime? birthDate,
  DateTime? expiryDate,
  String? tckn,
  String? surname,
  String? givenNames,
}) {
  return LedgerObservation(
    LedgerCase(
      id: id,
      expectLock: expectLock,
      documentNumber: expectLock ? documentNumber : null,
      birthDate: expectLock ? (birthDate ?? DateTime(1974, 8, 12)) : null,
      expiryDate: expectLock ? (expiryDate ?? DateTime(2012, 4, 15)) : null,
      tckn: tckn,
      surname: surname,
      givenNames: givenNames,
    ),
    decision,
  );
}

const _quad = Quad(
  tl: Point2(0, 0),
  tr: Point2(1, 0),
  br: Point2(1, 1),
  bl: Point2(0, 1),
);

ScanDecision _lock(MrzData mrz, int elapsedMs) {
  return ScanLocked(
    capture: KycCapture.fromMrz(mrz),
    quad: _quad,
    detections: const [],
    elapsedMs: elapsedMs,
    fixture: true,
  );
}

ScanDecision _card(String pan, String expiry, int elapsedMs) {
  return ScanLocked(
    capture: KycCapture.fromCard(cardNumber: pan, expiry: expiry),
    quad: _quad,
    detections: const [],
    elapsedMs: elapsedMs,
    fixture: false,
  );
}

MrzData _specimen({String raw = 'RAWSENTINEL', String? tckn}) {
  return MrzData(
    format: MrzFormat.td3,
    documentCode: 'P<',
    issuingState: 'UTO',
    documentNumber: 'L898902C3',
    surname: 'ERIKSSON',
    givenNames: 'ANNA MARIA',
    nationality: 'UTO',
    sex: 'F',
    birthDate: DateTime(1974, 8, 12),
    expiryDate: DateTime(2012, 4, 15),
    optionalData: 'OPTIONALDATA',
    tckn: tckn,
    documentNumberValid: true,
    birthDateValid: true,
    expiryDateValid: true,
    optionalDataValid: true,
    compositeValid: true,
    tcknValid: true,
    raw: raw,
  );
}
