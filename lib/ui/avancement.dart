// lib/ui/avancement.dart
// Nouvelle interface — avancement d'un inventaire calculé À LA DEMANDE : « Actualiser » de la carte
// « Inventaire en cours » (écran de l'inventaire choisi) et déroulé de la liste « Voir les inventaires »
// de l'accueil (une ligne après l'autre, résultat gardé). Jamais au lancement : le serveur n'expose pas
// (encore) l'état des rayons en une requête (voir docs/DEMANDE_SERVEUR_COMPTAGE.md).
//
// Mêmes appels que l'écran « Choisir un rayon » : GET …/rayons, puis pour chaque rayon
// GET …/detailsTouchedRayon et GET …/detailsUntouchedRayon. Même règle d'état des rayons : 0 pas
// commencé, 1 commencé, 2 terminé. Depuis la 4.13, les listes reçues servent aussi à compter les
// PRODUITS (« 110 / 130 », pourcentage) et les écarts : la seconde requête est donc faite pour chaque
// rayon (avant : seulement pour les rayons entamés).
// En plus : progression « Rayon 3/12 », annulation, un seul calcul à la fois (anti double appui),
// motif d'échec affiché (réseau, session expirée…), résultat gardé en mémoire et sur l'appareil avec
// son heure (« Avancement à 10:42 »). Les saisies faites ensuite sur l'appareil sont ajoutées à
// l'affichage sans nouvelle requête ([etatAvancement]).
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Résultat d'un calcul d'avancement (par inventaire).
class AvancementRayons {
  final String inventaireId;
  final DateTime calculeA;

  /// État par rayon : 0 pas commencé, 1 commencé, 2 terminé (absent : non lu).
  final Map<String, int> statuts;
  final int total;

  /// Produits de l'inventaire (lignes) ; null : calcul d'une version précédente (rayons seulement).
  final int? totalProduits;

  /// Lignes comptées sur le serveur au moment du calcul.
  final Set<int>? comptes;

  /// Lignes comptées dont la quantité diffère du stock théorique (écarts) au moment du calcul.
  final int? ecarts;

  const AvancementRayons({
    required this.inventaireId,
    required this.calculeA,
    required this.statuts,
    required this.total,
    this.totalProduits,
    this.comptes,
    this.ecarts,
  });

  /// Comptes en produits disponibles (calcul 4.13).
  bool get produitsConnus => totalProduits != null && comptes != null;

  int get termines => statuts.values.where((s) => s == 2).length;
  int get commences => statuts.values.where((s) => s == 1).length;
  int get pasCommences => statuts.values.where((s) => s == 0).length;

  /// Rayons dont l'état n'a pas pu être lu (erreur isolée).
  int get inconnus => total - statuts.length;

  /// Avancement arrondi : en produits comptés si connus, sinon par rayons (terminé = 1, commencé = ½).
  int get pourcentage {
    if (produitsConnus) return totalProduits == 0 ? 0 : (comptes!.length / totalProduits! * 100).round();
    return total == 0 ? 0 : ((termines + commences * 0.5) / total * 100).round();
  }

  /// « 10:42 », ou « 12/10 à 10:42 » si le calcul ne date pas d'aujourd'hui.
  String heure({DateTime? maintenant}) {
    final n = maintenant ?? DateTime.now();
    String d2(int v) => v.toString().padLeft(2, '0');
    final h = '${d2(calculeA.hour)}:${d2(calculeA.minute)}';
    final memeJour = n.year == calculeA.year && n.month == calculeA.month && n.day == calculeA.day;
    return memeJour ? h : '${d2(calculeA.day)}/${d2(calculeA.month)} à $h';
  }

  Map<String, dynamic> toJson() => {
        'inv': inventaireId,
        'a': calculeA.toIso8601String(),
        'total': total,
        'statuts': statuts,
        if (totalProduits != null) 'produits': totalProduits,
        if (comptes != null) 'comptes': comptes!.toList(),
        if (ecarts != null) 'ecarts': ecarts,
      };

  static AvancementRayons? fromJson(Map<String, dynamic> j) {
    try {
      return AvancementRayons(
        inventaireId: j['inv'] as String,
        calculeA: DateTime.parse(j['a'] as String),
        total: (j['total'] as num).toInt(),
        statuts: {for (final e in (j['statuts'] as Map).entries) e.key as String: (e.value as num).toInt()},
        totalProduits: (j['produits'] as num?)?.toInt(),
        comptes: j['comptes'] is List ? {for (final c in j['comptes'] as List) (c as num).toInt()} : null,
        ecarts: (j['ecarts'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Fin d'un calcul.
enum FinAvancement { termine, annule, erreur, dejaEnCours }

/// Calcul de l'avancement à la demande (un seul à la fois).
class AvancementCalcul extends ChangeNotifier {
  /// Résultats gardés pour la session (en plus de l'appareil) : l'accueil reconstruit ne recalcule rien.
  static final Map<String, AvancementRayons> _cache = {};

  static String cle(String inventaireId) => 'nv_avancement_v1_$inventaireId';

  /// Vide le cache mémoire (tests).
  @visibleForTesting
  static void viderCache() => _cache.clear();

  /// Deux rayons de suite illisibles pour cause de réseau : on arrête (inutile d'attendre tous les
  /// délais d'un serveur injoignable).
  static const echecsReseauMax = 2;

  String? _inventaireId;
  int _rayon = 0;
  int _rayons = 0;
  int _generation = 0;
  bool _enCours = false;
  Object? _erreur;
  String? _erreurInventaireId;

  bool get enCours => _enCours;

  /// Inventaire en cours de calcul.
  String? get inventaireId => _inventaireId;

  /// Rayon en cours de lecture (1…[rayons]) ; 0 tant que la liste des rayons n'est pas lue.
  int get rayon => _rayon;
  int get rayons => _rayons;

  /// Dernier échec (pour [inventaireId]) ; effacé au calcul suivant.
  Object? erreurPour(String inventaireId) => _erreurInventaireId == inventaireId ? _erreur : null;

  AvancementRayons? resultat(String inventaireId) => _cache[inventaireId];

  /// Résultat gardé pour [inventaireId] (mémoire de la session), sans instance.
  static AvancementRayons? enCache(String inventaireId) => _cache[inventaireId];

  /// Relit le résultat gardé sur l'appareil (sans requête).
  Future<AvancementRayons?> charger(String inventaireId) async {
    final deja = _cache[inventaireId];
    if (deja != null) return deja;
    try {
      final brut = (await SharedPreferences.getInstance()).getString(cle(inventaireId));
      if (brut == null) return null;
      final r = AvancementRayons.fromJson(Map<String, dynamic>.from(json.decode(brut) as Map));
      if (r == null || r.inventaireId != inventaireId) return null;
      _cache[inventaireId] = r;
      notifyListeners();
      return r;
    } catch (_) {
      return null;
    }
  }

  Future<void> _garder(AvancementRayons r) async {
    _cache[r.inventaireId] = r;
    try {
      await (await SharedPreferences.getInstance()).setString(cle(r.inventaireId), json.encode(r.toJson()));
    } catch (_) {}
  }

  /// Arrête le calcul en cours : la réponse attendue est ignorée, le résultat précédent est gardé.
  void annuler() {
    if (!_enCours) return;
    _generation++;
    _enCours = false;
    _inventaireId = null;
    notifyListeners();
  }

  /// Calcule l'avancement de [inventaireId]. Un second appel pendant un calcul ne relance rien.
  Future<FinAvancement> actualiser(ApiService api, String inventaireId, {DateTime Function()? horloge}) async {
    if (_enCours) return FinAvancement.dejaEnCours;
    final gen = ++_generation;
    _enCours = true;
    _inventaireId = inventaireId;
    _rayon = 0;
    _rayons = 0;
    _erreur = null;
    _erreurInventaireId = null;
    notifyListeners();
    bool annule() => gen != _generation;

    FinAvancement echec(Object e) {
      _erreur = e;
      _erreurInventaireId = inventaireId;
      _enCours = false;
      _inventaireId = null;
      notifyListeners();
      return FinAvancement.erreur;
    }

    try {
      final rayons = await api.fetchRayons(inventaireId);
      if (annule()) return FinAvancement.annule;
      _rayons = rayons.length;
      final statuts = <String, int>{};
      final comptes = <int>{};
      var produits = 0;
      var ecarts = 0;
      var tousLus = true;
      var echecsReseau = 0;
      ApiLoadException? dernierEchec;
      for (var i = 0; i < rayons.length; i++) {
        _rayon = i + 1;
        notifyListeners();
        final r = rayons[i];
        try {
          final touches = await api.lignesCompteesRayon(inventaireId, r.id);
          if (annule()) return FinAvancement.annule;
          final restants = await api.lignesRestantesRayon(inventaireId, r.id);
          if (annule()) return FinAvancement.annule;
          statuts[r.id] = touches.isEmpty ? 0 : (restants.isEmpty ? 2 : 1);
          for (final l in touches) {
            final id = l['id'];
            if (id is num) comptes.add(id.toInt());
            final q = l['quantiteSaisie'], t = l['quantiteInitiale'];
            if (q is num && t is num && q != t) ecarts++;
          }
          produits += touches.length + restants.length;
          echecsReseau = 0;
        } on ApiLoadException catch (e) {
          if (annule()) return FinAvancement.annule;
          tousLus = false;
          dernierEchec = e;
          if (e.sessionExpiree) return echec(e);
          if (e.reseau && ++echecsReseau >= echecsReseauMax) return echec(e);
          // Autre refus isolé : rayon « non lu », on continue.
        }
      }
      if (rayons.isNotEmpty && statuts.isEmpty && dernierEchec != null) return echec(dernierEchec);
      await _garder(AvancementRayons(
        inventaireId: inventaireId,
        calculeA: (horloge ?? DateTime.now)(),
        statuts: statuts,
        total: rayons.length,
        // Comptes en produits seulement si tous les rayons ont été lus (sinon : par rayons).
        totalProduits: tousLus ? produits : null,
        comptes: tousLus ? comptes : null,
        ecarts: tousLus ? ecarts : null,
      ));
      if (annule()) return FinAvancement.annule;
      _enCours = false;
      _inventaireId = null;
      notifyListeners();
      return FinAvancement.termine;
    } catch (e) {
      if (annule()) return FinAvancement.annule;
      return echec(e);
    }
  }

  /// Motif lisible d'un échec (même texte que les écrans de chargement).
  static String motif(Object e) => messageErreur(e);
}


/// Que proposer pour un inventaire (bouton de la liste de l'accueil) ?
enum ActionInventaire {
  /// Rien de compté : « Commencer » (bleu clair).
  commencer,

  /// Commencé (0,1 à 99,9 %) : « Poursuivre » (orange).
  poursuivre,

  /// Tout est compté (100 %) : « Revérifier » (vert).
  reverifier,

  /// Avancement pas encore connu (calcul en attente ou en échec) : « Ouvrir ».
  inconnu,
}

extension ActionInventaireLibelle on ActionInventaire {
  String get libelle => switch (this) {
        ActionInventaire.commencer => 'Commencer',
        ActionInventaire.poursuivre => 'Poursuivre',
        ActionInventaire.reverifier => 'Revérifier',
        ActionInventaire.inconnu => 'Ouvrir',
      };
}

/// Avancement affiché d'un inventaire : résultat du dernier calcul ([r]) + saisies faites depuis sur
/// l'appareil ([lignesLocales] : lignes d'inventaire saisies, envoyées ou non), sans requête.
class EtatAvancement {
  /// Produits comptés (serveur ∪ appareil) ; null si inconnu.
  final int? comptes;

  /// Produits de l'inventaire ; null si inconnu.
  final int? total;

  /// Pourcentage (0 à 100) ; null si inconnu.
  final double? pourcentage;

  /// Produits en écart au dernier calcul ; null si inconnu.
  final int? ecarts;

  final ActionInventaire action;
  const EtatAvancement({this.comptes, this.total, this.pourcentage, this.ecarts, required this.action});

  /// Produits restant à compter ; null si inconnu.
  int? get restants => comptes == null || total == null ? null : (total! - comptes!).clamp(0, total!);
}

EtatAvancement etatAvancement(AvancementRayons? r, {Iterable<int> lignesLocales = const []}) {
  final locales = lignesLocales.toSet();
  if (r == null) {
    return EtatAvancement(action: locales.isEmpty ? ActionInventaire.inconnu : ActionInventaire.poursuivre);
  }
  if (r.produitsConnus) {
    final total = r.totalProduits!;
    final comptes = math.min(total, r.comptes!.union(locales).length);
    final pct = total == 0 ? 0.0 : comptes / total * 100;
    final ActionInventaire action;
    if (comptes == 0) {
      action = ActionInventaire.commencer;
    } else if (total > 0 && comptes >= total) {
      action = ActionInventaire.reverifier;
    } else {
      action = ActionInventaire.poursuivre;
    }
    return EtatAvancement(comptes: comptes, total: total, pourcentage: pct, ecarts: r.ecarts, action: action);
  }
  // Ancien calcul (rayons seulement).
  final pct = r.pourcentage.toDouble();
  final ActionInventaire action;
  if (r.termines + r.commences == 0 && locales.isEmpty) {
    action = ActionInventaire.commencer;
  } else if (r.total > 0 && r.termines == r.total) {
    action = ActionInventaire.reverifier;
  } else {
    action = ActionInventaire.poursuivre;
  }
  return EtatAvancement(pourcentage: pct, action: action);
}

/// « 0 % », « 0,4 % », « 85 % », « 99,6 % », « 100 % » : une décimale près de 0 et de 100 pour ne
/// jamais afficher 0 % (ou 100 %) quand l'inventaire est commencé (ou pas terminé).
String formatPourcentage(double p, {bool commence = false, bool termine = false}) {
  if (termine) return '100 %';
  if (p <= 0 && !commence) return '0 %';
  if (p < 1) return '${math.max(0.1, (p * 10).floor() / 10).toStringAsFixed(1).replaceAll('.', ',')} %';
  if (p > 99) return '${math.min(99.9, (p * 10).floor() / 10).toStringAsFixed(1).replaceAll('.', ',')} %';
  return '${p.round()} %';
}

/// Pourcentage de [e] mis en forme (« … » si inconnu).
String pourcentageAffiche(EtatAvancement e) => e.pourcentage == null
    ? '— %'
    : formatPourcentage(e.pourcentage!, commence: e.action == ActionInventaire.poursuivre, termine: e.action == ActionInventaire.reverifier);
