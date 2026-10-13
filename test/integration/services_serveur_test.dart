// INTÉGRATION — services de l'application contre le faux serveur Prestige servi en VRAI HTTP
// (HttpServer local 127.0.0.1) : en-têtes, cookie de session, codes HTTP, corps JSON, connexion
// coupée ou refusée. Aucun widget : entrées/sorties réelles.
//
// Règles vérifiées (à ne jamais casser) :
//  - licence : serveur injoignable, 5xx, 401, 403 ≠ « aucune licence » ;
//  - un échec de chargement n'est JAMAIS une liste vide ;
//  - le cookie JSESSIONID reçu à la connexion accompagne chaque requête ; session expirée → 401 → reconnexion ;
//  - une quantité saisie hors ligne n'est jamais perdue et part au retour du serveur.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
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
late String base;

/// Configuration de l'application pointant sur le faux serveur HTTP.
Future<AppConfig> configSur(FauxServeurPrestige s) async {
  SharedPreferences.setMockInitialValues({'localApiAddress': '127.0.0.1', 'localApiPort': '${s.port}', 'appName': 'prestige'});
  final c = AppConfig();
  await c.load();
  return c;
}

/// Connexion réelle (AuthProvider.login) sur le faux serveur.
Future<(AuthProvider, AppConfig)> connecte() async {
  final config = await configSur(serveur);
  final auth = AuthProvider();
  expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue, reason: auth.errorMessage);
  return (auth, config);
}

void main() {
  setUpAll(() {
    // Les tests de widgets remplacent HttpClient par un faux qui répond 400 : ici, vrai réseau local.
    HttpOverrides.global = null;
    IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: CoffreMemoire());
  });

  setUp(() async {
    ApiService.clientParDefaut = null;
    ApiService.oublierRoutesAbsentes();
    serveur = FauxServeurPrestige();
    base = await serveur.demarrer();
  });

  tearDown(() => serveur.arreter());

  group('Licence au lancement', () {
    Future<LicenseProvider> verifier() async {
      SharedPreferences.setMockInitialValues({});
      final l = LicenseProvider();
      await l.checkLicense(ApiService(baseUrl: base));
      return l;
    }

    test('licence valide : « valide », sans session (route publique)', () async {
      final l = await verifier();
      expect(l.status, LicenseStatus.valid);
      expect(l.daysRemaining, greaterThan(300));
      expect(serveur.recues('licence/find').single.cookie, isNull);
    });

    test('le serveur répond sans licence (corps vide) : « aucune licence »', () async {
      serveur.licence = null;
      expect((await verifier()).status, LicenseStatus.none);
    });

    test('le serveur répond 404 sur la licence : « aucune licence »', () async {
      serveur.scripter('licence/find', ReponseScriptee.code(404));
      expect((await verifier()).status, LicenseStatus.none);
    });

    for (final code in [500, 502, 503, 401, 403]) {
      test('réponse $code : serveur en erreur, PAS « aucune licence »', () async {
        serveur.scripter('licence/find', ReponseScriptee.code(code));
        final l = await verifier();
        expect(l.status, LicenseStatus.unreachable);
        expect(l.error, contains('code $code'));
        expect(l.error, contains('la licence n\'est pas en cause'));
      });
    }

    test('serveur arrêté (connexion refusée) : « injoignable », PAS « aucune licence »', () async {
      await serveur.arreter();
      expect((await verifier()).status, LicenseStatus.unreachable);
    });

    test('connexion coupée pendant la réponse : « injoignable »', () async {
      serveur.scripter('licence/find', ReponseScriptee.coupee());
      expect((await verifier()).status, LicenseStatus.unreachable);
    });

    test('réseau lent (sous le délai) : licence lue normalement', () async {
      serveur.scripter('licence/find', ReponseScriptee.lente(const Duration(milliseconds: 600)));
      expect((await verifier()).status, LicenseStatus.valid);
    });

    test('licence expirée : « expirée »', () async {
      serveur.licence = {...licenceFictive(), 'dateEnd': '2001-01-01'};
      expect((await verifier()).status, LicenseStatus.expired);
    });
  });

  group('Connexion et cookie de session', () {
    test('bons identifiants : session ouverte, cookie JSESSIONID gardé (en mémoire), utilisateur lu', () async {
      final (auth, _) = await connecte();
      expect(auth.isLoggedIn, isTrue);
      expect(auth.sessionCookie, 'JSESSIONID=essai-1');
      expect(auth.user!.firstName, CompteFictif.prenom);
      expect(auth.user!.officine, CompteFictif.officine);
      final req = serveur.recues('user/auth').single;
      expect(req.methode, 'POST');
      expect(req.corps, contains(CompteFictif.login));
      expect((await SharedPreferences.getInstance()).getKeys().where((k) => k.toLowerCase().contains('cookie')), isEmpty,
          reason: 'cookie jamais écrit sur l\'appareil');
    });

    test('mauvais mot de passe (success:false) : refus lisible, pas de session', () async {
      final config = await configSur(serveur);
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, 'faux', config), isFalse);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.sessionCookie, isNull);
      expect(auth.errorMessage, 'Identifiant ou mot de passe incorrect.');
    });

    test('erreur 500 à la connexion : « Erreur serveur (500) »', () async {
      serveur.scripter('user/auth', ReponseScriptee.code(500));
      final config = await configSur(serveur);
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isFalse);
      expect(auth.errorMessage, 'Erreur serveur (500)');
    });

    test('serveur arrêté : message réseau', () async {
      final config = await configSur(serveur);
      await serveur.arreter();
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isFalse);
      expect(auth.errorMessage, contains('Vérifiez le réseau'));
    });

    test('chaque requête porte le cookie de la session ; sans cookie : 401 → « session expirée », jamais liste vide', () async {
      final (auth, config) = await connecte();
      final api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      final invs = await api.fetchInventories(maxResult: 10);
      expect(invs.map((i) => i.id), ['INV1', 'INV2']);
      expect(serveur.recues('ws/inventaires').single.cookie, 'JSESSIONID=essai-1');

      final sansSession = ApiService(baseUrl: config.currentApiUrl);
      await expectLater(sansSession.fetchInventories(),
          throwsA(isA<ApiLoadException>().having((e) => e.sessionExpiree, 'session expirée', isTrue)));
    });

    test('session expirée côté serveur puis reconnexion : le NOUVEAU cookie est utilisé par le même service', () async {
      final (auth, config) = await connecte();
      final api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      serveur.expirerSessions();
      await expectLater(api.fetchRayons('INV1'), throwsA(isA<ApiLoadException>().having((e) => e.sessionExpiree, 'session', isTrue)));
      expect((await api.poserQuantite(1, 3)).type, ResultatEnvoi.session);

      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue);
      expect(auth.sessionCookie, 'JSESSIONID=essai-2');
      expect((await api.fetchRayons('INV1')).length, 3);
      expect(serveur.recues('rayons').last.cookie, 'JSESSIONID=essai-2');
    });

    test('déconnexion : cookie envoyé, session fermée côté serveur ; serveur coupé : déconnexion locale quand même', () async {
      final (auth, config) = await connecte();
      await auth.logout(config);
      expect(serveur.recues('user/logout').single.cookie, 'JSESSIONID=essai-1');
      expect(serveur.sessionsValides, isEmpty);
      expect((auth.isLoggedIn, auth.sessionCookie), (false, null));

      final (auth2, config2) = await connecte();
      await serveur.arreter();
      await auth2.logout(config2);
      expect(auth2.isLoggedIn, isFalse);
    });
  });

  group('Chargements (un échec n\'est jamais une liste vide)', () {
    late ApiService api;
    setUp(() async {
      final (auth, config) = await connecte();
      api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
    });

    test('rayons, produits d\'un rayon (triés), écarts, restants', () async {
      expect((await api.fetchRayons('INV1')).map((r) => r.id), containsAll(['S1A0T2', 'S2B2', 'S3']));
      final s2 = await api.fetchProducts('INV1', 'S2B2');
      expect(s2.map((p) => p.produitName).toList(), [...s2.map((p) => p.produitName)]..sort());
      expect(s2.map((p) => p.id), containsAll([2, 4, 6, 9]));
      final ecarts = await api.fetchGlobalVariances('INV1');
      expect(ecarts.every((p) => p.quantiteSaisie != p.quantiteInitiale), isTrue);
      expect(ecarts, isNotEmpty);
      final restants = await api.fetchUntouchedProducts('INV1');
      expect(restants.map((p) => p.id), containsAll([1, 4, 5]));
      expect(serveur.recues('detailsAllEcarts').single.parametres['idInventaire'], 'INV1');
    });

    test('500 : refus avec le code', () async {
      serveur.scripter('details', ReponseScriptee.code(500));
      await expectLater(api.fetchProducts('INV1', 'S2B2'), throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('code 500'))));
    });

    test('réponse illisible : « données »', () async {
      serveur.scripter('rayons', ReponseScriptee(corps: '<html>maintenance</html>'));
      await expectLater(
          api.fetchRayons('INV1'), throwsA(isA<ApiLoadException>().having((e) => e.type, 'type', TypeErreurChargement.donnees)));
    });

    test('connexion coupée : « réseau »', () async {
      serveur.scripter('detailsAllUntouched', ReponseScriptee.coupee());
      await expectLater(api.fetchUntouchedProducts('INV1'), throwsA(isA<ApiLoadException>().having((e) => e.reseau, 'réseau', isTrue)));
    });

    test('déjà compté : quantité du serveur ; une erreur LÈVE (jamais « jamais compté »)', () async {
      expect(await api.verifierDejaCompte('INV1', '3400935959001', ligneId: 2), 6);
      expect(await api.verifierDejaCompte('INV1', '3400930000001', ligneId: 1), isNull);
      serveur.scripter('detailsAllTouched', ReponseScriptee.code(503));
      await expectLater(api.verifierDejaCompte('INV1', '3400935959001'), throwsA(isA<ApiLoadException>()));
    });
  });

  group('Écritures', () {
    late ApiService api;
    setUp(() async {
      final (auth, config) = await connecte();
      api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
    });

    test('PUT details : quantité posée ; 401 → session ; 500 → erreur serveur ; coupure → réseau', () async {
      expect((await api.poserQuantite(4, 7)).type, ResultatEnvoi.ok);
      expect(serveur.catalogue.produit(4).saisi, 7);
      expect(serveur.recues('details', methode: 'PUT').single.corps, '{"id":4,"quantite":7}');
      serveur.scripter('details', ReponseScriptee.code(401, fois: 1), methode: 'PUT');
      expect((await api.poserQuantite(4, 8)).type, ResultatEnvoi.session);
      serveur.scripter('details', ReponseScriptee.code(500, fois: 1), methode: 'PUT');
      expect((await api.poserQuantite(4, 8)).type, ResultatEnvoi.erreurServeur);
      serveur.scripter('details', ReponseScriptee.coupee(fois: 1), methode: 'PUT');
      expect((await api.poserQuantite(4, 8)).type, ResultatEnvoi.reseau);
      expect(serveur.catalogue.produit(4).saisi, 7, reason: 'aucun des envois en échec n\'a été appliqué');
    });

    test('POST ligne/quantite (auteur) : succès ; success:false lisible ; « connecter » → session ; 404 → route habituelle', () async {
      expect((await api.poserQuantiteSession(5, 12)).type, ResultatEnvoi.ok);
      expect(serveur.catalogue.produit(5).saisi, 12);
      serveur.scripter('ligne/quantite', ReponseScriptee.json({'success': 0, 'errors': 'Quantite invalide.'}, fois: 1));
      final refus = await api.poserQuantiteSession(5, 13);
      expect((refus.type, refus.message), (ResultatEnvoi.refus, 'Quantite invalide.'));
      serveur.scripter('ligne/quantite', ReponseScriptee.echec('Veuillez vous connecter', fois: 1));
      expect((await api.poserQuantiteSession(5, 13)).type, ResultatEnvoi.session);
      serveur.scripter('ligne/quantite', ReponseScriptee.code(404));
      expect((await api.poserQuantiteSession(5, 14)).type, ResultatEnvoi.ok);
      expect(serveur.recues('details', methode: 'PUT').single.corps, '{"id":5,"quantite":14}');
    });

    test('création d\'inventaire : succès, refus lisible, session, réponse perdue = issue incertaine', () async {
      final ok = await api.creerInventaire('Réserve novembre', 'Emplacement');
      expect((ok.succes, ok.lignes), (true, 12));
      expect(serveur.catalogue.inventaires.values.first, 'Réserve novembre');
      serveur.scripter('inventaire/creation', ReponseScriptee.echec('Indiquez un libelle pour cet inventaire.', fois: 1));
      final refus = await api.creerInventaire('', 'Emplacement');
      expect((refus.succes, refus.message), (false, 'Indiquez un libelle pour cet inventaire.'));
      serveur.scripter('inventaire/creation', ReponseScriptee.code(401, fois: 1));
      expect((await api.creerInventaire('X', 'Famille')).session, isTrue);
      serveur.scripter('inventaire/creation', ReponseScriptee.coupee(fois: 1));
      expect((await api.creerInventaire('X', 'Famille')).incertain, isTrue);
    });
  });

  group('File des saisies et versement sur le vrai transport HTTP', () {
    test('hors ligne : saisies gardées ; au retour du serveur, elles partent (cookie compris)', () async {
      final (auth, config) = await connecte();
      final disque = DisqueMemoire();
      final q = SaisieQueue(store: disque);
      q.serveurFactory = () => ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      await q.load();
      for (final (ligne, qte) in [(1, 20), (4, 2), (5, 31)]) {
        await q.enregistrer(inventaireId: 'INV1', ligneId: ligne, quantite: qte);
      }
      serveur.couper();
      final bilan = await q.envoyer();
      expect(bilan.complet, isFalse);
      expect(q.enAttente(), 3);
      expect(disque.saisies.where((s) => s.enAttente), hasLength(3), reason: 'rien n\'est perdu sur l\'appareil');

      serveur.retablir();
      final bilan2 = await q.envoyer();
      expect(bilan2.complet, isTrue, reason: '${bilan2.interruption}');
      expect([1, 4, 5].map((id) => serveur.catalogue.produit(id).saisi), [20, 2, 31]);
      expect(serveur.recues('details', methode: 'PUT').map((r) => r.cookie).toSet(), {'JSESSIONID=essai-1'});
      q.arreterReprise();
    });

    test('session expirée pendant l\'envoi : gardées ; reconnexion → reprise', () async {
      final (auth, config) = await connecte();
      final q = SaisieQueue(store: DisqueMemoire());
      q.serveurFactory = () => ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      await q.load();
      // Un premier envoi réussi (la liste des inventaires ouverts est alors connue, 60 s).
      await q.enregistrer(inventaireId: 'INV1', ligneId: 12, quantite: 1);
      expect((await q.envoyer()).complet, isTrue);
      await q.enregistrer(inventaireId: 'INV1', ligneId: 10, quantite: 9);
      serveur.expirerSessions();
      final bilan = await q.envoyer();
      expect(bilan.sessionExpiree, isTrue);
      expect(q.enAttente(), 1);
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue);
      expect((await q.envoyer()).complet, isTrue);
      expect(serveur.catalogue.produit(10).saisi, 9);
    });

    // Anomalie A1 (corrigée) : si la session a expiré AVANT tout envoi, la lecture des inventaires
    // ouverts reçoit 401 ; la file l'annonçait « serveur injoignable ». Elle propose désormais de se
    // reconnecter, garde les saisies et les envoie après la reconnexion.
    test('session expirée avant le premier envoi : signalée comme session expirée, envoi repris après reconnexion', () async {
      final (auth, config) = await connecte();
      final q = SaisieQueue(store: DisqueMemoire());
      q.serveurFactory = () => ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      await q.load();
      await q.enregistrer(inventaireId: 'INV1', ligneId: 10, quantite: 9);
      serveur.expirerSessions();
      final bilan = await q.envoyer();
      expect(q.enAttente(), 1, reason: 'saisie gardée');
      expect(bilan.sessionExpiree, isTrue);
      expect(q.sessionExpiree, isTrue);
      expect(bilan.interruption, startsWith('Session expirée — reconnectez-vous'));
      expect(q.derniereErreur, isNot(contains('injoignable')));
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue);
      q.signalerReconnexion();
      final limite = DateTime.now().add(const Duration(seconds: 10));
      while ((q.envoiEnCours || q.enAttente() > 0) && DateTime.now().isBefore(limite)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(serveur.catalogue.produit(10).saisi, 9, reason: 'envoyée après la reconnexion');
      expect(q.sessionExpiree, isFalse);
    });

    test('403 sur la liste des inventaires ouverts : session expirée aussi (pas « serveur injoignable »)', () async {
      final (auth, config) = await connecte();
      final q = SaisieQueue(store: DisqueMemoire());
      q.serveurFactory = () => ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      await q.load();
      await q.enregistrer(inventaireId: 'INV1', ligneId: 10, quantite: 9);
      serveur.scripter('ws/inventaires', ReponseScriptee.code(403));
      final bilan = await q.envoyer();
      expect(bilan.sessionExpiree, isTrue);
      expect(q.enAttente(), 1);
    });

    test('versement d\'une collecte hors ligne : codes reconnus posés (route avec auteur), inconnus au rapport', () async {
      final (auth, config) = await connecte();
      final q = SaisieQueue(store: DisqueMemoire());
      final moteur = MoteurVersement(
        api: ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie),
        queue: q,
        auteur: CompteFictif.login,
        enregistrer: (_) async {},
      );
      q.serveurFactory = () => ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      final v = Versement.depuisCollecte([
        CollectedItem(code: '3400930000001', quantity: 12, dateScan: DateTime(2026, 10, 13, 9)),
        CollectedItem(code: '3400938000004', quantity: 4, dateScan: DateTime(2026, 10, 13, 9, 2)),
        CollectedItem(code: '9999999999999', quantity: 3, dateScan: DateTime(2026, 10, 13, 9, 5)),
      ], inventaireId: 'INV1', inventaireLibelle: 'Inventaire annuel 2026', mode: ModeDejaCompte.remplacer, maintenant: DateTime(2026, 10, 13, 10));
      final r = await moteur.executer(v);
      expect(r.statut, StatutVersement.termine);
      expect((serveur.catalogue.produit(1).saisi, serveur.catalogue.produit(5).saisi), (12, 4));
      expect(r.nonReconnues.single.code, '9999999999999');
      final posts = serveur.recues('ligne/quantite', methode: 'POST');
      expect(posts, hasLength(2));
      expect(posts.every((p) => p.cookie == 'JSESSIONID=essai-1'), isTrue);
    });
  });
}
