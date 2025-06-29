// lib/providers/auth_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/user.dart';
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

  Future<void> loadUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberMe = prefs.getBool('rememberMe') ?? false;

    // NOTE: On ne charge plus de session au démarrage.
    // L'utilisateur devra toujours se reconnecter.
    // Cette méthode ne sert plus qu'à pré-charger l'état de "rememberMe".
    notifyListeners();
  }

  Future<bool> login(String login, String password, AppConfig appConfig) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final url = Uri.parse('${appConfig.currentApiUrl}/laborex/api/v1/user/auth');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'login': login, 'password': password}),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          _user = AppUser.fromJson(responseData);
          _isLoggedIn = true;
          _parseAndSetCookie(response); // On met le cookie en mémoire, sans le sauvegarder

          final prefs = await SharedPreferences.getInstance();
          if (_rememberMe) {
            await prefs.setString('savedLogin', login);
            await prefs.setString('savedPassword', password);
          } else {
            await prefs.remove('savedLogin');
            await prefs.remove('savedPassword');
          }

          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _errorMessage = "Identifiant ou mot de passe incorrect.";
        }
      } else {
        _errorMessage = "Erreur serveur (${response.statusCode})";
      }
    } catch (e) {
      _errorMessage = "Erreur de connexion. Vérifiez le réseau et l'adresse du serveur.";
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // La méthode ne sauvegarde plus le cookie, elle le met juste en mémoire
  void _parseAndSetCookie(http.Response response) {
    final rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      _sessionCookie = rawCookie.split(';').firstWhere((c) => c.trim().startsWith('JSESSIONID'));
    }
  }

  Future<void> setRememberMe(bool value) async {
    _rememberMe = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rememberMe', value);
    if (!value) {
      await prefs.remove('savedLogin');
      await prefs.remove('savedPassword');
    }
    notifyListeners();
  }

  Future<void> logout(AppConfig appConfig) async {
    final url = Uri.parse('${appConfig.currentApiUrl}/laborex/api/v1/user/logout');
    if (_sessionCookie != null) {
      await http.post(url, headers: {'Cookie': _sessionCookie!});
    }

    _user = null;
    _sessionCookie = null;
    _isLoggedIn = false;

    // On ne supprime plus de cookie du stockage car il n'y est plus
    final prefs = await SharedPreferences.getInstance();
    if (!rememberMe) {
      await prefs.remove('savedLogin');
      await prefs.remove('savedPassword');
    }

    notifyListeners();
  }
}