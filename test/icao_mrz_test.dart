import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the ICAO Eriksson TD3 specimen', () {
    final lines = IcaoSamples.erikssonTd3.split('\n');
    expect(lines[0].length, 44);
    expect(lines[1].length, 44);

    final mrz = parseMrz(IcaoSamples.erikssonTd3);
    expect(mrz, isNotNull);
    expect(mrz!.isValid, isTrue);
    expect(mrz.format, MrzFormat.td3);
    expect(mrz.documentNumber, 'L898902C3');
    expect(mrz.surname, 'ERIKSSON');
    expect(mrz.givenNames, 'ANNA MARIA');
    expect(mrz.nationality, 'UTO');
    expect(mrz.sex, 'F');
    expect(mrz.birthDate, DateTime(1974, 8, 12));
    expect(mrz.expiryDate, DateTime(2012, 4, 15));
    expect(mrz.optionalData, contains('ZE184226B'));
  });

  test('a flipped TD3 check digit does not produce a valid capture', () {
    final parsed = parseMrz(brokenErikssonMrz());
    expect(parsed, isNotNull);
    expect(parsed!.isValid, isFalse);
    final manual = checkManual(mrz: brokenErikssonMrz());
    expect(manual.capture, isNull);
    expect(manual.reason, RejectReason.checksum);
  });

  test('builds a valid TD1 and keeps the name line out of the checksum', () {
    final tckn = _tckn('100000001');
    final mrz = _td1(tckn: tckn);
    final parsed = parseMrz(mrz);
    expect(parsed, isNotNull);
    expect(parsed!.isValid, isTrue);
    expect(parsed.format, MrzFormat.td1);
    expect(parsed.tckn, tckn);
    expect(parsed.surname, 'ERIKSSON');

    final lines = mrz.split('\n');
    final renamed =
        '${lines[0]}\n${lines[1]}\n${'OTHER<<NAME'.padRight(30, '<')}';
    expect(parseMrz(renamed)!.isValid, isTrue);

    final badTckn = _td1(tckn: '${tckn.substring(0, 10)}9');
    expect(parseMrz(badTckn)!.tcknValid, isFalse);
    expect(parseMrz(badTckn)!.isValid, isFalse);
  });

  test('builds a valid TD2', () {
    final parsed = parseMrz(_td2());
    expect(parsed, isNotNull);
    expect(parsed!.format, MrzFormat.td2);
    expect(parsed.isValid, isTrue);
    expect(parsed.documentNumber, 'D23145890');
  });

  test('manual PAN check locks only when Luhn and expiry agree', () {
    final locked = checkManual(pan: '4242424242424242', expiry: '12/30');
    expect(locked.locked, isTrue);
    expect(locked.capture!.cardNumber, '4242424242424242');
    expect(locked.capture!.expiry, '12/30');
    expect(locked.capture!.redactedCardNumber, '**** **** **** 4242');
    expect(locked.capture!.isValid, isTrue);

    final rejected = checkManual(pan: '4242424242424243', expiry: '12/30');
    expect(rejected.capture, isNull);
    expect(rejected.reason, RejectReason.checksum);

    final badMonth = checkManual(pan: '4242424242424242', expiry: '13/30');
    expect(badMonth.capture, isNull);
  });
}

String _tckn(String first9) {
  final d = [for (final char in first9.split('')) int.parse(char)];
  final odd = d[0] + d[2] + d[4] + d[6] + d[8];
  final even = d[1] + d[3] + d[5] + d[7];
  final tenth = ((odd * 7 - even) % 10 + 10) % 10;
  final eleventh = (d.reduce((a, b) => a + b) + tenth) % 10;
  return '$first9$tenth$eleventh';
}

String _field(String value, int length) {
  final trimmed = value.length > length ? value.substring(0, length) : value;
  return trimmed.padRight(length, '<');
}

String _td1({required String tckn}) {
  const doc = 'L898902C3';
  final line1 = 'I<TUR$doc${icaoCheckDigit(doc)}${_field(tckn, 15)}';
  const birth = '740812';
  const expiry = '300101';
  const optional2 = '<<<<<<<<<<<';
  final birthCheck = icaoCheckDigit(birth);
  final expiryCheck = icaoCheckDigit(expiry);
  final compositeSource =
      line1.substring(5) +
      birth +
      birthCheck.toString() +
      expiry +
      expiryCheck.toString() +
      optional2;
  final line2 =
      '$birth$birthCheck'
      'M'
      '$expiry$expiryCheck'
      'TUR'
      '$optional2${icaoCheckDigit(compositeSource)}';
  const line3 = 'ERIKSSON<<ANNA<MARIA<<<<<<<<<<';
  expect(line1.length, 30, reason: 'td1 line 1');
  expect(line2.length, 30, reason: 'td1 line 2');
  expect(line3.length, 30, reason: 'td1 line 3');
  return '$line1\n$line2\n$line3';
}

String _td2() {
  const doc = 'D23145890';
  const birth = '740812';
  const expiry = '300101';
  const optional = '<<<<<<<';
  final birthCheck = icaoCheckDigit(birth);
  final expiryCheck = icaoCheckDigit(expiry);
  final docCheck = icaoCheckDigit(doc);
  final compositeSource =
      doc +
      docCheck.toString() +
      birth +
      birthCheck.toString() +
      expiry +
      expiryCheck.toString() +
      optional;
  final line2 =
      '$doc$docCheck'
      'UTO'
      '$birth$birthCheck'
      'F'
      '$expiry$expiryCheck'
      '$optional${icaoCheckDigit(compositeSource)}';
  final line1 = 'I<UTO${_field('ERIKSSON<<ANNA<MARIA', 31)}';
  expect(line1.length, 36);
  expect(line2.length, 36);
  return '$line1\n$line2';
}
