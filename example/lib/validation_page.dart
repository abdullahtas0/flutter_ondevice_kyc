import 'package:flutter/material.dart';
import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';

import 'result_panel.dart';

class ValidationPage extends StatefulWidget {
  const ValidationPage({super.key});

  @override
  State<ValidationPage> createState() => _ValidationPageState();
}

class _ValidationPageState extends State<ValidationPage> {
  final _mrz = TextEditingController();
  final _pan = TextEditingController();
  final _expiry = TextEditingController();
  ManualCheckResult? _result;

  @override
  void dispose() {
    _mrz.dispose();
    _pan.dispose();
    _expiry.dispose();
    super.dispose();
  }

  void _check() {
    final result = checkManual(
      mrz: _mrz.text,
      pan: _pan.text,
      expiry: _expiry.text,
    );
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const Text(
          'Yapıştırılan satır checksum tutmazsa kilit yok. Bu bir hata fırlatmaz.',
          style: TextStyle(color: Color(0xFF8C9386)),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('mrz-field'),
          controller: _mrz,
          minLines: 3,
          maxLines: 5,
          style: const TextStyle(
            fontFamily: 'Menlo',
            fontFamilyFallback: ['Courier', 'monospace'],
            fontSize: 13,
          ),
          decoration: const InputDecoration(
            labelText: 'MRZ',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('pan-field'),
          controller: _pan,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Kart numarası'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('expiry-field'),
          controller: _expiry,
          decoration: const InputDecoration(labelText: 'Son kullanma AA/YY'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('check-button'),
          onPressed: _check,
          child: const Text('Kontrol et'),
        ),
        if (result != null) ...[
          const SizedBox(height: 16),
          ResultPanel(
            locked: result.locked,
            title: result.locked ? 'Kilit' : 'Kilit yok',
            detail: result.locked
                ? 'Checksum tuttu.'
                : rejectLabel(result.reason ?? RejectReason.unreadable),
            rows: result.capture == null
                ? const []
                : captureRows(result.capture!),
          ),
        ],
      ],
    );
  }
}
