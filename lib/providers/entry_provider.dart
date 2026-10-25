// lib/providers/entry_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/models/product_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/utils/saisie_input.dart';

class EntryProvider with ChangeNotifier {
  /// [queue] : file persistante des saisies (par défaut celle de l'application, [SaisieQueue.instance]).
  /// Toute quantité saisie y est écrite AVANT d'être envoyée ; c'est elle qui sait ce qui reste à envoyer.
  EntryProvider({SaisieQueue? queue}) : _queueOverride = queue {
    _queueEcoutee = _queue;
    _queueEcoutee?.addListener(_surChangementFile);
  }

  final SaisieQueue? _queueOverride;
  SaisieQueue? _queueEcoutee;
  SaisieQueue? get _queue => _queueOverride ?? SaisieQueue.instance;
  SaisieQueue? get queue => _queue;

  String? _inventoryId;
  String _inventoryLibelle = '';

  /// Identifiant de connexion de l'opérateur (noté sur chaque saisie locale).
  String auteur = '';

  List<Rayon> _rayons = [];
  Rayon? _selectedRayon;
  bool _isLoading = false;
  String? _error;
  Object? _errorObj;

  /// Erreur levée au dernier chargement (pour « Se reconnecter » si la session a expiré).
  Object? get errorObject => _errorObj;

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];

  ProductFilter _activeFilter = ProductFilter();

  int _currentProductIndex = 0;
  final Map<String, int> _lastIndexByRayon = {};

  bool _hasPendingSession = false;
  List<Map<String, dynamic>> _cumulLogs = [];
  final Map<String, int> _rayonStatuses = {};
  bool _isLoadingStatuses = false;

  // LA MÉMOIRE LOCALE INFAILLIBLE : Stocke les IDs des produits touchés pendant cette session
  final Set<int> _locallyTouchedProductIds = {};

  List<Rayon> get rayons => _rayons;
  Rayon? get selectedRayon => _selectedRayon;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasPendingSession => _hasPendingSession;
  bool get isGlobalMode => _isGlobalMode;
  bool _isGlobalMode = false;

  ProductFilter get activeFilter => _activeFilter;
  List<Product> get products => _filteredProducts;
  List<Product> get allProducts => _allProducts;
  int get totalProducts => _filteredProducts.length;
  int get totalProductsInRayon => _allProducts.length;
  int get currentProductIndex => _currentProductIndex;

  List<Map<String, dynamic>> get cumulLogs => _cumulLogs;
  Map<String, int> get rayonStatuses => _rayonStatuses;

  Product? get currentProduct => _filteredProducts.isNotEmpty && _currentProductIndex < _filteredProducts.length
      ? _filteredProducts[_currentProductIndex]
      : null;

  String? get inventoryId => _inventoryId;

  /// Saisies non confirmées par le serveur dans le périmètre affiché : le rayon ouvert (saisie guidée),
  /// tout l'inventaire en saisie rapide (aucun rayon choisi).
  bool get hasUnsyncedData {
    final q = _queue;
    final inv = _inventoryId;
    if (q == null || inv == null) return _allProducts.any((p) => !p.isSynced);
    if (_selectedRayon == null) return q.enAttente(inventaireId: inv) > 0;
    return _allProducts.any((p) => q.estEnAttente(inv, p.id));
  }

  /// Saisies de l'inventaire (tous rayons) non confirmées par le serveur.
  int get pendingCountInventory {
    final q = _queue;
    final inv = _inventoryId;
    if (q == null || inv == null) return _allProducts.where((p) => !p.isSynced).length;
    return q.enAttente(inventaireId: inv);
  }

  /// « Serveur à jour » : tout est réellement confirmé par le serveur (rien en attente, rien en cours).
  bool get inventaireAJour {
    final q = _queue;
    final inv = _inventoryId;
    if (q == null || inv == null) return !_allProducts.any((p) => !p.isSynced);
    return q.estAJour(inv);
  }

  /// Ouverture d'un inventaire (avant tout chargement : la saisie rapide n'a pas de rayon).
  void ouvrirInventaire(String inventoryId, {String libelle = ''}) {
    _inventoryId = inventoryId;
    if (libelle.isNotEmpty) _inventoryLibelle = libelle;
  }

  /// La file a changé (envoi confirmé…) : les produits affichés dont la DERNIÈRE valeur est confirmée
  /// par le serveur passent « à jour ».
  void _surChangementFile() {
    final q = _queue;
    final inv = _inventoryId;
    if (q != null && inv != null) {
      for (final p in _allProducts) {
        if (p.isSynced) continue;
        final s = q.ligne(inv, p.id);
        if (s != null && s.envoyee && s.quantiteEnvoyee == p.quantiteSaisie) {
          p.isSynced = true;
          _locallyTouchedProductIds.add(p.id);
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _queueEcoutee?.removeListener(_surChangementFile);
    super.dispose();
  }

  /// Écrit la saisie dans la file persistante (sur disque) — AVANT tout envoi.
  Future<void> _enregistrer(Product p, int quantite, String inventoryId) async {
    _inventoryId = inventoryId;
    final q = _queue;
    if (q == null) return;
    await q.enregistrer(
      inventaireId: inventoryId,
      ligneId: p.id,
      quantite: quantite,
      inventaireLibelle: _inventoryLibelle,
      cip: p.produitCip,
      nom: p.produitName,
      rayonId: _selectedRayon?.id,
      rayonLibelle: _selectedRayon?.libelle ?? p.locationLabel,
      origine: _selectedRayon == null ? OrigineSaisie.rapide : OrigineSaisie.guidee,
      auteur: auteur,
    );
  }

  String _getPrefKey(String inventoryId, String suffix, {String? rayonId}) {
    return rayonId != null
        ? 'inv_${inventoryId}_ray_${rayonId}_$suffix'
        : 'inv_${inventoryId}_$suffix';
  }

  // --- NOUVELLE MÉTHODE POUR L'AFFICHAGE DU "COMPTÉ : X" ---
  bool isProductTouched(int productId) {
    return _locallyTouchedProductIds.contains(productId);
  }

  Future<int?> checkExistingQuantityLocal(String cip) async {
    try {
      final product = _allProducts.firstWhere((p) => p.produitCip == cip);
      if (product.dtUpdated != null || (!product.isSynced && product.quantiteSaisie >= 0)) {
        return product.quantiteSaisie;
      }
    } catch (e) {}
    return null;
  }

  // --- NOUVEAU DÉCOMPTE INFAILLIBLE ---
  int get uncountedProductsCount {
    if (_allProducts.isEmpty) return 0;
    return _allProducts.where((p) {
      return p.dtUpdated == null && !_locallyTouchedProductIds.contains(p.id);
    }).length;
  }

  void filterToUncounted() {
    _filteredProducts = _allProducts.where((p) =>
    p.dtUpdated == null && !_locallyTouchedProductIds.contains(p.id)
    ).toList();

    _currentProductIndex = 0;
    _activeFilter = ProductFilter(type: FilterType.numeric, from: "Rattrapage", to: "Oublis");

    notifyListeners();
  }

  /// Nouvelle interface : VRAI filtre « oublis » (produits pas encore comptés), distinct du filtre par
  /// numéro. Comme [filterToUncounted] (gardé tel quel pour les écrans d'origine), il n'est pas
  /// enregistré : le filtre choisi auparavant revient à la prochaine ouverture du rayon.
  void filtrerOublis() {
    _activeFilter = ProductFilter(type: FilterType.oublis);
    _runFilterLogic();
    _currentProductIndex = 0;
    notifyListeners();
  }

  // --- PERSISTANCE ET SYNC ---

  Future<void> _saveCurrentIndex(String inventoryId) async {
    if (_selectedRayon != null) {
      _lastIndexByRayon[_selectedRayon!.id] = _currentProductIndex;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_getPrefKey(inventoryId, 'index', rayonId: _selectedRayon!.id), _currentProductIndex);
    }
  }

  Future<void> _saveFilter(String inventoryId) async {
    if (_selectedRayon != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_getPrefKey(inventoryId, 'filter', rayonId: _selectedRayon!.id), _activeFilter.toRawJson());
    }
  }

  Future<ProductFilter> _loadFilter(String inventoryId, String rayonId) async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_getPrefKey(inventoryId, 'filter', rayonId: rayonId)) ?? '';
    if (rawJson.isEmpty) return ProductFilter();
    return ProductFilter.fromRawJson(rawJson);
  }

  Future<void> addCumulLog(Product product, int oldQty, int addedQty) async {
    final log = {
      'date': DateTime.now().toIso8601String(),
      'cip': product.produitCip,
      'name': product.produitName,
      'oldQty': oldQty,
      'addedQty': addedQty,
      'newQty': oldQty + addedQty,
      'rayon': _selectedRayon?.libelle ?? 'Global',
      // 4.16.2 (décision du pharmacien) : qui avait compté la quantité « avant » (serveur à jour, demande 50 :
      // auteurNom / auteurLogin) ; absent sur un serveur plus ancien.
      if (product.auteur != null) 'comptePar': product.auteur,
    };
    _cumulLogs.add(log);
    final prefs = await SharedPreferences.getInstance();
    final keySuffix = _selectedRayon?.id ?? 'global';
    await prefs.setString('cumul_logs_$keySuffix', json.encode(_cumulLogs));
    notifyListeners();
  }

  Future<void> loadCumulLogs(String suffixId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? logsString = prefs.getString('cumul_logs_$suffixId');
    if (logsString != null) {
      try {
        final List<dynamic> decoded = json.decode(logsString);
        _cumulLogs = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) { _cumulLogs = []; }
    } else { _cumulLogs = []; }
    notifyListeners();
  }

  void _runFilterLogic() {
    if (!_activeFilter.isActive) {
      _filteredProducts = List.from(_allProducts);
      return;
    }
    if (_activeFilter.from == "Rattrapage") return;

    switch (_activeFilter.type) {
      case FilterType.numeric:
        try {
          int from = int.parse(_activeFilter.from) - 1;
          int to = int.parse(_activeFilter.to);
          if (from < 0) from = 0;
          if (to > _allProducts.length) to = _allProducts.length;
          _filteredProducts = _allProducts.sublist(from, to);
        } catch (e) { _filteredProducts = []; }
        break;
      case FilterType.alphabetic:
        try {
          final from = _activeFilter.from.toLowerCase();
          final to = _activeFilter.to.toLowerCase() + '\uffff';
          _filteredProducts = _allProducts.where((p) {
            final name = p.produitName.toLowerCase();
            return name.compareTo(from) >= 0 && name.compareTo(to) <= 0;
          }).toList();
        } catch (e) { _filteredProducts = []; }
        break;
      case FilterType.oublis:
        _filteredProducts = _allProducts.where((p) => p.dtUpdated == null && !_locallyTouchedProductIds.contains(p.id)).toList();
        break;
      default:
        _filteredProducts = List.from(_allProducts);
        break;
    }
  }

  Future<void> applyFilter(ProductFilter newFilter, String inventoryId) async {
    _activeFilter = newFilter;
    await _saveFilter(inventoryId);
    _runFilterLogic();
    _currentProductIndex = 0;
    await _saveCurrentIndex(inventoryId);
    notifyListeners();
  }

  Future<void> fetchRayons(ApiService api, String inventoryId) async {
    _inventoryId = inventoryId;
    _isLoading = true; _error = null; _errorObj = null; notifyListeners();
    try {
      _rayons = await api.fetchRayons(inventoryId);
      loadRayonStatuses(api, inventoryId);
      if (_rayons.length == 1) {
        await fetchProducts(api, inventoryId, _rayons.first.id);
      }
    } catch (e) { _error = e.toString(); _errorObj = e; }
    _isLoading = false; notifyListeners();
  }

  Future<void> loadRayonStatuses(ApiService api, String inventoryId) async {
    if (_isLoadingStatuses || _rayons.isEmpty) return;
    _isLoadingStatuses = true;
    // 4.15 (demande 30) : serveur récent → l'état de TOUS les rayons en une requête (au lieu d'une ou
    // deux par rayon). Indisponible ou en échec : l'ancien chemin, rayon par rayon.
    try {
      final etat = await api.etatRayons(inventoryId);
      if (etat != null) {
        for (final e in etat) {
          if (_rayons.any((r) => r.id == e.rayon.id)) _rayonStatuses[e.rayon.id] = e.statut;
        }
        _isLoadingStatuses = false;
        notifyListeners();
        return;
      }
    } on ApiLoadException {
      // Erreur : état inconnu → ancien chemin (chaque rayon garde son état précédent en cas d'échec).
    }
    for (var rayon in _rayons) {
      // Erreur réseau : état INCONNU (on garde l'état précédent) — avant, une erreur affichait
      // « pas commencé » ou « reste à faire » à tort.
      final hasTouched = await api.hasTouchedProductsInRayon(inventoryId, rayon.id);
      if (hasTouched == null) continue;
      int status = 0;
      if (hasTouched) {
        final hasUntouched = await api.hasUntouchedProductsInRayon(inventoryId, rayon.id);
        if (hasUntouched == null) continue;
        status = !hasUntouched ? 2 : 1;
      }
      _rayonStatuses[rayon.id] = status;
      notifyListeners();
    }
    _isLoadingStatuses = false;
  }

  Future<void> fetchProducts(ApiService api, String inventoryId, String rayonId) async {
    _inventoryId = inventoryId;
    _isLoading = true; _error = null; _errorObj = null; _isGlobalMode = false;
    _locallyTouchedProductIds.clear();

    _selectedRayon = _rayons.firstWhere((r) => r.id == rayonId, orElse: () => Rayon(id: rayonId, code: '', libelle: 'Inconnu'));
    notifyListeners();
    try {
      final apiProducts = await api.fetchProducts(inventoryId, rayonId);
      _allProducts = await _loadAndMergeUnsyncedData(inventoryId, rayonId, apiProducts);
      await loadCumulLogs(rayonId);

      _activeFilter = await _loadFilter(inventoryId, rayonId);
      _runFilterLogic();

      final prefs = await SharedPreferences.getInstance();
      final lastIndex = prefs.getInt(_getPrefKey(inventoryId, 'index', rayonId: rayonId)) ?? 0;
      _currentProductIndex = (lastIndex >= 0 && lastIndex < _filteredProducts.length) ? lastIndex : 0;
    } catch (e) { _error = e.toString(); _errorObj = e; }
    _isLoading = false; notifyListeners();
  }

  /// Applique aux produits chargés du serveur les saisies encore en attente dans la file (quel que soit
  /// le rayon ou le mode où elles ont été faites : la ligne d'inventaire fait foi).
  Future<List<Product>> _loadAndMergeUnsyncedData(String inventoryId, String rayonId, List<Product> apiProducts) async {
    final q = _queue;
    if (q == null) {
      _hasPendingSession = false;
      return apiProducts;
    }
    await q.load();
    var trouve = false;
    for (final a in apiProducts) {
      final s = q.ligne(inventoryId, a.id);
      if (s != null && s.enAttente) {
        a.quantiteSaisie = s.quantite;
        a.isSynced = false;
        _locallyTouchedProductIds.add(a.id);
        trouve = true;
      }
    }
    _hasPendingSession = trouve;
    return apiProducts;
  }

  List<Product> _appliquerAttentes(String inventoryId, List<Product> produits) {
    final q = _queue;
    if (q == null) return produits;
    for (final a in produits) {
      final s = q.ligne(inventoryId, a.id);
      if (s != null && s.enAttente) {
        a.quantiteSaisie = s.quantite;
        a.isSynced = false;
      }
    }
    return produits;
  }

  Future<List<Product>> searchProductOnline(ApiService api, String inventoryId, String query) async {
    _inventoryId = inventoryId;
    _isLoading = true; notifyListeners();
    List<Product> results = [];
    try {
      // La liste en mémoire ne sert qu'à l'affichage : chaque quantité saisie est déjà dans la file
      // persistante, un nouveau scan n'en efface aucune (correction P1).
      results = _appliquerAttentes(inventoryId, await api.fetchProducts(inventoryId, _selectedRayon?.id, query: query));
      if (results.isNotEmpty && _selectedRayon == null) {
        _allProducts = results;
        _filteredProducts = results;
        _isGlobalMode = true;
        _currentProductIndex = 0;
      }
    } finally {
      // Une recherche en échec ne remplace plus tout l'écran par l'erreur : elle est relancée
      // à l'appelant, qui affiche le message (≠ « produit introuvable »).
      _isLoading = false; notifyListeners();
    }
    return results;
  }

  Future<void> loadGlobalInventory(ApiService api, String inventoryId) async {
    _inventoryId = inventoryId;
    _isLoading = true; _isGlobalMode = true; _error = null; notifyListeners();
    try {
      final rs = await api.fetchRayons(inventoryId);
      _rayons = rs;
      _allProducts = [];
      for (var r in rs) {
        final ps = await api.fetchProducts(inventoryId, r.id);
        for(var p in ps) p.locationLabel = r.libelle;
        _allProducts.addAll(await _loadAndMergeUnsyncedData(inventoryId, r.id, ps));
      }
      _filteredProducts = List.from(_allProducts);
    } catch (e) { _error = "Err global: $e"; _errorObj = e; }
    _isLoading = false; notifyListeners();
  }

  /// Quantité saisie pour le produit courant : écrite dans la file persistante AVANT tout envoi.
  /// Valeur vide ou invalide : rien n'est enregistré (jamais de 0 implicite).
  Future<void> updateQuantity(String value, String inventoryId) async {
    final p = currentProduct;
    if (p == null) return;
    final qte = SaisieInput.parseQuantite(value);
    if (qte == null) return;
    await _enregistrer(p, qte, inventoryId);
    p.quantiteSaisie = qte;
    p.isSynced = false;
    _locallyTouchedProductIds.add(p.id);
    notifyListeners();
  }

  /// Quantité [p.quantiteSaisie] d'un produit trouvé par recherche / scan : écrite dans la file
  /// persistante même si le produit n'est pas (ou plus) dans la liste affichée.
  Future<void> updateSpecificProduct(Product p, String inventoryId) async {
    await _enregistrer(p, p.quantiteSaisie, inventoryId);
    p.isSynced = false;
    final index = _allProducts.indexWhere((item) => item.id == p.id);
    if (index != -1) {
      _allProducts[index].quantiteSaisie = p.quantiteSaisie;
      _allProducts[index].isSynced = false;
    }
    _locallyTouchedProductIds.add(p.id);
    notifyListeners();
  }

  void nextProduct(String inventoryId) {
    if (_currentProductIndex < _filteredProducts.length - 1) {
      _currentProductIndex++;
      _saveCurrentIndex(inventoryId);
      notifyListeners();
    }
  }

  void previousProduct(String inventoryId) {
    if (_currentProductIndex > 0) {
      _currentProductIndex--;
      _saveCurrentIndex(inventoryId);
      notifyListeners();
    }
  }

  void jumpToProduct(Product p, String inventoryId) {
    final idx = _filteredProducts.indexWhere((item) => item.id == p.id);
    if (idx != -1) {
      _currentProductIndex = idx;
      _saveCurrentIndex(inventoryId);
      notifyListeners();
    }
  }

  /// Envoie les saisies en attente de l'inventaire (tous rayons), dans l'ordre de saisie.
  /// Renvoie le nombre de saisies confirmées par le serveur.
  Future<int> sendDataToServer(ApiService api, String inventoryId, [Function(int, int)? onProgress]) async {
    return (await envoyerInventaire(inventoryId, onProgress)).envoyees;
  }

  Future<BilanEnvoi> envoyerInventaire(String inventoryId, [Function(int, int)? onProgress]) async {
    _inventoryId = inventoryId;
    final q = _queue;
    if (q == null) return const BilanEnvoi();
    final bilan = await q.envoyer(inventaireId: inventoryId, onProgress: onProgress == null ? null : (a, b) => onProgress(a, b));
    _surChangementFile();
    return bilan;
  }

  void reset() {
    _allProducts = []; _filteredProducts = []; _selectedRayon = null; _currentProductIndex = 0;
    _activeFilter = ProductFilter(); _isGlobalMode = false; _locallyTouchedProductIds.clear(); notifyListeners();
  }
  void acknowledgedPendingSession() => _hasPendingSession = false;
}