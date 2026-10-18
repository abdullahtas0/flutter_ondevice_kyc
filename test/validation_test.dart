import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts known test PANs and rejects a broken check digit', () {
    expect(luhnValid('4242424242424242'), isTrue);
    expect(luhnValid('4242 4242 4242 4242'), isTrue);
    expect(luhnValid('4111111111111111'), isTrue);
    expect(luhnValid('4242424242424243'), isFalse);
    expect(luhnValid('4242'), isFalse);
    expect(extractPan('PAN 4242-4242-4242-4242 exp'), '4242424242424242');
  });

  test('redacts every digit except the last four', () {
    expect(redactPan('4242424242424242'), '**** **** **** 4242');
  });

  test('validates a generated TCKN and rejects a flipped digit', () {
    final tckn = _tckn('100000001');
    expect(tcknValid(tckn), isTrue);
    final broken = '${tckn.substring(0, 10)}${(int.parse(tckn[10]) + 1) % 10}';
    expect(tcknValid(broken), isFalse);
    expect(tcknValid('00000000000'), isFalse);
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
