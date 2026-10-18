/// Luhn check for a primary account number of 13 to 19 digits.
///
/// Spaces and hyphens are ignored. Any other non-digit rejects the value.
bool luhnValid(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^\d{13,19}$').hasMatch(digits)) return false;
  var sum = 0;
  var doubleDigit = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var n = digits.codeUnitAt(i) - 0x30;
    if (doubleDigit) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    doubleDigit = !doubleDigit;
  }
  return sum % 10 == 0;
}

/// The digit run in [text] that satisfies Luhn, or null.
///
/// Groups may be separated by spaces or hyphens. A slash starts a new field,
/// so an expiry is not glued onto the number. A failing run is not scanned
/// for a shorter valid subset inside those same digits.
String? extractPan(String text) {
  final masked = text.replaceAll('-', ' ');
  for (final part in masked.split(RegExp(r'[^0-9 ]+'))) {
    final groups = RegExp(r'\d+')
        .allMatches(part)
        .map((match) => match.group(0)!)
        .toList();
    if (groups.isEmpty) continue;
    final joined = groups.join();
    if (_panLength(joined) && luhnValid(joined)) return joined;
    for (final group in groups) {
      if (_panLength(group) && luhnValid(group)) return group;
    }
  }
  return null;
}

/// True when [text] contains a 13–19 digit run, whether or not Luhn passes.
bool hasPanCandidate(String text) {
  final masked = text.replaceAll('-', ' ');
  for (final part in masked.split(RegExp(r'[^0-9 ]+'))) {
    final joined = RegExp(r'\d+')
        .allMatches(part)
        .map((match) => match.group(0)!)
        .join();
    if (joined.length >= 13) return true;
  }
  return false;
}

bool _panLength(String digits) => digits.length >= 13 && digits.length <= 19;
