// lib/providers/entry_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
// NOUVEAU
import 'package:prestinv/models/product_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EntryProvider with ChangeNotifier {
  List<Rayon> _rayons = [];
  Rayon? _selectedRayon;
  bool _isLoading = false;
  String? _error;

  // MODIFIÉ : _products est renommé _allProducts (source de vérité)
  List<Product> _allProducts = [];
  // NOUVEAU : La liste que l'UI va réellement afficher
  List<Product> _filteredProducts = [];

  // NOUVEAU : Gère le filtre actif
  ProductFilter _activeFilter = ProductFilter();

  // MODIFIÉ : L'index est maintenant géré par emplacement
  int _currentProductIndex = 0;
  final Map<String, int> _lastIndexByRayon = {};

  // Pour gérer la session non envoyée
  bool _hasPendingSession = false;

  // --- Getters publics pour l'interface utilisateur ---
  List<Rayon> get rayons => _rayons;
  Rayon? get selectedRayon => _selectedRayon;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasPendingSession => _hasPendingSession;

  // NOUVEAU : Le filtre actif
  ProductFilter get activeFilter => _activeFilter;

  // MODIFIÉ : 'products' retourne maintenant la liste FILTRÉE
  List<Product> get products => _filteredProducts;

  // MODIFIÉ : 'totalProducts' est le total des produits FILTRÉS
  int get totalProducts => _filteredProducts.length;

  // NOUVEAU : Le total des produits de l'emplacement (pour le badge)
  int get totalProductsInRayon => _allProducts.length;

  // MODIFIÉ : 'currentProductIndex' est maintenant un getter
  int get currentProductIndex => _currentProductIndex;

  Product? get currentProduct => _filteredProducts.isNotEmpty && _currentProductIndex < _filteredProducts.length
      ? _filteredProducts[_currentProductIndex]
      : null;

  // MODIFIÉ : Vérifie la liste complète
  bool get hasUnsyncedData => _allProducts.any((p) => !p.isSynced);

  // --- PERSISTANCE DES DONNÉES LOCALES (Filtres et Index) ---

  /// Sauvegarde uniquement les produits non synchronisés (fonctionne sur _allProducts)
  Future<void> _saveUnsyncedData() async {
    if (_selectedRayon == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'unsynced_data_${_selectedRayon!.id}';

    // MODIFIÉ : Utilise _allProducts
    final unsyncedProducts = _allProducts.where((p) => !p.isSynced).toList();

    if (unsyncedProducts.isEmpty) {
      await prefs.remove(key);
    } else {
      final dataToSave = unsyncedProducts.map((p) => p.toJson()).toList();
      await prefs.setString(key, json.encode(dataToSave));
    }
  }

  /// Charge et fusionne les données non synchronisées avec les données de l'API.
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
        // Le produit n'a pas été trouvé dans la sauvegarde, on garde la version de l'API
      }
      return apiProduct;
    }).toList();

    return mergedProducts;
  }

  /// Sauvegarde la position actuelle pour l'emplacement en cours.
  void _saveCurrentIndex() async {
    if (_selectedRayon != null) {
      _lastIndexByRayon[_selectedRayon!.id] = _currentProductIndex;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastIndex_${_selectedRayon!.id}', _currentProductIndex);
    }
  }

  // NOUVEAU : Sauvegarde le filtre pour l'emplacement en cours
  Future<void> _saveFilter() async {
    if (_selectedRayon != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('filter_${_selectedRayon!.id}', _activeFilter.toRawJson());
    }
  }

  // NOUVEAU : Charge le filtre pour l'emplacement en cours
  Future<ProductFilter> _loadFilter(String rayonId) async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString('filter_$rayonId') ?? '';
    return ProductFilter.fromRawJson(rawJson);
  }

  // --- LOGIQUE DE FILTRAGE ---

  // NOUVEAU : Applique le filtre et réinitialise l'index
  Future<void> applyFilter(ProductFilter newFilter) async {
    _activeFilter = newFilter;
    await _saveFilter();
    _runFilterLogic();
    // Réinitialise l'index au début de la nouvelle liste filtrée
    _currentProductIndex = 0;
    _saveCurrentIndex();
    notifyListeners();
  }

  // NOUVEAU : Exécute la logique de filtrage
  void _runFilterLogic() {
    if (!_activeFilter.isActive) {
      _filteredProducts = List.from(_allProducts);
      return;
    }

    switch (_activeFilter.type) {
      case FilterType.numeric:
        try {
          // 'De' (1-based index) -> 0-based index
          int from = int.parse(_activeFilter.from) - 1;
          int to = int.parse(_activeFilter.to); // 'to' est inclusif

          // Validation des bornes
          if (from < 0) from = 0;
          if (to > _allProducts.length) to = _allProducts.length;
          if (from >= to) {
            _filteredProducts = []; // Ou gérer comme une erreur
            return;
          }

          _filteredProducts = _allProducts.sublist(from, to);
        } catch (e) {
          _filteredProducts = []; // Erreur de parsing
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

  // --- MÉTHODES PUBLIQUES APPELÉES PAR L'INTERFACE ---

  /// Réinitialise l'état du provider.
  void reset() {
    _rayons = [];
    _allProducts = [];
    _filteredProducts = []; // MODIFIÉ
    _selectedRayon = null;
    _currentProductIndex = 0;
    _error = null;
    _hasPendingSession = false;
    _activeFilter = ProductFilter(); // MODIFIÉ
    notifyListeners();
  }

  /// Récupère les emplacements pour un inventaire.
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

  /// Charge les produits pour un emplacement et restaure la position et le filtre.
  Future<void> fetchProducts(ApiService api, String inventoryId, String rayonId) async {
    _isLoading = true;
    _error = null;
    _selectedRayon = _rayons.firstWhere((r) => r.id == rayonId);
    notifyListeners();

    try {
      final apiProducts = await api.fetchProducts(inventoryId, rayonId);
      // MODIFIÉ : Charge dans _allProducts
      _allProducts = await _loadAndMergeUnsyncedData(rayonId, apiProducts);

      // NOUVEAU : Charge et applique le filtre
      _activeFilter = await _loadFilter(rayonId);
      _runFilterLogic(); // Applique le filtre pour générer _filteredProducts

      // MODIFIÉ : Charge l'index
      final lastIndex = _lastIndexByRayon[rayonId] ?? (await SharedPreferences.getInstance()).getInt('lastIndex_$rayonId') ?? 0;

      // Valide l'index par rapport à la liste filtrée
      _currentProductIndex = (lastIndex >= 0 && lastIndex < _filteredProducts.length) ? lastIndex : 0;
      _lastIndexByRayon[rayonId] = _currentProductIndex;

    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Met à jour la quantité et sauvegarde localement.
  Future<void> updateQuantity(String value) async {
    if (currentProduct != null) {
      final int quantity = int.tryParse(value) ?? 0;
      if (quantity >= 0) {

        // MODIFIÉ : Doit mettre à jour la quantité dans les DEUX listes
        final productId = currentProduct!.id;

        // Mise à jour dans la liste filtrée (pour l'UI)
        currentProduct!.quantiteSaisie = quantity;
        currentProduct!.isSynced = false;

        // Mise à jour dans la liste source (_allProducts) (pour la persistance)
        try {
          final productInAll = _allProducts.firstWhere((p) => p.id == productId);
          productInAll.quantiteSaisie = quantity;
          productInAll.isSynced = false;
        } catch (e) {
          // Le produit n'est pas dans la liste complète, c'est un problème
          _error = "Erreur de synchronisation des listes.";
        }

        await _saveUnsyncedData();
        notifyListeners();
      }
    }
  }

  /// Passe au produit suivant (dans la liste filtrée).
  void nextProduct() {
    if (_currentProductIndex < _filteredProducts.length - 1) {
      _currentProductIndex++;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  /// Revient au produit précédent (dans la liste filtrée).
  void previousProduct() {
    if (_currentProductIndex > 0) {
      _currentProductIndex--;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  /// Va au tout premier produit (de la liste filtrée).
  void goToFirstProduct() {
    if (_filteredProducts.isNotEmpty) {
      _currentProductIndex = 0;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  // NOUVEAU : Fait "sauter" l'index au produit sélectionné (par la recherche)
  void jumpToProduct(Product product) {
    // MODIFIÉ : Cherche l'index dans la liste FILTRÉE
    final index = _filteredProducts.indexWhere((p) => p.id == product.id);

    if (index != -1) {
      _currentProductIndex = index;
      _saveCurrentIndex();
      notifyListeners();
    }
  }


  /// Gère l'envoi des données au serveur.
  Future<void> sendDataToServer(ApiService api, [Function(int, int)? onProgress]) async {
    // MODIFIÉ : Doit scanner la liste _allProducts
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

  /// Marque la session en attente comme ayant été notifiée à l'utilisateur.
  void acknowledgedPendingSession() {
    _hasPendingSession = false;
  }
}