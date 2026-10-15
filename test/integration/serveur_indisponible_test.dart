// INTÉGRATION — 4.15.2, retour du pharmacien : « pendant le redéploiement de Prestige, je vois "erreur 404" ;
// ce serait mieux "Serveur indisponible, veuillez réessayer" ». Contre le faux serveur en VRAI HTTP :
//  - connexion : 404 sans réponse de Prestige (page HTML / vide), 502, 503, 504, connexion refusée →
//    « Serveur indisponible, veuillez réessayer. » ; mauvais mot de passe et 500 : messages inchangés ;
//  - lectures : même message (type réseau : Réessayer), jamais une liste vide ni « aucune licence » ;
//  - envoi d'une quantité pendant le redéploiement : saisie GARDÉE puis envoyée (jamais « refusée ») ;
//    un 404 MÉTIER de Prestige (corps JSON, LIGNE_INCONNUE) reste un refus lisible.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart';
import '../helpers/coffre_memoire.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

late FauxServeurPrestige serveur;

const pageHtml404 = '<!DOCTYPE html><html><head><title>Payara Server - Error report</title></head><body><h1>HTTP Status 404 - Not Found</h1></body></html>';

Future<AppConfig> config() async {
  SharedPreferences.setMockInitialValues({'localApiAddress': '127.0.0.1', 'localApiPort': '${serveur.port}', 'appName': 'prestige'});
  final c = AppConfig();
  await c.load();
  return c;
}

Future<(AuthProvider, AppConfig, ApiService)> connecte() async {
  final c = await config();
  final auth = AuthProvider();
  expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isTrue, reason: auth.errorMessage);
  return (auth, c, ApiService(baseUrl: c.currentApiUrl, cookie: () => auth.sessionCookie));
}

Matcher indisponible() => isA<ApiLoadException>()
    .having((e) => e.message, 'message', startsWith('Serveur indisponible, veuillez réessayer'))
    .having((e) => e.reseau, 'réseau (Réessayer)', isTrue);

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
    IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: CoffreMemoire());
  });

  setUp(() async {
    ApiService.clientParDefaut = null;
    ApiService.oublierRoutesAbsentes();
    serveur = FauxServeurPrestige();
    await serveur.demarrer();
  });

  tearDown(() => serveur.arreter());

  group('Connexion', () {
    for (final (nom, reponse) in [
      ('404 page HTML (redéploiement)', ReponseScriptee(code: 404, corps: pageHtml404)),
      ('404 vide', ReponseScriptee.code(404)),
      ('502', ReponseScriptee.code(502)),
      ('503', ReponseScriptee.code(503)),
      ('504', ReponseScriptee.code(504)),
    ]) {
      test('$nom → « Serveur indisponible, veuillez réessayer. »', () async {
        final c = await config();
        serveur.scripter('user/auth', reponse);
        final auth = AuthProvider();
        expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isFalse);
        expect(auth.errorMessage, 'Serveur indisponible, veuillez réessayer.');
      });
    }

    test('connexion refusée (Prestige arrêté) → « Serveur indisponible, veuillez réessayer. »', () async {
      final c = await config();
      await serveur.arreter();
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isFalse);
      expect(auth.errorMessage, 'Serveur indisponible, veuillez réessayer.');
    });

    test('jamais confondu : mauvais mot de passe, erreur 500', () async {
      final c = await config();
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, 'faux', c), isFalse);
      expect(auth.errorMessage, 'Identifiant ou mot de passe incorrect.');
      serveur.scripter('user/auth', ReponseScriptee.code(500));
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isFalse);
      expect(auth.errorMessage, 'Erreur serveur (500)');
    });
  });

  group('Lectures', () {
    test('liste des inventaires, rayons, produits, déjà compté : 404 HTML / 503 → « Serveur indisponible »', () async {
      final (_, _, api) = await connecte();
      serveur.scripter('ws/inventaires', ReponseScriptee(code: 404, corps: pageHtml404));
      await expectLater(api.fetchTousInventairesOuverts(), throwsA(indisponible()));
      serveur.scripter('rayons', ReponseScriptee.code(503));
      await expectLater(api.fetchRayons('INV1'), throwsA(indisponible()));
      serveur.scripter('detailsAll', ReponseScriptee.code(502));
      await expectLater(api.fetchProducts('INV1', null), throwsA(indisponible()));
      serveur.scripter('detailsAllTouched', ReponseScriptee.code(404));
      await expectLater(api.verifierDejaCompte('INV1', '3400930000001'), throwsA(indisponible()));
    });

    test('connexion refusée pendant une lecture : « Serveur indisponible, veuillez réessayer » (réseau)', () async {
      final (_, _, api) = await connecte();
      await serveur.arreter();
      await expectLater(api.fetchTousInventairesOuverts(), throwsA(indisponible()));
    });

    test('licence : 404 au lancement (redéploiement) → serveur indisponible, PAS « aucune licence »', () async {
      final c = await config();
      serveur.scripter('licence/find', ReponseScriptee(code: 404, corps: pageHtml404));
      final l = LicenseProvider();
      await l.checkLicense(ApiService(baseUrl: c.currentApiUrl));
      expect(l.status, LicenseStatus.unreachable);
      expect(l.error, startsWith('Serveur indisponible, veuillez réessayer'));
    });
  });

  group('Envoi des quantités pendant le redéploiement', () {
    test('PUT details 404 HTML / 503 : saisie GARDÉE (réseau), envoyée au retour ; 404 MÉTIER : refus lisible', () async {
      final (auth, c, api) = await connecte();
      serveur.scripter('details', ReponseScriptee(code: 404, corps: pageHtml404), methode: 'PUT');
      final r = await api.poserQuantite(4, 7);
      expect(r.type, ResultatEnvoi.reseau);
      expect(r.message, 'Serveur indisponible, veuillez réessayer.');
      serveur.scripter('details', ReponseScriptee.json({'success': 0, 'code': 'LIGNE_INCONNUE', 'message': 'x'}, code: 404), methode: 'PUT');
      expect((await api.poserQuantite(4, 7)).type, ResultatEnvoi.refus, reason: '404 métier de Prestige : refus');

      final q = SaisieQueue(store: DisqueMemoire())..serveurFactory = () => ApiService(baseUrl: c.currentApiUrl, cookie: () => auth.sessionCookie);
      await q.load();
      await q.enregistrer(inventaireId: 'INV1', ligneId: 4, quantite: 9);
      serveur.scripter('details', ReponseScriptee.code(503), methode: 'PUT');
      await q.envoyer();
      expect(q.enAttente(), 1, reason: 'gardée pendant le redéploiement');
      expect(q.refusees(), 0, reason: 'jamais « refusée » à tort');
      serveur.oublierScripts();
      expect((await q.envoyer()).complet, isTrue);
      expect(serveur.catalogue.produit(4).saisi, 9);
    });

    test('route « avec auteur » ET route habituelle en 404 (redéploiement) : la route avec auteur n\'est pas oubliée', () async {
      final (_, _, api) = await connecte();
      serveur.scripter('ligne/quantite', ReponseScriptee.code(404, fois: 1));
      serveur.scripter('details', ReponseScriptee.code(404, fois: 1), methode: 'PUT');
      final r = await api.poserQuantiteSession(4, 3);
      expect(r.type, ResultatEnvoi.reseau);
      expect((await api.poserQuantiteSession(4, 3)).type, ResultatEnvoi.ok);
      expect(serveur.recues('ligne/quantite', methode: 'POST'), hasLength(2), reason: 'route avec auteur réessayée');
      expect(serveur.catalogue.produit(4).auteur, 'admin');
    });
  });
}
