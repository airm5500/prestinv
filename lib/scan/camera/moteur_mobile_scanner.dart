// lib/scan/camera/moteur_mobile_scanner.dart
// Moteur réel du scan par l'appareil photo : mobile_scanner 6.0.2 (CameraX 1.3 + ML Kit, version figée
// comme dans prestige_vente_app). Formats lus : EAN-13, EAN-8, UPC-A (EAN-13 commençant par 0, lu ainsi
// par ML Kit), Code 128, DataMatrix, QR. Le contenu rendu garde le séparateur GS du DataMatrix GS1.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prestinv/scan/camera/scan_camera.dart';

class MoteurMobileScanner implements MoteurCamera {
  static const List<BarcodeFormat> formats = [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.code128,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.qrCode,
  ];

  final MobileScannerController _controleur = MobileScannerController(
    formats: formats,
    // Lectures régulières (et non « sans doublon » : le même produit peut être recompté plus tard) ;
    // l'anti-doublon de la page écarte les relectures immédiates.
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
  );
  final ValueNotifier<bool?> _lampe = ValueNotifier<bool?>(null);

  MoteurMobileScanner() {
    _controleur.addListener(_majLampe);
  }

  void _majLampe() {
    final t = _controleur.value.torchState;
    _lampe.value = switch (t) {
      TorchState.on => true,
      TorchState.off || TorchState.auto => false,
      TorchState.unavailable => null,
    };
  }

  /// Contenu d'un code : UPC-A → EAN-13 ; DataMatrix dont le texte a perdu les séparateurs GS mais pas
  /// les octets bruts → octets bruts (lot et série restent séparés).
  static String? valeur(Barcode b) {
    final v = b.rawValue;
    if (b.format == BarcodeFormat.upcA && v != null && RegExp(r'^\d{12}$').hasMatch(v)) return '0$v';
    final o = b.rawBytes;
    if (o != null && o.contains(29) && (v == null || !v.contains('\u001d')) && o.every((x) => x == 29 || (x >= 32 && x <= 126))) {
      return String.fromCharCodes(o);
    }
    return v;
  }

  @override
  Widget apercu(BuildContext context, {required ValueChanged<String> surCode, required ValueChanged<String> surErreur}) {
    return MobileScanner(
      controller: _controleur,
      onDetect: (capture) {
        for (final b in capture.barcodes) {
          final v = valeur(b);
          if (v != null && v.isNotEmpty) {
            surCode(v);
            return;
          }
        }
      },
      errorBuilder: (context, erreur, child) => _Erreur(
        erreur.errorCode == MobileScannerErrorCode.permissionDenied
            ? ScanCamera.messageRefus
            : 'L\'appareil photo ne démarre pas sur cet appareil (${erreur.errorCode.name}). '
                'Fermez cet aperçu et utilisez la douchette ou la recherche au clavier.',
      ),
    );
  }

  @override
  ValueListenable<bool?> get lampe => _lampe;

  @override
  Future<void> basculerLampe() async {
    try {
      await _controleur.toggleTorch();
    } catch (_) {}
  }

  @override
  void liberer() {
    _controleur.removeListener(_majLampe);
    unawaited(_controleur.dispose());
    _lampe.dispose();
  }
}

class _Erreur extends StatelessWidget {
  final String message;
  const _Erreur(this.message);

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, key: const ValueKey('camera-erreur'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ),
      );
}
