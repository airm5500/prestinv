// DE BOUT EN BOUT — 4.13 (maquette validée par le pharmacien), application entière (racineApplication)
// contre le faux serveur Prestige :
//  - accueil → « Voir les inventaires » déroulé → choisir → inventaire choisi → saisie guidée → filtre
//    (paire obligatoire) → Retirer → menu ⋮ → Quitter la saisie ;
//  - onglet Scanner → « Scanner pour… » → Collecte / Scan continu dans l'inventaire choisi ;
//  - envoi manuel : message BLOQUANT après le délai réglé, « Envoyer maintenant » ; délai 0 : envoi
//    automatique toutes les 15 min (horloge simulée) ;
//  - création réservée (profil), réglage protégé, création depuis la collecte ;
//  - taille de l'écran (réglage protégé) appliquée par « Relancer maintenant ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/saisie/rappel_envoi.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/rapport_versement_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/taille_ecran.dart';

import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';

Future<void> toucherCle(WidgetTester tester, String cle) => toucher(tester, find.byKey(ValueKey(cle)));

/// Ouvre la saisie guidée du rayon ANTIBIOTIQUES de INV1 depuis l'accueil.
Future<void> ouvrirSaisie(WidgetTester tester) async {
  await choisirInventaire(tester, 'INV1');
  await toucherCle(tester, 'nv-saisie-guidee');
  await tester.pumpAndSettle();
  await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
  await tester.pumpAndSettle();
  expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
}

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('accueil → liste déroulée → inventaire choisi → saisie guidée → filtre → Retirer → Quitter (menu ⋮)', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    await seConnecter(tester);
    expect(find.byKey(const ValueKey('nv-fleche-bas')), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-ouvrir-INV1')), findsNothing, reason: 'liste repliée');
    await deroulerInventaires(tester);
    expect(find.byKey(const ValueKey('nv-fleche-haut')), findsOneWidget, reason: 'flèche ▲ pour replier');
    // Avancement calculé au déroulé : INV1 commencé → « Poursuivre ».
    expect(tester.widget<Text>(find.byKey(const ValueKey('nv-action-INV1'))).data, 'Poursuivre');
    await choisirInventaire(tester, 'INV1');
    expect(find.byType(NvInventaireScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-avancement-compte')), findsOneWidget, reason: '« 8 / 12 » sur la ligne de la barre');

    await toucherCle(tester, 'nv-saisie-guidee');
    await tester.pumpAndSettle();
    expect(find.byType(NvChoixRayonScreen), findsOneWidget);
    await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
    await tester.pumpAndSettle();
    expect(find.text('Pas encore de filtre appliqué'), findsOneWidget);

    // Filtre : « De » seul refusé ; paire valide appliquée.
    await tester.tap(find.byKey(const ValueKey('nv-filtre')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('nv-filtre-num-de')), '2');
    await tester.tap(find.byKey(const ValueKey('nv-appliquer-filtre')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nv-filtre-erreur')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('nv-filtre-num-a')), '3');
    await tester.tap(find.byKey(const ValueKey('nv-appliquer-filtre')));
    await tester.pumpAndSettle();
    expect(find.text('Filtre : n° 2 à 3 · 2 produits'), findsOneWidget);
    expect(find.text('2 / 4'), findsOneWidget, reason: 'compte « produit / total » sur la ligne de la barre');

    // Annuler ne garde pas une valeur tapée par erreur.
    await tester.tap(find.byKey(const ValueKey('nv-filtre')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('nv-filtre-num-a')), '9');
    await tester.tap(find.byKey(const ValueKey('nv-annuler-filtre')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nv-filtre')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('nv-filtre-num-a'))).controller!.text, '3');
    await tester.tap(find.byKey(const ValueKey('nv-annuler-filtre')));
    await tester.pumpAndSettle();

    // Une saisie, puis « ✕ Retirer » le filtre.
    await taperNv(tester, '5');
    await tester.pumpAndSettle();
    expect(app.saisies.enAttente(), 1);
    await tester.tap(find.byKey(const ValueKey('nv-retirer-filtre')));
    await tester.pumpAndSettle();
    expect(find.text('Pas encore de filtre appliqué'), findsOneWidget);

    // Menu ⋮ (feuille du bas) → Quitter la saisie → fenêtre au nouveau style.
    await tester.tap(find.byKey(const ValueKey('nv-menu-guidee')));
    await tester.pumpAndSettle();
    expect(find.text('Récapitulatif du rayon'), findsOneWidget);
    expect(find.text('Changer de rayon'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-menu-quitter')));
    await tester.pumpAndSettle();
    expect(find.text('Quitter la saisie ?'), findsOneWidget);
    expect(find.textContaining('1 saisie(s) ne sont pas encore envoyées'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-quitter-ignorer')));
    await tester.pumpAndSettle();
    expect(find.byType(NvChoixRayonScreen), findsOneWidget);
    expect(app.saisies.enAttente(), 1, reason: 'saisie gardée sur le téléphone');
    await fermerApplication(tester);
  });

  testWidgets('onglet Scanner : « Scanner pour… » → Collecte ; → scan continu dans l\'inventaire choisi (présélection)', (tester) async {
    tailleEcran(tester, telephone360);
    await lancerApplication(tester);
    await seConnecter(tester);
    await choisirInventaire(tester, 'INV2');
    await revenirAccueil(tester);

    await toucher(tester, find.text('Scanner'));
    await tester.pumpAndSettle();
    expect(find.text('Scanner pour…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-scanner-collecte')));
    await tester.pumpAndSettle();
    expect(find.byType(NvCollecteScreen), findsOneWidget);
    await revenirAccueil(tester);

    await toucher(tester, find.text('Scanner'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Réserve S3 — octobre'), findsWidgets, reason: 'dernier inventaire présélectionné');
    await tester.tap(find.byKey(const ValueKey('nv-scanner-commencer')));
    await tester.pumpAndSettle();
    expect(find.byType(NvScanContinuScreen), findsOneWidget);
    expect(find.textContaining('Réserve S3 — octobre'), findsWidgets);
    await fermerApplication(tester);
  });

  group('Envoi manuel (Collecte)', () {
    late DateTime maintenant;
    setUp(() {
      maintenant = DateTime(2026, 10, 13, 9);
      GardienEnvoi.horloge = () => maintenant;
    });
    tearDown(() => GardienEnvoi.horloge = DateTime.now);

    testWidgets('message BLOQUANT après le délai réglé (15 min) ; « Envoyer maintenant » envoie ; il ne revient plus', (tester) async {
      tailleEcran(tester, telephone360);
      final app = await lancerApplication(tester, horloge: () => maintenant);
      await seConnecter(tester);
      await ouvrirSaisie(tester);
      await taperNv(tester, '7');
      await tester.pumpAndSettle();
      expect(app.saisies.enAttente(), 1);

      maintenant = maintenant.add(const Duration(minutes: 10));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-rappel-sauvegarde')), findsNothing, reason: 'délai pas encore dépassé');

      maintenant = maintenant.add(const Duration(minutes: 6));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.text('Veuillez sauvegarder vos saisies'), findsOneWidget);
      // Bloquant : le retour arrière ne le ferme pas.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Veuillez sauvegarder vos saisies'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nv-rappel-envoyer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-envoi-saisies')), findsOneWidget, reason: 'progression d\'envoi modernisée');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(app.saisies.enAttente(), 0);
      expect(app.serveur.catalogue.produits.where((p) => p.saisi == 7 && p.rayon == 'S2B2'), isNotEmpty);

      maintenant = maintenant.add(const Duration(minutes: 30));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.text('Veuillez sauvegarder vos saisies'), findsNothing, reason: 'tout est envoyé');
      await fermerApplication(tester);
    });

    testWidgets('délai réglé à 0 : pas de message, envoi automatique au bout de 15 min', (tester) async {
      tailleEcran(tester, telephone360);
      final app = await lancerApplication(tester, horloge: () => maintenant, prefs: {'sendReminderMinutes': 0});
      await seConnecter(tester);
      await ouvrirSaisie(tester);
      await taperNv(tester, '4');
      await tester.pumpAndSettle();
      maintenant = maintenant.add(const Duration(minutes: 14));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(app.saisies.enAttente(), 1);
      maintenant = maintenant.add(const Duration(minutes: 2));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.text('Veuillez sauvegarder vos saisies'), findsNothing);
      expect(app.saisies.enAttente(), 0, reason: 'envoyée automatiquement');
      await fermerApplication(tester);
    });
  });

  testWidgets('saisie guidée en envoi manuel : icône d\'envoi avec pastille du nombre de saisies non envoyées', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    await seConnecter(tester);
    await ouvrirSaisie(tester);
    expect(find.byKey(const ValueKey('nv-envoyer-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-badge-attente')), findsNothing);
    await taperNv(tester, '3');
    await tester.pumpAndSettle();
    await taperNv(tester, '2');
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('nv-badge-attente')), matching: find.text('2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-envoyer-badge')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('nv-envoi-saisies')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(app.saisies.enAttente(), 0);
    expect(find.byKey(const ValueKey('nv-badge-attente')), findsNothing);
    await fermerApplication(tester);
  });

  group('Création d\'inventaire réservée', () {
    testWidgets('autre profil : pas de « Créer » ; réglage protégé activé (code administrateur) → bouton visible', (tester) async {
      tailleEcran(tester, telephone360);
      final serveur = FauxServeurPrestige()..typeAccueil = 'mainmenumanager';
      final app = await lancerApplication(tester, serveur: serveur);
      await seConnecter(tester);
      expect(find.byKey(const ValueKey('nouvel-inventaire')), findsNothing);
      await toucher(tester, find.text('Réglages'));
      await tester.pumpAndSettle();
      expect(find.byType(NvConfigScreen), findsOneWidget);
      final reglage = find.byKey(const ValueKey('nv-creation-autres'));
      await tester.scrollUntilVisible(reglage, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(reglage);
      await tester.pumpAndSettle();
      expect(find.text('Code administrateur'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, codeAdminFictif);
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(app.config.creationAutresComptes, isTrue);
      await revenirAccueil(tester);
      expect(find.byKey(const ValueKey('nouvel-inventaire')), findsOneWidget);
      await fermerApplication(tester);
    });

    testWidgets('profil inconnu (serveur plus ancien) : la création demande le code administrateur', (tester) async {
      tailleEcran(tester, telephone360);
      final app = await lancerApplication(tester, serveur: FauxServeurPrestige()..typeAccueil = null);
      await seConnecter(tester);
      await toucherCle(tester, 'nouvel-inventaire');
      await tester.pumpAndSettle();
      expect(find.text('Code administrateur'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(NvAccueilScreen), findsOneWidget, reason: 'sans le code : rien');
      await toucherCle(tester, 'nouvel-inventaire');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, codeAdminFictif);
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(app.serveur.catalogue.creations, isEmpty);
      expect(find.byKey(const ValueKey('libelle-inventaire')), findsOneWidget, reason: 'écran de création ouvert');
      await fermerApplication(tester);
    });
  });

  testWidgets('collecte → « Créer un inventaire avec ces produits » → versement → rapport (non reconnus)', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    await seConnecter(tester);
    await CollecteStore.ecrire([
      CollectedItem(code: '3400930000001', quantity: 12, dateScan: DateTime(2026, 10, 13, 9)),
      CollectedItem(code: '9999999999999', quantity: 3, dateScan: DateTime(2026, 10, 13, 9, 1)),
    ]);
    await toucherCle(tester, 'nv-tuile-collecte');
    await tester.pumpAndSettle();
    await toucherCle(tester, 'creer-avec-collecte');
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('libelle-inventaire'))).controller!.text, startsWith('Collecte du '));
    await toucherCle(tester, 'bouton-creer');
    await tester.pumpAndSettle();
    await toucherCle(tester, 'confirmer-creation');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    expect(app.serveur.catalogue.creations.single.$1, startsWith('Collecte du '));
    expect(find.byType(NvRapportVersementScreen), findsOneWidget);
    expect(find.text('codes non reconnus'), findsOneWidget);
    expect(app.serveur.catalogue.produit(1).saisi, 12);
    await fermerApplication(tester);
  });

  testWidgets('taille de l\'écran : Très compact (code administrateur) → « Relancer maintenant » → interface réduite', (tester) async {
    tailleEcran(tester, sunmiV2s);
    await lancerApplication(tester);
    await seConnecter(tester);
    expect(MediaQuery.sizeOf(tester.element(find.byType(NvAccueilScreen))).width, 360);
    await toucher(tester, find.text('Réglages'));
    await tester.pumpAndSettle();
    final choix = find.byKey(const ValueKey('nv-taille-tresCompact'));
    await tester.scrollUntilVisible(choix, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(choix);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, codeAdminFictif);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(TailleEcranReglage.enregistree, TailleEcran.tresCompact);
    expect(find.byKey(const ValueKey('nv-taille-relancer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-relancer-maintenant')));
    await tester.pumpAndSettle();
    expect(find.byType(NvAccueilScreen), findsOneWidget, reason: 'interface relancée sur l\'accueil, session gardée');
    expect(MediaQuery.sizeOf(tester.element(find.byType(NvAccueilScreen))).width, closeTo(450, 0.01));
    // Les touchers suivent la réduction : la liste se déroule normalement.
    await deroulerInventaires(tester);
    expect(find.byKey(const ValueKey('nv-ouvrir-INV1')), findsOneWidget);
    await fermerApplication(tester);
  });
}
