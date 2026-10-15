// lib/providers/auth_provider.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/user.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  AppUser? _user;
  String? _sessionCookie;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _rememberMe = false;

  AppUser? get user => _user;
  String? get sessionCookie => _sessionCookie;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get rememberMe => _rememberMe;

  AuthProvider() {
    loadUserFromStorage();
  }

  /// Tests : session ouverte sans appel réseau.
  @visibleForTesting
  void connecterPourTest(
      {String login = 'test',
      String cookie = 'JSESSIONID=test',
      String? prenom,
      String nom = '',
      String officine = '',
      String? typeAccueil = 'dashboard',
      bool? droitCreation}) {
    _user = AppUser(
        id: login, login: login, firstName: prenom ?? login, lastName: nom, officine: officine, typeAccueil: typeAccueil, droitCreation: droitCreation);
    _sessionCookie = cookie;
    _isLoggedIn = true;
    notifyListeners();
  }

  Future<void> loadUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberMe = prefs.getBool('rememberMe') ?? false;
    notifyListeners();
  }

  Future<bool> login(String login, String password, AppConfig appConfig) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // CORRECTION : On retire "/laborex" qui est maintenant dans currentApiUrl
    final url = Uri.parse('${appConfig.currentApiUrl}/api/v1/user/auth');

    try {
      final client = ApiService.clientParDefaut;
      final headers = {'Content-Type': 'application/json'};
      final body = json.encode({'login': login, 'password': password});
      final response = await (client != null ? client.post(url, headers: headers, body: body) : http.post(url, headers: headers, body: body))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          _user = AppUser.fromJson(responseData);
          _isLoggedIn = true;
          // 4.15 : serveur à jour (réponse avec `role` / `droits`, demande 10) → routes récentes essayées.
          ApiService.noterServeur(appConfig.currentApiUrl, recent: responseData['droits'] is Map || responseData['role'] is Map);
          _parseAndSetCookie(response);

          // « Rester connecté » : identifiant dans les préférences, mot de passe dans le stockage
          // SÉCURISÉ (plus jamais en clair). Le cookie de session reste en mémoire seulement.
          final prefs = await SharedPreferences.getInstance();
          if (_rememberMe) {
            await prefs.setString('savedLogin', login);
            await IdentifiantsSecurises.instance.ecrire(password);
          } else {
            await prefs.remove('savedLogin');
            await IdentifiantsSecurises.instance.effacer();
          }

          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _errorMessage = "Identifiant ou mot de passe incorrect.";
        }
      } else if (ApiService.serveurIndisponible(response)) {
        // 4.15.3 (retour du pharmacien), cas 2 : le serveur répond mais Prestige n'est pas déployé (404 HTML /
        // vide de Payara, 502 / 503 / 504) — et non « erreur 404 ».
        _errorMessage = ApiService.messageIndisponible;
      } else {
        _errorMessage = "Erreur serveur (${response.statusCode})";
      }
    } on TimeoutException {
      // 4.15.3, cas 1 : aucune réponse.
      _errorMessage = ApiService.messageInjoignable;
    } catch (e) {
      // 4.14.2 : certificat HTTPS refusé ≠ réseau. 4.15.3, cas 1 : hôte ou réseau inaccessible, connexion refusée
      // (PC serveur éteint, Payara arrêté).
      _errorMessage = ApiService.estCertificatRefuse(e) ? ApiService.messageCertificat : ApiService.messageInjoignable;
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  void _parseAndSetCookie(http.Response response) {
    final rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      // Plusieurs cookies possibles (séparés par « ; » ou « , ») : on garde JSESSIONID s'il est là.
      final morceaux = rawCookie.split(RegExp(r'[;,]')).map((c) => c.trim());
      final session = morceaux.where((c) => c.startsWith('JSESSIONID=')).firstOrNull;
      if (session != null) _sessionCookie = session;
    }
  }

  Future<void> setRememberMe(bool value) async {
    _rememberMe = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rememberMe', value);
    if (!value) {
      await prefs.remove('savedLogin');
      await IdentifiantsSecurises.instance.effacer();
    }
    notifyListeners();
  }

  Future<void> logout(AppConfig appConfig) async {
    // CORRECTION : On retire "/laborex" qui est maintenant dans currentApiUrl
    final url = Uri.parse('${appConfig.currentApiUrl}/api/v1/user/logout');
    if (_sessionCookie != null) {
      // Réseau coupé : on se déconnecte quand même sur l'appareil (avant : impossible de se déconnecter).
      try {
        final client = ApiService.clientParDefaut;
        final headers = {'Cookie': _sessionCookie!};
        await (client != null ? client.post(url, headers: headers) : http.post(url, headers: headers)).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    _user = null;
    _sessionCookie = null;
    _isLoggedIn = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sessionCookie');
    if (!rememberMe) {
      await prefs.remove('savedLogin');
      await IdentifiantsSecurises.instance.effacer();
    }

    notifyListeners();
  }
}
