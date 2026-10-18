import '../validation/icao_mrz.dart';

/// Fixes one OCR confusion when every printed check digit agrees.
///
/// Several characters can fake a single field check (`B`/`8`, `O`/`0`). A
/// change is kept only when it is the only one that makes the whole MRZ valid.
/// The name line is not edited.
String repairMrz(String raw) {
  final lines = _clean(raw);
  if (lines == null) return raw;
  if (_valid(lines)) return lines.join('\n');
  final direct = _uniqueValid(_variants(lines));
  if (direct != null) return direct;
  final snapped = <List<String>>[];
  for (final candidate in _snapOne(lines)) {
    snapped.add(candidate);
    snapped.addAll(_variants(candidate));
  }
  return _uniqueValid(snapped) ?? lines.join('\n');
}

const _alternatives = {
  '0': ['O', 'D', 'Q'],
  'O': ['0', 'D', 'Q'],
  '1': ['I', 'L'],
  'I': ['1', 'L'],
  'L': ['1', 'I'],
  '2': ['Z'],
  'Z': ['2'],
  '5': ['S'],
  'S': ['5'],
  '6': ['G'],
  'G': ['6'],
  '8': ['B'],
  'B': ['8'],
  'D': ['0', 'O'],
  'Q': ['0', 'O'],
};

List<String>? _clean(String raw) {
  final lines = raw
      .toUpperCase()
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim().replaceAll(RegExp(r'[^A-Z0-9<]'), ''))
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length == 3 || lines.length == 2) return lines;
  return null;
}

bool _valid(List<String> lines) => parseMrz(lines.join('\n'))?.isValid == true;

String? _uniqueValid(Iterable<List<String>> candidates) {
  final found = <String>{};
  for (final candidate in candidates) {
    if (_valid(candidate)) found.add(candidate.join('\n'));
  }
  if (found.length == 1) return found.single;
  return null;
}

List<List<String>> _variants(List<String> lines) {
  final spots = _spots(lines);
  if (spots == null) return const [];
  final out = <List<String>>[];
  for (final spot in spots) {
    final line = lines[spot.$1];
    final alternatives = _alternatives[line[spot.$2]];
    if (alternatives == null) continue;
    for (final alternative in alternatives) {
      final next = [...lines];
      next[spot.$1] = line.replaceRange(spot.$2, spot.$2 + 1, alternative);
      out.add(next);
    }
  }
  return out;
}

/// Data positions covered by a check digit. Check digits themselves stay put,
/// so a wrong read cannot be laundered by rewriting the digit.
List<(int, int)>? _spots(List<String> lines) {
  if (lines.length == 3 && lines.every((line) => line.length == 30)) {
    return [
      for (var i = 5; i < 30; i++)
        if (i != 14) (0, i),
      for (var i = 0; i < 7; i++)
        if (i != 6) (1, i),
      for (var i = 8; i < 15; i++)
        if (i != 14) (1, i),
      for (var i = 18; i < 29; i++) (1, i),
    ];
  }
  if (lines.length == 2 && lines.every((line) => line.length == 44)) {
    return [
      for (var i = 0; i < 44; i++)
        if (i != 9 && i != 19 && i != 27 && i != 42 && i != 43) (1, i),
    ];
  }
  if (lines.length == 2 && lines.every((line) => line.length == 36)) {
    return [
      for (var i = 0; i < 36; i++)
        if (i != 9 && i != 19 && i != 27 && i != 35) (1, i),
    ];
  }
  return null;
}

List<List<String>> _snapOne(List<String> lines) {
  final target = _targetLength(lines);
  if (target == null) return const [];
  final off = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].length != target) off.add(i);
  }
  if (off.length != 1) return const [];
  final index = off.single;
  final line = lines[index];
  final out = <List<String>>[];
  if (line.length == target - 1) {
    for (var i = 0; i <= line.length; i++) {
      out.add(_replaced(lines, index, line.replaceRange(i, i, '<')));
    }
  } else if (line.length == target + 1) {
    for (var i = 0; i < line.length; i++) {
      out.add(_replaced(lines, index, line.replaceRange(i, i + 1, '')));
    }
  }
  return out;
}

int? _targetLength(List<String> lines) {
  if (lines.length == 3) return 30;
  if (lines.length != 2) return null;
  final longest = lines[0].length > lines[1].length
      ? lines[0].length
      : lines[1].length;
  if (longest >= 40) return 44;
  return 36;
}

List<String> _replaced(List<String> lines, int index, String line) {
  return [for (var i = 0; i < lines.length; i++) i == index ? line : lines[i]];
}
