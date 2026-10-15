// RÉSEAU — 4.15 : création depuis la collecte, retenue des produits, versement en lot, état des rayons,
// sur un réseau difficile.
//  - écran (temps simulé) : recherche des produits LENTE (5 s, 8 s) → indicateur, aucun message d'erreur,
//    puis récapitulatif ; création lente → « Création en cours… », un second toucher ne crée rien ;
//  - services contre le VRAI serveur HTTP local : coupure pendant la création (rien de créé, jamais deux
//    inventaires), réponse TRONQUÉE du versement en lot (lot gardé, même clé à la reprise, compté une
//    seule fois), versement et retenue lents (sous le délai) aboutis, coupures répétées pendant l'analyse.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/produits_collecte.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart';
import '../helpers/coffre_memoire.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

const codes = ['3400930000001', '3400935959001', '3400938000004'];

final indicateur = find.byWidgetPredicate((w) => w is ProgressIndicator);

Finder erreurs() => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final t = (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase();
      return t.contains('injoignable') || t.contains('trop de temps') || t.contains('erreur') || t.contains('non retrouvés');
    });

void main() {
  group('Écran de création depuis la collecte (temps simulé)', () {
    setUpAll(chargerPolicesReelles);
    setUp(() {
      reinitialiserDouchette();
      installerFauxRetour();
    });

    for (final d in [const Duration(seconds: 5), const Duration(seconds: 8)]) {
      testWidgets('recherche des produits lente (${d.inSeconds} s) : indicateur, aucune erreur, puis récapitulatif', (tester) async {
        tailleEcran(tester, sunmiV2s);
        final b = await preparerBanc(serveur: serveurRealiste());
        ApiService.oublierRoutesAbsentes();
        b.auth.connecterPourTest();
        b.serveur.delais['fiche'] = d;
        await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte lente', codesCollectes: codes)));
        for (var t = Duration.zero; t < d - const Duration(milliseconds: 500); t += const Duration(milliseconds: 500)) {
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byKey(const ValueKey('recherche-produits')), findsOneWidget, reason: 'recherche visible à ${t.inMilliseconds} ms');
          expect(erreurs(), findsNothing, reason: 'aucune erreur à ${t.inMilliseconds} ms');
        }
        // 3 codes, 4 recherches en parallèle : un seul délai, puis l'essai de la route de retenue.
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('3 produits, 3 emplacements'), findsOneWidget);
        expect(erreurs(), findsNothing);
        await demonter(tester);
      });
    }

    testWidgets('création lente (8 s) : « Création en cours… », second toucher sans effet, un seul inventaire', (tester) async {
      tailleEcran(tester, sunmiV2s);
      final b = await preparerBanc(serveur: serveurRealiste());
      ApiService.oublierRoutesAbsentes();
      b.auth.connecterPourTest();
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte lente', codesCollectes: codes)));
      await tester.pumpAndSettle();
      b.serveur.delais['creation'] = const Duration(seconds: 8);
      await toucher(tester, find.byKey(const ValueKey('bouton-creer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmer-creation')));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Création en cours…'), findsOneWidget);
      expect(indicateur, findsWidgets);
      await tester.tap(find.byKey(const ValueKey('bouton-creer')), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(b.serveur.creations, hasLength(1));
      expect(b.serveur.crees['NEW1']!.lignesRetenues, hasLength(3));
      await demonter(tester);
    });
  });

  group('Services contre le vrai serveur HTTP local', () {
    late FauxServeurPrestige serveur;

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

    Future<(AuthProvider, AppConfig, ApiService)> connecte() async {
      SharedPreferences.setMockInitialValues({'localApiAddress': '127.0.0.1', 'localApiPort': '${serveur.port}', 'appName': 'prestige'});
      final config = AppConfig();
      await config.load();
      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue);
      return (auth, config, ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie));
    }

    test('coupures répétées pendant l\'analyse : erreur réseau à chaque fois, puis résultat complet', () async {
      final (_, _, api) = await connecte();
      for (var i = 0; i < 3; i++) {
        serveur.scripter('fiche', ReponseScriptee.coupee(fois: 1));
        final a = await ProduitsCollecte.analyser(api, codes);
        expect(a.erreur?.reseau, isTrue);
        expect(a.creationPossible, isFalse);
      }
      final a = await ProduitsCollecte.analyser(api, codes);
      expect(a.produits, hasLength(3));
    });

    test('coupure pendant la création (avant le serveur) : rien de créé ; nouvelle tentative → UN inventaire', () async {
      final (_, _, api) = await connecte();
      final service = CreationInventaire(api);
      final a = await ProduitsCollecte.analyser(api, codes);
      serveur.scripter('inventaire/creation', ReponseScriptee.coupee(fois: 1));
      final r = await service.creerDepuisCollecte('Collecte coupée', a);
      expect(r.issue, IssueCreation.incertaine);
      expect(serveur.catalogue.crees, isEmpty);
      final r2 = await service.creerDepuisCollecte('Collecte coupée', a);
      expect(r2.ok, isTrue, reason: r2.message);
      expect(serveur.catalogue.crees.keys, ['NEW1']);
      expect(r2.retenus, 3);
    });

    test('réponse PERDUE après la création : l\'inventaire est retrouvé, jamais créé deux fois', () async {
      final (_, _, api) = await connecte();
      final service = CreationInventaire(api);
      final a = await ProduitsCollecte.analyser(api, codes);
      serveur.catalogue.creationReponsePerdue = true;
      final r = await service.creerDepuisCollecte('Collecte réponse perdue', a);
      serveur.catalogue.creationReponsePerdue = false;
      expect(r.ok, isTrue, reason: r.message);
      expect(r.inventaire?.id, 'NEW1');
      expect(r.retenus, 3);
      expect(serveur.catalogue.creations, hasLength(1));
    });

    test('retenue lente (5 s, sous le délai de 30 s) : aboutie', () async {
      final (_, _, api) = await connecte();
      final a = await ProduitsCollecte.analyser(api, codes);
      serveur.scripter('lignes/retenue', ReponseScriptee.lente(const Duration(seconds: 5)));
      final r = await CreationInventaire(api).creerDepuisCollecte('Collecte retenue lente', a);
      expect(r.ok, isTrue, reason: r.message);
      expect(r.retenus, 3);
    }, timeout: const Timeout(Duration(seconds: 60)));

    group('versement en lot (serveur à jour)', () {
      setUp(() => serveur.serveurRecent = true);

      (MoteurVersement, List<Versement>) moteur(AuthProvider auth, AppConfig config) {
        final q = SaisieQueue(store: DisqueMemoire())..serveurFactory = () => ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
        final etats = <Versement>[];
        return (
          MoteurVersement(
            api: ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie),
            queue: q,
            enregistrer: (v) async => etats.add(Versement.fromJson(json.decode(json.encode(v.toJson())) as Map<String, dynamic>)),
          ),
          etats
        );
      }

      Versement v() => Versement.depuisCollecte([for (final c in codes) CollectedItem(code: c, quantity: 3, dateScan: DateTime(2026, 10, 15))],
          inventaireId: 'INV1', inventaireLibelle: 'Inventaire annuel 2026', mode: ModeDejaCompte.ajouter, maintenant: DateTime(2026, 10, 15, 10));

      test('réponse TRONQUÉE : lot gardé, reprise avec la même clé, compté UNE fois', () async {
        final (auth, config, _) = await connecte();
        final (m, etats) = moteur(auth, config);
        serveur.scripter('versement', ReponseScriptee.tronquee('{"success":1,"lignes":[{"index":0,"statut":"ok","ligneId":"1"', fois: 1));
        final r1 = await m.executer(v());
        expect(r1.statut, StatutVersement.interrompu);
        expect(r1.lotEnCours, isNotNull);
        final r2 = await m.executer(etats.last);
        expect(r2.statut, StatutVersement.termine);
        expect(serveur.catalogue.produit(1).saisi, 3, reason: 'jamais compté : 0 + 3, une seule fois');
        expect(serveur.catalogue.produit(5).saisi, 3);
        final envois = serveur.catalogue.versementsLot;
        expect(envois, hasLength(1), reason: 'la requête tronquée n\'a pas été traitée ; la reprise, si');
        expect(serveur.recues('versement', methode: 'POST'), hasLength(2));
        expect(json.decode(serveur.recues('versement', methode: 'POST').first.corps)['cle'],
            json.decode(serveur.recues('versement', methode: 'POST').last.corps)['cle']);
      });

      test('versement lent (8 s, sous le délai de 60 s) : abouti en une requête', () async {
        final (auth, config, _) = await connecte();
        final (m, _) = moteur(auth, config);
        serveur.scripter('versement', ReponseScriptee.lente(const Duration(seconds: 8)));
        final r = await m.executer(v());
        expect(r.statut, StatutVersement.termine);
        expect(serveur.recues('versement', methode: 'POST'), hasLength(1));
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('serveur coupé pendant le lot : interrompu, rien perdu ; au retour : versé une fois', () async {
        final (auth, config, _) = await connecte();
        final (m, etats) = moteur(auth, config);
        serveur.scripter('versement', ReponseScriptee.coupee(fois: 2));
        final r1 = await m.executer(v());
        expect(r1.statut, StatutVersement.interrompu);
        final r2 = await m.executer(etats.last);
        expect(r2.statut, StatutVersement.interrompu);
        final r3 = await m.executer(etats.last);
        expect(r3.statut, StatutVersement.termine);
        expect(serveur.catalogue.produit(1).saisi, 3);
      });
    });
  });
}
