/// Turkish national id checksum (11 digits, first digit not zero).
bool tcknValid(String raw) {
  if (!RegExp(r'^[1-9]\d{10}$').hasMatch(raw)) return false;
  final d = [for (var i = 0; i < 11; i++) raw.codeUnitAt(i) - 0x30];
  final odd = d[0] + d[2] + d[4] + d[6] + d[8];
  final even = d[1] + d[3] + d[5] + d[7];
  final tenth = _mod10(odd * 7 - even);
  if (tenth != d[9]) return false;
  final eleventh = _mod10(d.take(10).reduce((a, b) => a + b));
  return eleventh == d[10];
}

int _mod10(int value) => ((value % 10) + 10) % 10;
