// lib/services/identifiants_securises.dart
// Mot de passe mémorisé (« Rester connecté ») : gardé dans le stockage sécurisé d'Android
// (flutter_secure_storage, chiffré par le Keystore, exclu des sauvegardes — res/xml/regles_*.xml) et
// non plus en clair dans SharedPreferences (ancienne clé `savedPassword`). Même principe que
// IdentifiantsSecurises de prestige_vente_app.
//
// MIGRATION transparente : si l'ancienne clé en clair existe, elle est copiée dans le stockage sûr, la
// copie est relue et vérifiée, puis la clé en clair est SUPPRIMÉE. Si le stockage sûr échoue (Keystore
// indisponible…), l'ancien comportement est gardé (connexion automatique conservée) et la migration
// est retentée au lancement suivant. Le mot de passe n'apparaît jamais dans le journal.
//
// Le cookie de session n'est jamais écrit sur l'appareil (gardé en mémoire seulement).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:prestinv/utils/journal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage sûr d'une valeur (remplaçable dans les tests pour simuler une panne du Keystore).
abstract class CoffreIdentifiants {
  Future<String?> lire(String cle);
  Future<void> ecrire(String cle, String valeur);
  Future<void> effacer(String cle);
}

/// Stockage sécurisé Android (Keystore) via flutter_secure_storage.
class CoffreIdentifiantsSecurise implements CoffreIdentifiants {
  final FlutterSecureStorage _s;
  const CoffreIdentifiantsSecurise([this._s = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))]);

  @override
  Future<String?> lire(String cle) => _s.read(key: cle);
  @override
  Future<void> ecrire(String cle, String valeur) => _s.write(key: cle, value: valeur);
  @override
  Future<void> effacer(String cle) => _s.delete(key: cle);
}

class IdentifiantsSecurises {
  /// Ancienne clé, en clair dans SharedPreferences (lue seulement pour la migration / le repli).
  static const cleClaire = 'savedPassword';

  /// Clé dans le stockage sécurisé.
  static const cleSure = 'prestinv_mot_de_passe_v1';

  static const delai = Duration(seconds: 5);

  final CoffreIdentifiants coffre;

  IdentifiantsSecurises({CoffreIdentifiants? coffre}) : coffre = coffre ?? const CoffreIdentifiantsSecurise();

  /// Instance de l'appli (remplaçable dans les tests).
  static IdentifiantsSecurises instance = IdentifiantsSecurises();

  bool _migre = false;
  Future<bool>? _migrationEnCours;

  /// Migre l'ancienne clé en clair vers le stockage sûr. `true` si plus aucun mot de passe n'est en
  /// clair. N'échoue jamais.
  Future<bool> migrer() {
    if (_migre) return Future.value(true);
    return _migrationEnCours ??= _migrer().whenComplete(() => _migrationEnCours = null);
  }

  Future<bool> _migrer() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return false;
    }
    final clair = prefs.getString(cleClaire);
    if (clair == null) {
      _migre = true;
      return true;
    }
    try {
      await coffre.ecrire(cleSure, clair).timeout(delai);
      final relu = await coffre.lire(cleSure).timeout(delai);
      if (relu != clair) throw const _RelectureDifferente();
    } catch (e) {
      _noterEchec('Migration du mot de passe mémorisé vers le stockage sécurisé', e);
      return false;
    }
    await prefs.remove(cleClaire);
    _migre = true;
    journal('Mot de passe mémorisé déplacé dans le stockage sécurisé');
    return true;
  }

  /// Mot de passe mémorisé, ou `null`.
  Future<String?> lire() async {
    await migrer();
    // Clé en clair encore présente = stockage sûr en échec : c'est elle la plus récente.
    try {
      final clair = (await SharedPreferences.getInstance()).getString(cleClaire);
      if (clair != null) return clair;
    } catch (_) {}
    try {
      return await coffre.lire(cleSure).timeout(delai);
    } catch (e) {
      _noterEchec('Lecture du mot de passe mémorisé', e);
      return null;
    }
  }

  /// Mémorise le mot de passe (stockage sûr ; repli en clair si le stockage sûr échoue).
  Future<void> ecrire(String motDePasse) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await coffre.ecrire(cleSure, motDePasse).timeout(delai);
      final relu = await coffre.lire(cleSure).timeout(delai);
      if (relu != motDePasse) throw const _RelectureDifferente();
    } catch (e) {
      _noterEchec('Enregistrement du mot de passe mémorisé', e);
      await prefs.setString(cleClaire, motDePasse);
      return;
    }
    await prefs.remove(cleClaire);
  }

  /// Oublie le mot de passe partout (stockage sûr ET ancienne clé en clair).
  Future<void> effacer() async {
    try {
      await (await SharedPreferences.getInstance()).remove(cleClaire);
    } catch (_) {}
    try {
      await coffre.effacer(cleSure).timeout(delai);
    } catch (e) {
      _noterEchec('Effacement du mot de passe mémorisé', e);
    }
  }

  void _noterEchec(String action, Object e) {
    final motif = e is PlatformException
        ? 'stockage sécurisé indisponible (${e.code})'
        : e is _RelectureDifferente
            ? 'relecture du stockage sécurisé différente'
            : e is TimeoutException
                ? 'stockage sécurisé : délai dépassé'
                : 'stockage sécurisé indisponible (${e.runtimeType})';
    // Jamais le mot de passe : seulement l'action et la nature de l'échec.
    journal('Identifiants : $action — $motif ; ancien comportement conservé, nouvel essai au prochain lancement');
  }
}

class _RelectureDifferente implements Exception {
  const _RelectureDifferente();
}
