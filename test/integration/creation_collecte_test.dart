// INTÉGRATION — 4.15, création d'un inventaire DEPUIS LA COLLECTE, contre le faux serveur Prestige servi
// en VRAI HTTP (127.0.0.1).
//
// Décision du pharmacien (retour sur la 4.14.1, limitée à UN emplacement) : « 4 produits de 4 emplacements
// → comme sur Prestige : emplacement = tous, l'inventaire des 4 produits ; à l'ouverture, juste les
// emplacements de ces produits ». Vérifié ici, paramètres reçus par le serveur à l'appui :
//  - création classique (accueil) : inchangée (ni `valeurs`, ni `bool_INVENTAIRE`) ;
//  - produit d'un code (fiche article) : CIP, EAN-13, jamais une correspondance partielle ou ambiguë ;
//  - analyse de la collecte : produits distincts (CIP + EAN du même produit = 1), emplacements, inconnus ;
//  - création : `valeurs` = emplacements des produits, `bool_INVENTAIRE = 0`, puis lignes RETENUES
//    (`POST /inventaire/lignes/retenue`) des seuls produits collectés → l'inventaire ouvert ne propose que
//    ces emplacements et ces produits ;
//  - serveur à jour : identifiant `lgInventaireId` (pas de relecture de liste), état des rayons ;
//  - serveur ancien sans la route de retenue (404) : tous les produits de CES emplacements, jamais de toute
//    l'officine ;
//  - pannes : session, 500, coupure, droit manquant (403 « interdit ») ; échec de la retenue après création
//    → « Réessayer » ne recrée rien.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/produits_collecte.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/coffre_memoire.dart';
import '../helpers/faux_prestige_http.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

late FauxServeurPrestige serveur;

/// 4 produits collectés, 3 emplacements : DOLIPRANE (RÉSERVE), AMOXICILLINE et SPASFON (ANTIBIOTIQUES),
/// BÉTADINE (CANNES) ; le SPASFON scanné deux fois ; un code inconnu.
const collecte = ['3400930000001', '3400935959001', '3400938000004', '3400937000003', '3400937000003', '0000000000000'];

Future<(AuthProvider, ApiService)> connecte() async {
  SharedPreferences.setMockInitialValues({'localApiAddress': '127.0.0.1', 'localApiPort': '${serveur.port}', 'appName': 'prestige'});
  final config = AppConfig();
  await config.load();
  final auth = AuthProvider();
  expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue, reason: auth.errorMessage);
  return (auth, ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie));
}

Map<String, dynamic> corpsCreation() => json.decode(serveur.recues('inventaire/creation', methode: 'POST').single.corps) as Map<String, dynamic>;

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

  group('Création classique (accueil) : inchangée', () {
    test('sans `valeurs` ni `bool_INVENTAIRE` → tous les produits', () async {
      final (_, api) = await connecte();
      final r = await CreationInventaire(api).creer('Réserve novembre', TypeInventaire.famille);
      expect(r.ok, isTrue, reason: r.message);
      expect(corpsCreation(), {'str_NAME': 'Réserve novembre', 'str_TYPE_TRANSACTION': 'Famille'});
      expect(r.lignes, serveur.catalogue.produits.length);
      expect(serveur.recues('lignes/retenue'), isEmpty);
    });

    test('valeurs vides : non envoyées (jamais de liste vide ambiguë)', () async {
      final (_, api) = await connecte();
      await api.creerInventaire('Essai', 'Emplacement', valeurs: const []);
      expect(corpsCreation().containsKey('valeurs'), isFalse);
    });
  });

  group('Produit d\'un code (fiche article)', () {
    test('CIP, EAN-13 : identifiant, CIP, emplacement ; inconnu → null ; cookie de session envoyé', () async {
      final (_, api) = await connecte();
      final p = await api.produitParCode('3400930000001');
      expect(p?.id, 'F1');
      expect(p?.emplacement?.id, 'S3');
      expect(p?.emplacement?.libelle, 'RÉSERVE');
      expect(serveur.recues('produit-search/fiche').single.cookie, contains('JSESSIONID'));
      expect(await api.produitParCode('9999999999999'), isNull, reason: 'produit inconnu');
    });

    test('correspondance PARTIELLE (début de CIP) ou plusieurs produits possibles : refusée', () async {
      final (_, api) = await connecte();
      expect(await api.produitParCode('3400939'), isNull, reason: 'plusieurs produits commencent ainsi');
      expect(await api.produitParCode('340093000000'), isNull, reason: 'un seul produit, mais trouvé par le début de son CIP');
    });

    test('session expirée, 500, coupure : erreur levée (jamais « inconnu »)', () async {
      final (_, api) = await connecte();
      serveur.scripter('fiche', ReponseScriptee.code(500), methode: 'GET');
      await expectLater(api.produitParCode('3400930000001'), throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('500'))));
      serveur.scripter('fiche', ReponseScriptee.coupee(), methode: 'GET');
      await expectLater(api.produitParCode('3400930000001'), throwsA(isA<ApiLoadException>().having((e) => e.reseau, 'réseau', isTrue)));
      serveur.oublierScripts();
      serveur.expirerSessions();
      await expectLater(api.produitParCode('3400930000001'), throwsA(isA<ApiLoadException>().having((e) => e.sessionExpiree, 'session', isTrue)));
    });
  });

  group('Analyse de la collecte', () {
    test('4 produits, 3 emplacements, 1 code inconnu ; une requête par code distinct', () async {
      final (_, api) = await connecte();
      final a = await ProduitsCollecte.analyser(api, collecte);
      expect(a.erreur, isNull);
      expect(a.produits.map((p) => p.id), ['F1', 'F2', 'F5', 'F4']);
      expect([for (final e in a.emplacements) (e.rayon.id, e.produits)], [('S2B2', 2), ('S1A0T2', 1), ('S3', 1)]);
      expect(a.introuvables, ['0000000000000']);
      expect(a.creationPossible, isTrue);
      // 5 codes distincts : 4 trouvés du premier coup, l'inconnu essayé sous ses autres formes.
      expect(serveur.recues('produit-search/fiche').where((r) => r.parametres['search_value'] != '0000000000000').length, 4);
    });

    test('CIP et EAN du même produit : UN seul produit', () async {
      serveur.catalogue.produits.add(FauxProduit(13, '3400930000999', 'SÉRUM PHYSIOLOGIQUE', 'S3', 5, ean: '8712345678906'));
      final (_, api) = await connecte();
      // Retrouvé par son CIP puis par son EAN (même lg_FAMILLE_ID) ; espaces autour du code ignorés.
      final a = await ProduitsCollecte.analyser(api, ['3400930000999', '8712345678906', ' 3400930000999 ', '3400935959001']);
      expect(a.produits.map((p) => p.id), ['F13', 'F2']);
      expect(a.introuvables, isEmpty);
    });

    test('panne : erreur, rien de proposé', () async {
      final (_, api) = await connecte();
      serveur.expirerSessions();
      final a = await ProduitsCollecte.analyser(api, collecte);
      expect(a.erreur?.sessionExpiree, isTrue);
      expect(a.creationPossible, isFalse);
      expect(a.emplacements, isEmpty);
    });

    test('au plus ${ProduitsCollecte.maxCodes} codes analysés', () async {
      final (_, api) = await connecte();
      final codes = [for (var i = 0; i < ProduitsCollecte.maxCodes + 7; i++) '9${i.toString().padLeft(12, '0')}'];
      final a = await ProduitsCollecte.analyser(api, codes);
      expect(a.nonAnalyses, 7);
      expect(a.introuvables.length, ProduitsCollecte.maxCodes);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Création depuis la collecte (serveur actuel, sans les routes récentes)', () {
    test('emplacements des produits, lignes non retenues, puis SEULS les produits collectés retenus', () async {
      final (_, api) = await connecte();
      final a = await ProduitsCollecte.analyser(api, collecte);
      final r = await CreationInventaire(api).creerDepuisCollecte('Collecte du 15-10-2026 09.30', a);
      expect(r.ok, isTrue, reason: r.message);
      expect(r.retenus, 4);
      final corps = corpsCreation();
      expect(corps['str_TYPE_TRANSACTION'], 'Emplacement');
      expect((corps['valeurs'] as List).toSet(), {'S2B2', 'S1A0T2', 'S3'});
      expect(corps['bool_INVENTAIRE'], 0);
      // Essai sans effet de la route, puis retenue des 4 produits.
      final ret = serveur.recues('inventaire/lignes/retenue', methode: 'POST');
      expect(ret, hasLength(2));
      expect(json.decode(ret.first.corps), {'lg_INVENTAIRE_ID': '', 'ids': []});
      expect(json.decode(ret.last.corps), {'lg_INVENTAIRE_ID': r.inventaire!.id, 'produits': ['F1', 'F2', 'F5', 'F4'], 'retenue': true});

      // À l'ouverture : les 3 emplacements de ces produits seulement, et seulement ces produits.
      final id = r.inventaire!.id;
      final rayons = await api.fetchRayons(id);
      expect(rayons.map((x) => x.id).toSet(), {'S1A0T2', 'S2B2', 'S3'});
      expect((await api.fetchProducts(id, null)).map((p) => p.produitCip).toSet(),
          {'3400930000001', '3400935959001', '3400938000004', '3400937000003'});
      expect((await api.fetchProducts(id, 'S1A0T2')).map((p) => p.produitName), ['BÉTADINE DERMIQUE 10 %']);
      // Rien de compté dans le nouvel inventaire.
      expect(await api.fetchUntouchedProducts(id), hasLength(4));
    });

    test('2 emplacements seulement si les produits y sont tous', () async {
      final (_, api) = await connecte();
      final a = await ProduitsCollecte.analyser(api, ['3400935959001', '3400937000003', '3400930000001']);
      final r = await CreationInventaire(api).creerDepuisCollecte('Collecte deux rayons', a);
      expect(r.ok, isTrue);
      expect((await api.fetchRayons(r.inventaire!.id)).map((x) => x.id).toSet(), {'S2B2', 'S3'});
    });

    test('aucun produit retrouvé : rien n\'est envoyé', () async {
      final (_, api) = await connecte();
      final a = await ProduitsCollecte.analyser(api, ['0000000000000']);
      final r = await CreationInventaire(api).creerDepuisCollecte('Collecte vide', a);
      expect(r.issue, IssueCreation.refus);
      expect(serveur.recues('inventaire/creation'), isEmpty);
    });

    test('serveur ANCIEN sans la route de retenue (404) : tous les produits de CES emplacements, pas de toute l\'officine', () async {
      serveur.catalogue.sansRouteRetenue = true;
      final (_, api) = await connecte();
      final a = await ProduitsCollecte.analyser(api, ['3400935959001', '3400930000001']);
      final r = await CreationInventaire(api).creerDepuisCollecte('Collecte ancien serveur', a);
      expect(r.ok, isTrue, reason: r.message);
      expect(r.retenus, isNull);
      final corps = corpsCreation();
      expect(corps.containsKey('bool_INVENTAIRE'), isFalse, reason: 'lignes retenues d\'office');
      expect((corps['valeurs'] as List).toSet(), {'S2B2', 'S3'});
      final attendus = serveur.catalogue.produits.where((p) => p.rayon == 'S2B2' || p.rayon == 'S3').length;
      expect(r.lignes, attendus);
      expect(await api.fetchProducts(r.inventaire!.id, null), hasLength(attendus));
      expect(attendus, lessThan(serveur.catalogue.produits.length));
    });

    test('retenue coupée après la création → « produits non ajoutés », Réessayer ne recrée rien', () async {
      final (_, api) = await connecte();
      final service = CreationInventaire(api);
      final a = await ProduitsCollecte.analyser(api, collecte);
      // L'essai sans effet passe, la vraie retenue est coupée.
      expect(await api.routeRetenueDisponible(), isTrue);
      serveur.scripter('lignes/retenue', ReponseScriptee.coupee(fois: 1));
      final r = await service.creerDepuisCollecte('Collecte coupée', a);
      expect(r.issue, IssueCreation.produitsNonAjoutes);
      expect(r.inventaire, isNotNull);
      expect(r.message, contains('Réessayer'));
      expect(await api.fetchProducts(r.inventaire!.id, null), isEmpty, reason: 'aucune ligne retenue encore');
      final r2 = await service.retenir(r.inventaire!, a);
      expect(r2.ok, isTrue, reason: r2.message);
      expect(r2.retenus, 4);
      expect(serveur.recues('inventaire/creation'), hasLength(1), reason: 'jamais recréé');
      expect(await api.fetchProducts(r.inventaire!.id, null), hasLength(4));
    });

    test('libellé déjà ouvert → doublon (rien créé) ; « utiliser » y retient les produits', () async {
      final (_, api) = await connecte();
      final service = CreationInventaire(api);
      final a = await ProduitsCollecte.analyser(api, collecte);
      final r = await service.creerDepuisCollecte('Inventaire annuel 2026', a);
      expect(r.issue, IssueCreation.doublon);
      expect(serveur.recues('inventaire/creation'), isEmpty);
      final r2 = await service.retenir(r.inventaire!, a);
      expect(r2.ok, isTrue);
      expect(serveur.recues('lignes/retenue').last.corps, contains('"lg_INVENTAIRE_ID":"INV1"'));
    });

    test('session expirée avant la création : rien n\'est créé, message « session »', () async {
      final (_, api) = await connecte();
      final a = await ProduitsCollecte.analyser(api, collecte);
      serveur.expirerSessions();
      final r = await CreationInventaire(api).creerDepuisCollecte('Collecte session', a);
      expect(r.issue, IssueCreation.session);
      expect(serveur.recues('inventaire/creation'), isEmpty);
    });
  });

  group('Serveur à jour (réponse aux demandes mobiles)', () {
    setUp(() => serveur.serveurRecent = true);

    test('connexion : droits et rôle lus, serveur reconnu (aucune requête de plus)', () async {
      final (auth, api) = await connecte();
      expect(auth.user?.droitCreation, isTrue);
      expect(api.serveurRecent, isTrue);
      expect(serveur.requetes.map((r) => r.route), ['user/auth']);
    });

    test('identifiant donné par le serveur : pas de relecture de la liste, pas d\'essai de route', () async {
      final (_, api) = await connecte();
      final a = await ProduitsCollecte.analyser(api, collecte);
      final avant = serveur.requetes.length;
      final r = await CreationInventaire(api).creerDepuisCollecte('Collecte serveur à jour', a);
      expect(r.ok, isTrue, reason: r.message);
      expect(r.inventaire?.id, 'NEW1');
      expect(r.retenus, 4);
      expect(serveur.requetes.skip(avant).map((x) => '${x.methode} ${x.route}'), [
        'GET ws/inventaires', // doublon ?
        'POST inventaire/creation',
        'POST inventaire/lignes/retenue',
      ]);
      // Emplacements de l'inventaire : par l'état des rayons (une requête), lignes retenues seulement.
      final avant2 = serveur.requetes.length;
      final rayons = await api.fetchRayons('NEW1');
      expect(rayons.map((x) => x.id).toSet(), {'S1A0T2', 'S2B2', 'S3'});
      expect(serveur.requetes.skip(avant2).map((x) => x.route), ['ws/inventaires/NEW1/rayons/etat']);
    });

    test('droit manquant (403 « interdit ») : refus lisible, PAS « session expirée »', () async {
      final (_, api) = await connecte();
      serveur.scripter('inventaire/creation',
          ReponseScriptee.json({'success': 0, 'interdit': true, 'msg': 'Droit manquant : Créer un inventaire'}, code: 403));
      final r = await CreationInventaire(api).creer('Essai droit', TypeInventaire.emplacement);
      expect(r.issue, IssueCreation.refus);
      expect(r.message, 'Droit manquant : Créer un inventaire');
    });

    test('compte sans le droit : droits.creerInventaire = false lu à la connexion', () async {
      serveur.droitCreation = false;
      final (auth, _) = await connecte();
      expect(auth.user?.droitCreation, isFalse);
    });
  });
}
