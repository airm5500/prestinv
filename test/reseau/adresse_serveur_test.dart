// RÉSEAU — passage LOCAL ↔ DISTANT et adresse changée :
//  - services contre DEUX vrais serveurs HTTP locaux (« local » et « distant ») : après le changement
//    de mode ou d'adresse, chaque requête (listes, connexion, envoi de la file) part vers la NOUVELLE
//    adresse ; la session de l'ancien serveur n'y vaut rien → « session expirée », saisies gardées,
//    envoi repris sur le nouveau serveur après la reconnexion ; rien n'est envoyé à l'ancien ;
//  - application entière : serveur local injoignable au lancement → « Passer en Distant » → licence,
//    connexion et listes sur le serveur distant.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart' show DisqueMemoire;
import '../helpers/coffre_memoire.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

void main() {
  group('Services : deux vrais serveurs HTTP locaux', () {
    late FauxServeurPrestige local, distant;

    setUpAll(() {
      HttpOverrides.global = null;
      IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: CoffreMemoire());
    });
    setUp(() async {
      ApiService.clientParDefaut = null;
      local = FauxServeurPrestige();
      distant = FauxServeurPrestige();
      await local.demarrer();
      await distant.demarrer();
    });
    tearDown(() async {
      await local.arreter();
      await distant.arreter();
    });

    Future<AppConfig> config() async {
      SharedPreferences.setMockInitialValues({
        'localApiAddress': '127.0.0.1',
        'localApiPort': '${local.port}',
        'distantApiAddress': '127.0.0.1',
        'distantApiPort': '${distant.port}',
        'appName': 'prestige',
      });
      final c = AppConfig();
      await c.load();
      return c;
    }

    test('local → distant : listes et file des saisies vers le distant, reprise après reconnexion', () async {
      final c = await config();
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isTrue);
      final file = SaisieQueue(store: DisqueMemoire())
        ..serveurFactory = () => ApiService(baseUrl: c.currentApiUrl, cookie: () => auth.sessionCookie);
      await file.load();
      await file.enregistrer(inventaireId: 'INV1', ligneId: 2, quantite: 4);
      expect((await file.envoyer()).envoyees, 1);
      expect(local.catalogue.produit(2).saisi, 4);

      await c.setApiMode(ApiMode.distant);
      expect(c.currentApiUrl, distant.adresse);
      final avantLocal = local.requetes.length;
      await file.enregistrer(inventaireId: 'INV1', ligneId: 3, quantite: 7);
      final b = await file.envoyer();
      expect(b.sessionExpiree, isTrue, reason: 'la session du serveur local ne vaut rien sur le distant');
      expect(file.enAttente(), 1, reason: 'saisie gardée');

      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isTrue);
      expect(distant.recues('user/auth'), hasLength(1), reason: 'connexion sur le distant');
      file.signalerReconnexion();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(file.enAttente(), 0);
      expect(distant.catalogue.produit(3).saisi, 7);
      expect(local.requetes.length, avantLocal, reason: 'plus rien vers l\'ancien serveur après le changement');

      final invs = await ApiService(baseUrl: c.currentApiUrl, cookie: () => auth.sessionCookie).fetchTousInventairesOuverts();
      expect(invs, isNotEmpty);
      expect(distant.recues('ws/inventaires', methode: 'GET'), isNotEmpty);

      // Retour en local : les requêtes repartent vers le serveur local.
      await c.setApiMode(ApiMode.local);
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isTrue);
      expect(local.recues('user/auth'), hasLength(2));
    });

    test('adresse changée dans la configuration : la requête suivante part vers la nouvelle adresse', () async {
      final c = await config();
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isTrue);
      expect(local.recues('user/auth'), hasLength(1));
      await c.setApiConfig(localPort: '${distant.port}');
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isTrue);
      expect(distant.recues('user/auth'), hasLength(1));
      expect(local.recues('user/auth'), hasLength(1), reason: 'ancienne adresse abandonnée');
    });
  });

  group('Application entière', () {
    setUpAll(chargerPolicesReelles);

    testWidgets('serveur local injoignable au lancement → « Passer en Distant » → tout passe par le distant', (tester) async {
      tailleEcran(tester, telephone360);
      final serveurs = DeuxServeurs();
      serveurs.couper(); // le serveur LOCAL ne répond pas
      SharedPreferences.setMockInitialValues({});
      await lancerApplication(tester, serveur: serveurs, prefs: {'distantApiAddress': 'distant.invalid', 'distantApiPort': '8443'});
      expect(find.byKey(const ValueKey('nv-reessayer-serveur')), findsOneWidget, reason: 'aucune licence en cache : écran « injoignable »');
      await tester.tap(find.byKey(const ValueKey('nv-basculer-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-connexion')), findsOneWidget, reason: 'licence lue sur le distant');
      await seConnecter(tester);
      await deroulerInventaires(tester);
      expect(find.byKey(const ValueKey('nv-ouvrir-INV1')), findsOneWidget);
      expect(serveurs.distant.recues('licence/find'), hasLength(1));
      expect(serveurs.distant.recues('user/auth'), hasLength(1));
      expect(serveurs.distant.recues('ws/inventaires', methode: 'GET'), isNotEmpty);
      expect(serveurs.distant.requetes.every((r) => r.hote == 'distant.invalid:8443'), isTrue);
      await fermerApplication(tester);
    });
  });
}

/// Deux faux serveurs derrière un même client : « distant.invalid » → [distant], tout le reste → ce
/// serveur (le local, adresse fictive des tests).
class DeuxServeurs extends FauxServeurPrestige {
  final distant = FauxServeurPrestige();

  @override
  http.Client get client {
    final local = super.client;
    final loin = distant.client;
    return MockClient((req) async {
      final c = req.url.host == 'distant.invalid' ? loin : local;
      final copie = http.Request(req.method, req.url)
        ..headers.addAll(req.headers)
        ..bodyBytes = req.bodyBytes;
      return http.Response.fromStream(await c.send(copie));
    });
  }
}
