import 'dart:typed_data';

import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';
import 'package:flutter_ondevice_kyc/src/pipeline/onnx_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frame gate drops an in-flight frame and a frame inside 200 ms', () {
    final gate = FrameGate(minInterval: const Duration(milliseconds: 200));
    final start = DateTime(2026, 1, 1);
    expect(gate.tryAcquire(start), isTrue);
    expect(
      gate.tryAcquire(start.add(const Duration(milliseconds: 50))),
      isFalse,
    );
    gate.release();
    expect(
      gate.tryAcquire(start.add(const Duration(milliseconds: 100))),
      isFalse,
    );
    expect(
      gate.tryAcquire(start.add(const Duration(milliseconds: 200))),
      isTrue,
    );
  });

  test('nms keeps the higher score and a different class', () {
    const strong = Detection(
      x1: 0,
      y1: 0,
      x2: 10,
      y2: 10,
      score: 0.9,
      classId: 0,
      label: 'id_card',
    );
    const weak = Detection(
      x1: 1,
      y1: 1,
      x2: 11,
      y2: 11,
      score: 0.4,
      classId: 0,
      label: 'id_card',
    );
    const other = Detection(
      x1: 1,
      y1: 1,
      x2: 11,
      y2: 11,
      score: 0.8,
      classId: 1,
      label: 'mrz_zone',
    );
    const far = Detection(
      x1: 40,
      y1: 40,
      x2: 60,
      y2: 60,
      score: 0.7,
      classId: 0,
      label: 'id_card',
    );
    final kept = nms([weak, strong, other, far]);
    expect(kept.map((box) => box.score), containsAll([0.9, 0.8, 0.7]));
    expect(kept.where((box) => box.classId == 0), hasLength(2));
  });

  test('decodes one YOLOX cell at the origin grid', () {
    const input = 32;
    const classes = 3;
    final channels = 5 + classes;
    final output = List<double>.filled(
      yoloxPredictionCount(input) * channels,
      0,
    );
    output[4] = 1;
    output[5] = 1;
    final boxes = decodeYolox(
      output: output,
      inputSize: input,
      numClasses: classes,
      labels: DetectionLabels.kyc,
      scoreThreshold: 0.5,
    );
    expect(boxes, hasLength(1));
    expect(boxes.single.label, DetectionLabels.idCard);
    expect(boxes.single.x1, closeTo(-4, 0.001));
    expect(boxes.single.y1, closeTo(-4, 0.001));
    expect(boxes.single.x2, closeTo(4, 0.001));
    expect(boxes.single.score, closeTo(1, 0.001));
  });

  test('recognition decode reads the tensor class axis', () {
    final decoded = decodeRecognition([0, 1, 0, 0], [1, 1, 4], ['A', 'B']);
    expect(decoded, 'A');
  });

  test('recognition tensor pads a narrow line to width 320', () {
    final image = RgbImage(20, 40, Uint8List(20 * 40 * 3));
    final tensor = recognitionTensor(image);
    expect(tensor.width, 320);
    expect(tensor.values.length, 3 * 48 * 320);
  });

  test('ctc keeps repeated fillers when a blank separates them', () {
    const alphabet = ['A', '<'];
    final logits = logitsForText('A<<', alphabet);
    expect(ctcGreedyDecode(logits, alphabet), 'A<<');
    final collapsed = [
      [0.0, 1.0, 0.0],
      [0.0, 1.0, 0.0],
    ];
    expect(ctcGreedyDecode(collapsed, alphabet), 'A');
  });

  test('inward scan finds an ID-1 card and rejects a square', () {
    final card = SyntheticCardSpec.image();
    final quad = findCardQuad(card);
    expect(quad, isNotNull);
    expect(quad!.aspect, closeTo(240 / 152, 0.08));
    expect(quad.tl.x, closeTo(SyntheticCardSpec.left, 3));
    expect(quad.tl.y, closeTo(SyntheticCardSpec.top, 3));

    final square = RgbImage(80, 80, Uint8List(80 * 80 * 3));
    for (var y = 10; y < 70; y++) {
      for (var x = 10; x < 70; x++) {
        square.setRgb(x, y, 240, 240, 240);
      }
    }
    expect(findCardQuad(square), isNull);
  });

  test('warp keeps the card aspect and maps the corners', () {
    final source = RgbImage(90, 70, Uint8List(90 * 70 * 3));
    const quad = Quad(
      tl: Point2(10, 8),
      tr: Point2(70, 10),
      br: Point2(68, 50),
      bl: Point2(12, 48),
    );
    _paint(source, quad.tl, 255, 0, 0);
    _paint(source, quad.tr, 0, 255, 0);
    _paint(source, quad.br, 0, 0, 255);
    _paint(source, quad.bl, 255, 255, 0);

    final warped = warpQuad(source, quad);
    expect(warped, isNotNull);
    expect(warped!.width / warped.height, closeTo(quad.aspect, 0.05));
    expect(warped.red(0, 0), greaterThan(200));
    expect(warped.green(0, 0), lessThan(40));
    expect(warped.green(warped.width - 1, 0), greaterThan(200));
    expect(warped.blue(warped.width - 1, warped.height - 1), greaterThan(200));
    expect(warped.red(0, warped.height - 1), greaterThan(200));
    expect(warped.green(0, warped.height - 1), greaterThan(200));
  });

  test('a dark card on a light table is found inside the border', () {
    const width = 200;
    const height = 140;
    final image = RgbImage(width, height, Uint8List(width * height * 3));
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setRgb(x, y, 236, 236, 236);
      }
    }
    const left = 24;
    const top = 22;
    const cardWidth = 150;
    const cardHeight = 94;
    for (var y = top; y < top + cardHeight; y++) {
      for (var x = left; x < left + cardWidth; x++) {
        image.setRgb(x, y, 28, 32, 36);
      }
    }
    final quad = findCardQuad(image);
    expect(quad, isNotNull);
    expect(quad!.tl.x, closeTo(left, 4));
    expect(quad.tl.y, closeTo(top, 4));
    expect(quad.aspect, closeTo(cardWidth / cardHeight, 0.12));
  });

  test('a 90 degree turn stands the buffer upright', () {
    final packed = (
      bytes: Uint8List.fromList([
        10, 0, 0, 20, 0, 0, //
        30, 0, 0, 40, 0, 0,
      ]),
      width: 2,
      height: 2,
    );
    final turned = rotatePacked(packed, 1);
    expect(turned.width, 2);
    expect(turned.height, 2);
    expect(turned.bytes[0], 30);
    expect(turned.bytes[3], 10);
    expect(turned.bytes[6], 40);
    expect(turned.bytes[9], 20);
  });

  test('neutral YUV and BGRA become gray and swapped channels', () {
    final yuv = yuv420ToPacked(
      width: 2,
      height: 2,
      y: Uint8List.fromList([128, 128, 128, 128]),
      u: Uint8List.fromList([128]),
      v: Uint8List.fromList([128]),
      yRow: 2,
      uRow: 1,
      vRow: 1,
      yPix: 1,
      uPix: 1,
      vPix: 1,
    );
    expect(yuv.bytes[0], closeTo(yuv.bytes[1], 2));
    expect(yuv.bytes[1], closeTo(yuv.bytes[2], 2));
    expect(yuv.bytes[0], inInclusiveRange(120, 145));

    final bgra = bgraToPacked(
      width: 1,
      height: 1,
      bytes: Uint8List.fromList([10, 20, 30, 255]),
      bytesPerRow: 4,
    );
    expect(bgra.bytes, [30, 20, 10]);
  });

  test('letterbox pads the bottom with 114 and keeps BGR order', () {
    final image = RgbImage(100, 50, Uint8List(100 * 50 * 3));
    image.setRgb(0, 0, 10, 20, 30);
    final boxed = letterboxBgr(image, size: 416);
    expect(boxed.ratio, closeTo(416 / 100, 0.001));
    expect(boxed.tensor[0], 30);
    expect(boxed.tensor[416 * 416], 20);
    expect(boxed.tensor[2 * 416 * 416], 10);
    final pad = 400 * 416;
    expect(boxed.tensor[pad], 114);
  });
}

void _paint(RgbImage image, Point2 point, int red, int green, int blue) {
  final cx = point.x.round();
  final cy = point.y.round();
  for (var y = cy - 1; y <= cy + 1; y++) {
    for (var x = cx - 1; x <= cx + 1; x++) {
      if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
      image.setRgb(x, y, red, green, blue);
    }
  }
}
