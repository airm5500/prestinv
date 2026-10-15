// INTÉGRATION — 4.14.1, création d'un inventaire DEPUIS LA COLLECTE, contre le faux serveur Prestige
// servi en VRAI HTTP (127.0.0.1).
//
// Retour du pharmacien : un produit scanné puis « Créer un inventaire » → inventaire avec TOUS les
// emplacements. Cause : POST /inventaire/creation envoyé sans `valeurs` (le serveur prend alors tout).
// Vérifié ici, paramètres reçus par le serveur à l'appui :
//  - création classique (accueil) : inchangée, pas de `valeurs` ;
//  - création depuis la collecte : `valeurs` = [l'emplacement choisi], type « Emplacement » ;
//  - emplacement d'un produit (produit-search/fiche) et liste des emplacements (referentiel-article) ;
//  - regroupement des codes collectés par emplacement, présélection du plus fréquent ;
//  - pannes : session expirée, 500, coupure → erreur lisible, jamais une présélection trompeuse.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/emplacement_collecte.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/coffre_memoire.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

late FauxServeurPrestige serveur;

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
    serveur = FauxServeurPrestige();
    await serveur.demarrer();
  });

  tearDown(() => serveur.arreter());

  group('Paramètres de POST /inventaire/creation', () {
    test('création classique (accueil) : inchangée, sans `valeurs` → tous les produits', () async {
      final (_, api) = await connecte();
      final r = await CreationInventaire(api).creer('Réserve novembre', TypeInventaire.famille);
      expect(r.ok, isTrue, reason: r.message);
      final corps = corpsCreation();
      expect(corps, {'str_NAME': 'Réserve novembre', 'str_TYPE_TRANSACTION': 'Famille'});
      expect(corps.containsKey('valeurs'), isFalse);
      expect(r.lignes, serveur.catalogue.produits.length);
    });

    test('depuis la collecte : UN SEUL emplacement envoyé (type Emplacement, valeurs = [id])', () async {
      final (_, api) = await connecte();
      final r = await CreationInventaire(api).creer('Collecte du 15-10-2026', TypeInventaire.emplacement, valeurs: ['S3']);
      expect(r.ok, isTrue, reason: r.message);
      expect(corpsCreation(), {
        'str_NAME': 'Collecte du 15-10-2026',
        'str_TYPE_TRANSACTION': 'Emplacement',
        'valeurs': ['S3'],
      });
      expect(serveur.catalogue.creationsValeurs.single, ['S3']);
      // Le serveur ne met que les produits de cet emplacement.
      expect(r.lignes, serveur.catalogue.produits.where((p) => p.rayon == 'S3').length);
      expect(r.lignes, lessThan(serveur.catalogue.produits.length));
      expect(r.inventaire?.libelle, 'Collecte du 15-10-2026');
    });

    test('valeurs vides : non envoyées (jamais de liste vide ambiguë)', () async {
      final (_, api) = await connecte();
      await api.creerInventaire('Essai', 'Emplacement', valeurs: const []);
      expect(corpsCreation().containsKey('valeurs'), isFalse);
    });
  });

  group('Emplacements', () {
    test('emplacement d\'un produit par son code (CIP / EAN-13) : identifiant et libellé', () async {
      final (_, api) = await connecte();
      final r = await api.emplacementDuProduit('3400930000001');
      expect(r?.id, 'S3');
      expect(r?.libelle, 'RÉSERVE');
      final req = serveur.recues('produit-search/fiche').single;
      expect(req.parametres['search_value'], '3400930000001');
      expect(req.cookie, contains('JSESSIONID'));
      expect(await api.emplacementDuProduit('9999999999999'), isNull, reason: 'produit inconnu');
    });

    test('tous les emplacements de l\'officine (hors inventaire)', () async {
      final (_, api) = await connecte();
      final l = await api.fetchEmplacementsOfficine();
      expect(l.map((r) => r.id), containsAll(['S1A0T2', 'S2B2', 'S3', 'R3']));
      expect(l.firstWhere((r) => r.id == 'S2B2').libelle, 'ANTIBIOTIQUES');
      expect(serveur.recues('referentiel-article/zones-geographiques').single.parametres['limit'], '2000');
    });

    test('codes collectés regroupés par emplacement : le plus fréquent est proposé', () async {
      final (_, api) = await connecte();
      final a = await EmplacementsCollecte.analyser(api, [
        '3400935959001', // ANTIBIOTIQUES
        '3400937000003', // ANTIBIOTIQUES
        '3400930000001', // RÉSERVE
        '3400937000003', // doublon : compté une fois
        '0000000000000', // inconnu
      ]);
      expect(a.erreur, isNull);
      expect(a.propose?.id, 'S2B2');
      expect([for (final t in a.trouves) (t.rayon.id, t.codes)], [('S2B2', 2), ('S3', 1)]);
      expect(a.introuvables, 1);
      expect(serveur.recues('produit-search/fiche').length, 4, reason: 'un appel par code distinct');
    });

    test('au plus ${EmplacementsCollecte.maxCodes} codes interrogés', () async {
      final (_, api) = await connecte();
      final codes = [for (var i = 0; i < 55; i++) '34009300${i.toString().padLeft(5, '0')}'];
      final a = await EmplacementsCollecte.analyser(api, codes);
      expect(serveur.recues('produit-search/fiche').length, EmplacementsCollecte.maxCodes);
      expect(a.nonAnalyses, 55 - EmplacementsCollecte.maxCodes);
    });
  });

  group('Pannes : jamais de présélection trompeuse', () {
    test('session expirée → erreur « session », aucun emplacement proposé', () async {
      final (_, api) = await connecte();
      serveur.expirerSessions();
      final a = await EmplacementsCollecte.analyser(api, ['3400930000001']);
      expect(a.propose, isNull);
      expect(a.erreur?.sessionExpiree, isTrue);
      await expectLater(api.fetchEmplacementsOfficine(), throwsA(isA<ApiLoadException>().having((e) => e.sessionExpiree, 'session', isTrue)));
    });

    test('erreur 500 et coupure réseau → erreur lisible', () async {
      final (_, api) = await connecte();
      serveur.scripter('fiche', ReponseScriptee.code(500));
      final a = await EmplacementsCollecte.analyser(api, ['3400930000001']);
      expect(a.propose, isNull);
      expect(a.erreur?.message, contains('code 500'));
      serveur.scripter('zones-geographiques', ReponseScriptee.coupee());
      await expectLater(api.fetchEmplacementsOfficine(), throwsA(isA<ApiLoadException>().having((e) => e.reseau, 'réseau', isTrue)));
    });

    test('refus applicatif (success:false) → message du serveur', () async {
      final (_, api) = await connecte();
      serveur.scripter('zones-geographiques', ReponseScriptee.echec('Accès refusé à cette liste.'));
      await expectLater(api.fetchEmplacementsOfficine(), throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', 'Accès refusé à cette liste.')));
    });
  });
}
