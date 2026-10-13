// lib/providers/license_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/license.dart';
import 'package:prestinv/utils/journal.dart';

/// [unreachable] : serveur injoignable au premier lancement (aucune licence en cache) — ce n'est PAS
/// un problème de licence ; écran « Serveur injoignable » avec réessai automatique (avant : écran
/// « Application non activée »).
enum LicenseStatus { loading, valid, expired, none, error, unreachable }

class LicenseProvider with ChangeNotifier {
  License? _license;
  LicenseStatus _status = LicenseStatus.loading;
  String? _error;

  License? get license => _license;
  LicenseStatus get status => _status;
  String? get error => _error;

  /// Tests : pose une licence connue sans appel réseau.
  @visibleForTesting
  void setLicenseForTest(License license) {
    _license = license;
    _error = null;
    _updateStatus();
    notifyListeners();
  }

  /// Retourne le nombre de jours restants avant expiration
  int get daysRemaining {
    if (_license == null) return 0;
    final now = DateTime.now();
    // On compare les dates pures sans les heures/minutes
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(_license!.dateEnd.year, _license!.dateEnd.month, _license!.dateEnd.day);
    return end.difference(today).inDays;
  }

  /// Vérifie la licence (serveur, puis cache si le serveur ne répond pas).
  ///
  /// [silent] (retour au premier plan) : pas de passage par l'état « chargement » — l'écran en cours
  /// n'est plus remplacé par un sablier à chaque retour dans l'application.
  Future<void> checkLicense(ApiService api, {bool silent = false}) async {
    final silencieux = silent && (_status == LicenseStatus.valid || _status == LicenseStatus.expired);
    if (!silencieux) {
      _status = LicenseStatus.loading;
      _error = null;
      notifyListeners();
    }

    try {
      // 1. Priorité au serveur (Mise à jour date fin, renouvellement...)
      final onlineLicense = await api.findLicense();
      _license = onlineLicense;
      _error = null;
      await _cacheLicense(onlineLicense); // Mise à jour du cache
      _updateStatus();
    } catch (e) {
      journal('Licence non lue sur le serveur ($e) : repli sur la licence en cache.');
      final reseau = e is ApiLoadException && e.reseau;
      // 2. Repli sur le cache local
      final cached = await _loadCachedLicense();
      if (cached != null) {
        _license = cached;
        _updateStatus();
      } else if (reseau) {
        // Premier lancement sans joindre le serveur : on ne sait rien de la licence.
        _status = LicenseStatus.unreachable;
        _error = e.message;
      } else {
        // Le serveur a répondu mais sans licence valide.
        _status = LicenseStatus.none;
        _error = "Aucune licence valide n'a été trouvée sur le serveur.";
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