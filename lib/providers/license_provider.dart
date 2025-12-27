// lib/providers/license_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/license.dart';

enum LicenseStatus { loading, valid, expired, none, error }

class LicenseProvider with ChangeNotifier {
  License? _license;
  LicenseStatus _status = LicenseStatus.loading;
  String? _error;

  License? get license => _license;
  LicenseStatus get status => _status;
  String? get error => _error;

  /// Retourne le nombre de jours restants avant expiration
  int get daysRemaining {
    if (_license == null) return 0;
    final now = DateTime.now();
    // On compare les dates pures sans les heures/minutes
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(_license!.dateEnd.year, _license!.dateEnd.month, _license!.dateEnd.day);
    return end.difference(today).inDays;
  }

  /// Vérifie la licence (Serveur puis Cache si échec)
  Future<void> checkLicense(ApiService api) async {
    _status = LicenseStatus.loading;
    _error = null;
    notifyListeners();

    try {
      // 1. Priorité au serveur (Mise à jour date fin, renouvellement...)
      final onlineLicense = await api.findLicense();
      _license = onlineLicense;
      await _cacheLicense(onlineLicense); // Mise à jour du cache
      _updateStatus();
    } catch (e) {
      print("Erreur licence ligne : $e. Passage en mode HORS-LIGNE.");
      // 2. Repli sur le cache local
      final cached = await _loadCachedLicense();
      if (cached != null) {
        _license = cached;
        _updateStatus();
      } else {
        // Pas de cache et pas de réseau = On ne peut pas valider -> État 'none' ou 'error'
        _status = LicenseStatus.none;
        _error = "Impossible de vérifier la licence (Premier démarrage sans réseau ?)";
      }
    }
    notifyListeners();
  }

  /// Tente d'enregistrer une nouvelle clé
  Future<bool> registerLicense(ApiService api, String key) async {
    try {
      final success = await api.saveLicense(key);
      if (success) {
        await checkLicense(api); // Re-vérifie immédiatement pour mettre à jour l'état
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void _updateStatus() {
    if (_license == null) {
      _status = LicenseStatus.none;
    } else {
      _status = daysRemaining >= 0 ? LicenseStatus.valid : LicenseStatus.expired;
    }
  }

  // --- Gestion du Cache (SharedPreferences) ---

  Future<void> _cacheLicense(License l) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_license', json.encode(l.toJson()));
  }

  Future<License?> _loadCachedLicense() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('cached_license');
    if (jsonStr != null) {
      try {
        return License.fromJson(json.decode(jsonStr));
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}