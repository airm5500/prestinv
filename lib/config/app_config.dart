// lib/config/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Énumérations pour des choix clairs et sûrs
enum ApiMode { local, distant }
enum SendMode { direct, collect }

class AppConfig with ChangeNotifier {
  late SharedPreferences _prefs;

  // --- Paramètres de Connexion API ---
  String _localApiAddress = '192.168.1.50';
  String _localApiPort = '8080';
  String _distantApiAddress = '';
  String _distantApiPort = '8080';
  ApiMode _apiMode = ApiMode.local;
  String _appName = 'prestige';

  // --- Paramètres de l'Application ---
  int _maxResult = 3;
  bool _showTheoreticalStock = true;
  int _largeValueThreshold = 1000;
  int _autoLogoutMinutes = 0; // 0 = désactivé
  String _networkExportPath = '';
  // Nouvelle installation : Direct (envoi immédiat, la file persistante sert de secours).
  SendMode _sendMode = SendMode.direct;
  int _sendReminderMinutes = 15; // 0 = désactivé

  // CORRECTION : Variable d'instance privée (pas de static)
  bool _isCumulEnabled = false;

  // --- Scan (douchette) ---
  bool _sonScan = true;
  bool _vibrationScan = true;
  // Quantité proposée dans la fenêtre de quantité après un scan (null : aucune, saisie obligatoire).
  int? _quantiteScanDefaut = quantiteScanDefautInitiale;

  /// Quantité proposée après un scan sur une nouvelle installation (et tant que rien n'est réglé).
  static const int quantiteScanDefautInitiale = 1;

  // --- Getters publics pour un accès sécurisé depuis l'UI ---
  String get localApiAddress => _localApiAddress;
  String get localApiPort => _localApiPort;
  String get distantApiAddress => _distantApiAddress;
  String get distantApiPort => _distantApiPort;
  ApiMode get apiMode => _apiMode;
  String get appName => _appName;
  int get maxResult => _maxResult;
  bool get showTheoreticalStock => _showTheoreticalStock;
  int get largeValueThreshold => _largeValueThreshold;
  int get autoLogoutMinutes => _autoLogoutMinutes;
  String get networkExportPath => _networkExportPath;
  SendMode get sendMode => _sendMode;
  int get sendReminderMinutes => _sendReminderMinutes;

  // CORRECTION : Getter public ajouté
  bool get isCumulEnabled => _isCumulEnabled;

  /// Bip après un scan (succès / déjà compté / erreur).
  bool get sonScan => _sonScan;

  /// Vibration après un scan.
  bool get vibrationScan => _vibrationScan;

  /// Quantité proposée après un scan (null : aucune).
  int? get quantiteScanDefaut => _quantiteScanDefaut;

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

    address = address.trim();
    if (address.isEmpty) return '';
    while (address.endsWith('/')) {
      address = address.substring(0, address.length - 1);
    }

    // « http:// » par défaut ; « https:// » accepté s'il est saisi (non imposé).
    String url = RegExp(r'^https?://', caseSensitive: false).hasMatch(address) ? address : 'http://$address';

    if (port.isNotEmpty) {
      url += ':$port';
    }

    // On ajoute le nom de l'application (contexte) à la fin
    if (_appName.isNotEmpty) {
      url += '/$_appName';
    }

    return url;
  }

  /// Charge toutes les préférences depuis le stockage local au démarrage de l'app.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    _localApiAddress = _prefs.getString('localApiAddress') ?? '192.168.1.50';
    _localApiPort = _prefs.getString('localApiPort') ?? '8080';
    _distantApiAddress = _prefs.getString('distantApiAddress') ?? '';
    _distantApiPort = _prefs.getString('distantApiPort') ?? '8080';
    _appName = _prefs.getString('appName') ?? 'prestige';

    _maxResult = _prefs.getInt('maxResult') ?? 5;
    _showTheoreticalStock = _prefs.getBool('showTheoreticalStock') ?? true;
    _largeValueThreshold = _prefs.getInt('largeValueThreshold') ?? 1000;
    _autoLogoutMinutes = _prefs.getInt('autoLogoutMinutes') ?? 0;
    _networkExportPath = _prefs.getString('networkExportPath') ?? '';
    _sendReminderMinutes = _prefs.getInt('sendReminderMinutes') ?? 15;

    // CORRECTION : Chargement correct de la variable
    _isCumulEnabled = _prefs.getBool('isCumulEnabled') ?? false;

    _sonScan = _prefs.getBool('scanSon') ?? true;
    _vibrationScan = _prefs.getBool('scanVibration') ?? true;
    final qDefaut = _prefs.getInt('scanQuantiteDefaut');
    _quantiteScanDefaut = qDefaut == null
        ? quantiteScanDefautInitiale
        : (qDefaut >= 1 && qDefaut <= 99999 ? qDefaut : null);

    // On charge les énumérations à partir de leur index stocké (valeur abîmée : valeur par défaut)
    final apiModeIndex = _prefs.getInt('apiMode') ?? ApiMode.local.index;
    _apiMode = ApiMode.values[(apiModeIndex >= 0 && apiModeIndex < ApiMode.values.length) ? apiModeIndex : 0];
    _sendMode = await _chargerModeEnvoi(_prefs);

    notifyListeners();
  }

  /// Clés qui prouvent que l'application a déjà été utilisée sur cet appareil (versions précédentes).
  static const _clesInstallationExistante = [
    'localApiAddress', 'localApiPort', 'distantApiAddress', 'distantApiPort', 'appName', 'apiMode',
    'maxResult', 'showTheoreticalStock', 'largeValueThreshold', 'autoLogoutMinutes', 'networkExportPath',
    'sendReminderMinutes', 'isCumulEnabled', 'rememberMe', 'savedLogin', 'savedPassword', 'cached_license',
    'collection_data',
  ];

  static bool installationExistante(SharedPreferences prefs) {
    final cles = prefs.getKeys();
    return _clesInstallationExistante.any(cles.contains) ||
        cles.any((k) => k.startsWith('inv_') || k.startsWith('cumul_logs_'));
  }

  /// Mode d'envoi :
  /// - choix déjà enregistré : conservé tel quel ;
  /// - application déjà utilisée SANS choix enregistré (elle tournait donc en Collecte, l'ancien défaut) :
  ///   Collecte est gardé et enregistré — rien ne change pour l'utilisateur existant ;
  /// - nouvelle installation : Direct (nouveau défaut), enregistré.
  static Future<SendMode> _chargerModeEnvoi(SharedPreferences prefs) async {
    final stocke = prefs.getInt('sendMode');
    if (stocke != null && stocke >= 0 && stocke < SendMode.values.length) return SendMode.values[stocke];
    final mode = installationExistante(prefs) ? SendMode.collect : SendMode.direct;
    try {
      await prefs.setInt('sendMode', mode.index);
    } catch (_) {}
    return mode;
  }

  /// Sauvegarde les paramètres de connexion API.
  Future<void> setApiConfig({
    String? localAddress, String? localPort,
    String? distantAddress, String? distantPort,
    String? appName,
  }) async {
    _localApiAddress = localAddress ?? _localApiAddress;
    _localApiPort = localPort ?? _localApiPort;
    _distantApiAddress = distantAddress ?? _distantApiAddress;
    _distantApiPort = distantPort ?? _distantApiPort;
    _appName = appName ?? _appName;

    await _prefs.setString('localApiAddress', _localApiAddress);
    await _prefs.setString('localApiPort', _localApiPort);
    await _prefs.setString('distantApiAddress', _distantApiAddress);
    await _prefs.setString('distantApiPort', _distantApiPort);
    await _prefs.setString('appName', _appName);

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
    bool? isCumulEnabled,
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
    // CORRECTION : Sauvegarde de la variable d'instance
    if (isCumulEnabled != null) {
      _isCumulEnabled = isCumulEnabled;
      await _prefs.setBool('isCumulEnabled', isCumulEnabled);
    }
    notifyListeners();
  }

  /// Réglages du scan : son, vibration, quantité proposée ([aucuneQuantite] : plus de quantité proposée).
  Future<void> setScanSettings({bool? son, bool? vibration, int? quantiteDefaut, bool aucuneQuantite = false}) async {
    if (son != null) {
      _sonScan = son;
      await _prefs.setBool('scanSon', son);
    }
    if (vibration != null) {
      _vibrationScan = vibration;
      await _prefs.setBool('scanVibration', vibration);
    }
    if (aucuneQuantite) {
      _quantiteScanDefaut = null;
      await _prefs.setInt('scanQuantiteDefaut', -1);
    } else if (quantiteDefaut != null && quantiteDefaut >= 1 && quantiteDefaut <= 99999) {
      _quantiteScanDefaut = quantiteDefaut;
      await _prefs.setInt('scanQuantiteDefaut', quantiteDefaut);
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