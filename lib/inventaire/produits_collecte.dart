// lib/inventaire/produits_collecte.dart
// 4.15 — Création d'un inventaire DEPUIS LA COLLECTE : les PRODUITS collectés et leurs emplacements.
//
// Décision du pharmacien (retour sur la 4.14.1, qui limitait la création à UN emplacement) : « si j'ai 4
// produits de 4 emplacements différents ? On doit faire comme sur Prestige : emplacement = tous, et il crée
// l'inventaire des 4 produits ; à l'ouverture de l'inventaire on a juste 4 emplacements, ceux des 4
// produits ». Chaque code collecté est donc retrouvé sur le serveur (fiche article : identifiant du
// produit et son emplacement) ; l'inventaire est ensuite créé sur les emplacements de CES produits, ses
// lignes non retenues, puis seules les lignes de ces produits sont retenues (voir CreationInventaire.
// creerDepuisCollecte). Aucun code n'est deviné : une correspondance partielle ou ambiguë est signalée.
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/scan/code_scan.dart';

/// Un emplacement des produits collectés, avec le nombre de produits qui s'y rangent.
class EmplacementCollecte {
  final Rayon rayon;
  final int produits;
  const EmplacementCollecte(this.rayon, this.produits);
}

class AnalyseCollecte {
  /// Produits retrouvés (distincts), dans l'ordre de la collecte.
  final List<ProduitServeur> produits;

  /// Codes collectés introuvables sur le serveur (inconnus, ambigus ou correspondance partielle).
  final List<String> introuvables;

  /// Codes non analysés (au-delà de [ProduitsCollecte.maxCodes]).
  final int nonAnalyses;

  /// Échec des recherches (réseau, session…) : rien n'est proposé, l'utilisateur réessaie.
  final ApiLoadException? erreur;

  const AnalyseCollecte({this.produits = const [], this.introuvables = const [], this.nonAnalyses = 0, this.erreur});

  /// Emplacements des produits retrouvés, du plus fourni au moins fourni (à égalité : par libellé).
  List<EmplacementCollecte> get emplacements {
    final parId = <String, Rayon>{};
    final compte = <String, int>{};
    for (final p in produits) {
      final e = p.emplacement;
      if (e == null) continue;
      parId.putIfAbsent(e.id, () => e);
      compte[e.id] = (compte[e.id] ?? 0) + 1;
    }
    return [for (final e in compte.entries) EmplacementCollecte(parId[e.key]!, e.value)]
      ..sort((a, b) => b.produits != a.produits ? b.produits.compareTo(a.produits) : a.rayon.libelle.compareTo(b.rayon.libelle));
  }

  /// Produits retrouvés mais sans emplacement (ils ne peuvent pas entrer dans l'inventaire).
  List<ProduitServeur> get sansEmplacement => produits.where((p) => p.emplacement == null).toList();

  /// Produits qui entreront dans l'inventaire.
  List<ProduitServeur> get inclus => produits.where((p) => p.emplacement != null).toList();

  bool get creationPossible => erreur == null && inclus.isNotEmpty;
}

class ProduitsCollecte {
  ProduitsCollecte._();

  /// Au plus 500 codes distincts (le serveur retient 200 produits par requête ; au-delà, verser la
  /// collecte dans un inventaire existant).
  static const int maxCodes = 500;

  /// Recherches menées en parallèle (4 à la fois, pour ne pas charger le serveur).
  static const int parallele = 4;

  /// Retrouve le produit de chaque code collecté (distincts, dans l'ordre). Le code tel que scanné est
  /// cherché d'abord, puis ses autres formes (EAN-13 34009 → CIP7, GTIN, DataMatrix) seulement s'il n'est
  /// pas trouvé. Une session expirée ou un serveur injoignable arrête l'analyse ([AnalyseCollecte.erreur]).
  static Future<AnalyseCollecte> analyser(ApiService api, List<String> codes) async {
    final distincts = <String>[];
    for (final c in codes) {
      final n = CodeScan.nettoyer(c);
      if (n.isNotEmpty && !distincts.contains(n)) distincts.add(n);
    }
    final aChercher = distincts.take(maxCodes).toList();
    final trouves = <String, ProduitServeur?>{};
    ApiLoadException? erreur;

    Future<ProduitServeur?> chercher(String code) async {
      final formes = <String>[code, ...CodeScan.candidats(code).where((c) => c != code)];
      for (final f in formes) {
        final p = await api.produitParCode(f);
        if (p != null) return p;
      }
      return null;
    }

    for (var i = 0; i < aChercher.length && erreur == null; i += parallele) {
      final lot = aChercher.skip(i).take(parallele).toList();
      final resultats = await Future.wait(lot.map((c) async {
        try {
          return (c, await chercher(c));
        } on ApiLoadException catch (e) {
          erreur ??= e;
          return (c, null);
        }
      }));
      if (erreur != null) break;
      for (final (c, p) in resultats) {
        trouves[c] = p;
      }
    }
    if (erreur != null) return AnalyseCollecte(erreur: erreur, nonAnalyses: distincts.length);
    final produits = <String, ProduitServeur>{};
    final introuvables = <String>[];
    for (final c in aChercher) {
      final p = trouves[c];
      if (p == null) {
        introuvables.add(c);
      } else {
        produits.putIfAbsent(p.id, () => p); // deux codes du même produit (CIP et EAN) : un seul produit
      }
    }
    return AnalyseCollecte(produits: produits.values.toList(), introuvables: introuvables, nonAnalyses: distincts.length - aChercher.length);
  }
}
