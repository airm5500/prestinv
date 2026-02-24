// lib/providers/entry_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/models/product_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestinv/config/app_config.dart';

class EntryProvider with ChangeNotifier {
  List<Rayon> _rayons = [];
  Rayon? _selectedRayon;
  bool _isLoading = false;
  String? _error;

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

  bool get hasUnsyncedData => _allProducts.any((p) => !p.isSynced);

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

  Future<void> _saveUnsyncedData(String inventoryId) async {
    if (_selectedRayon == null) return;
    final String key = _getPrefKey(inventoryId, 'unsynced', rayonId: _selectedRayon!.id);
    final prefs = await SharedPreferences.getInstance();

    final unsyncedProducts = _allProducts.where((p) => !p.isSynced).toList();

    if (unsyncedProducts.isEmpty) {
      await prefs.remove(key);
    } else {
      final dataToSave = unsyncedProducts.map((p) => p.toJson()).toList();
      await prefs.setString(key, json.encode(dataToSave));
    }
  }

  Future<void> markAsSynced(int productId, String inventoryId) async {
    final index = _allProducts.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _allProducts[index].isSynced = true;
      _locallyTouchedProductIds.add(productId);
      await _saveUnsyncedData(inventoryId);
      notifyListeners();
    }
  }

  void markAsConfirmedFromServer(int productId) {
    final index = _allProducts.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _allProducts[index].isSynced = true;
      notifyListeners();
    }
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
    _isLoading = true; _error = null; notifyListeners();
    try {
      _rayons = await api.fetchRayons(inventoryId);
      loadRayonStatuses(api, inventoryId);
      if (_rayons.length == 1) {
        await fetchProducts(api, inventoryId, _rayons.first.id);
      }
    } catch (e) { _error = e.toString(); }
    _isLoading = false; notifyListeners();
  }

  Future<void> loadRayonStatuses(ApiService api, String inventoryId) async {
    if (_isLoadingStatuses || _rayons.isEmpty) return;
    _isLoadingStatuses = true;
    for (var rayon in _rayons) {
      bool hasTouched = await api.hasTouchedProductsInRayon(inventoryId, rayon.id);
      int status = 0;
      if (hasTouched) {
        bool hasUntouched = await api.hasUntouchedProductsInRayon(inventoryId, rayon.id);
        status = !hasUntouched ? 2 : 1;
      }
      _rayonStatuses[rayon.id] = status;
      notifyListeners();
    }
    _isLoadingStatuses = false;
  }

  Future<void> fetchProducts(ApiService api, String inventoryId, String rayonId) async {
    _isLoading = true; _error = null; _isGlobalMode = false;
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
    } catch (e) { _error = e.toString(); }
    _isLoading = false; notifyListeners();
  }

  Future<List<Product>> _loadAndMergeUnsyncedData(String inventoryId, String rayonId, List<Product> apiProducts) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_getPrefKey(inventoryId, 'unsynced', rayonId: rayonId));
    if (saved == null) { _hasPendingSession = false; return apiProducts; }
    try {
      final List decoded = json.decode(saved);
      final savedP = decoded.map((d) => Product.fromJson(d)).toList();
      if (savedP.isEmpty) { _hasPendingSession = false; return apiProducts; }
      _hasPendingSession = true;
      return apiProducts.map((a) {
        try {
          final s = savedP.firstWhere((p) => p.id == a.id);
          a.quantiteSaisie = s.quantiteSaisie;
          a.isSynced = s.isSynced;
          _locallyTouchedProductIds.add(a.id);
        } catch (e) {}
        return a;
      }).toList();
    } catch (e) { return apiProducts; }
  }

  Future<List<Product>> searchProductOnline(ApiService api, String inventoryId, String query) async {
    _isLoading = true; _error = null; notifyListeners();
    List<Product> results = [];
    try {
      results = await api.fetchProducts(inventoryId, _selectedRayon?.id, query: query);
      if (results.isNotEmpty && _selectedRayon == null) {
        _allProducts = results;
        _filteredProducts = results;
        _isGlobalMode = true;
        _currentProductIndex = 0;
      }
    } catch (e) { _error = "Erreur recherche: $e"; }
    _isLoading = false; notifyListeners();
    return results;
  }

  Future<void> loadGlobalInventory(ApiService api, String inventoryId) async {
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
    } catch (e) { _error = "Err global: $e"; }
    _isLoading = false; notifyListeners();
  }

  Future<void> updateQuantity(String value, String inventoryId) async {
    if (currentProduct != null) {
      final qte = int.tryParse(value) ?? 0;
      currentProduct!.quantiteSaisie = qte;
      currentProduct!.isSynced = false;
      _locallyTouchedProductIds.add(currentProduct!.id);
      await _saveUnsyncedData(inventoryId);
      notifyListeners();
    }
  }

  Future<void> updateSpecificProduct(Product p, String inventoryId) async {
    final index = _allProducts.indexWhere((item) => item.id == p.id);
    if (index != -1) {
      _allProducts[index].quantiteSaisie = p.quantiteSaisie;
      _allProducts[index].isSynced = false;
      _locallyTouchedProductIds.add(p.id);
      await _saveUnsyncedData(inventoryId);
      notifyListeners();
    }
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

  Future<void> sendDataToServer(ApiService api, String inventoryId, [Function(int, int)? onProgress]) async {
    List<Product> unsynced = _allProducts.where((p) => !p.isSynced).toList();
    int total = unsynced.length;
    if (total == 0) return;
    for (int i = 0; i < total; i++) {
      try {
        await api.updateProductQuantity(unsynced[i].id, unsynced[i].quantiteSaisie);
        unsynced[i].isSynced = true;
        _locallyTouchedProductIds.add(unsynced[i].id);
        onProgress?.call(i + 1, total);
      } catch (e) {
        print("Error syncing: $e");
      }
    }
    await _saveUnsyncedData(inventoryId);
    notifyListeners();
  }

  void reset() {
    _allProducts = []; _filteredProducts = []; _selectedRayon = null; _currentProductIndex = 0;
    _activeFilter = ProductFilter(); _isGlobalMode = false; _locallyTouchedProductIds.clear(); notifyListeners();
  }
  void acknowledgedPendingSession() => _hasPendingSession = false;
}