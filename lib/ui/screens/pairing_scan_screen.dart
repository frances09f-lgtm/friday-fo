import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/link/pairing_code.dart';

class PairingScanScreen extends StatefulWidget {
  const PairingScanScreen({super.key});
  @override
  State<PairingScanScreen> createState() => _PairingScanScreenState();
}

class _PairingScanScreenState extends State<PairingScanScreen> {
  bool done = false;
  String? error;
  final scanner = MobileScannerController();
  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Scan other Friday')),
      body: Column(children: [
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'Scan the QR on your laptop. This fills the address/key only. Review and tap Pair.')),
        Expanded(
            child: MobileScanner(
                controller: scanner,
                onDetect: (capture) {
                  if (done) return;
                  for (final b in capture.barcodes) {
                    final raw = b.rawValue;
                    if (raw == null) continue;
                    try {
                      final code = PairingCode.decode(raw);
                      done = true;
                      Navigator.pop(context, code);
                      return;
                    } catch (_) {
                      setState(() => error =
                          'Not a valid current Friday QR. Refresh it on the other device.');
                    }
                  }
                },
                errorBuilder: (context, e) => const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Camera unavailable or permission denied. Allow camera access in Settings, or use the address/key fields.'))))),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
      ]));
}
