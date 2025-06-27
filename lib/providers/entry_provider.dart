// lib/providers/entry_provider.dart

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';

class EntryProvider with ChangeNotifier {
  List<Rayon> _rayons = [];
  List<Product> _products = [];
  Rayon? _selectedRayon;
  int _currentProductIndex = 0;

  bool _isLoading = false;
  String? _error;

  List<Rayon> get rayons => _rayons;
  List<Product> get products => _products;
  Rayon? get selectedRayon => _selectedRayon;
  Product? get currentProduct => _products.isNotEmpty ? _products[_currentProductIndex] : null;
  int get currentProductIndex => _currentProductIndex;
  int get totalProducts => _products.length;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // MODIFICATION: La logique de chargement automatique est ajoutée ici
  Future<void> fetchRayons(ApiService api, String inventoryId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _rayons = await api.fetchRayons(inventoryId);

      // Si un seul emplacement est retourné, on le sélectionne
      // et on charge ses produits automatiquement.
      if (_rayons.length == 1) {
        _selectedRayon = _rayons.first;
        // On appelle la logique de fetchProducts directement depuis ici
        _products = await api.fetchProducts(inventoryId, _selectedRayon!.id);
        _currentProductIndex = 0;
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
      _products = await api.fetchProducts(inventoryId, rayonId);
      _currentProductIndex = 0;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  void updateQuantity(String value) {
    if (currentProduct != null) {
      final int quantity = int.tryParse(value) ?? 0;
      if (quantity >= 0) {
        currentProduct!.quantiteSaisie = quantity;
        currentProduct!.isSynced = false;
        notifyListeners();
      }
    }
  }

  void nextProduct() {
    if (_currentProductIndex < _products.length - 1) {
      _currentProductIndex++;
      notifyListeners();
    }
  }

  void previousProduct() {
    if (_currentProductIndex > 0) {
      _currentProductIndex--;
      notifyListeners();
    }
  }

  Future<void> sendDataToServer(ApiService api) async {
    _isLoading = true;
    notifyListeners();

    List<Product> unsyncedProducts = _products.where((p) => !p.isSynced).toList();

    for (var product in unsyncedProducts) {
      bool success = await api.updateProductQuantity(product.id, product.quantiteSaisie);
      if(success) {
        product.isSynced = true;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  void reset() {
    _rayons = [];
    _products = [];
    _selectedRayon = null;
    _currentProductIndex = 0;
    _error = null;
  }
}