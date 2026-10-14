// lib/saisie/rappel_envoi.dart
// ENVOI MANUEL (mode « Collecte ») — garde-fou global de la nouvelle interface (décision du pharmacien,
// 4.13), branché sur la file des saisies (SaisieQueue) dans main.dart :
//  - délai de rappel réglé (Réglages → « Rappel d'envoi », sendReminderMinutes) > 0 : quand la PLUS
//    ANCIENNE saisie non envoyée dépasse ce délai, un message BLOQUANT « Veuillez sauvegarder vos
//    saisies » s'affiche avec « Envoyer maintenant » ; il revient tant que les saisies ne sont pas
//    envoyées (après un essai qui n'a pas tout envoyé : au bout de [relanceApresEssai]) ;
//  - délai réglé à 0 : pas de rappel, mais ENVOI AUTOMATIQUE des saisies non envoyées toutes les
//    15 minutes ([intervalleEnvoiAuto]), en arrière-plan.
// En mode Direct, rien de tout cela : la file envoie déjà chaque saisie.
// La décision est une fonction pure ([deciderRappel]) testée avec une horloge simulée.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prestinv/saisie/saisie_queue.dart';

enum DecisionRappel { rien, rappel, envoiAuto }

/// Envoi automatique quand le délai de rappel est réglé à 0.
const intervalleEnvoiAuto = Duration(minutes: 15);

/// Après un « Envoyer maintenant » qui n'a pas tout envoyé (réseau…), le message revient au bout de :
const relanceApresEssai = Duration(minutes: 2);

/// Que faire maintenant ?
/// [plusAncienne] : date de la plus ancienne saisie non envoyée (null : rien à envoyer) ;
/// [dernierEnvoiAuto] : dernier envoi automatique (délai 0) ; [reporteJusqua] : rappel suspendu
/// jusqu'à cette heure (juste après un essai d'envoi).
DecisionRappel deciderRappel({
  required bool envoiManuel,
  required int delaiMinutes,
  required DateTime? plusAncienne,
  required DateTime maintenant,
  DateTime? dernierEnvoiAuto,
  DateTime? reporteJusqua,
}) {
  if (!envoiManuel || plusAncienne == null) return DecisionRappel.rien;
  if (delaiMinutes > 0) {
    if (reporteJusqua != null && maintenant.isBefore(reporteJusqua)) return DecisionRappel.rien;
    return maintenant.difference(plusAncienne) >= Duration(minutes: delaiMinutes) ? DecisionRappel.rappel : DecisionRappel.rien;
  }
  final depuis = dernierEnvoiAuto != null && dernierEnvoiAuto.isAfter(plusAncienne) ? dernierEnvoiAuto : plusAncienne;
  return maintenant.difference(depuis) >= intervalleEnvoiAuto ? DecisionRappel.envoiAuto : DecisionRappel.rien;
}

/// Plus ancienne saisie non envoyée (date de sa dernière modification), toutes saisies confondues.
DateTime? plusAncienneEnAttente(SaisieQueue q) {
  DateTime? d;
  for (final s in q.lignes()) {
    if (!s.enAttente) continue;
    if (d == null || s.modifieLe.isBefore(d)) d = s.modifieLe;
  }
  return d;
}

/// Surveille la file des saisies et déclenche le rappel bloquant ou l'envoi automatique.
class GardienEnvoi {
  final SaisieQueue queue;

  /// Mode d'envoi manuel (Collecte) actif ?
  final bool Function() envoiManuel;

  /// Délai de rappel réglé (minutes, 0 = envoi automatique toutes les 15 min).
  final int Function() delaiMinutes;

  /// Le garde-fou s'applique-t-il maintenant (connecté, nouvelle interface) ?
  final bool Function() actif;

  /// Affiche le message bloquant ; se termine quand l'opérateur a lancé l'envoi (et que celui-ci est
  /// fini). Renvoie le bilan de l'envoi (null : rien d'envoyé).
  final Future<BilanEnvoi?> Function(int nombre, Duration depuis) afficherRappel;

  /// Horloge (tests : horloge simulée).
  static DateTime Function() horloge = DateTime.now;

  /// Vérification périodique.
  static Duration periode = const Duration(seconds: 30);

  GardienEnvoi({required this.queue, required this.envoiManuel, required this.delaiMinutes, required this.actif, required this.afficherRappel});

  Timer? _minuterie;
  bool _rappelAffiche = false;
  DateTime? _dernierEnvoiAuto;
  DateTime? _reporte;

  bool get rappelAffiche => _rappelAffiche;

  void demarrer() {
    _minuterie?.cancel();
    _minuterie = Timer.periodic(periode, (_) => verifier());
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  /// Une vérification (appelée par la minuterie ; publique pour les tests).
  Future<DecisionRappel> verifier() async {
    if (_rappelAffiche || !actif()) return DecisionRappel.rien;
    final maintenant = horloge();
    final ancienne = plusAncienneEnAttente(queue);
    final d = deciderRappel(
      envoiManuel: envoiManuel(),
      delaiMinutes: delaiMinutes(),
      plusAncienne: ancienne,
      maintenant: maintenant,
      dernierEnvoiAuto: _dernierEnvoiAuto,
      reporteJusqua: _reporte,
    );
    switch (d) {
      case DecisionRappel.rien:
        break;
      case DecisionRappel.envoiAuto:
        if (!queue.envoiEnCours) {
          _dernierEnvoiAuto = maintenant;
          unawaited(queue.envoyer());
        }
      case DecisionRappel.rappel:
        _rappelAffiche = true;
        try {
          await afficherRappel(queue.enAttente(), maintenant.difference(ancienne!));
        } finally {
          _rappelAffiche = false;
          // Tout n'est pas parti (réseau…) : le message reviendra un peu plus tard.
          _reporte = queue.enAttente() > 0 ? horloge().add(relanceApresEssai) : null;
        }
    }
    return d;
  }

  @visibleForTesting
  DateTime? get dernierEnvoiAuto => _dernierEnvoiAuto;
}
