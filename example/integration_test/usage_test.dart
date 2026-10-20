import 'package:flutter/material.dart';
import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kyc_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('usage: pasted MRZ, a rejected digit, a card number, then the scan view', (
    tester,
  ) async {
    await tester.pumpWidget(const KycDemoApp());
    await tester.pumpAndSettle();
    debugPrint('KYC_USAGE_VISIBLE');
    await _watch(tester, const Duration(seconds: 2));

    await _type(tester, const Key('mrz-field'), IcaoSamples.erikssonTd3);
    await _tap(tester, const Key('check-button'));
    await _reveal(tester, find.text('ERIKSSON'));
    expect(find.text('Kilit'), findsOneWidget);
    await _watch(tester, const Duration(seconds: 3));

    await _type(tester, const Key('mrz-field'), _brokenEriksson());
    await _tap(tester, const Key('check-button'));
    await _reveal(tester, find.text('Kilit yok'));
    await _watch(tester, const Duration(seconds: 2));

    await _type(tester, const Key('mrz-field'), '');
    await _type(tester, const Key('pan-field'), '4242424242424242');
    await _type(tester, const Key('expiry-field'), '12/30');
    await _tap(tester, const Key('check-button'));
    await _reveal(tester, find.text('**** **** **** 4242'));
    await _watch(tester, const Duration(seconds: 3));

    await tester.tap(find.byKey(const Key('tab-scan')));
    await tester.pump();
    await _until(tester, find.byKey(const Key('fixture-button')));
    await _watch(tester, const Duration(seconds: 4));

    final fixtureMode =
        find.text('Fikstür').evaluate().isNotEmpty ||
        find.text('Model açılamadı').evaluate().isNotEmpty;
    if (fixtureMode) {
      await tester.tap(find.byKey(const Key('fixture-button')));
      await tester.pump();
      await _until(tester, find.text('ERIKSSON'));
      await tester.ensureVisible(find.text('ERIKSSON'));
      await tester.pump();
      await _watch(tester, const Duration(seconds: 3));
    }

    debugPrint('KYC_USAGE_DONE');
    await _watch(tester, const Duration(seconds: 1));
  });
}

Future<void> _watch(WidgetTester tester, Duration duration) {
  return tester.runAsync(() => Future<void>.delayed(duration));
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isNotEmpty) return;
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) {
    expect(target.hitTestable(), findsOneWidget);
    return;
  }
  for (final delta in const [350.0, -350.0]) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    try {
      await tester.scrollUntilVisible(
        target,
        delta,
        scrollable: scrollable.first,
        maxScrolls: 12,
        duration: const Duration(milliseconds: 200),
      );
    } on Object {
      // The target sits in the other scroll direction.
    }
    await tester.pumpAndSettle();
  }
  if (target.evaluate().isEmpty) {
    for (final element in find.byType(Text).evaluate()) {
      final widget = element.widget as Text;
      debugPrint('KYC_TEXT ${widget.data}');
    }
  }
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _type(WidgetTester tester, Key key, String value) async {
  final field = find.byKey(key);
  await _reveal(tester, field);
  final editable = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  editable.controller.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
  await tester.pump();
  expect(editable.controller.text, value);
  await _watch(tester, const Duration(milliseconds: 1100));
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final button = find.byKey(key);
  await _reveal(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
    await _watch(tester, const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for $finder');
}

String _brokenEriksson() {
  final text = IcaoSamples.erikssonTd3;
  final last = text[text.length - 1];
  return '${text.substring(0, text.length - 1)}${last == '0' ? '1' : '0'}';
}
