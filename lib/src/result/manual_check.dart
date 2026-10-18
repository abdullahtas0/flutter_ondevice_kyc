import '../validation/expiry.dart';
import '../validation/icao_mrz.dart';
import '../validation/luhn.dart';
import 'kyc_capture.dart';
import 'scan_decision.dart';

class ManualCheckResult {
  const ManualCheckResult.locked(this.capture) : reason = null;

  const ManualCheckResult.rejected(this.reason) : capture = null;

  final KycCapture? capture;
  final RejectReason? reason;

  bool get locked => capture != null;
}

/// Checks whatever the operator pasted. A miss returns a reason and no capture.
///
/// Non-empty fields are checked together: a bad MRZ is not saved just because
/// the PAN field is valid.
ManualCheckResult checkManual({
  String mrz = '',
  String pan = '',
  String expiry = '',
}) {
  final mrzText = mrz.trim();
  final panText = pan.trim();
  final expiryText = expiry.trim();
  if (mrzText.isEmpty && panText.isEmpty && expiryText.isEmpty) {
    return const ManualCheckResult.rejected(RejectReason.unreadable);
  }

  MrzData? mrzData;
  if (mrzText.isNotEmpty) {
    mrzData = parseMrz(mrzText);
    if (mrzData == null || !mrzData.isValid) {
      return const ManualCheckResult.rejected(RejectReason.checksum);
    }
  }

  String? card;
  String? cardExpiry;
  if (panText.isNotEmpty || expiryText.isNotEmpty) {
    if (panText.isEmpty) {
      return const ManualCheckResult.rejected(RejectReason.unreadable);
    }
    card = extractPan(panText);
    if (card == null) {
      return const ManualCheckResult.rejected(RejectReason.checksum);
    }
    if (expiryText.isNotEmpty) {
      cardExpiry = extractExpiry(expiryText);
      if (cardExpiry == null) {
        return const ManualCheckResult.rejected(RejectReason.checksum);
      }
    } else {
      cardExpiry = extractExpiry(panText);
    }
  }

  if (mrzData == null && card == null) {
    return const ManualCheckResult.rejected(RejectReason.unreadable);
  }
  return ManualCheckResult.locked(
    KycCapture(
      cardNumber: card,
      expiry: cardExpiry,
      mrz: mrzData,
      isValid: true,
    ),
  );
}
