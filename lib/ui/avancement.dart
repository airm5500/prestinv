// lib/ui/avancement.dart
// Nouvelle interface — avancement de l'inventaire calculé À LA DEMANDE (bouton « Actualiser
// l'avancement » de la carte « EN COURS » de l'accueil). Jamais de calcul automatique : le serveur
// n'expose pas (encore) l'état des rayons en une requête, il faut aujourd'hui deux requêtes par rayon
// (voir docs/DEMANDE_SERVEUR_COMPTAGE.md).
//
// Mêmes appels que l'écran « Choisir un rayon » (EntryProvider.fetchRayons + loadRayonStatuses) :
//   GET …/rayons, puis pour chaque rayon GET …/detailsTouchedRayon et, s'il a été entamé,
//   GET …/detailsUntouchedRayon. Même règle d'état : 0 pas commencé, 1 commencé, 2 terminé.
// En plus : progression « Rayon 3/12 », annulation, un seul calcul à la fois (anti double appui),
// motif d'échec affiché (réseau, session expirée…), résultat gardé en mémoire et sur l'appareil avec
// son heure (« Avancement à 10:42 »).
import 'dart:convert';

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

  const AvancementRayons({required this.inventaireId, required this.calculeA, required this.statuts, required this.total});

  int get termines => statuts.values.where((s) => s == 2).length;
  int get commences => statuts.values.where((s) => s == 1).length;
  int get pasCommences => statuts.values.where((s) => s == 0).length;

  /// Rayons dont l'état n'a pas pu être lu (erreur isolée).
  int get inconnus => total - statuts.length;

  /// Même calcul que la carte de l'accueil : terminé = 1, commencé = ½.
  int get pourcentage => total == 0 ? 0 : ((termines + commences * 0.5) / total * 100).round();

  /// « 10:42 », ou « 12/10 à 10:42 » si le calcul ne date pas d'aujourd'hui.
  String heure({DateTime? maintenant}) {
    final n = maintenant ?? DateTime.now();
    String d2(int v) => v.toString().padLeft(2, '0');
    final h = '${d2(calculeA.hour)}:${d2(calculeA.minute)}';
    final memeJour = n.year == calculeA.year && n.month == calculeA.month && n.day == calculeA.day;
    return memeJour ? h : '${d2(calculeA.day)}/${d2(calculeA.month)} à $h';
  }

  Map<String, dynamic> toJson() => {'inv': inventaireId, 'a': calculeA.toIso8601String(), 'total': total, 'statuts': statuts};

  static AvancementRayons? fromJson(Map<String, dynamic> j) {
    try {
      return AvancementRayons(
        inventaireId: j['inv'] as String,
        calculeA: DateTime.parse(j['a'] as String),
        total: (j['total'] as num).toInt(),
        statuts: {for (final e in (j['statuts'] as Map).entries) e.key as String: (e.value as num).toInt()},
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
      var echecsReseau = 0;
      ApiLoadException? dernierEchec;
      for (var i = 0; i < rayons.length; i++) {
        _rayon = i + 1;
        notifyListeners();
        final r = rayons[i];
        try {
          final touche = await api.rayonAProduitsComptes(inventaireId, r.id);
          if (annule()) return FinAvancement.annule;
          var statut = 0;
          if (touche) {
            final restants = await api.rayonAProduitsRestants(inventaireId, r.id);
            if (annule()) return FinAvancement.annule;
            statut = restants ? 1 : 2;
          }
          statuts[r.id] = statut;
          echecsReseau = 0;
        } on ApiLoadException catch (e) {
          if (annule()) return FinAvancement.annule;
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
