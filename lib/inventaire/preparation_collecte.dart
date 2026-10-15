// lib/inventaire/preparation_collecte.dart
// 4.15 — État de l'écran « Créer un inventaire avec ces produits » (nouvelle ET ancienne interface) :
// analyse des codes collectés (produits, emplacements, codes non retrouvés), capacité du serveur à
// limiter l'inventaire aux produits, inventaire créé dont les produits restent à ajouter (Réessayer).
import 'package:flutter/foundation.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/produits_collecte.dart';
import 'package:prestinv/models/inventory.dart';

class PreparationCollecte extends ChangeNotifier {
  final CreationInventaire service;
  final List<String> codes;
  PreparationCollecte(this.service, this.codes);

  bool _analyseEnCours = false;
  AnalyseCollecte? _analyse;
  bool? _limiteAuxProduits;
  Inventory? _sansProduits;
  bool _ferme = false;

  bool get analyseEnCours => _analyseEnCours;
  AnalyseCollecte? get analyse => _analyse;

  /// Le serveur sait-il limiter l'inventaire aux produits ? null : pas encore su (vérifié à la création).
  bool? get limiteAuxProduits => _limiteAuxProduits;

  /// Inventaire créé dont les produits collectés ne sont pas encore retenus (« Réessayer »).
  Inventory? get sansProduits => _sansProduits;

  bool get creationPossible => !_analyseEnCours && (_analyse?.creationPossible ?? false);

  Future<void> analyser() async {
    if (_analyseEnCours) return;
    _analyseEnCours = true;
    _notifier();
    final a = await ProduitsCollecte.analyser(service.api, codes);
    if (a.creationPossible && _limiteAuxProduits == null) {
      try {
        _limiteAuxProduits = await service.api.routeRetenueDisponible();
      } on ApiLoadException {
        _limiteAuxProduits = null; // vérifié à nouveau au moment de créer
      }
    }
    _analyse = a;
    _analyseEnCours = false;
    _notifier();
  }

  /// Crée l'inventaire (ou, après un échec, retient seulement les produits de l'inventaire déjà créé).
  Future<ResultatCreation> creer(String libelle) async {
    final a = _analyse;
    if (a == null) return const ResultatCreation(IssueCreation.refus, message: 'Analyse de la collecte non terminée.');
    final deja = _sansProduits;
    final r = deja != null ? await service.retenir(deja, a) : await service.creerDepuisCollecte(libelle, a);
    _apres(r);
    return r;
  }

  /// Un inventaire ouvert du même libellé est choisi : les produits collectés y sont retenus.
  Future<ResultatCreation> utiliser(Inventory existant) async {
    final a = _analyse;
    if (a == null) return ResultatCreation(IssueCreation.creee, inventaire: existant);
    final r = await service.retenir(existant, a);
    _apres(r);
    return r;
  }

  void _apres(ResultatCreation r) {
    if (r.retenus != null) _limiteAuxProduits = true;
    _sansProduits = r.issue == IssueCreation.produitsNonAjoutes ? r.inventaire : null;
    _notifier();
  }

  void _notifier() {
    if (!_ferme) notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    super.dispose();
  }
}
