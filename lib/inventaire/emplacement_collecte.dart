// lib/inventaire/emplacement_collecte.dart
// 4.14.1 — Création d'un inventaire DEPUIS LA COLLECTE : emplacement (rayon) des produits collectés.
//
// Retour du pharmacien : « Créer un inventaire » depuis la collecte créait un inventaire avec TOUS les
// emplacements (l'appli n'envoyait ni emplacement ni produit : le serveur prend alors tout). Désormais
// l'écran de création présélectionne l'emplacement des produits collectés (le plus fréquent), modifiable,
// et seul cet emplacement est envoyé (`valeurs` de POST /inventaire/creation).
//
// Le serveur ne sait pas créer un inventaire limité à une LISTE de produits (demande :
// docs/DEMANDE_SERVEUR_COMPTAGE.md) : l'inventaire contient les produits actifs de l'emplacement choisi.
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/rayon.dart';

/// Un emplacement trouvé parmi les produits collectés, avec le nombre de codes qui s'y rangent.
class EmplacementTrouve {
  final Rayon rayon;
  final int codes;
  const EmplacementTrouve(this.rayon, this.codes);
}

class AnalyseEmplacements {
  /// Du plus fréquent au moins fréquent (à égalité : ordre alphabétique du libellé).
  final List<EmplacementTrouve> trouves;

  /// Codes inconnus du serveur ou sans emplacement.
  final int introuvables;

  /// Codes non analysés (au-delà de [EmplacementsCollecte.maxCodes]).
  final int nonAnalyses;

  /// Échec des recherches (réseau, session…) : message, l'utilisateur choisit l'emplacement à la main.
  final ApiLoadException? erreur;

  const AnalyseEmplacements(this.trouves, {this.introuvables = 0, this.nonAnalyses = 0, this.erreur});

  Rayon? get propose => trouves.isEmpty ? null : trouves.first.rayon;
}

class EmplacementsCollecte {
  EmplacementsCollecte._();

  /// Au plus 40 codes distincts interrogés (au-delà, la présélection est déjà sûre).
  static const int maxCodes = 40;

  /// Recherches menées en parallèle (4 à la fois, pour ne pas charger le serveur).
  static const int parallele = 4;

  /// Emplacement de chaque code collecté (distincts, dans l'ordre), regroupé par emplacement.
  /// Une session expirée ou un serveur injoignable arrête l'analyse ([AnalyseEmplacements.erreur]).
  static Future<AnalyseEmplacements> analyser(ApiService api, List<String> codes) async {
    final distincts = codes.map((c) => c.trim()).where((c) => c.isNotEmpty).toSet().toList();
    final aChercher = distincts.take(maxCodes).toList();
    final parId = <String, Rayon>{};
    final compte = <String, int>{};
    var introuvables = 0;
    ApiLoadException? erreur;
    for (var i = 0; i < aChercher.length && erreur == null; i += parallele) {
      final lot = aChercher.skip(i).take(parallele);
      final resultats = await Future.wait(lot.map((c) async {
        try {
          return await api.emplacementDuProduit(c);
        } on ApiLoadException catch (e) {
          erreur ??= e;
          return null;
        }
      }));
      if (erreur != null) break;
      for (final r in resultats) {
        if (r == null) {
          introuvables++;
          continue;
        }
        parId.putIfAbsent(r.id, () => r);
        compte[r.id] = (compte[r.id] ?? 0) + 1;
      }
    }
    final trouves = [for (final e in compte.entries) EmplacementTrouve(parId[e.key]!, e.value)]
      ..sort((a, b) => b.codes != a.codes ? b.codes.compareTo(a.codes) : a.rayon.libelle.compareTo(b.rayon.libelle));
    return AnalyseEmplacements(trouves,
        introuvables: introuvables, nonAnalyses: distincts.length - aChercher.length, erreur: erreur);
  }
}
