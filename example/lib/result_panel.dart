import 'package:flutter/material.dart';
import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';

import 'theme.dart';

class ResultPanel extends StatelessWidget {
  const ResultPanel({
    required this.locked,
    required this.title,
    required this.detail,
    this.rows = const [],
    this.caption,
    super.key,
  });

  final bool locked;
  final String title;
  final String detail;
  final List<(String, String)> rows;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final color = locked ? lockGreen : holdAmber;
    return Container(
      key: const Key('verdict'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: locked ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: muted)),
          for (final row in rows) ...[
            const SizedBox(height: 10),
            Text(row.$1, style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 2),
            Text(row.$2, style: mrzStyle),
          ],
          if (caption != null) ...[
            const SizedBox(height: 12),
            Text(caption!, style: const TextStyle(color: muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

List<(String, String)> captureRows(KycCapture capture) {
  final rows = <(String, String)>[];
  final mrz = capture.mrz;
  if (mrz != null) {
    rows.add(('Belge no', mrz.documentNumber));
    rows.add(('Soyad', mrz.surname));
    if (mrz.givenNames.isNotEmpty) rows.add(('Ad', mrz.givenNames));
    final birth = mrz.birthDate;
    if (birth != null) rows.add(('Doğum', _day(birth)));
    final expiry = mrz.expiryDate;
    if (expiry != null) rows.add(('Son kullanma', _day(expiry)));
    if (mrz.nationality.isNotEmpty) rows.add(('Uyruk', mrz.nationality));
    final tckn = mrz.tckn;
    if (tckn != null) rows.add(('TCKN', tckn));
  }
  final pan = capture.cardNumber;
  if (pan != null) {
    rows.add(('Kart numarası', pan));
    final redacted = capture.redactedCardNumber;
    if (redacted != null) rows.add(('Log örneği', redacted));
  }
  final cardExpiry = capture.expiry;
  if (cardExpiry != null) rows.add(('Son kullanma', cardExpiry));
  return rows;
}

String _day(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
