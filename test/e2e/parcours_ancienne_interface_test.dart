// DE BOUT EN BOUT — ANCIENNE INTERFACE (choisie explicitement dans les paramètres : choix enregistré
// `false`) : application entière, faux serveur Prestige. Mêmes parcours que la nouvelle interface, sur
// les écrans d'origine (lib/screens/…), qui doivent rester strictement fonctionnels.
// 4.13.1 : le rappel global « Veuillez sauvegarder vos saisies » (envoi manuel) s'applique aussi ici,
// au style d'origine, à la place de l'ancien bandeau de 5 s ; délai 0 → envoi automatique 15 min.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/saisie/rappel_envoi.dart';
import 'package:prestinv/screens/a_envoyer_screen.dart';
import 'package:prestinv/screens/collection_screen.dart';
import 'package:prestinv/screens/global_variance_screen.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/donnees_fictives.dart';

/// Écran de test large : la police d'essai (carrés) est plus large que Roboto (voir banc_essai.dart).
void ecran(WidgetTester tester) => ecranTerminal(tester);

Future<void> ouvrirInventaire(WidgetTester tester, String bouton) async {
  await tester.tap(find.text(bouton));
  await tester.pumpAndSettle();
  expect(find.byType(InventoryListScreen), findsOneWidget);
  await tester.tap(find.text('Inventaire annuel 2026'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('lancement → connexion d\'origine → accueil d\'origine (cookie de session)', (tester) async {
    ecran(tester);
    final app = await lancerApplication(tester, nouvelleInterface: false);
    expect(InterfaceVersion.useNew.value, isFalse, reason: 'choix explicite respecté');
    expect(find.byType(AncienLoginScreen), findsOneWidget);
    await seConnecter(tester, motDePasse: 'mauvais');
    expect(find.byType(AncienLoginScreen), findsOneWidget);
    expect(app.auth.isLoggedIn, isFalse);
    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await seConnecter(tester);
    expect(find.byType(AncienHomeScreen), findsOneWidget);
    expect(find.text('Bienvenue, ${CompteFictif.prenom}'), findsOneWidget);
    expect(app.auth.sessionCookie, 'JSESSIONID=essai-1');
    await fermerApplication(tester);
  });

  testWidgets('saisie guidée : inventaire → emplacement → quantité → « À envoyer » → serveur à jour', (tester) async {
    ecran(tester);
    final app = await lancerApplication(tester, nouvelleInterface: false);
    await seConnecter(tester);
    await ouvrirInventaire(tester, 'SAISIE GUIDEE\n(Mode Guidé)');
    expect(find.byType(InventoryEntryScreen), findsOneWidget);
    await tester.tap(find.text('Sélectionner un emplacement'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('ANTIBIOTIQUES').last);
    await tester.pumpAndSettle();
    await taperQuantite(tester, '7');
    await tester.pumpAndSettle();
    final s = app.disque.saisies.single;
    expect((s.inventaireId, s.quantite, s.enAttente), ('INV1', 7, true));
    expect(app.serveur.catalogue.produit(s.ligneId).rayon, 'S2B2');

    await revenirAccueil(tester);
    await tester.tap(find.text('1 saisie(s) à envoyer'));
    await tester.pumpAndSettle();
    expect(find.byType(AEnvoyerScreen), findsOneWidget);
    await tester.tap(find.text('Envoyer maintenant'));
    await tester.pumpAndSettle();
    expect(app.serveur.catalogue.produit(s.ligneId).saisi, 7);
    expect(find.text('Tout est envoyé.'), findsOneWidget);
    await fermerApplication(tester);
  });

  testWidgets('saisie rapide (scan) : douchette Sunmi → quantité → envoi direct', (tester) async {
    ecran(tester);
    final app = await lancerApplication(tester, nouvelleInterface: false, mode: SendMode.direct);
    await seConnecter(tester);
    await ouvrirInventaire(tester, 'SAISIE RAPIDE\n(Mode Scan)');
    expect(find.text('Scan'), findsOneWidget);
    expect(champScanAFocus(tester), isTrue);
    await douchette(tester, '3400937000003');
    await tester.pumpAndSettle();
    expect(find.text('SPASFON LYOC 80 MG'), findsWidgets);
    await taperQuantite(tester, '5');
    await tester.pumpAndSettle();
    expect(app.serveur.catalogue.produit(4).saisi, 5);
    expect(app.saisies.ligne('INV1', 4)!.envoyee, isTrue);
    await fermerApplication(tester);
  });

  testWidgets('correction des écarts : liste des écarts de l\'inventaire', (tester) async {
    ecran(tester);
    final app = await lancerApplication(tester, nouvelleInterface: false);
    await seConnecter(tester);
    await ouvrirInventaire(tester, 'CORRECTION ÉCARTS\n(Scan & Liste)');
    expect(find.byType(GlobalVarianceScreen), findsOneWidget);
    expect(app.serveur.recues('detailsAllEcarts'), isNotEmpty);
    expect(find.textContaining('INSULINE LANTUS SOLOSTAR'), findsWidgets);
    await fermerApplication(tester);
  });

  testWidgets('collecte libre (douchette) → versement dans l\'inventaire → rapport', (tester) async {
    ecran(tester);
    final app = await lancerApplication(tester, nouvelleInterface: false);
    await seConnecter(tester);
    await tester.tap(find.text('COLLECTE LIBRE\n(Mode Hors-ligne)'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionScreen), findsOneWidget);
    // Écran d'origine : champ texte simple (la douchette en émulation clavier y écrit puis valide).
    await tester.enterText(find.widgetWithText(TextField, 'Scanner un code'), '3400938000004');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Code : 3400938000004'), findsOneWidget);
    await taperQuantite(tester, '30');
    await tester.pumpAndSettle();
    expect((await CollecteStore.lire()).single.quantity, 30);
    expect(app.serveur.recues('ligne/quantite'), isEmpty, reason: 'rien n\'est envoyé avant le versement');

    await tester.tap(find.byKey(const ValueKey('verser-collecte')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('versement-inv-INV1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmer-versement')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    expect(app.serveur.catalogue.produit(5).saisi, 30);
    expect((await CollecteStore.lire()).single.versee, isTrue);
    await fermerApplication(tester);
  });

  testWidgets('Configuration d\'origine : passage à la nouvelle interface (code administrateur)', (tester) async {
    ecran(tester);
    await lancerApplication(tester, nouvelleInterface: false);
    await seConnecter(tester);
    await tester.tap(find.byTooltip('Configuration'));
    await tester.pumpAndSettle();
    final interrupteur = find.byKey(const ValueKey('interrupteur-nouvelle-interface'));
    await tester.scrollUntilVisible(interrupteur, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(interrupteur);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, codeAdminFictif);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(InterfaceVersion.useNew.value, isTrue);
    await revenirAccueil(tester);
    expect(find.byType(NvAccueilScreen), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool(InterfaceVersion.key), isTrue);
    await fermerApplication(tester);
  });

  group('Envoi manuel (Collecte) — rappel global dans l\'ancienne interface (4.13.1)', () {
    late DateTime maintenant;
    setUp(() {
      maintenant = DateTime(2026, 10, 13, 9);
      GardienEnvoi.horloge = () => maintenant;
    });
    tearDown(() => GardienEnvoi.horloge = DateTime.now);

    Future<void> saisirSept(WidgetTester tester) async {
      await ouvrirInventaire(tester, 'SAISIE GUIDEE\n(Mode Guidé)');
      await tester.tap(find.text('Sélectionner un emplacement'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ANTIBIOTIQUES').last);
      await tester.pumpAndSettle();
      await taperQuantite(tester, '7');
      await tester.pumpAndSettle();
    }

    testWidgets('message BLOQUANT au style d\'origine après le délai (15 min), sans l\'ancien bandeau ; « Envoyer maintenant » envoie', (tester) async {
      ecran(tester);
      final app = await lancerApplication(tester, nouvelleInterface: false, horloge: () => maintenant);
      await seConnecter(tester);
      await saisirSept(tester);
      expect(app.saisies.enAttente(), 1);

      maintenant = maintenant.add(const Duration(minutes: 10));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.text('⚠️ Veuillez sauvegarder vos saisies'), findsNothing, reason: 'délai pas encore dépassé');

      // 16 minutes de temps simulé : l'ancien rappel de l'écran (bandeau de 5 s après 15 min) aurait
      // eu le temps de partir ; seul le message global, une seule fois, apparaît.
      maintenant = maintenant.add(const Duration(minutes: 6));
      await tester.pump(const Duration(minutes: 16));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('origine-rappel-sauvegarde')), findsOneWidget);
      expect(find.text('⚠️ Veuillez sauvegarder vos saisies'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'style de l\'ancienne interface');
      expect(find.byKey(const ValueKey('nv-rappel-sauvegarde')), findsNothing, reason: 'pas le style de la nouvelle interface');
      expect(find.byType(NvCadreDialogue), findsNothing);
      expect(find.text('Rappel : Vous avez des données non envoyées !'), findsNothing, reason: 'ancien rappel remplacé (pas de doublon)');
      expect(find.byType(InventoryEntryScreen), findsOneWidget, reason: 'affiché par-dessus la saisie guidée d\'origine');
      // Bloquant : le retour arrière ne le ferme pas.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('origine-rappel-sauvegarde')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('origine-rappel-envoyer')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('origine-envoi-saisies')), findsOneWidget, reason: 'progression d\'envoi d\'origine');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('origine-envoi-saisies')), findsNothing);
      expect(app.saisies.enAttente(), 0);
      expect(app.serveur.catalogue.produits.where((p) => p.saisi == 7 && p.rayon == 'S2B2'), isNotEmpty);

      maintenant = maintenant.add(const Duration(minutes: 30));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('origine-rappel-sauvegarde')), findsNothing, reason: 'tout est envoyé');
      await fermerApplication(tester);
    });

    testWidgets('serveur coupé : le message revient 2 minutes après l\'essai, saisies gardées', (tester) async {
      ecran(tester);
      final app = await lancerApplication(tester, nouvelleInterface: false, horloge: () => maintenant);
      await seConnecter(tester);
      await saisirSept(tester);
      maintenant = maintenant.add(const Duration(minutes: 16));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      app.serveur.couper();
      await tester.tap(find.byKey(const ValueKey('origine-rappel-envoyer')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(app.saisies.enAttente(), 1, reason: 'gardée sur l\'appareil');
      expect(find.byKey(const ValueKey('origine-rappel-sauvegarde')), findsNothing);
      maintenant = maintenant.add(const Duration(minutes: 1));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('origine-rappel-sauvegarde')), findsNothing, reason: 'pas avant 2 minutes');
      maintenant = maintenant.add(const Duration(minutes: 2));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('origine-rappel-sauvegarde')), findsOneWidget, reason: 'il revient');
      app.serveur.retablir();
      await tester.tap(find.byKey(const ValueKey('origine-rappel-envoyer')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(app.saisies.enAttente(), 0);
      await fermerApplication(tester);
    });

    testWidgets('délai réglé à 0 : pas de message, envoi automatique au bout de 15 min (horloge simulée)', (tester) async {
      ecran(tester);
      final app = await lancerApplication(tester, nouvelleInterface: false, horloge: () => maintenant, prefs: {'sendReminderMinutes': 0});
      await seConnecter(tester);
      await saisirSept(tester);
      expect(app.saisies.enAttente(), 1);
      maintenant = maintenant.add(const Duration(minutes: 14));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(app.saisies.enAttente(), 1, reason: 'pas avant 15 minutes');
      expect(app.serveur.recues('ligne/quantite'), isEmpty);
      maintenant = maintenant.add(const Duration(minutes: 2));
      await tester.pump(GardienEnvoi.periode);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('origine-rappel-sauvegarde')), findsNothing);
      expect(find.text('Rappel : Vous avez des données non envoyées !'), findsNothing);
      expect(app.saisies.enAttente(), 0, reason: 'envoyée automatiquement');
      expect(app.serveur.catalogue.produits.where((p) => p.saisi == 7 && p.rayon == 'S2B2'), isNotEmpty);
      await fermerApplication(tester);
    });
  });
}
