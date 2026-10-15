// INTÉGRATION — 4.15.2 / 4.15.3, retours du pharmacien : DEUX cas distincts, contre le faux serveur en VRAI HTTP :
//  1. aucune réponse (connexion refusée : PC serveur éteint, Payara arrêté ; délai dépassé) → « Serveur
//     injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé. » ;
//  2. Payara répond mais Prestige n'est pas déployé (404 HTML / vide, 502, 503, 504) → « Serveur indisponible :
//     Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant. » ;
//  - mauvais mot de passe et 500 : messages inchangés ;
//  - lectures : même message (type réseau : Réessayer), jamais une liste vide ni « aucune licence » ;
//  - envoi d'une quantité pendant le redéploiement : saisie GARDÉE puis envoyée (jamais « refusée ») ;
//    un 404 MÉTIER de Prestige (corps JSON, LIGNE_INCONNUE) reste un refus lisible.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/produits_collecte.dart';
import 'package:prestinv/models/collected_item.dart';
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
    .having((e) => e.message, 'message', allOf(startsWith('Serveur indisponible'), contains('démarrage ou de redéploiement')))
    .having((e) => e.reseau, 'réseau (Réessayer)', isTrue);

Matcher injoignable() => isA<ApiLoadException>()
    .having((e) => e.message, 'message', allOf(startsWith('Serveur injoignable'), contains('PC serveur est allumé')))
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
      test('$nom → cas 2, « Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement… »', () async {
        final c = await config();
        serveur.scripter('user/auth', reponse);
        final auth = AuthProvider();
        expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isFalse);
        expect(auth.errorMessage, ApiService.messageIndisponible);
        expect(auth.errorMessage, 'Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant.');
      });
    }

    test('connexion refusée (PC serveur éteint, Payara arrêté) → cas 1, « Serveur injoignable… »', () async {
      final c = await config();
      await serveur.arreter();
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isFalse);
      expect(auth.errorMessage, 'Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé.');
    });

    test('délai dépassé (aucune réponse) → cas 1, « Serveur injoignable… »', () async {
      final c = await config();
      serveur.scripter('user/auth', ReponseScriptee.lente(const Duration(seconds: 25)));
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, c), isFalse);
      expect(auth.errorMessage, ApiService.messageInjoignable);
    }, timeout: const Timeout(Duration(seconds: 60)));

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

    test('connexion refusée pendant une lecture : cas 1, « Serveur injoignable » (réseau)', () async {
      final (_, _, api) = await connecte();
      await serveur.arreter();
      await expectLater(api.fetchTousInventairesOuverts(), throwsA(injoignable()));
    });

    test('licence : 404 au lancement (redéploiement) → serveur indisponible, PAS « aucune licence »', () async {
      final c = await config();
      serveur.scripter('licence/find', ReponseScriptee(code: 404, corps: pageHtml404));
      final l = LicenseProvider();
      await l.checkLicense(ApiService(baseUrl: c.currentApiUrl));
      expect(l.status, LicenseStatus.unreachable);
      expect(l.error, startsWith('Serveur indisponible'));
      expect(l.error, contains('la licence n\'est pas en cause'));
    });
  });

  group('Envoi des quantités pendant le redéploiement', () {
    test('PUT details 404 HTML / 503 : saisie GARDÉE (réseau), envoyée au retour ; 404 MÉTIER : refus lisible', () async {
      final (auth, c, api) = await connecte();
      serveur.scripter('details', ReponseScriptee(code: 404, corps: pageHtml404), methode: 'PUT');
      final r = await api.poserQuantite(4, 7);
      expect(r.type, ResultatEnvoi.reseau);
      expect(r.message, ApiService.messageIndisponible);
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

  group('4.15.3 — 404 d\'une route nouvelle pendant un redéploiement : jamais « ancien serveur »', () {
    setUp(() => serveur.serveurRecent = true);

    test('état des rayons : Prestige non déployé → « Serveur indisponible », route NON oubliée ; au retour, route nouvelle', () async {
      final (_, _, api) = await connecte();
      serveur.nonDeploye = true;
      await expectLater(api.fetchRayons('INV1'), throwsA(indisponible()));
      expect(serveur.recues('licence/find'), hasLength(1), reason: 'vérification faite seulement après le 404');
      expect(serveur.recues('ws/inventaires/rayons'), isEmpty, reason: 'pas de passage à l\'ancienne méthode');
      serveur.nonDeploye = false;
      expect((await api.fetchRayons('INV1')).map((r) => r.id).toSet(), {'S1A0T2', 'S2B2', 'S3'});
      expect(serveur.recues('rayons/etat'), hasLength(2), reason: 'la route nouvelle est toujours utilisée');
      expect(serveur.recues('ws/inventaires/rayons'), isEmpty);
    });

    test('état des rayons : 404 mais Prestige répond (vrai serveur sans la route) → ancien chemin', () async {
      final (_, _, api) = await connecte();
      serveur.scripter('etat', ReponseScriptee.code(404));
      expect((await api.fetchRayons('INV1')).map((r) => r.id).toSet(), {'S1A0T2', 'S2B2', 'S3'});
      expect(serveur.recues('ws/inventaires/rayons'), hasLength(1));
    });

    test('fonctionnement normal : AUCUNE vérification en plus', () async {
      final (_, _, api) = await connecte();
      await api.fetchRayons('INV1');
      expect(serveur.recues('licence/find'), isEmpty);
    });

    test('versement en lot pendant le redéploiement : interrompu, lot gardé, rien en ancien chemin ; au retour, versé une fois', () async {
      final (auth, c, _) = await connecte();
      final q = SaisieQueue(store: DisqueMemoire())..serveurFactory = () => ApiService(baseUrl: c.currentApiUrl, cookie: () => auth.sessionCookie);
      final etats = <Versement>[];
      final m = MoteurVersement(
        api: ApiService(baseUrl: c.currentApiUrl, cookie: () => auth.sessionCookie),
        queue: q,
        enregistrer: (v) async => etats.add(Versement.fromJson(json.decode(json.encode(v.toJson())) as Map<String, dynamic>)),
      );
      final v = Versement.depuisCollecte([CollectedItem(code: '3400930000001', quantity: 4, dateScan: DateTime(2026, 10, 15))],
          inventaireId: 'INV1', inventaireLibelle: 'Inventaire annuel 2026', mode: ModeDejaCompte.ajouter, maintenant: DateTime(2026, 10, 15, 10));
      // Lignes de l'inventaire lues, puis Prestige redéployé juste avant le lot.
      serveur.scripter('versement', ReponseScriptee(code: 404, corps: pageHtml404, fois: 1));
      serveur.scripter('licence/find', ReponseScriptee(code: 404, corps: pageHtml404, fois: 1));
      final r1 = await m.executer(v);
      expect(r1.statut, StatutVersement.interrompu);
      expect(r1.interruption, startsWith('Serveur indisponible'));
      expect(r1.lotEnCours, isNotNull, reason: 'lot gardé, même clé à la reprise');
      expect(serveur.recues('ligne/quantite'), isEmpty, reason: 'jamais l\'ancienne méthode à cause d\'un redéploiement');
      final r2 = await m.executer(etats.last);
      expect(r2.statut, StatutVersement.termine);
      expect(serveur.catalogue.produit(1).saisi, 4, reason: 'compté une seule fois');
      expect(serveur.recues('versement', methode: 'POST'), hasLength(2));
    });

    test('création depuis la collecte pendant le redéploiement : « Serveur indisponible », PAS « serveur ancien »', () async {
      final (_, _, api) = await connecte();
      serveur.serveurRecent = false; // l'essai de la route de retenue est alors fait
      ApiService.oublierRoutesAbsentes();
      final a = await ProduitsCollecte.analyser(api, ['3400930000001']);
      serveur.nonDeploye = true;
      final r = await CreationInventaire(api).creerDepuisCollecte('Collecte redéploiement', a);
      expect(r.issue, IssueCreation.reseau);
      expect(r.message, startsWith('Serveur indisponible'));
      expect(r.message, isNot(CreationInventaire.messageServeurAncien));
      serveur.nonDeploye = false;
      final r2 = await CreationInventaire(api).creerDepuisCollecte('Collecte redéploiement', a);
      expect(r2.ok, isTrue, reason: r2.message);
      expect(r2.retenus, 1);
    });
  });
}
