// lib/screens/barcode_scanner_screen.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatelessWidget {
  const BarcodeScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner le Code-barres')),
      body: MobileScanner(
        // La détection d'un code-barres se produit ici
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final String? scannedCode = barcodes.first.rawValue;
            // On ferme l'écran du scanner et on renvoie le code scanné
            // à l'écran précédent.
            if (scannedCode != null) {
              Navigator.of(context).pop(scannedCode);
            }
          }
        },
      ),
    );
  }
}