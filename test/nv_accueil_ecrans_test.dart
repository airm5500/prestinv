// Nouvelle interface — accueil (maquette A ; tablette : menu latéral, maquette C), choix du rayon,
// « À envoyer », collecte hors ligne + versement + rapport, nouvel inventaire, connexion, licence,
// serveur injoignable, configuration, réglages scan et sons, récapitulatif, analyse, cumuls :
// actions principales branchées sur la même logique que les écrans d'origine.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/services/pin_securise.dart';
import 'package:prestinv/ui/ecrans/a_envoyer_screen.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/cumuls_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/rapport_versement_screen.dart';
import 'package:prestinv/ui/ecrans/recap_screen.dart';
import 'package:prestinv/ui/ecrans/reglages_scan_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/navigation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/banc_essai.dart';
import 'helpers/coffre_memoire.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

final _inv = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

Future<Banc> banc({SendMode mode = SendMode.collect}) async {
  final b = await preparerBanc(serveur: serveurRealiste(), mode: mode);
  b.auth.connecterPourTest(login: 'Awa K.');
  return b;
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  group('Accueil', () {
    testWidgets('inventaires ouverts, inventaire en cours, À envoyer → Envoyer, Reprendre au dernier rayon', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await b.queue.enregistrer(inventaireId: 'INV1', ligneId: 10, quantite: 8, nom: 'BILAN BIOLOGIQUE TOTAL', rayonId: 'S1A0T2', rayonLibelle: 'CANNES');
      await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-en-cours')), findsOneWidget);
      expect(find.text('Inventaire annuel 2026'), findsWidgets);
      expect(find.textContaining('1 saisie(s) sur le téléphone'), findsOneWidget);
      expect(find.text('Reprendre : rayon CANNES'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nv-envoyer-tout')));
      await tester.pumpAndSettle();
      expect(b.serveur.puts, [(10, 8)], reason: 'même envoi que « À envoyer » (SaisieQueue.envoyer)');
      expect(find.byKey(const ValueKey('nv-bandeau-a-envoyer')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('nv-reprendre')));
      await tester.pumpAndSettle();
      expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
      expect(find.text('S1A0T2 – CANNES'), findsOneWidget);
      await demonter(tester);
    });

    testWidgets('modes : Saisie guidée → choix du rayon ; Scan continu ; Écarts ; Restants ; Collecte ; barre du bas', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
      await tester.pumpAndSettle();
      Future<void> ouvrirPuisRevenir(Finder f, Type ecran) async {
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
        expect(find.byType(ecran), findsOneWidget);
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.popUntil((r) => r.isFirst);
        await tester.pumpAndSettle();
      }

      await ouvrirPuisRevenir(find.byKey(const ValueKey('nv-saisie-guidee')), NvChoixRayonScreen);
      await ouvrirPuisRevenir(find.byKey(const ValueKey('nv-scan-continu')), NvScanContinuScreen);
      await ouvrirPuisRevenir(find.byKey(const ValueKey('nv-tuile-ecarts')), NvEcartsScreen);
      await ouvrirPuisRevenir(find.byKey(const ValueKey('nv-tuile-collecte')), NvCollecteScreen);
      await ouvrirPuisRevenir(find.text('Scanner'), NvScanContinuScreen);
      await ouvrirPuisRevenir(find.text('Réglages'), NvConfigScreen);
      await demonter(tester);
    });

    testWidgets('choix de l\'inventaire en cours (mémorisé) et nouvel inventaire (créé, puis choisi)', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('nv-inv-INV2')), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('nv-inv-INV2')));
      await tester.pumpAndSettle();
      expect((await SharedPreferences.getInstance()).getString(InventaireCourant.cle), 'INV2');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('nouvel-inventaire')), -200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('nouvel-inventaire')));
      await tester.pumpAndSettle();
      expect(find.byType(NvCreationInventaireScreen), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve novembre');
      await tester.tap(find.byKey(const ValueKey('bouton-creer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmer-creation')));
      await tester.pumpAndSettle();
      expect(b.serveur.creations.single.$1, 'Réserve novembre');
      expect(find.byType(NvAccueilScreen), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Nouveau — créé depuis ce terminal'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Nouveau — créé depuis ce terminal'), findsOneWidget);
      await demonter(tester);
    });

    testWidgets('tablette : menu latéral (maquette C) qui ouvre les mêmes écrans', (tester) async {
      tailleEcran(tester, tablette, densite: 1.5);
      final b = await banc();
      InterfaceVersion.useNew.value = true;
      addTearDown(() => InterfaceVersion.useNew.value = false);
      await tester.pumpWidget(monter(b, const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(NvAccueilScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-accueil')), findsOneWidget);
      expect(find.byKey(const ValueKey('nv-barre-bas')), findsNothing, reason: 'pas de barre du bas sur tablette');
      await tester.tap(find.byKey(const ValueKey('menu-restants')));
      await tester.pumpAndSettle();
      expect(find.text('Restants à faire'), findsOneWidget);
      await demonter(tester);
    });
  });

  testWidgets('choix du rayon : état des rayons, filtres, saisies en attente par rayon, ouverture', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    // Rayon CANNES pas encore commencé sur le serveur.
    for (final p in b.serveur.produits.where((p) => p.rayon == 'S1A0T2')) {
      p.dtUpdated = null;
    }
    await b.queue.enregistrer(inventaireId: 'INV1', ligneId: 10, quantite: 8, rayonId: 'S1A0T2');
    await tester.pumpWidget(monterNv(b, NvChoixRayonScreen(inventaire: _inv)));
    await tester.pumpAndSettle();
    expect(find.text('S2B2 – ANTIBIOTIQUES'), findsOneWidget);
    expect(find.textContaining('1 en attente d\'envoi'), findsOneWidget);
    expect(find.text('Terminés 0'), findsOneWidget);
    await tester.tap(find.text('À faire 1'));
    await tester.pumpAndSettle();
    expect(find.text('S1A0T2 – CANNES'), findsOneWidget, reason: 'aucun produit compté');
    expect(find.text('S2B2 – ANTIBIOTIQUES'), findsNothing);
    await tester.tap(find.text('S1A0T2 – CANNES'));
    await tester.pumpAndSettle();
    expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('À envoyer : Envoyer maintenant ; saisie refusée : remettre en attente', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await b.queue.enregistrer(inventaireId: 'INV1', inventaireLibelle: 'Inventaire annuel 2026', ligneId: 1, quantite: 5, nom: 'DOLIPRANE');
    await tester.pumpWidget(monterNv(b, const NvAEnvoyerScreen()));
    await tester.pumpAndSettle();
    expect(find.text('en attente d\'envoi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-envoyer-maintenant')));
    await tester.pumpAndSettle();
    expect(b.serveur.puts, [(1, 5)]);
    expect(find.text('Tout est envoyé.'), findsOneWidget);
    await demonter(tester);
  });

  group('Collecte hors ligne', () {
    testWidgets('scan (douchette) → quantité → ligne gardée (même clé), additionnée si le code revient', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvCollecteScreen()));
      await tester.pumpAndSettle();
      expect(champScanAFocus(tester), isTrue);
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      expect(find.text('Code 3400930000001'), findsOneWidget);
      await taperNv(tester, '12');
      await tester.pumpAndSettle();
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      await douchette(tester, '3'); // chiffres + Entrée de la douchette
      await tester.pumpAndSettle();
      final items = await CollecteStore.lire();
      expect(items.single.quantity, 15);
      expect(champScanAFocus(tester), isTrue);
      await demonter(tester);
    });

    testWidgets('verser : inventaire ouvert, mode Ajouter, progression, rapport', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await CollecteStore.ecrire([
        CollectedItem(code: '3400930000001', quantity: 12, dateScan: DateTime(2026, 10, 13, 9)),
        CollectedItem(code: '9999999999999', quantity: 3, dateScan: DateTime(2026, 10, 13, 9, 1)),
      ]);
      await tester.pumpWidget(monterNv(b, const NvCollecteScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('verser-collecte')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('versement-inv-INV1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mode-ajouter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmer-versement')));
      await tester.pumpAndSettle();
      expect(find.byType(NvRapportVersementScreen), findsOneWidget);
      expect(b.serveur.produit(1).saisi, 12, reason: 'jamais compté sur le serveur : la quantité collectée est posée');
      expect(find.text('codes non reconnus'), findsOneWidget);
      final items = await CollecteStore.lire();
      expect(items.firstWhere((i) => i.code == '3400930000001').versee, isTrue);
      await demonter(tester);
    });

    testWidgets('rapport : export PDF / CSV partagés', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      final partages = <List<XFile>>[];
      NvExports.partager = (f, t) async => partages.add(f);
      final dossier = (await tester.runAsync(() => Directory.systemTemp.createTemp('prestinv_nv_rapport_')))!;
      NvRapportVersementScreen.dossierExport = () async => dossier;
      final v = Versement(
        id: 'V1',
        inventaireId: 'INV1',
        inventaireLibelle: 'Inventaire annuel 2026',
        mode: ModeDejaCompte.remplacer,
        debut: DateTime(2026, 10, 13, 9),
        statut: StatutVersement.termine,
        lignes: [LigneVersement(code: '1', quantiteCollectee: 1, etat: EtatLigneVersement.nonReconnue, raison: 'introuvable')],
      );
      await tester.pumpWidget(monterNv(b, NvRapportVersementScreen(versement: v)));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Partager'));
        for (var i = 0; i < 50 && partages.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await tester.pumpAndSettle();
      expect(partages.single.map((f) => f.path.split('.').last), ['pdf', 'csv']);
      await tester.runAsync(() => dossier.delete(recursive: true));
      await demonter(tester);
    });
  });

  group('Entrée', () {
    testWidgets('connexion : identifiants → AuthProvider.login → accueil', (tester) async {
      tailleEcran(tester, sunmiV2s);
      final b = await preparerBanc(serveur: serveurRealiste());
      InterfaceVersion.useNew.value = true;
      addTearDown(() => InterfaceVersion.useNew.value = false);
      await tester.pumpWidget(monterNv(b, const NvConnexionScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nv-identifiant')), 'admin');
      await tester.enterText(find.byKey(const ValueKey('nv-mot-de-passe')), 'secret');
      await tester.tap(find.byKey(const ValueKey('nv-connexion')));
      await tester.pumpAndSettle();
      expect(b.serveur.appels, contains('POST auth'));
      expect(b.auth.user?.login, isNot('test'), reason: 'session ouverte par la connexion');
      expect(find.byType(NvAccueilScreen), findsOneWidget);
      await demonter(tester);
    });

    testWidgets('serveur injoignable : Réessayer, passage Local ⇄ Distant (adresse renseignée), saisies rappelées', (tester) async {
      tailleEcran(tester, sunmiV2s);
      final b = await preparerBanc(serveur: serveurRealiste(), prefsEnPlus: {'distantApiAddress': 'prestige.exemple.ci'});
      await b.queue.enregistrer(inventaireId: 'INV1', ligneId: 1, quantite: 2);
      var essais = 0;
      await tester.pumpWidget(monterNv(b, NvServeurInjoignableScreen(reessayer: () async => essais++)));
      await tester.pumpAndSettle();
      expect(find.textContaining('licence n\'est pas en cause'), findsOneWidget);
      expect(find.textContaining('1 saisie(s) en attente'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-reessayer-serveur')));
      await tester.pumpAndSettle();
      expect(essais, 1);
      await tester.tap(find.byKey(const ValueKey('nv-basculer-mode')));
      await tester.pumpAndSettle();
      expect(b.config.apiMode, ApiMode.distant);
      expect(essais, 2);
      await tester.pump(const Duration(seconds: 11));
      expect(essais, 3, reason: 'réessai automatique toutes les 10 s');
      await demonter(tester);
    });
  });

  group('Réglages', () {
    testWidgets('connexion verrouillée par le code ; valeurs contrôlées puis enregistrées', (tester) async {
      tailleEcran(tester, telephone360);
      CodeAdmin.instance = CodeAdmin(coffre: CoffreMemoire(), iterations: 1000);
      final b = await banc();
      var pin = false;
      await tester.pumpWidget(monterNv(b, NvConfigScreen(verifierPin: (_) async => pin)));
      await tester.pumpAndSettle();
      final adresse = find.widgetWithText(TextFormField, 'IP ou domaine').first;
      expect(tester.widget<TextFormField>(adresse).enabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('nv-deverrouiller')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(adresse).enabled, isFalse, reason: 'mauvais code');
      pin = true;
      await tester.tap(find.byKey(const ValueKey('nv-deverrouiller')));
      await tester.pumpAndSettle();
      await tester.enterText(adresse, '192.168.1.60');
      await tester.enterText(find.widgetWithText(TextFormField, 'Seuil d\'alerte « grande quantité »'), '500');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('nv-valider-config')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('nv-valider-config')));
      await tester.pumpAndSettle();
      expect(b.config.localApiAddress, '192.168.1.60');
      expect(b.config.largeValueThreshold, 500);
      await demonter(tester);
    });

    testWidgets('réglages scan et sons : son, vibration, essai, quantité proposée', (tester) async {
      tailleEcran(tester, sunmiV2s);
      final b = await banc();
      final retour = installerFauxRetour();
      await tester.pumpWidget(monterNv(b, const NvReglagesScanScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reglage-son-scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erreur'));
      await tester.pump();
      expect(retour.bips, isEmpty, reason: 'son coupé');
      expect(retour.vibrations, ['erreur']);
      await tester.enterText(find.byKey(const ValueKey('reglage-quantite-scan')), '6');
      await tester.tap(find.byKey(const ValueKey('nv-enregistrer-scan')));
      await tester.pumpAndSettle();
      expect((b.config.sonScan, b.config.vibrationScan, b.config.quantiteScanDefaut), (false, true, 6));
      await demonter(tester);
    });
  });

  group('Récapitulatif, cumuls', () {
    testWidgets('récapitulatif : totaux au prix d\'achat / de vente, écart valorisé, impression', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      Uint8List? pdf;
      NvExports.imprimer = (doc, nom) async => pdf = await doc();
      await tester.pumpWidget(monterNv(b, const NvRecapScreen(inventoryId: 'INV1', rayonId: 'S1A0T2', rayonName: 'CANNES')));
      await tester.pumpAndSettle();
      // CANNES : BÉTADINE 30×1800, VOLTARENE 11×3600 (théo 3), BILAN 12×1250, SMECTA 12×2450 (théo 15), ORTHOPÉDIE 4×9800.
      expect(find.text(francs(30 * 1800 + 11 * 3600 + 12 * 1250 + 12 * 2450 + 4 * 9800)), findsOneWidget);
      expect(find.text(francs(8 * 3600 - 3 * 2450, signeExplicite: true)), findsOneWidget);
      await tester.tap(find.byTooltip('Imprimer le récapitulatif'));
      await tester.pumpAndSettle();
      expect(pdf, isNotNull);
      expect(String.fromCharCodes(pdf!.take(4)), '%PDF');
      await demonter(tester);
    });

    testWidgets('historique des cumuls : lignes « avant + ajout = total »', (tester) async {
      tailleEcran(tester, sunmiV2s);
      final b = await banc();
      await b.entry.addCumulLog(
          Product(id: 2, produitCip: '3400935959001', produitName: 'AMOXICILLINE 500 GÉL B/12', produitPrixAchat: 0, produitPrixUni: 0, quantiteInitiale: 10, quantiteSaisie: 6),
          6,
          4);
      await tester.pumpWidget(monterNv(b, const NvCumulsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('6 + 4 = 10'), findsOneWidget);
      await demonter(tester);
    });
  });

  testWidgets('saisies faites dans la nouvelle interface = mêmes données que l\'ancienne (file des saisies, clés)', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await tester.pumpWidget(monterNv(b, NvScanContinuScreen(inventaire: _inv)));
    await tester.pumpAndSettle();
    await douchette(tester, '3400930000001');
    await tester.pumpAndSettle();
    await taperNv(tester, '');
    await tester.pumpAndSettle();
    final s = b.queue.ligne('INV1', 1)!;
    expect((s.quantite, s.origine, s.auteur, s.enAttente, s.inventaireLibelle), (1, OrigineSaisie.rapide, 'Awa K.', true, 'Inventaire annuel 2026'));
    await demonter(tester);
  });
}

