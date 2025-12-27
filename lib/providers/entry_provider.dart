// lib/providers/entry_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/models/product_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Product? get currentProduct => _filteredProducts.isNotEmpty && _currentProductIndex < _filteredProducts.length
      ? _filteredProducts[_currentProductIndex]
      : null;

  bool get hasUnsyncedData => _allProducts.any((p) => !p.isSynced);

  Future<void> _saveUnsyncedData() async {
    // Sauvegarde contextuelle (Rayon ou Global)
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

  Future<List<Product>> _loadAndMergeUnsyncedData(String rayonId, List<Product> apiProducts) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'unsynced_data_$rayonId';
    final savedDataString = prefs.getString(key);
    if (savedDataString == null) { _hasPendingSession = false; return apiProducts; }

    try {
      final savedProductsData = json.decode(savedDataString) as List;
      final savedProducts = savedProductsData.map((data) => Product.fromJson(data)).toList();

      if (savedProducts.isEmpty) { _hasPendingSession = false; return apiProducts; }

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
          if (from >= to) { _filteredProducts = []; return; }
          _filteredProducts = _allProducts.sublist(from, to);
        } catch (e) { _filteredProducts = []; }
        break;

      case FilterType.alphabetic:
        try {
          final from = _activeFilter.from.toLowerCase();
          // CORRECTION: Ajout du caractère unicode maximum pour inclure les mots commençant par 'to'
          // Ex: "TOT" -> "TOT\uffff". Ainsi "TOTHEMA" <= "TOT\uffff" sera VRAI.
          final to = _activeFilter.to.toLowerCase() + '\uffff';

          _filteredProducts = _allProducts.where((p) {
            final name = p.produitName.toLowerCase();
            return name.compareTo(from) >= 0 && name.compareTo(to) <= 0;
          }).toList();
        } catch(e) { _filteredProducts = []; }
        break;

      case FilterType.none:
      default:
        _filteredProducts = List.from(_allProducts);
        break;
    }
  }

  void reset() {
    _rayons = [];
    _allProducts = [];
    _filteredProducts = [];
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
      if (_rayons.length == 1) {
        await fetchProducts(api, inventoryId, _rayons.first.id);
      }
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchProducts(ApiService api, String inventoryId, String rayonId) async {
    _isLoading = true;
    _error = null;
    _isGlobalMode = false;
    _selectedRayon = _rayons.firstWhere((r) => r.id == rayonId, orElse: () => Rayon(id: rayonId, code: '', libelle: 'Inconnu'));
    notifyListeners();
    try {
      final apiProducts = await api.fetchProducts(inventoryId, rayonId);
      _allProducts = await _loadAndMergeUnsyncedData(rayonId, apiProducts);
      _activeFilter = await _loadFilter(rayonId);
      _runFilterLogic();
      final lastIndex = _lastIndexByRayon[rayonId] ?? (await SharedPreferences.getInstance()).getInt('lastIndex_$rayonId') ?? 0;
      _currentProductIndex = (lastIndex >= 0 && lastIndex < _filteredProducts.length) ? lastIndex : 0;
      _lastIndexByRayon[rayonId] = _currentProductIndex;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<List<Product>> searchProductOnline(ApiService api, String inventoryId, String query) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    List<Product> results = [];

    try {
      final rayonId = _selectedRayon?.id;
      // ApiService gère le basculement details/detailsAll via idRayon null ou non
      results = await api.fetchProducts(inventoryId, rayonId, query: query);

      if (results.isNotEmpty) {
        if (rayonId == null) {
          // Mode Global : On remplace la liste affichée par les résultats
          _allProducts = results;
          _filteredProducts = results;
          _isGlobalMode = true;
          _currentProductIndex = 0;
        }
        // Mode Rayon : On ne remplace pas la liste, on retourne juste les résultats pour popup
      }
    } catch (e) {
      _error = "Erreur recherche: $e";
      results = [];
    }

    _isLoading = false;
    notifyListeners();
    return results;
  }

  Future<void> loadGlobalInventory(ApiService api, String inventoryId) async {
    _isLoading = true;
    _error = null;
    _isGlobalMode = true;
    _allProducts = [];
    _filteredProducts = [];
    notifyListeners();
    try {
      final rayons = await api.fetchRayons(inventoryId);
      _rayons = rayons;
      if (rayons.isEmpty) { _isLoading = false; notifyListeners(); return; }

      final List<Future<List<Product>>> downloadTasks = rayons.map((rayon) {
        return api.fetchProducts(inventoryId, rayon.id).then((products) async {
          for (var p in products) {
            p.locationLabel = rayon.libelle;
          }
          return await _loadAndMergeUnsyncedData(rayon.id, products);
        });
      }).toList();

      final List<List<Product>> results = await Future.wait(downloadTasks);
      for (var list in results) {
        _allProducts.addAll(list);
      }

      _filteredProducts = List.from(_allProducts);
      if (rayons.isNotEmpty) { _selectedRayon = rayons.first; }

    } catch (e) {
      _error = "Erreur chargement global : $e";
    }
    _isLoading = false;
    notifyListeners();
  }

  // Cette méthode met à jour la quantité d'un produit en assurant la persistance
  // dans la liste principale, même si on est en mode recherche ou filtre.
  Future<void> updateSpecificProduct(Product productToUpdate) async {
    try {
      // On cherche l'instance "réelle" dans la liste complète
      final index = _allProducts.indexWhere((p) => p.id == productToUpdate.id);

      if (index != -1) {
        // Mise à jour de l'existant
        _allProducts[index].quantiteSaisie = productToUpdate.quantiteSaisie;
        _allProducts[index].isSynced = false;
      } else {
        // Ajout (Cas Saisie Rapide sur produit non chargé initialement)
        productToUpdate.isSynced = false;
        _allProducts.add(productToUpdate);

        // Si on est en mode affichage filtré/global, on met à jour la vue aussi
        if (_isGlobalMode) {
          final filterIndex = _filteredProducts.indexWhere((p) => p.id == productToUpdate.id);
          if (filterIndex != -1) {
            _filteredProducts[filterIndex].quantiteSaisie = productToUpdate.quantiteSaisie;
            _filteredProducts[filterIndex].isSynced = false;
          } else {
            _filteredProducts.add(productToUpdate);
          }
        }
      }
    } catch (e) {
      print("Erreur updateSpecificProduct : $e");
    }

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

  void nextProduct() { if (_currentProductIndex < _filteredProducts.length - 1) { _currentProductIndex++; _saveCurrentIndex(); notifyListeners(); } }
  void previousProduct() { if (_currentProductIndex > 0) { _currentProductIndex--; _saveCurrentIndex(); notifyListeners(); } }
  void goToFirstProduct() { if (_filteredProducts.isNotEmpty) { _currentProductIndex = 0; _saveCurrentIndex(); notifyListeners(); } }

  void jumpToProduct(Product product) {
    final index = _filteredProducts.indexWhere((p) => p.id == product.id);
    if (index != -1) { _currentProductIndex = index; _saveCurrentIndex(); notifyListeners(); }
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

  void acknowledgedPendingSession() {
    _hasPendingSession = false;
  }
}