// lib/providers/entry_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EntryProvider with ChangeNotifier {
  List<Rayon> _rayons = [];
  List<Product> _products = [];
  Rayon? _selectedRayon;
  int _currentProductIndex = 0;
  bool _isLoading = false;
  String? _error;

  // Pour gérer la session non envoyée
  bool _hasPendingSession = false;

  // --- Getters publics pour l'interface utilisateur ---
  List<Rayon> get rayons => _rayons;
  List<Product> get products => _products;
  Rayon? get selectedRayon => _selectedRayon;
  Product? get currentProduct => _products.isNotEmpty && _currentProductIndex < _products.length ? _products[_currentProductIndex] : null;
  int get currentProductIndex => _currentProductIndex;
  int get totalProducts => _products.length;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasPendingSession => _hasPendingSession;

  /// Indique s'il y a des produits dont la quantité a été modifiée mais pas encore envoyée.
  bool get hasUnsyncedData => _products.any((p) => !p.isSynced);

  // --- PERSISTANCE DES DONNÉES LOCALES ---

  /// Sauvegarde uniquement les produits non synchronisés dans le stockage local.
  Future<void> _saveUnsyncedData() async {
    if (_selectedRayon == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'unsynced_data_${_selectedRayon!.id}';

    final unsyncedProducts = _products.where((p) => !p.isSynced).toList();

    if (unsyncedProducts.isEmpty) {
      await prefs.remove(key); // On nettoie s'il n'y a plus rien à synchroniser
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastIndex_${_selectedRayon!.id}', _currentProductIndex);
    }
  }

  // --- MÉTHODES PUBLIQUES APPELÉES PAR L'INTERFACE ---

  /// Réinitialise l'état du provider.
  void reset() {
    _rayons = [];
    _products = [];
    _selectedRayon = null;
    _currentProductIndex = 0;
    _error = null;
    _hasPendingSession = false;
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

  /// Charge les produits pour un emplacement et restaure la position.
  Future<void> fetchProducts(ApiService api, String inventoryId, String rayonId) async {
    _isLoading = true;
    _error = null;
    _selectedRayon = _rayons.firstWhere((r) => r.id == rayonId);
    notifyListeners();
    try {
      final apiProducts = await api.fetchProducts(inventoryId, rayonId);
      _products = await _loadAndMergeUnsyncedData(rayonId, apiProducts);

      final prefs = await SharedPreferences.getInstance();
      final lastIndex = prefs.getInt('lastIndex_${_selectedRayon!.id}') ?? 0;
      _currentProductIndex = (lastIndex >= 0 && lastIndex < _products.length) ? lastIndex : 0;
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
        currentProduct!.quantiteSaisie = quantity;
        currentProduct!.isSynced = false;
        await _saveUnsyncedData();
        notifyListeners();
      }
    }
  }

  /// Passe au produit suivant.
  void nextProduct() {
    if (_currentProductIndex < _products.length - 1) {
      _currentProductIndex++;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  /// Revient au produit précédent.
  void previousProduct() {
    if (_currentProductIndex > 0) {
      _currentProductIndex--;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  /// Va au tout premier produit de la liste.
  void goToFirstProduct() {
    if (_products.isNotEmpty) {
      _currentProductIndex = 0;
      _saveCurrentIndex();
      notifyListeners();
    }
  }

  /// Gère l'envoi des données au serveur.
  Future<void> sendDataToServer(ApiService api, [Function(int, int)? onProgress]) async {
    List<Product> unsyncedProducts = _products.where((p) => !p.isSynced).toList();
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