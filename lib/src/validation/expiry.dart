/// Month/year as printed on a card, `MM/YY`. Invalid months are rejected.
String? extractExpiry(String text) {
  final match = RegExp(r'(0[1-9]|1[0-2])\s*/\s*(\d{2})').firstMatch(text);
  if (match == null) return null;
  return '${match.group(1)}/${match.group(2)}';
}
