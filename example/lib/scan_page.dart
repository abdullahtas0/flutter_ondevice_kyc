import 'package:flutter/material.dart';
import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';

import 'demo_copy.dart';
import 'gallery_image.dart';
import 'result_panel.dart';
import 'scanner_factory.dart';
import 'theme.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({required this.opened, super.key});

  final OpenedScanner opened;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  ScanDecision? _manual;
  String? _note;

  Future<void> _gallery() async {
    try {
      final image = await rgbFromGallery();
      if (image == null || !mounted) return;
      final decision = await widget.opened.scanner.scanStill(image);
      if (!mounted) return;
      setState(() => _manual = decision);
    } on Object {
      if (mounted) setState(() => _note = 'Görsel okunamadı');
    }
  }

  Future<void> _fixtureLock() async {
    final decision = await widget.opened.scanner.scanStill(
      SyntheticCardSpec.image(),
    );
    if (!mounted) return;
    setState(() => _manual = decision);
  }

  @override
  Widget build(BuildContext context) {
    final manual = _manual;
    final locked = manual is ScanLocked ? manual : null;
    final rejected = manual is ScanRejected ? manual : null;
    final fixtureCaption = widget.opened.fixture && locked != null
        ? 'Örnek checksum. Belgeden okunmadı.'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              key: const Key('mode-chip'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.opened.label),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: KycScanView(
              scanner: widget.opened.scanner,
              rejectText: demoRejectLabel,
              idleHint:
                  'Kartı çerçeveye oturt. Alt üç çizgi MRZ satırları.',
              focusingHint: 'MRZ satırlarına kilitleniyor.',
              lockedHint: 'Checksum tuttu.',
              cameraMissingHint: 'Kamera açılamadı',
            ),
          ),
          if (_note != null) ...[
            const SizedBox(height: 8),
            Text(_note!, style: const TextStyle(color: holdAmber)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: _gallery, child: const Text('Galeri')),
              TextButton(
                key: const Key('fixture-button'),
                onPressed: _fixtureLock,
                child: const Text('Fikstür kilidi'),
              ),
            ],
          ),
          if (locked != null) ...[
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: ResultPanel(
                  locked: true,
                  title: 'Kilit',
                  detail: 'Checksum tuttu. ${locked.elapsedMs} ms',
                  rows: captureRows(locked.capture),
                  caption: fixtureCaption,
                ),
              ),
            ),
          ] else if (rejected != null) ...[
            const SizedBox(height: 10),
            ResultPanel(
              locked: false,
              title: 'Kilit yok',
              detail: demoRejectLabel(rejected.reason),
            ),
          ],
        ],
      ),
    );
  }
}
