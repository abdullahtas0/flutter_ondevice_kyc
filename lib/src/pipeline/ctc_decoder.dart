/// Greedy CTC decode. Class 0 is the blank; [alphabet] item 0 is class 1.
String ctcGreedyDecode(List<List<double>> logits, List<String> alphabet) {
  final buffer = StringBuffer();
  var previous = -1;
  for (final step in logits) {
    var arg = 0;
    var best = step.isEmpty ? 0.0 : step[0];
    for (var i = 1; i < step.length; i++) {
      if (step[i] > best) {
        best = step[i];
        arg = i;
      }
    }
    if (arg != 0 && arg != previous) {
      final index = arg - 1;
      if (index >= 0 && index < alphabet.length) {
        buffer.write(alphabet[index]);
      }
    }
    previous = arg;
  }
  return buffer.toString();
}

/// One-hot logits with a blank between every character so repeats survive.
List<List<double>> logitsForText(String text, List<String> alphabet) {
  final width = alphabet.length + 1;
  final steps = <List<double>>[];
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final index = alphabet.indexOf(char);
    if (index < 0) {
      throw ArgumentError('Alphabet has no entry for "$char"');
    }
    final step = List<double>.filled(width, 0);
    step[index + 1] = 1;
    steps.add(step);
    steps.add(List<double>.filled(width, 0)..[0] = 1);
  }
  return steps;
}

const mrzAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<\n';
