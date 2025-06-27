// lib/config/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ApiMode { local, distant }

class AppConfig extends ChangeNotifier {
  late SharedPreferences _prefs;

  String _localApiUrl = '';
  String _distantApiUrl = '';
  ApiMode _apiMode = ApiMode.local;

  // --- NOUVEAUX PARAMETRES ---
  int _maxResult = 3; // Valeur par défaut
  bool _showTheoreticalStock = true; // Valeur par défaut

  // --- METHODE DE CHARGEMENT MISE A JOUR ---
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _localApiUrl = _prefs.getString('localApiUrl') ?? '';
    _distantApiUrl = _prefs.getString('distantApiUrl') ?? '';
    // Charger les nouvelles valeurs
    _maxResult = _prefs.getInt('maxResult') ?? 3;
    _showTheoreticalStock = _prefs.getBool('showTheoreticalStock') ?? true;
  }

  // Getters pour les nouvelles valeurs
  String get localApiUrl => _localApiUrl;
  String get distantApiUrl => _distantApiUrl;
  ApiMode get apiMode => _apiMode;
  int get maxResult => _maxResult;
  bool get showTheoreticalStock => _showTheoreticalStock;

  String get currentApiUrl {
    return _apiMode == ApiMode.local ? _localApiUrl : _distantApiUrl;
  }

  Future<void> setApiUrls(String localUrl, String distantUrl) async {
    _localApiUrl = localUrl;
    _distantApiUrl = distantUrl;
    await _prefs.setString('localApiUrl', localUrl);
    await _prefs.setString('distantApiUrl', distantUrl);
    notifyListeners();
  }

  // --- NOUVELLE METHODE POUR SAUVEGARDER LES PARAMETRES ---
  Future<void> setAppSettings({int? maxResult, bool? showStock}) async {
    if (maxResult != null) {
      _maxResult = maxResult;
      await _prefs.setInt('maxResult', maxResult);
    }
    if (showStock != null) {
      _showTheoreticalStock = showStock;
      await _prefs.setBool('showTheoreticalStock', showStock);
    }
    notifyListeners();
  }

  void setApiMode(ApiMode mode) {
    if (_apiMode != mode) {
      _apiMode = mode;
      notifyListeners();
    }
  }
}