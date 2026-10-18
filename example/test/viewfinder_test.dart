import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_example/viewfinder.dart';

void main() {
  test('portrait sensor turn and the guide crop stay on the card', () {
    expect(portraitQuarterTurns(90), 1);
    expect(portraitQuarterTurns(270), 3);
    expect(portraitQuarterTurns(0), 0);
    expect(
      analysisTurns(
        bufferWidth: 1920,
        bufferHeight: 1080,
        sensorOrientation: 90,
      ),
      1,
    );
    expect(
      analysisTurns(
        bufferWidth: 1080,
        bufferHeight: 1920,
        sensorOrientation: 90,
      ),
      0,
    );
    final focus = mrzFocusPoint(const Size(400, 700));
    expect(focus.dx, closeTo(0.5, 0.08));
    expect(focus.dy, greaterThan(0.5));

    const view = Size(400, 700);
    const image = Size(1080, 1920);
    final crop = guideCrop(view, image);
    expect(crop.right - crop.left, closeTo(0.9, 0.05));
    expect(crop.left, greaterThan(0));
    expect(crop.bottom, lessThan(1));
    final guide = idGuideRect(view);
    expect(guide.width / guide.height, closeTo(id1Aspect, 0.01));
  });
}
