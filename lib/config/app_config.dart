// lib/config/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ApiMode { local, distant }

class AppConfig extends ChangeNotifier {
  late SharedPreferences _prefs;

  // --- Paramètres de Connexion API ---
  String _localApiAddress = '';
  String _localApiPort = '8080';
  String _distantApiAddress = '';
  String _distantApiPort = '8080';
  ApiMode _apiMode = ApiMode.local;

  // --- Paramètres de l'Application ---
  int _maxResult = 3;
  bool _showTheoreticalStock = true;
  int _largeValueThreshold = 1000;
  int _autoLogoutMinutes = 0; // 0 = désactivé

  // --- Getters publics pour accéder aux valeurs ---
  String get localApiAddress => _localApiAddress;
  String get localApiPort => _localApiPort;
  String get distantApiAddress => _distantApiAddress;
  String get distantApiPort => _distantApiPort;
  ApiMode get apiMode => _apiMode;
  int get maxResult => _maxResult;
  bool get showTheoreticalStock => _showTheoreticalStock;
  int get largeValueThreshold => _largeValueThreshold;
  int get autoLogoutMinutes => _autoLogoutMinutes;

  /// Construit l'URL complète actuelle en fonction du mode (Local/Distant)
  String get currentApiUrl {
    String address;
    String port;

    if (_apiMode == ApiMode.local) {
      address = _localApiAddress;
      port = _localApiPort;
    } else {
      address = _distantApiAddress;
      port = _distantApiPort;
    }

    if (address.isEmpty) return '';

    String url = address.startsWith('http') ? address : 'http://$address';

    if (port.isNotEmpty) {
      url += ':$port';
    }

    return url;
  }

  /// Charge toutes les préférences depuis le stockage local au démarrage de l'app
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    _localApiAddress = _prefs.getString('localApiAddress') ?? '';
    _localApiPort = _prefs.getString('localApiPort') ?? '8080';
    _distantApiAddress = _prefs.getString('distantApiAddress') ?? '';
    _distantApiPort = _prefs.getString('distantApiPort') ?? '8080';

    _maxResult = _prefs.getInt('maxResult') ?? 3;
    _showTheoreticalStock = _prefs.getBool('showTheoreticalStock') ?? true;
    _largeValueThreshold = _prefs.getInt('largeValueThreshold') ?? 1000;
    _autoLogoutMinutes = _prefs.getInt('autoLogoutMinutes') ?? 0;
  }

  /// Sauvegarde les paramètres de connexion API
  Future<void> setApiConfig({
    String? localAddress, String? localPort,
    String? distantAddress, String? distantPort
  }) async {
    _localApiAddress = localAddress ?? _localApiAddress;
    _localApiPort = localPort ?? _localApiPort;
    _distantApiAddress = distantAddress ?? _distantApiAddress;
    _distantApiPort = distantPort ?? _distantApiPort;

    await _prefs.setString('localApiAddress', _localApiAddress);
    await _prefs.setString('localApiPort', _localApiPort);
    await _prefs.setString('distantApiAddress', _distantApiAddress);
    await _prefs.setString('distantApiPort', _distantApiPort);

    notifyListeners();
  }

  /// Sauvegarde les paramètres généraux de l'application
  Future<void> setAppSettings({int? maxResult, bool? showStock, int? largeValue, int? logoutMinutes}) async {
    if (maxResult != null) {
      _maxResult = maxResult;
      await _prefs.setInt('maxResult', maxResult);
    }
    if (showStock != null) {
      _showTheoreticalStock = showStock;
      await _prefs.setBool('showTheoreticalStock', showStock);
    }
    if (largeValue != null) {
      _largeValueThreshold = largeValue;
      await _prefs.setInt('largeValueThreshold', largeValue);
    }
    if (logoutMinutes != null) {
      _autoLogoutMinutes = logoutMinutes;
      await _prefs.setInt('autoLogoutMinutes', logoutMinutes);
    }
    notifyListeners();
  }

  /// Change le mode de connexion API (Local/Distant)
  void setApiMode(ApiMode mode) {
    if (_apiMode != mode) {
      _apiMode = mode;
      notifyListeners();
    }
  }
}