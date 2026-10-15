// lib/scan/camera/moteur_mobile_scanner.dart
// Moteur réel du scan par l'appareil photo : mobile_scanner 6.0.2 (CameraX 1.3 + ML Kit, version figée
// comme dans prestige_vente_app). Formats lus : EAN-13, EAN-8, UPC-A (EAN-13 commençant par 0, lu ainsi
// par ML Kit), UPC-E, Code 128, Code 39, Code 93, ITF (2 parmi 5 entrelacé), Codabar, DataMatrix, QR
// (4.14.1 : les « simples » codes-barres linéaires des étiquettes internes et de certains fournisseurs
// n'étaient pas lus). Contenu normalisé ([valeur]) : UPC-A et UPC-E → EAN-13, délimiteurs de début / fin
// du Code 39 (*) et du Codabar (A-D) retirés, caractères de contrôle retirés (sauf le séparateur GS du
// DataMatrix GS1, conservé).
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
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.itf,
    BarcodeFormat.codabar,
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

  static final RegExp _controle = RegExp(r'[\x00-\x1C\x1E\x1F\x7F]');

  /// Contenu d'un code, normalisé pour la recherche du produit :
  /// - UPC-A (12 chiffres) → EAN-13 (0 devant) ; UPC-E (6, 7 ou 8 chiffres) → UPC-A → EAN-13 ;
  /// - Code 39 : astérisques de début / fin retirés ; Codabar : lettres de début / fin (A-D) retirées ;
  /// - caractères de contrôle et espaces de début / fin retirés, séparateur GS (FNC1) conservé ;
  /// - DataMatrix dont le texte a perdu les séparateurs GS mais pas les octets bruts → octets bruts (lot
  ///   et série restent séparés).
  static String? valeur(Barcode b) {
    final o = b.rawBytes;
    final v0 = b.rawValue;
    if (o != null &&
        o.contains(29) &&
        (v0 == null || !v0.contains('\u001d')) &&
        o.every((x) => x == 29 || (x >= 32 && x <= 126))) {
      return String.fromCharCodes(o);
    }
    if (v0 == null) return null;
    var v = v0.replaceAll(_controle, '').trim();
    switch (b.format) {
      case BarcodeFormat.upcA:
        if (RegExp(r'^\d{12}$').hasMatch(v)) return '0$v';
      case BarcodeFormat.upcE:
        final upcA = upcEVersUpcA(v);
        if (upcA != null) return '0$upcA';
      case BarcodeFormat.code39:
        if (v.length > 2 && v.startsWith('*') && v.endsWith('*')) v = v.substring(1, v.length - 1).trim();
      case BarcodeFormat.codabar:
        final m = RegExp(r'^[A-Da-d](.+)[A-Da-d]$').firstMatch(v);
        if (m != null) v = m.group(1)!.trim();
      default:
        break;
    }
    return v;
  }

  /// UPC-E (6 chiffres, 7 avec le système de numérotation, 8 avec la clé) → UPC-A (12 chiffres, clé
  /// recalculée). null si ce n'est pas un UPC-E valide (système de numérotation 0 ou 1 seulement).
  static String? upcEVersUpcA(String code) {
    if (!RegExp(r'^\d{6,8}$').hasMatch(code)) return null;
    final ns = code.length == 6 ? '0' : code[0];
    if (ns != '0' && ns != '1') return null;
    final d = code.length == 6 ? code : code.substring(1, 7);
    final String corps;
    switch (d[5]) {
      case '0' || '1' || '2':
        corps = '${d.substring(0, 2)}${d[5]}0000${d.substring(2, 5)}';
      case '3':
        corps = '${d.substring(0, 3)}00000${d.substring(3, 5)}';
      case '4':
        corps = '${d.substring(0, 4)}00000${d[4]}';
      default:
        corps = '${d.substring(0, 5)}0000${d[5]}';
    }
    final onze = '$ns$corps';
    var somme = 0;
    for (var i = 0; i < 11; i++) {
      somme += int.parse(onze[i]) * (i.isEven ? 3 : 1);
    }
    return '$onze${(10 - somme % 10) % 10}';
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
