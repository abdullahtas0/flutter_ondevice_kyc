import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Fails when [report] repeats a manifest value other than a case id.
void expectLedgerHidesManifest(String report, String manifest) {
  final decoded = jsonDecode(manifest);
  final ids = <String>{};
  final cases = (decoded as Map)['cases'] as List;
  for (final item in cases) {
    ids.add((item as Map)['id'] as String);
  }
  for (final value in _strings(decoded)) {
    if (value.length < 4) continue;
    if (value == 'lock' || value == 'reject') continue;
    if (ids.contains(value)) continue;
    expect(
      RegExp(
        '(?:^|\\s)${RegExp.escape(value)}(?:\\s|\$)',
        multiLine: true,
      ).hasMatch(report),
      isFalse,
      reason: 'ledger echoed a manifest field',
    );
  }
}

Iterable<String> _strings(Object? node) sync* {
  if (node is String) {
    yield node;
  } else if (node is List) {
    for (final item in node) {
      yield* _strings(item);
    }
  } else if (node is Map) {
    for (final value in node.values) {
      yield* _strings(value);
    }
  }
}
