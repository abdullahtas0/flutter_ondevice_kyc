import '../privacy/redact.dart';
import '../validation/icao_mrz.dart';

/// Fields emitted only after Luhn or ICAO 9303 accepts the frame.
class KycCapture {
  const KycCapture({
    required this.cardNumber,
    required this.expiry,
    required this.mrz,
    required this.isValid,
  });

  factory KycCapture.fromMrz(MrzData mrz) {
    return KycCapture(
      cardNumber: null,
      expiry: null,
      mrz: mrz,
      isValid: mrz.isValid,
    );
  }

  factory KycCapture.fromCard({
    required String cardNumber,
    String? expiry,
    MrzData? mrz,
  }) {
    return KycCapture(
      cardNumber: cardNumber,
      expiry: expiry,
      mrz: mrz,
      isValid: true,
    );
  }

  final String? cardNumber;
  final String? expiry;
  final MrzData? mrz;
  final bool isValid;

  String? get redactedCardNumber =>
      cardNumber == null ? null : redactPan(cardNumber!);
}
