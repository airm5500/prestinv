// lib/providers/inventory_provider.dart

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/inventory.dart';
import '../models/collected_item.dart';

class InventoryProvider with ChangeNotifier {
  List<Inventory> _inventories = [];
  bool _isLoading = false;
  String? _error;

  List<Inventory> get inventories => _inventories;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // --- MODIFICATION DE LA SIGNATURE DE LA METHODE ---
  // On ajoute le paramètre optionnel {int maxResult = 3}
  Future<void> fetchInventories(ApiService api, {int maxResult = 3}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // --- MODIFICATION DE L'APPEL A L'API ---
      // On passe le paramètre maxResult à l'appel de l'API
      _inventories = await api.fetchInventories(maxResult: maxResult);
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

}