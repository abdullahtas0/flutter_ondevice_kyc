import 'dart:typed_data';

import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_ondevice_kyc/src/pipeline/mrz_lines.dart';
import 'package:flutter_ondevice_kyc/src/pipeline/mrz_repair.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('three full-width lines are split and a short mark is ignored', () {
    final image = _sheet();
    _bar(image, 140, 158, 0, image.width);
    _bar(image, 168, 186, 0, image.width);
    _bar(image, 196, 214, 0, image.width);
    _bar(image, 30, 46, 20, 70);

    final lines = segmentMrzLines(image);
    expect(lines, hasLength(3));

    final merged = _sheet();
    _bar(merged, 150, 214, 0, merged.width);
    expect(segmentMrzLines(merged), hasLength(3));
    expect(lines.first.height, lessThan(image.height ~/ 4));
    expect(segmentMrzLines(rotate180(image)), hasLength(3));
  });

  test('one OCR confusion in a TD1 field is repaired', () {
    final valid = _td1();
    final parsed = parseMrz(valid);
    expect(parsed!.isValid, isTrue);

    final broken = valid.replaceFirst('740812', '740B12');
    final repaired = repairMrz(broken);
    final again = parseMrz(repaired)!;
    expect(again.isValid, isTrue);
    expect(again.birthDate, DateTime(1974, 8, 12));
    expect(again.surname, 'ERIKSSON');
    expect(again.tckn, parsed.tckn);

    final two = valid.replaceFirst('740812', '74OB12');
    expect(parseMrz(repairMrz(two))!.isValid, isFalse);
  });

  test('one OCR confusion in a TD3 document number is repaired', () {
    const broken = '''
P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
L898902C36UTO740B122F1204159ZE184226B<<<<<10
''';
    final repaired = parseMrz(repairMrz(broken))!;
    expect(repaired.isValid, isTrue);
    expect(repaired.birthDate, DateTime(1974, 8, 12));
  });
}

RgbImage _sheet() {
  final image = RgbImage(320, 220, Uint8List(320 * 220 * 3));
  for (var i = 0; i < image.bytes.length; i++) {
    image.bytes[i] = 236;
  }
  return image;
}

void _bar(RgbImage image, int top, int bottom, int left, int right) {
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      image.setRgb(x, y, 16, 16, 16);
    }
  }
}

String _td1() {
  const doc = 'L898902C3';
  const tckn = '10000000146';
  final line1 = 'I<TUR$doc${icaoCheckDigit(doc)}${tckn.padRight(15, '<')}';
  const birth = '740812';
  const expiry = '300101';
  const optional2 = '<<<<<<<<<<<';
  final birthCheck = icaoCheckDigit(birth);
  final expiryCheck = icaoCheckDigit(expiry);
  final compositeSource =
      '${line1.substring(5)}$birth$birthCheck$expiry$expiryCheck$optional2';
  final line2 =
      '$birth$birthCheck'
      'M'
      '$expiry$expiryCheck'
      'TUR'
      '$optional2${icaoCheckDigit(compositeSource)}';
  const line3 = 'ERIKSSON<<ANNA<MARIA<<<<<<<<<<';
  return '$line1\n$line2\n$line3';
}
