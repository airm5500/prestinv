// Stockage sécurisé en mémoire (remplace le Keystore Android dans les tests), avec panne simulable.
import 'package:flutter/services.dart';
import 'package:prestinv/services/identifiants_securises.dart';

class CoffreMemoire implements CoffreIdentifiants {
  final Map<String, String> valeurs = {};
  bool enPanne = false;

  void _verifier() {
    if (enPanne) throw PlatformException(code: 'KeystoreIndisponible');
  }

  @override
  Future<String?> lire(String cle) async {
    _verifier();
    return valeurs[cle];
  }

  @override
  Future<void> ecrire(String cle, String valeur) async {
    _verifier();
    valeurs[cle] = valeur;
  }

  @override
  Future<void> effacer(String cle) async {
    _verifier();
    valeurs.remove(cle);
  }
}
