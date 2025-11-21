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

  // La liste complète (source de vérité)
  List<Product> _allProducts = [];
  // La liste affichée (filtrée)
  List<Product> _filteredProducts = [];

  ProductFilter _activeFilter = ProductFilter();

  int _currentProductIndex = 0;
  final Map<String, int> _lastIndexByRayon = {};

  bool _hasPendingSession = false;

  // --- Getters publics ---
  List<Rayon> get rayons => _rayons;
  Rayon? get selectedRayon => _selectedRayon;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasPendingSession => _hasPendingSession;

  ProductFilter get activeFilter => _activeFilter;

  // Retourne la liste FILTRÉE (pour l'affichage standard)
  List<Product> get products => _filteredProducts;

  // NOUVEAU : Retourne la liste COMPLÈTE (pour la recherche globale "Scan")
  List<Product> get allProducts => _allProducts;

  // Total des produits filtrés
  int get totalProducts => _filteredProducts.length;

  // Total des produits de l'emplacement
  int get totalProductsInRayon => _allProducts.length;

  int get currentProductIndex => _currentProductIndex;

  Product? get currentProduct => _filteredProducts.isNotEmpty && _currentProductIndex < _filteredProducts.length
      ? _filteredProducts[_currentProductIndex]
      : null;

  bool get hasUnsyncedData => _allProducts.any((p) => !p.isSynced);

  // --- PERSISTANCE ---

  Future<void> _saveUnsyncedData() async {
    if (_selectedRayon == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'unsynced_data_${_selectedRayon!.id}';

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

    if (savedDataString == null) {
      _hasPendingSession = false;
      return apiProducts;
    }

    final savedProductsData = json.decode(savedDataString) as List;
    final savedProducts = savedProductsData.map((data) => Product.fromJson(data)).toList();

    if (savedProducts.isEmpty) {
      _hasPendingSession = false;
      return apiProducts;
    }

    _hasPendingSession = true;

    final mergedProducts = apiProducts.map((apiProduct) {
      try {
        final savedVersion = savedProducts.firstWhere((p) => p.id == apiProduct.id);
        apiProduct.quantiteSaisie = savedVersion.quantiteSaisie;
        apiProduct.isSynced = savedVersion.isSynced;
      } catch (e) {
        // Pas de sauvegarde locale pour ce produit
      }
      return apiProduct;
    }).toList();

    return mergedProducts;
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

  // --- LOGIQUE DE FILTRAGE ---

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
          final to = _activeFilter.to.toLowerCase();

          _filteredProducts = _allProducts.where((p) {
            final name = p.produitName.toLowerCase();
            return name.compareTo(from) >= 0 && name.compareTo(to) <= 0;
          }).toList();
        } catch(e) {
          _filteredProducts = [];
        }
        break;

      case FilterType.none:
      default:
        _filteredProducts = List.from(_allProducts);
        break;
    }
  }

  // --- MÉTHODES PUBLIQUES ---

  void reset() {
    _rayons = [];
    _allProducts = [];
    _filteredProducts = [];
    _selectedRayon = null;
    _currentProductIndex = 0;
    _error = null;
    _hasPendingSession = false;
    _activeFilter = ProductFilter();
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
    _selectedRayon = _rayons.firstWhere((r) => r.id == rayonId);
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

  Future<void> updateQuantity(String value) async {
    if (currentProduct != null) {
      final int quantity = int.tryParse(value) ?? 0;
      if (quantity >= 0) {
        final productId = currentProduct!.id;

        currentProduct!.quantiteSaisie = quantity;
        currentProduct!.isSynced = false;

        try {
          final productInAll = _allProducts.firstWhere((p) => p.id == productId);
          productInAll.quantiteSaisie = quantity;
          productInAll.isSynced = false;
        } catch (e) {
          _error = "Erreur de synchronisation des listes.";
        }

        await _saveUnsyncedData();
        notifyListeners();
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

  void goToFirstProduct() {
    if (_filteredProducts.isNotEmpty) {
      _currentProductIndex = 0;
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

  void acknowledgedPendingSession() {
    _hasPendingSession = false;
  }
}