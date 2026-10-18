import 'package:flutter/material.dart';
import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_example/main.dart';

void main() {
  testWidgets('pasted MRZ locks, a bad digit does not throw', (tester) async {
    await tester.pumpWidget(const KycDemoApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('mrz-field')),
      IcaoSamples.erikssonTd3,
    );
    await tester.tap(find.byKey(const Key('check-button')));
    await tester.pumpAndSettle();
    expect(find.text('Kilit'), findsOneWidget);
    expect(find.text('ERIKSSON'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const Key('mrz-field')),
      brokenErikssonMrz(),
    );
    await tester.tap(find.byKey(const Key('check-button')));
    await tester.pumpAndSettle();
    expect(find.text('Kilit yok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fixture mode shows a green lock without a model file', (
    tester,
  ) async {
    await tester.pumpWidget(const KycDemoApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-scan')));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();

    final detection = find.text('Tespit modeli').evaluate().isNotEmpty;
    final fixture =
        find.text('Fikstür').evaluate().isNotEmpty ||
        find.text('Model açılamadı').evaluate().isNotEmpty;
    expect(detection || fixture, isTrue);

    if (fixture) {
      await tester.tap(find.byKey(const Key('fixture-button')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Kilit'), findsOneWidget);
      expect(find.text('ERIKSSON'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
