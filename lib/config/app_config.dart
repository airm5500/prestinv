// lib/config/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Énumérations pour des choix clairs et sûrs
enum ApiMode { local, distant }
enum SendMode { direct, collect }

class AppConfig with ChangeNotifier {
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
  String _networkExportPath = '';
  SendMode _sendMode = SendMode.collect;
  int _sendReminderMinutes = 15; // 0 = désactivé

  // --- Getters publics pour un accès sécurisé depuis l'UI ---
  String get localApiAddress => _localApiAddress;
  String get localApiPort => _localApiPort;
  String get distantApiAddress => _distantApiAddress;
  String get distantApiPort => _distantApiPort;
  ApiMode get apiMode => _apiMode;
  int get maxResult => _maxResult;
  bool get showTheoreticalStock => _showTheoreticalStock;
  int get largeValueThreshold => _largeValueThreshold;
  int get autoLogoutMinutes => _autoLogoutMinutes;
  String get networkExportPath => _networkExportPath;
  SendMode get sendMode => _sendMode;
  int get sendReminderMinutes => _sendReminderMinutes;

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

    // Assure que l'URL a bien le préfixe http://
    String url = address.startsWith('http') ? address : 'http://$address';

    if (port.isNotEmpty) {
      url += ':$port';
    }

    return url;
  }

  /// Charge toutes les préférences depuis le stockage local au démarrage de l'app.
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
    _networkExportPath = _prefs.getString('networkExportPath') ?? '';
    _sendReminderMinutes = _prefs.getInt('sendReminderMinutes') ?? 15;

    // On charge les énumérations à partir de leur index stocké
    _apiMode = ApiMode.values[_prefs.getInt('apiMode') ?? ApiMode.local.index];
    _sendMode = SendMode.values[_prefs.getInt('sendMode') ?? SendMode.collect.index];
  }

  /// Sauvegarde les paramètres de connexion API.
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

  /// Sauvegarde les paramètres généraux de l'application.
  Future<void> setAppSettings({
    int? maxResult,
    bool? showStock,
    int? largeValue,
    int? logoutMinutes,
    String? exportPath,
    int? sendReminderMinutes,
  }) async {
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
    if (exportPath != null) {
      _networkExportPath = exportPath;
      await _prefs.setString('networkExportPath', exportPath);
    }
    if (sendReminderMinutes != null) {
      _sendReminderMinutes = sendReminderMinutes;
      await _prefs.setInt('sendReminderMinutes', sendReminderMinutes);
    }
    notifyListeners();
  }

  /// Change et sauvegarde le mode de connexion API (Local/Distant).
  Future<void> setApiMode(ApiMode mode) async {
    if (_apiMode != mode) {
      _apiMode = mode;
      await _prefs.setInt('apiMode', mode.index);
      notifyListeners();
    }
  }

  /// Change et sauvegarde le mode d'envoi des données.
  Future<void> setSendMode(SendMode newMode) async {
    if (_sendMode != newMode) {
      _sendMode = newMode;
      await _prefs.setInt('sendMode', newMode.index);
      notifyListeners();
    }
  }
}
