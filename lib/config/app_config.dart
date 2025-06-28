// lib/config/app_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ApiMode { local, distant }

class AppConfig extends ChangeNotifier {
  late SharedPreferences _prefs;

  // MODIFICATION: On stocke maintenant l'adresse et le port séparément
  String _localApiAddress = '';
  String _localApiPort = '8080'; // Port par défaut
  String _distantApiAddress = '';
  String _distantApiPort = '8080'; // Port par défaut

  ApiMode _apiMode = ApiMode.local;
  int _maxResult = 3;
  bool _showTheoreticalStock = true;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    // Charger les nouvelles valeurs séparées
    _localApiAddress = _prefs.getString('localApiAddress') ?? '';
    _localApiPort = _prefs.getString('localApiPort') ?? '8080';
    _distantApiAddress = _prefs.getString('distantApiAddress') ?? '';
    _distantApiPort = _prefs.getString('distantApiPort') ?? '8080';

    _maxResult = _prefs.getInt('maxResult') ?? 3;
    _showTheoreticalStock = _prefs.getBool('showTheoreticalStock') ?? true;
  }

  // Getters pour les nouvelles valeurs
  String get localApiAddress => _localApiAddress;
  String get localApiPort => _localApiPort;
  String get distantApiAddress => _distantApiAddress;
  String get distantApiPort => _distantApiPort;

  ApiMode get apiMode => _apiMode;
  int get maxResult => _maxResult;
  bool get showTheoreticalStock => _showTheoreticalStock;

  // MODIFICATION: L'URL complète est maintenant construite à la volée
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

    // On s'assure que le préfixe http:// est là
    String url = address.startsWith('http') ? address : 'http://$address';

    // On ajoute le port s'il est renseigné
    if (port.isNotEmpty) {
      url += ':$port';
    }

    return url;
  }

  // MODIFICATION: Nouvelle méthode pour sauvegarder la config API
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