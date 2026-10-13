// lib/scan/retour_scan.dart
// Retour sonore et vibration distincts après un scan (audibles en rayon, sans regarder l'écran) :
// - succès (produit trouvé) : bip court, vibration brève ;
// - déjà compté : double bip, deux vibrations (la question Remplacer / Ajouter suit selon le réglage
//   « Cumul » existant) ;
// - erreur (code introuvable, réseau, refus) : bip long, vibration longue.
// Son et vibration se coupent séparément dans la Configuration.
//
// Sur Android, le son vient du générateur de tonalités du système (canal « prestinv/retour », voir
// MainActivity.kt) : SystemSound de Flutter ne sait jouer qu'un « clic » sur Android.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum TypeRetour { succes, dejaCompte, erreur }

abstract class LecteurRetour {
  Future<void> bip(TypeRetour type);
  Future<void> vibrer(TypeRetour type);
}

/// Lecteur Android (canal natif) ; à défaut (autre plateforme, canal absent) : clic système / haptique.
class LecteurRetourSysteme implements LecteurRetour {
  static const MethodChannel _canal = MethodChannel('prestinv/retour');

  @override
  Future<void> bip(TypeRetour type) async {
    try {
      await _canal.invokeMethod<void>('bip', {'type': type.name});
    } catch (_) {
      try {
        await SystemSound.play(type == TypeRetour.erreur ? SystemSoundType.alert : SystemSoundType.click);
      } catch (_) {}
    }
  }

  @override
  Future<void> vibrer(TypeRetour type) async {
    try {
      await _canal.invokeMethod<void>('vibrer', {'type': type.name});
    } catch (_) {
      try {
        switch (type) {
          case TypeRetour.succes:
            await HapticFeedback.lightImpact();
          case TypeRetour.dejaCompte:
            await HapticFeedback.mediumImpact();
          case TypeRetour.erreur:
            await HapticFeedback.vibrate();
        }
      } catch (_) {}
    }
  }
}

class RetourScan {
  RetourScan._();

  /// Lecteur utilisé (remplaçable dans les tests).
  static LecteurRetour lecteur = LecteurRetourSysteme();

  /// Joue le retour [type] selon les réglages [son] et [vibration]. Ne lève jamais.
  static Future<void> jouer(TypeRetour type, {required bool son, required bool vibration}) async {
    try {
      if (son) await lecteur.bip(type);
      if (vibration) await lecteur.vibrer(type);
    } catch (e) {
      if (kDebugMode) debugPrint('Retour scan impossible : $e');
    }
  }
}
