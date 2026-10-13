// Mot de passe mémorisé : stockage sécurisé + migration de l'ancienne clé en clair ; journaux sans secret.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:prestinv/utils/journal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/faux_prestige_http.dart';

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

void main() {
  late CoffreMemoire coffre;
  setUp(() {
    coffre = CoffreMemoire();
    IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: coffre);
  });

  test('migration : l\'ancien mot de passe en clair passe dans le stockage sûr puis est SUPPRIMÉ des préférences', () async {
    SharedPreferences.setMockInitialValues({'savedPassword': 'Secret!42', 'savedLogin': 'koffi', 'rememberMe': true});
    expect(await IdentifiantsSecurises.instance.migrer(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('savedPassword'), isFalse);
    expect(coffre.valeurs[IdentifiantsSecurises.cleSure], 'Secret!42');
    expect(await IdentifiantsSecurises.instance.lire(), 'Secret!42');
    expect(prefs.getString('savedLogin'), 'koffi'); // l'identifiant reste
  });

  test('stockage sûr en panne : rien n\'est perdu (ancien comportement), nouvel essai ensuite', () async {
    SharedPreferences.setMockInitialValues({'savedPassword': 'Secret!42'});
    coffre.enPanne = true;
    expect(await IdentifiantsSecurises.instance.migrer(), isFalse);
    expect(await IdentifiantsSecurises.instance.lire(), 'Secret!42');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('savedPassword'), 'Secret!42');

    coffre.enPanne = false;
    IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: coffre); // lancement suivant
    expect(await IdentifiantsSecurises.instance.migrer(), isTrue);
    expect(prefs.containsKey('savedPassword'), isFalse);
  });

  test('effacer : plus de mot de passe nulle part', () async {
    SharedPreferences.setMockInitialValues({'savedPassword': 'x'});
    await IdentifiantsSecurises.instance.ecrire('y');
    await IdentifiantsSecurises.instance.effacer();
    expect(await IdentifiantsSecurises.instance.lire(), isNull);
    expect((await SharedPreferences.getInstance()).containsKey('savedPassword'), isFalse);
  });

  test('connexion avec « Rester connecté » : mot de passe dans le stockage sûr, jamais en clair ; cookie jamais écrit',
      () async {
    SharedPreferences.setMockInitialValues({'rememberMe': true, 'localApiAddress': 'serveur'});
    final srv = FauxPrestige(nombre: 1);
    ApiService.clientParDefaut = srv.client;
    addTearDown(() => ApiService.clientParDefaut = null);
    final config = AppConfig();
    await config.load();
    final auth = AuthProvider();
    await auth.loadUserFromStorage();
    expect(await auth.login('admin', 'Test1234', config), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('savedPassword'), isFalse);
    expect(prefs.getKeys().any((k) => (prefs.get(k)?.toString() ?? '').contains('Test1234')), isFalse);
    expect(prefs.getKeys().any((k) => (prefs.get(k)?.toString() ?? '').contains('JSESSIONID')), isFalse);
    expect(coffre.valeurs[IdentifiantsSecurises.cleSure], 'Test1234');

    // Décocher « Rester connecté » efface le mot de passe.
    await auth.setRememberMe(false);
    expect(coffre.valeurs.containsKey(IdentifiantsSecurises.cleSure), isFalse);
  });

  test('journaux : mot de passe, cookie, clé de licence et paramètres d\'URL masqués', () {
    expect(masquerSecrets('Cookie: JSESSIONID=abc123; Path=/'), isNot(contains('abc123')));
    expect(masquerSecrets('{"login":"admin","password":"Test1234"}'), isNot(contains('Test1234')));
    expect(masquerSecrets('GET http://srv/prestige/api/v1/licence/save/CLE-SECRETE'), isNot(contains('CLE-SECRETE')));
    expect(masquerSecrets('GET http://srv/api/v1/ws/inventaires/detailsAll?idInventaire=1&query=3400'), isNot(contains('3400')));
    expect(masquerSecrets('Chargement des produits'), 'Chargement des produits');
  });
}
