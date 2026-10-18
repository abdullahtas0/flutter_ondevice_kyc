import 'tckn.dart';

/// ICAO 9303 machine-readable zone parser for TD1, TD2, and TD3.
///
/// A parse with [MrzData.isValid] false is a checksum miss, not an exception.
/// The name line has no check digit and does not gate [MrzData.isValid].

enum MrzFormat { td1, td2, td3 }

class MrzData {
  const MrzData({
    required this.format,
    required this.documentCode,
    required this.issuingState,
    required this.documentNumber,
    required this.surname,
    required this.givenNames,
    required this.nationality,
    required this.sex,
    required this.birthDate,
    required this.expiryDate,
    required this.optionalData,
    required this.tckn,
    required this.documentNumberValid,
    required this.birthDateValid,
    required this.expiryDateValid,
    required this.optionalDataValid,
    required this.compositeValid,
    required this.tcknValid,
    required this.raw,
  });

  final MrzFormat format;
  final String documentCode;
  final String issuingState;
  final String documentNumber;
  final String surname;
  final String givenNames;
  final String nationality;
  final String sex;
  final DateTime? birthDate;
  final DateTime? expiryDate;
  final String optionalData;
  final String? tckn;
  final bool documentNumberValid;
  final bool birthDateValid;
  final bool expiryDateValid;
  final bool optionalDataValid;
  final bool compositeValid;
  final bool tcknValid;
  final String raw;

  bool get isValid =>
      documentNumberValid &&
      birthDateValid &&
      expiryDateValid &&
      optionalDataValid &&
      compositeValid &&
      tcknValid;
}

/// Fictional ICAO specimen. Not a real person.
abstract final class IcaoSamples {
  static const erikssonTd3 =
      'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10';
}

/// Check digit for an MRZ field. Weights repeat 7, 3, 1.
///
/// Returns null when [field] contains a character outside `0-9`, `A-Z`, `<`.
int? icaoCheckDigit(String field) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < field.length; i++) {
    final value = _value(field.codeUnitAt(i));
    if (value < 0) return null;
    sum += value * weights[i % 3];
  }
  return sum % 10;
}

/// Parses TD1 (3×30), TD2 (2×36), or TD3 (2×44). Returns null when the line
/// shape is not an MRZ. A shaped MRZ with a bad check digit is returned with
/// [MrzData.isValid] false.
MrzData? parseMrz(String raw) {
  final lines = _lines(raw);
  if (lines == null) return null;
  if (lines.length == 2 && lines[0].length == 44 && lines[1].length == 44) {
    return _td3(lines);
  }
  if (lines.length == 2 && lines[0].length == 36 && lines[1].length == 36) {
    return _td2(lines);
  }
  if (lines.length == 3 &&
      lines[0].length == 30 &&
      lines[1].length == 30 &&
      lines[2].length == 30) {
    return _td1(lines);
  }
  return null;
}

int _value(int code) {
  if (code >= 0x30 && code <= 0x39) return code - 0x30;
  if (code >= 0x41 && code <= 0x5A) return code - 55;
  if (code == 0x3C) return 0;
  return -1;
}

bool _digitIs(String field, String digit) {
  if (digit.length != 1 || digit.codeUnitAt(0) < 0x30) return false;
  final expected = icaoCheckDigit(field);
  return expected != null && digit == '$expected';
}

List<String>? _lines(String raw) {
  final parts = raw
      .toUpperCase()
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim().replaceAll(' ', ''))
      .where((line) => line.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  if (parts.length == 1) {
    final compact = parts.single;
    if (compact.length == 88) {
      return [compact.substring(0, 44), compact.substring(44)];
    }
    if (compact.length == 72) {
      return [compact.substring(0, 36), compact.substring(36)];
    }
    if (compact.length == 90) {
      return [
        compact.substring(0, 30),
        compact.substring(30, 60),
        compact.substring(60),
      ];
    }
  }
  return parts;
}

MrzData _td3(List<String> lines) {
  final line1 = lines[0];
  final line2 = lines[1];
  final names = _name(line1.substring(5));
  final doc = line2.substring(0, 9);
  final birth = line2.substring(13, 19);
  final expiry = line2.substring(21, 27);
  final optional = line2.substring(28, 42);
  final tckn = _tckn(optional);
  return MrzData(
    format: MrzFormat.td3,
    documentCode: line1.substring(0, 2),
    issuingState: _trimFillers(line1.substring(2, 5)),
    documentNumber: _trimFillers(doc),
    surname: names.$1,
    givenNames: names.$2,
    nationality: _trimFillers(line2.substring(10, 13)),
    sex: line2.substring(20, 21),
    birthDate: _date(birth, birth: true),
    expiryDate: _date(expiry, birth: false),
    optionalData: _trimFillers(optional),
    tckn: tckn,
    documentNumberValid: _digitIs(doc, line2.substring(9, 10)),
    birthDateValid: _digitIs(birth, line2.substring(19, 20)),
    expiryDateValid: _digitIs(expiry, line2.substring(27, 28)),
    optionalDataValid: _digitIs(optional, line2.substring(42, 43)),
    compositeValid: _digitIs(
      line2.substring(0, 10) +
          line2.substring(13, 20) +
          line2.substring(21, 43),
      line2.substring(43),
    ),
    tcknValid: tckn == null || tcknValid(tckn),
    raw: lines.join('\n'),
  );
}

MrzData _td2(List<String> lines) {
  final line1 = lines[0];
  final line2 = lines[1];
  final names = _name(line1.substring(5));
  final doc = line2.substring(0, 9);
  final birth = line2.substring(13, 19);
  final expiry = line2.substring(21, 27);
  final optional = line2.substring(28, 35);
  final tckn = _tckn(optional);
  return MrzData(
    format: MrzFormat.td2,
    documentCode: line1.substring(0, 2),
    issuingState: _trimFillers(line1.substring(2, 5)),
    documentNumber: _trimFillers(doc),
    surname: names.$1,
    givenNames: names.$2,
    nationality: _trimFillers(line2.substring(10, 13)),
    sex: line2.substring(20, 21),
    birthDate: _date(birth, birth: true),
    expiryDate: _date(expiry, birth: false),
    optionalData: _trimFillers(optional),
    tckn: tckn,
    documentNumberValid: _digitIs(doc, line2.substring(9, 10)),
    birthDateValid: _digitIs(birth, line2.substring(19, 20)),
    expiryDateValid: _digitIs(expiry, line2.substring(27, 28)),
    optionalDataValid: true,
    compositeValid: _digitIs(
      line2.substring(0, 10) +
          line2.substring(13, 20) +
          line2.substring(21, 35),
      line2.substring(35),
    ),
    tcknValid: tckn == null || tcknValid(tckn),
    raw: lines.join('\n'),
  );
}

MrzData _td1(List<String> lines) {
  final line1 = lines[0];
  final line2 = lines[1];
  final names = _name(lines[2]);
  final doc = line1.substring(5, 14);
  final birth = line2.substring(0, 6);
  final expiry = line2.substring(8, 14);
  final optional = line1.substring(15) + line2.substring(18, 29);
  final tckn = _tckn(optional);
  return MrzData(
    format: MrzFormat.td1,
    documentCode: line1.substring(0, 2),
    issuingState: _trimFillers(line1.substring(2, 5)),
    documentNumber: _trimFillers(doc),
    surname: names.$1,
    givenNames: names.$2,
    nationality: _trimFillers(line2.substring(15, 18)),
    sex: line2.substring(7, 8),
    birthDate: _date(birth, birth: true),
    expiryDate: _date(expiry, birth: false),
    optionalData: _trimFillers(optional),
    tckn: tckn,
    documentNumberValid: _digitIs(doc, line1.substring(14, 15)),
    birthDateValid: _digitIs(birth, line2.substring(6, 7)),
    expiryDateValid: _digitIs(expiry, line2.substring(14, 15)),
    optionalDataValid: true,
    compositeValid: _digitIs(
      line1.substring(5) +
          line2.substring(0, 7) +
          line2.substring(8, 15) +
          line2.substring(18, 29),
      line2.substring(29),
    ),
    tcknValid: tckn == null || tcknValid(tckn),
    raw: lines.join('\n'),
  );
}

(String, String) _name(String field) {
  final trimmed = field.replaceAll(RegExp(r'<+$'), '');
  final parts = trimmed.split('<<');
  final surname = parts.first.replaceAll('<', ' ').trim();
  final given = parts.length < 2
      ? ''
      : parts
            .sublist(1)
            .join('<')
            .replaceAll('<', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
  return (surname, given);
}

String _trimFillers(String field) => field.replaceAll('<', '').trim();

String? _tckn(String field) => RegExp(r'\d{11}').firstMatch(field)?.group(0);

DateTime? _date(String yymmdd, {required bool birth}) {
  if (yymmdd.length != 6 || yymmdd.contains('<')) return null;
  final yy = int.tryParse(yymmdd.substring(0, 2));
  final mm = int.tryParse(yymmdd.substring(2, 4));
  final dd = int.tryParse(yymmdd.substring(4, 6));
  if (yy == null || mm == null || dd == null) return null;
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
  final nowYy = DateTime.now().year % 100;
  final year = birth ? (yy > nowYy ? 1900 + yy : 2000 + yy) : 2000 + yy;
  final date = DateTime(year, mm, dd);
  if (date.month != mm || date.day != dd) return null;
  return date;
}
