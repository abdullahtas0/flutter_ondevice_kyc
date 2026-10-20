import 'dart:convert';

import '../result/kyc_capture.dart';
import '../result/scan_decision.dart';

/// A ledger failure whose text never includes a document field.
class LedgerException implements Exception {
  const LedgerException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _opaqueId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
final _longDigits = RegExp(r'\d{9,}');
final _fieldKey = RegExp(r'^[A-Za-z][A-Za-z0-9]{0,31}$');

/// Case ids are labels such as `td3-01`. They contain a hyphen and fewer than
/// nine digits, so a document number or a PAN cannot become a report line.
bool opaqueCaseId(String id) {
  if (!_opaqueId.hasMatch(id) || !id.contains('-')) return false;
  if (_longDigits.hasMatch(id)) return false;
  var digits = 0;
  for (final code in id.codeUnits) {
    if (code >= 0x30 && code <= 0x39) digits++;
  }
  return digits < 9;
}

/// Relative path with no `.` or `..` segment and no drive or root prefix.
void checkLedgerPath(String id, String relative) {
  final label = opaqueCaseId(id) ? id : 'a case';
  if (relative.isEmpty || _leavesFolder(relative)) {
    throw LedgerException('case $label file is not inside the folder');
  }
}

bool _leavesFolder(String relative) {
  if (relative.startsWith('/') ||
      relative.startsWith(r'\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(relative)) {
    return true;
  }
  final segments = relative.split(RegExp(r'[\\/]'));
  return segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  );
}

/// What the frame should do, plus the fields the checksum is allowed to lock.
class LedgerCase {
  const LedgerCase({
    required this.id,
    required this.expectLock,
    this.documentNumber,
    this.birthDate,
    this.expiryDate,
    this.tckn,
    this.cardNumber,
    this.cardExpiry,
    this.surname,
    this.givenNames,
  });

  final String id;
  final bool expectLock;
  final String? documentNumber;
  final DateTime? birthDate;
  final DateTime? expiryDate;
  final String? tckn;
  final String? cardNumber;
  final String? cardExpiry;
  final String? surname;
  final String? givenNames;

  bool get gatesMrz =>
      documentNumber != null && birthDate != null && expiryDate != null;

  bool get gatesPan => cardNumber != null;

  /// An expected lock with neither gate is unscored. It cannot raise the rate.
  bool get canScoreLock => gatesMrz || gatesPan;
}

/// One manifest row. [relativePath] is never written into the report.
class LedgerFrame {
  const LedgerFrame({required this.truth, required this.relativePath});

  final LedgerCase truth;
  final String relativePath;
}

/// A truth paired with the decision for that still frame.
class LedgerObservation {
  const LedgerObservation(this.truth, this.decision);

  final LedgerCase truth;
  final ScanDecision? decision;
}

enum LedgerKind {
  correctLock,
  miss,
  falseLock,
  correctReject,
  skipped,
  unscored,
}

/// One scored case. [fields] is a fixed vocabulary, never a field value.
class LedgerRow {
  LedgerRow({
    required this.id,
    required this.kind,
    required this.expectedLock,
    required this.elapsedMs,
    required List<String> fields,
    required this.nameMismatch,
  }) : fields = List.unmodifiable(fields) {
    if (!opaqueCaseId(id)) {
      throw const LedgerException('a case id is not opaque');
    }
    if (elapsedMs != null && elapsedMs! < 0) {
      throw const LedgerException('elapsed is negative');
    }
    for (final field in fields) {
      if (!_allowedField(field)) {
        throw const LedgerException('ledger field is not a fixed token');
      }
    }
  }

  final String id;
  final LedgerKind kind;
  final bool expectedLock;
  final int? elapsedMs;
  final List<String> fields;
  final bool nameMismatch;
}

const _gatedTokens = {
  'documentNumber',
  'birthDate',
  'expiryDate',
  'tckn',
  'cardNumber',
  'cardExpiry',
  'unexpected',
};

bool _allowedField(String token) {
  if (_gatedTokens.contains(token)) return true;
  return RejectReason.values.any((reason) => reason.name == token);
}

bool _processed(LedgerKind kind) {
  return kind == LedgerKind.correctLock ||
      kind == LedgerKind.miss ||
      kind == LedgerKind.falseLock ||
      kind == LedgerKind.correctReject;
}

/// Counts and the three headline figures.
class LedgerReport {
  LedgerReport(List<LedgerRow> rows) : rows = List.unmodifiable(rows);

  final List<LedgerRow> rows;

  int get processed => rows.where((row) => _processed(row.kind)).length;

  int get expectedLocks =>
      rows.where((row) => row.expectedLock && _processed(row.kind)).length;

  int get correctLocks => _count(LedgerKind.correctLock);

  int get misses => _count(LedgerKind.miss);

  int get falseLocks => _count(LedgerKind.falseLock);

  int get correctRejects => _count(LedgerKind.correctReject);

  int get skipped => _count(LedgerKind.skipped);

  int get unscored => _count(LedgerKind.unscored);

  int get nameMismatches => rows
      .where((row) => row.kind == LedgerKind.correctLock && row.nameMismatch)
      .length;

  /// Correct locks over expected locks that named a gate.
  double? get lockRate =>
      expectedLocks == 0 ? null : correctLocks / expectedLocks;

  /// False locks over processed cases.
  double? get falseLockRate => processed == 0 ? null : falseLocks / processed;

  /// 95% point on sorted processed elapsed times, interpolated.
  int? get p95Ms {
    final samples = [
      for (final row in rows)
        if (_processed(row.kind) && row.elapsedMs != null) row.elapsedMs!,
    ];
    return _percentile95(samples);
  }

  int _count(LedgerKind kind) => rows.where((row) => row.kind == kind).length;
}

/// Scores decisions. The name line does not move [LedgerReport.lockRate] or
/// [LedgerReport.falseLockRate]. A skipped frame is outside both rates.
LedgerReport scoreLedger(List<LedgerObservation> observations) {
  final rows = <LedgerRow>[];
  final seen = <String>{};
  for (final observation in observations) {
    final id = observation.truth.id;
    if (!opaqueCaseId(id)) {
      throw const LedgerException('a case id is not opaque');
    }
    if (!seen.add(id)) {
      throw LedgerException('duplicate case id $id');
    }
    rows.add(_score(observation));
  }
  rows.sort((a, b) => a.id.compareTo(b.id));
  return LedgerReport(rows);
}

LedgerRow _score(LedgerObservation observation) {
  final truth = observation.truth;
  final decision = observation.decision;
  if (truth.expectLock && !truth.canScoreLock) {
    return LedgerRow(
      id: truth.id,
      kind: LedgerKind.unscored,
      expectedLock: true,
      elapsedMs: null,
      fields: const [],
      nameMismatch: false,
    );
  }
  if (decision == null) {
    throw LedgerException('case ${truth.id} was not scanned');
  }
  return switch (decision) {
    ScanSkipped() => LedgerRow(
      id: truth.id,
      kind: LedgerKind.skipped,
      expectedLock: truth.expectLock,
      elapsedMs: null,
      fields: const [],
      nameMismatch: false,
    ),
    ScanRejected(:final reason, :final elapsedMs) => LedgerRow(
      id: truth.id,
      kind: truth.expectLock ? LedgerKind.miss : LedgerKind.correctReject,
      expectedLock: truth.expectLock,
      elapsedMs: elapsedMs,
      fields: [reason.name],
      nameMismatch: false,
    ),
    ScanLocked locked => _lock(truth, locked),
  };
}

LedgerRow _lock(LedgerCase truth, ScanLocked decision) {
  if (!truth.expectLock) {
    return LedgerRow(
      id: truth.id,
      kind: LedgerKind.falseLock,
      expectedLock: false,
      elapsedMs: decision.elapsedMs,
      fields: const ['unexpected'],
      nameMismatch: false,
    );
  }
  final mismatched = _mismatched(truth, decision.capture);
  if (mismatched.isNotEmpty) {
    return LedgerRow(
      id: truth.id,
      kind: LedgerKind.falseLock,
      expectedLock: true,
      elapsedMs: decision.elapsedMs,
      fields: mismatched,
      nameMismatch: false,
    );
  }
  return LedgerRow(
    id: truth.id,
    kind: LedgerKind.correctLock,
    expectedLock: true,
    elapsedMs: decision.elapsedMs,
    fields: const [],
    nameMismatch: _nameMismatch(truth, decision.capture),
  );
}

List<String> _mismatched(LedgerCase truth, KycCapture capture) {
  final fields = <String>[];
  final mrz = capture.mrz;
  if (truth.gatesMrz) {
    if (mrz == null || !_sameDoc(mrz.documentNumber, truth.documentNumber!)) {
      fields.add('documentNumber');
    }
    if (mrz == null || !_sameDay(mrz.birthDate, truth.birthDate)) {
      fields.add('birthDate');
    }
    if (mrz == null || !_sameDay(mrz.expiryDate, truth.expiryDate)) {
      fields.add('expiryDate');
    }
    if (truth.tckn != null && (mrz == null || mrz.tckn != truth.tckn)) {
      fields.add('tckn');
    }
  }
  if (truth.gatesPan) {
    final got = capture.cardNumber;
    if (got == null || _digits(got) != _digits(truth.cardNumber!)) {
      fields.add('cardNumber');
    }
    if (truth.cardExpiry != null && capture.expiry != truth.cardExpiry) {
      fields.add('cardExpiry');
    }
  }
  return fields;
}

bool _nameMismatch(LedgerCase truth, KycCapture capture) {
  final mrz = capture.mrz;
  if (truth.surname != null) {
    if (mrz == null || _name(mrz.surname) != _name(truth.surname!)) return true;
  }
  if (truth.givenNames != null) {
    if (mrz == null || _name(mrz.givenNames) != _name(truth.givenNames!)) {
      return true;
    }
  }
  return false;
}

bool _sameDay(DateTime? got, DateTime? expected) {
  if (got == null || expected == null) return false;
  return got.year == expected.year &&
      got.month == expected.month &&
      got.day == expected.day;
}

bool _sameDoc(String got, String expected) => _doc(got) == _doc(expected);

String _doc(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[\s<]'), '');

String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

String _name(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Nearest-millisecond linear interpolation at 95% of the sorted sample.
int? _percentile95(List<int> samples) {
  if (samples.isEmpty) return null;
  final sorted = [...samples]..sort();
  if (sorted.length == 1) return sorted.first;
  final product = (sorted.length - 1) * 95;
  final low = product ~/ 100;
  final weight = product % 100;
  if (weight == 0) return sorted[low];
  final value = sorted[low] * (100 - weight) + sorted[low + 1] * weight;
  return (value + 50) ~/ 100;
}

String _kindLabel(LedgerKind kind) {
  return switch (kind) {
    LedgerKind.correctLock => 'correctLock',
    LedgerKind.miss => 'miss',
    LedgerKind.falseLock => 'falseLock',
    LedgerKind.correctReject => 'correctReject',
    LedgerKind.skipped => 'skipped',
    LedgerKind.unscored => 'unscored',
  };
}

/// Text safe to store. [model] is `onnx` or `fixture`.
String renderLedger(LedgerReport report, {required String model}) {
  if (model != 'onnx' && model != 'fixture') {
    throw const LedgerException('ledger model is not onnx or fixture');
  }
  final buffer = StringBuffer()
    ..writeln('model: $model')
    ..writeln('# lockRate is correctLocks/expectedLocks')
    ..writeln('# falseLockRate is falseLocks/processed')
    ..writeln('# p95Ms interpolates processed elapsed milliseconds')
    ..writeln(
      'lockRate: ${_rate(report.lockRate, report.correctLocks, report.expectedLocks)}',
    )
    ..writeln(
      'falseLockRate: ${_rate(report.falseLockRate, report.falseLocks, report.processed)}',
    )
    ..writeln('p95Ms: ${report.p95Ms ?? 'n/a'}')
    ..writeln('processed: ${report.processed}')
    ..writeln('expectedLocks: ${report.expectedLocks}')
    ..writeln('correctLocks: ${report.correctLocks}')
    ..writeln('misses: ${report.misses}')
    ..writeln('falseLocks: ${report.falseLocks}')
    ..writeln('correctRejects: ${report.correctRejects}')
    ..writeln('skipped: ${report.skipped}')
    ..writeln('unscored: ${report.unscored}')
    ..writeln('nameMismatches: ${report.nameMismatches}');
  if (report.rows.isNotEmpty) buffer.writeln();
  for (final row in report.rows) {
    buffer.writeln(_renderRow(row));
  }
  return buffer.toString();
}

String _rate(double? rate, int numerator, int denominator) {
  if (rate == null) return 'n/a ($numerator/$denominator)';
  return '${rate.toStringAsFixed(3)} ($numerator/$denominator)';
}

String _renderRow(LedgerRow row) {
  final parts = <String>[row.id, _kindLabel(row.kind)];
  if (row.fields.isNotEmpty) parts.add(row.fields.join(','));
  if (row.nameMismatch) parts.add('name');
  if (row.elapsedMs != null) parts.add('${row.elapsedMs}ms');
  return parts.join(' ');
}

const _rootKeys = {'cases'};
const _caseKeys = {
  'id',
  'file',
  'expect',
  'documentNumber',
  'birthDate',
  'expiryDate',
  'tckn',
  'cardNumber',
  'cardExpiry',
  'surname',
  'givenNames',
};

/// Parses a manifest. Error text names the case id and the field, not the value.
List<LedgerFrame> parseLedgerManifest(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const LedgerException('manifest.json is not valid JSON');
  }
  if (decoded is! Map) {
    throw const LedgerException('manifest.json must be an object');
  }
  final root = Map<String, dynamic>.from(decoded);
  for (final key in root.keys) {
    if (!_rootKeys.contains(key)) {
      throw LedgerException('manifest.json has an unknown ${_fieldLabel(key)}');
    }
  }
  final cases = root['cases'];
  if (cases is! List) {
    throw const LedgerException('manifest.json cases must be a list');
  }
  if (cases.isEmpty) {
    throw const LedgerException('manifest.json has no cases');
  }
  final frames = <LedgerFrame>[];
  final seen = <String>{};
  for (final item in cases) {
    if (item is! Map) {
      throw const LedgerException('a case must be an object');
    }
    frames.add(_frame(Map<String, dynamic>.from(item), seen));
  }
  return frames;
}

LedgerFrame _frame(Map<String, dynamic> json, Set<String> seen) {
  for (final key in json.keys) {
    if (!_caseKeys.contains(key)) {
      throw LedgerException('a case has an unknown ${_fieldLabel(key)}');
    }
  }
  final idValue = json['id'];
  if (idValue is! String || !opaqueCaseId(idValue)) {
    throw const LedgerException('a case id is not opaque');
  }
  if (!seen.add(idValue)) {
    throw LedgerException('duplicate case id $idValue');
  }
  final expectValue = json['expect'];
  if (expectValue != 'lock' && expectValue != 'reject') {
    throw LedgerException('case $idValue expect must be lock or reject');
  }
  final relative = _required(json, idValue, 'file');
  checkLedgerPath(idValue, relative);
  final documentNumber = _document(json, idValue);
  final birthDate = _date(json, idValue, 'birthDate');
  final expiryDate = _date(json, idValue, 'expiryDate');
  final tckn = _tckn(json, idValue);
  final cardNumber = _pan(json, idValue);
  final cardExpiry = _expiry(json, idValue);
  final surname = _bounded(json, idValue, 'surname');
  final givenNames = _bounded(json, idValue, 'givenNames');
  return LedgerFrame(
    relativePath: relative,
    truth: LedgerCase(
      id: idValue,
      expectLock: expectValue == 'lock',
      documentNumber: documentNumber,
      birthDate: birthDate,
      expiryDate: expiryDate,
      tckn: tckn,
      cardNumber: cardNumber,
      cardExpiry: cardExpiry,
      surname: surname,
      givenNames: givenNames,
    ),
  );
}

String _fieldLabel(String key) => _fieldKey.hasMatch(key) ? key : 'field';

String _required(Map<String, dynamic> json, String id, String key) {
  final value = _optional(json, id, key);
  if (value == null) throw LedgerException('case $id $key is missing');
  return value;
}

String? _optional(Map<String, dynamic> json, String id, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! String) {
    throw LedgerException('case $id $key must be a string');
  }
  if (value.contains('\n') || value.contains('\r')) {
    throw LedgerException('case $id $key has a newline');
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) throw LedgerException('case $id $key is empty');
  return trimmed;
}

String? _document(Map<String, dynamic> json, String id) {
  final text = _optional(json, id, 'documentNumber');
  if (text == null) return null;
  final normalized = text.toUpperCase().replaceAll(RegExp(r'[\s<]'), '');
  if (!RegExp(r'^[A-Z0-9]{1,9}$').hasMatch(normalized)) {
    throw LedgerException(
      'case $id documentNumber is not 1 to 9 letters or digits',
    );
  }
  return normalized;
}

DateTime? _date(Map<String, dynamic> json, String id, String key) {
  final text = _optional(json, id, key);
  if (text == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) {
    throw LedgerException('case $id $key is not a calendar date');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw LedgerException('case $id $key is not a calendar date');
  }
  return date;
}

String? _tckn(Map<String, dynamic> json, String id) {
  final text = _optional(json, id, 'tckn');
  if (text == null) return null;
  if (!RegExp(r'^\d{11}$').hasMatch(text)) {
    throw LedgerException('case $id tckn is not 11 digits');
  }
  return text;
}

String? _pan(Map<String, dynamic> json, String id) {
  final text = _optional(json, id, 'cardNumber');
  if (text == null) return null;
  final digits = text.replaceAll(RegExp(r'\D'), '');
  if (!RegExp(r'^\d{13,19}$').hasMatch(digits)) {
    throw LedgerException('case $id cardNumber is not 13 to 19 digits');
  }
  return digits;
}

String? _expiry(Map<String, dynamic> json, String id) {
  final text = _optional(json, id, 'cardExpiry');
  if (text == null) return null;
  if (!RegExp(r'^(0[1-9]|1[0-2])/\d{2}$').hasMatch(text)) {
    throw LedgerException('case $id cardExpiry is not MM/YY');
  }
  return text;
}

String? _bounded(Map<String, dynamic> json, String id, String key) {
  final text = _optional(json, id, key);
  if (text != null && text.length > 80) {
    throw LedgerException('case $id $key is too long');
  }
  return text;
}
