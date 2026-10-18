import '../image/rgb_image.dart';

abstract final class DetectionClass {
  static const idCard = 0;
  static const mrzZone = 1;
  static const cardNumbers = 2;
}

abstract final class DetectionLabels {
  static const idCard = 'id_card';
  static const mrzZone = 'mrz_zone';
  static const cardNumbers = 'credit_card_numbers';
  static const kyc = [idCard, mrzZone, cardNumbers];
}

class Detection {
  const Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.classId,
    required this.label,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double score;
  final int classId;
  final String label;

  double get width => (x2 - x1).abs();

  double get height => (y2 - y1).abs();

  double get area => width * height;
}

abstract class CardDetector {
  Future<List<Detection>> detect(RgbImage image);

  Future<void> close() async {}
}

abstract class TextRecognizer {
  Future<String> recognize(RgbImage line);

  Future<void> close() async {}
}
