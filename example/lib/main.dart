import 'package:flutter/material.dart';

import 'scan_page.dart';
import 'scanner_factory.dart';
import 'theme.dart';
import 'validation_page.dart';

void main() {
  runApp(const KycDemoApp());
}

class KycDemoApp extends StatelessWidget {
  const KycDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KYC',
      debugShowCheckedModeBanner: false,
      theme: buildKycTheme(),
      home: const DemoShell(),
    );
  }
}

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  OpenedScanner? _opened;
  var _scanTab = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final opened = await openScanner();
    if (!mounted) return;
    setState(() => _opened = opened);
  }

  @override
  void dispose() {
    _opened?.scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opened = _opened;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Text(
                'KYC',
                style: TextStyle(letterSpacing: 3, color: muted, fontSize: 12),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Cihaz üstü okuma',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _TabButton(
                    key: const Key('tab-validation'),
                    label: 'Doğrulama',
                    selected: !_scanTab,
                    onTap: () => setState(() => _scanTab = false),
                  ),
                  const SizedBox(width: 8),
                  _TabButton(
                    key: const Key('tab-scan'),
                    label: 'Tara',
                    selected: _scanTab,
                    onTap: () => setState(() => _scanTab = true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _scanTab
                  ? opened == null
                        ? const Center(child: Text('Hazırlanıyor'))
                        : ScanPage(opened: opened)
                  : const ValidationPage(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? ink : muted,
        backgroundColor: selected ? panel : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: selected ? lockGreen : line),
        ),
      ),
      child: Text(label),
    );
  }
}
