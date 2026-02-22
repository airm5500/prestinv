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

  // Liste pour stocker l'historique des cumuls
  List<Map<String, dynamic>> _cumulLogs = [];

  // Map pour les statuts (couleurs) des rayons
  final Map<String, int> _rayonStatuses = {};
  bool _isLoadingStatuses = false;

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

  // --- VÉRIFICATION LOCALE INSTANTANÉE (ZÉRO LENTEUR) ---

  /// Cette méthode vérifie en mémoire locale si le produit a déjà été compté.
  /// Elle se base sur dtUpdated (preuve serveur) ou sur une saisie locale non synchronisée.
  Future<int?> checkExistingQuantityLocal(String cip) async {
    try {
      final product = _allProducts.firstWhere((p) => p.produitCip == cip);

      // On considère comme "déjà compté" si le serveur a une date de modif (dtUpdated)
      // OU si l'utilisateur a déjà saisi une quantité localement dans cette session (!isSynced)
      if (product.dtUpdated != null || (!product.isSynced && product.quantiteSaisie > 0)) {
        return product.quantiteSaisie;
      }
    } catch (e) {
      // Produit non trouvé dans la liste locale chargée
    }
    return null;
  }

  Future<void> _saveUnsyncedData() async {
    final String keySuffix = _selectedRayon?.id ?? 'global_${_isGlobalMode ? "quick" : "unknown"}';
    final prefs = await SharedPreferences.getInstance();
    final key = 'unsynced_data_$keySuffix';

    final unsyncedProducts = _allProducts.where((p) => !p.isSynced).toList();

    if (unsyncedProducts.isEmpty) {
      await prefs.remove(key);
    } else {
      final dataToSave = unsyncedProducts.map((p) => p.toJson()).toList();
      await prefs.setString(key, json.encode(dataToSave));
    }
  }

  Future<void> markAsSynced(int productId) async {
    final index = _allProducts.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _allProducts[index].isSynced = true;
      await _saveUnsyncedData();
      notifyListeners();
    }
  }

  // --- GESTION DES LOGS DE CUMUL ---

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
      } catch (e) {
        _cumulLogs = [];
      }
    } else {
      _cumulLogs = [];
    }
    notifyListeners();
  }

  // --- RESTE DU PROVIDER (LOGIQUE FILTRES ET PERSISTANCE) ---

  void _saveCurrentIndex() async {
    if (_selectedRayon != null) {
      _lastIndexByRayon[_selectedRayon!.id] = _currentProductIndex;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastIndex_${_selectedRayon!.id}', _currentProductIndex);
    }
  }

  Future<void> _saveFilter() async {
    if (_selectedRayon != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('filter_${_selectedRayon!.id}', _activeFilter.toRawJson());
    }
  }

  Future<ProductFilter> _loadFilter(String rayonId) async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString('filter_$rayonId') ?? '';
    return ProductFilter.fromRawJson(rawJson);
  }

  Future<void> applyFilter(ProductFilter newFilter) async {
    _activeFilter = newFilter;
    await _saveFilter();
    _runFilterLogic();
    _currentProductIndex = 0;
    _saveCurrentIndex();
    notifyListeners();
  }

  void _runFilterLogic() {
    if (!_activeFilter.isActive) {
      _filteredProducts = List.from(_allProducts);
      return;
    }
    switch (_activeFilter.type) {
      case FilterType.numeric:
        try {
          int from = int.parse(_activeFilter.from) - 1;
          int to = int.parse(_activeFilter.to);
          if (from < 0) from = 0;
          if (to > _allProducts.length) to = _allProducts.length;
          if (from >= to) {
            _filteredProducts = [];
            return;
          }
          _filteredProducts = _allProducts.sublist(from, to);
        } catch (e) {
          _filteredProducts = [];
        }
        break;

      case FilterType.alphabetic:
        try {
          final from = _activeFilter.from.toLowerCase();
          final to = _activeFilter.to.toLowerCase() + '\uffff';

          _filteredProducts = _allProducts.where((p) {
            final name = p.produitName.toLowerCase();
            return name.compareTo(from) >= 0 && name.compareTo(to) <= 0;
          }).toList();
        } catch (e) {
          _filteredProducts = [];
        }
        break;

      default:
        _filteredProducts = List.from(_allProducts);
        break;
    }
  }

  void reset() {
    _rayons = [];
    _allProducts = [];
    _filteredProducts = [];
    _cumulLogs = [];
    _rayonStatuses.clear();
    _selectedRayon = null;
    _currentProductIndex = 0;
    _error = null;
    _hasPendingSession = false;
    _activeFilter = ProductFilter();
    _isGlobalMode = false;
    notifyListeners();
  }

  Future<void> fetchRayons(ApiService api, String inventoryId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _rayons = await api.fetchRayons(inventoryId);
      loadRayonStatuses(api, inventoryId);
      if (_rayons.length == 1) {
        await fetchProducts(api, inventoryId, _rayons.first.id);
      }
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadRayonStatuses(ApiService api, String inventoryId) async {
    if (_isLoadingStatuses || _rayons.isEmpty) return;
    _isLoadingStatuses = true;
    _rayonStatuses.clear();

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
    _isLoading = true;
    _error = null;
    _isGlobalMode = false;
    _selectedRayon = _rayons.firstWhere((r) => r.id == rayonId,
        orElse: () => Rayon(id: rayonId, code: '', libelle: 'Inconnu'));
    notifyListeners();
    try {
      final apiProducts = await api.fetchProducts(inventoryId, rayonId);
      _allProducts = await _loadAndMergeUnsyncedData(rayonId, apiProducts);

      await loadCumulLogs(rayonId);

      _activeFilter = await _loadFilter(rayonId);
      _runFilterLogic();

      final lastIndex = _lastIndexByRayon[rayonId] ??
          (await SharedPreferences.getInstance()).getInt('lastIndex_$rayonId') ?? 0;

      _currentProductIndex = (lastIndex >= 0 && lastIndex < _filteredProducts.length) ? lastIndex : 0;
      _lastIndexByRayon[rayonId] = _currentProductIndex;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<List<Product>> _loadAndMergeUnsyncedData(String rayonId, List<Product> apiProducts) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'unsynced_data_$rayonId';
    final savedDataString = prefs.getString(key);
    if (savedDataString == null) {
      _hasPendingSession = false;
      return apiProducts;
    }

    try {
      final savedProductsData = json.decode(savedDataString) as List;
      final savedProducts = savedProductsData.map((data) => Product.fromJson(data)).toList();

      if (savedProducts.isEmpty) {
        _hasPendingSession = false;
        return apiProducts;
      }

      _hasPendingSession = true;
      return apiProducts.map((apiProduct) {
        try {
          final savedVersion = savedProducts.firstWhere((p) => p.id == apiProduct.id);
          apiProduct.quantiteSaisie = savedVersion.quantiteSaisie;
          apiProduct.isSynced = savedVersion.isSynced;
        } catch (e) {}
        return apiProduct;
      }).toList();
    } catch (e) {
      return apiProducts;
    }
  }

  Future<List<Product>> searchProductOnline(ApiService api, String inventoryId, String query) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    List<Product> results = [];
    try {
      final rayonId = _selectedRayon?.id;
      results = await api.fetchProducts(inventoryId, rayonId, query: query);
      if (results.isNotEmpty && rayonId == null) {
        _allProducts = results;
        _filteredProducts = results;
        _isGlobalMode = true;
        _currentProductIndex = 0;
      }
    } catch (e) {
      _error = "Erreur recherche: $e";
    }
    _isLoading = false;
    notifyListeners();
    return results;
  }

  Future<void> updateSpecificProduct(Product productToUpdate) async {
    try {
      final index = _allProducts.indexWhere((p) => p.id == productToUpdate.id);
      if (index != -1) {
        _allProducts[index].quantiteSaisie = productToUpdate.quantiteSaisie;
        _allProducts[index].isSynced = false;
      } else {
        productToUpdate.isSynced = false;
        _allProducts.add(productToUpdate);
      }
    } catch (e) {}
    await _saveUnsyncedData();
    notifyListeners();
  }

  Future<void> updateQuantity(String value) async {
    if (currentProduct != null) {
      final int quantity = int.tryParse(value) ?? 0;
      if (quantity >= 0) {
        currentProduct!.quantiteSaisie = quantity;
        await updateSpecificProduct(currentProduct!);
      }
    }
  }

  void nextProduct() {
    if (_currentProductIndex < _filteredProducts.length - 1) {
      _currentProductIndex++;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  void previousProduct() {
    if (_currentProductIndex > 0) {
      _currentProductIndex--;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  void jumpToProduct(Product product) {
    final index = _filteredProducts.indexWhere((p) => p.id == product.id);
    if (index != -1) {
      _currentProductIndex = index;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  Future<void> sendDataToServer(ApiService api, [Function(int, int)? onProgress]) async {
    List<Product> unsyncedProducts = _allProducts.where((p) => !p.isSynced).toList();
    int total = unsyncedProducts.length;
    int sentCount = 0;
    try {
      for (var product in unsyncedProducts) {
        await api.updateProductQuantity(product.id, product.quantiteSaisie);
        product.isSynced = true;
        sentCount++;
        onProgress?.call(sentCount, total);
      }
    } catch (e) {
      await _saveUnsyncedData();
      notifyListeners();
      rethrow;
    }
    await _saveUnsyncedData();
    notifyListeners();
  }

  void acknowledgedPendingSession() => _hasPendingSession = false;
}