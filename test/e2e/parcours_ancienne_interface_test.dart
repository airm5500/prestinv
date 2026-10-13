// DE BOUT EN BOUT — ANCIENNE INTERFACE (choisie explicitement dans les paramètres : choix enregistré
// `false`) : application entière, faux serveur Prestige. Mêmes parcours que la nouvelle interface, sur
// les écrans d'origine (lib/screens/…), qui doivent rester strictement fonctionnels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/a_envoyer_screen.dart';
import 'package:prestinv/screens/collection_screen.dart';
import 'package:prestinv/screens/global_variance_screen.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
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
}
