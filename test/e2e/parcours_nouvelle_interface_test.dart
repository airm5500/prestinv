// DE BOUT EN BOUT — NOUVELLE INTERFACE (celle par défaut depuis la 4.12) : l'application ENTIÈRE est
// montée (racineApplication, comme main()), sans aucun choix d'interface enregistré, contre le faux
// serveur Prestige. Chaque test suit un parcours réel du terminal, de l'écran de lancement jusqu'au
// serveur : licence → connexion → accueil → choix de l'inventaire → saisie guidée / scan (douchette
// Sunmi simulée) → envoi → écarts → avancement → collecte et versement → création d'inventaire →
// retour à l'ancienne interface par les réglages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/navigation.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/rapport_versement_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/donnees_fictives.dart';

Future<void> toucherCle(WidgetTester tester, String cle) => toucher(tester, find.byKey(ValueKey(cle)));

/// Laisse finir les requêtes retardées (minuteries) puis les animations.
Future<void> laisserFinir(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('lancement → connexion (refus puis succès, cookie) → accueil de la nouvelle interface', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    expect(InterfaceVersion.useNew.value, isTrue, reason: 'aucun choix enregistré : nouvelle interface');
    expect(app.serveur.recues('licence/find'), hasLength(1), reason: 'licence vérifiée au lancement');
    expect(find.byType(NvConnexionScreen), findsOneWidget);

    await seConnecter(tester, motDePasse: 'mauvais');
    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    expect(find.byType(NvConnexionScreen), findsOneWidget);
    expect(app.auth.isLoggedIn, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await seConnecter(tester);
    expect(find.byType(NvAccueilScreen), findsOneWidget);
    expect(app.auth.sessionCookie, 'JSESSIONID=essai-1');
    expect(find.text('Inventaire annuel 2026'), findsWidgets);
    // Toutes les requêtes après la connexion portent le cookie de la session.
    final derniereConnexion = app.serveur.requetes.lastIndexWhere((r) => r.route == 'user/auth');
    final apres = app.serveur.requetes.skip(derniereConnexion + 1).where((r) => r.route != 'licence/find');
    expect(apres, isNotEmpty);
    expect(apres.every((r) => r.cookie == 'JSESSIONID=essai-1'), isTrue, reason: '$apres');
    await fermerApplication(tester);
  });

  testWidgets('choix d\'inventaire → saisie guidée (rayon) → saisie gardée → Envoyer depuis l\'accueil → serveur à jour', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    await seConnecter(tester);

    // Choix de l'inventaire en cours (mémorisé).
    await toucher(tester, find.byKey(const ValueKey('nv-inv-INV2')));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString(InventaireCourant.cle), 'INV2');
    await toucher(tester, find.byKey(const ValueKey('nv-inv-INV1')));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString(InventaireCourant.cle), 'INV1');

    await toucherCle(tester, 'nv-saisie-guidee');
    await tester.pumpAndSettle();
    expect(find.byType(NvChoixRayonScreen), findsOneWidget);
    await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
    await tester.pumpAndSettle();
    expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
    final produit = tester.widget<Text>(find.byKey(const ValueKey('nv-produit-courant'))).data!;
    final ligne = app.serveur.catalogue.produits.firstWhere((p) => p.nom == produit);
    await taperNv(tester, '7');
    await tester.pumpAndSettle();
    expect(app.saisies.ligne('INV1', ligne.id)!.quantite, 7);
    expect(app.saisies.ligne('INV1', ligne.id)!.enAttente, isTrue, reason: 'mode Collecte : gardée jusqu\'à l\'envoi');
    expect(app.serveur.catalogue.produit(ligne.id).saisi, isNot(7));

    await revenirAccueil(tester);
    expect(find.textContaining('1 saisie(s) sur le téléphone'), findsOneWidget);
    await toucherCle(tester, 'nv-envoyer-tout');
    await tester.pumpAndSettle();
    expect(app.serveur.catalogue.produit(ligne.id).saisi, 7);
    expect(app.saisies.enAttente(), 0);
    expect(find.byKey(const ValueKey('nv-bandeau-a-envoyer')), findsNothing);
    await fermerApplication(tester);
  });

  testWidgets('scan continu : douchette Sunmi → quantité → envoi direct au serveur', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester, mode: SendMode.direct);
    await seConnecter(tester);
    await toucherCle(tester, 'nv-scan-continu');
    await tester.pumpAndSettle();
    expect(find.byType(NvScanContinuScreen), findsOneWidget);
    expect(champScanAFocus(tester), isTrue, reason: 'douchette prête dès l\'ouverture');

    expect(await toucheSunmi(tester, 521), isTrue, reason: 'touche latérale de scan reconnue');
    await douchette(tester, '3400930000001');
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000 MG CPR B/8'), findsWidgets);
    await taperNv(tester, '24');
    await laisserFinir(tester);
    expect(app.serveur.catalogue.produit(1).saisi, 24, reason: 'mode Direct : envoyé tout de suite');
    expect(app.saisies.ligne('INV1', 1)!.envoyee, isTrue);
    expect(champScanAFocus(tester), isTrue, reason: 'prête pour le scan suivant');

    // Code inconnu : signalé, rien n'est envoyé.
    final avant = app.serveur.recues('details', methode: 'PUT').length;
    await douchette(tester, '0000000000000');
    await tester.pumpAndSettle();
    expect(find.textContaining('introuvable'), findsWidgets);
    expect(app.serveur.recues('details', methode: 'PUT'), hasLength(avant));
    await fermerApplication(tester);
  });

  testWidgets('écarts et « Actualiser l\'avancement » depuis l\'accueil', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    await seConnecter(tester);
    expect(find.byKey(const ValueKey('nv-avancement-pct')), findsNothing, reason: 'jamais calculé automatiquement');
    final avant = app.serveur.recues('detailsTouchedRayon').length;
    await toucherCle(tester, 'nv-actualiser-avancement');
    await laisserFinir(tester);
    expect(app.serveur.recues('detailsTouchedRayon').length, greaterThan(avant));
    expect(find.byKey(const ValueKey('nv-avancement-pct')), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-avancement-heure')), findsOneWidget);

    await toucherCle(tester, 'nv-tuile-ecarts');
    await tester.pumpAndSettle();
    expect(find.byType(NvEcartsScreen), findsOneWidget);
    expect(app.serveur.recues('detailsAllEcarts'), isNotEmpty);
    // INSULINE : théorique 9, compté 4 → écart.
    expect(find.textContaining('INSULINE LANTUS SOLOSTAR'), findsWidgets);
    await fermerApplication(tester);
  });

  testWidgets('collecte hors ligne (douchette) → versement dans l\'inventaire ouvert → rapport', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    await seConnecter(tester);
    await toucherCle(tester, 'nv-tuile-collecte');
    await tester.pumpAndSettle();
    expect(find.byType(NvCollecteScreen), findsOneWidget);
    await douchette(tester, '3400938000004');
    await tester.pumpAndSettle();
    await taperNv(tester, '30');
    await tester.pumpAndSettle();
    await douchette(tester, '9999999999999');
    await tester.pumpAndSettle();
    await taperNv(tester, '2');
    await tester.pumpAndSettle();
    expect((await CollecteStore.lire()).map((i) => (i.code, i.quantity)), containsAll([('3400938000004', 30), ('9999999999999', 2)]));
    expect(app.serveur.recues('ligne/quantite'), isEmpty, reason: 'collecte : rien n\'est envoyé avant le versement');

    await toucherCle(tester, 'verser-collecte');
    await tester.pumpAndSettle();
    await toucherCle(tester, 'versement-inv-INV1');
    await tester.pumpAndSettle();
    await toucherCle(tester, 'confirmer-versement');
    await laisserFinir(tester);
    expect(find.byType(NvRapportVersementScreen), findsOneWidget);
    expect(app.serveur.catalogue.produit(5).saisi, 30);
    expect(find.text('codes non reconnus'), findsOneWidget);
    expect(app.serveur.recues('ligne/quantite', methode: 'POST').single.cookie, 'JSESSIONID=essai-1');
    await fermerApplication(tester);
  });

  testWidgets('création d\'un inventaire depuis l\'accueil → il devient choisissable', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    await seConnecter(tester);
    await toucherCle(tester, 'nouvel-inventaire');
    await tester.pumpAndSettle();
    expect(find.byType(NvCreationInventaireScreen), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve novembre');
    await toucherCle(tester, 'bouton-creer');
    await tester.pumpAndSettle();
    await toucherCle(tester, 'confirmer-creation');
    await tester.pumpAndSettle();
    expect(app.serveur.catalogue.creations.single.$1, 'Réserve novembre');
    expect(find.byType(NvAccueilScreen), findsOneWidget);
    expect(find.text('Réserve novembre'), findsWidgets);
    await fermerApplication(tester);
  });

  testWidgets('réglages : retour à l\'ancienne interface (code administrateur), gardé au relancement', (tester) async {
    tailleEcran(tester, telephone360);
    await lancerApplication(tester);
    await seConnecter(tester);
    await toucher(tester, find.text('Réglages'));
    await tester.pumpAndSettle();
    final interrupteur = find.byKey(const ValueKey('interrupteur-nouvelle-interface'));
    await tester.scrollUntilVisible(interrupteur, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(interrupteur);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, codeAdminFictif);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(InterfaceVersion.useNew.value, isFalse);
    await revenirAccueil(tester);
    expect(find.byType(AncienHomeScreen), findsOneWidget);
    expect(find.text('Inventaire - Accueil'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool(InterfaceVersion.key), isFalse);
    await fermerApplication(tester);
  });

  testWidgets('déconnexion : retour à la connexion, session fermée sur le serveur', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    await seConnecter(tester);
    await tester.tap(find.byTooltip('Déconnexion'));
    await tester.pumpAndSettle();
    // Confirmation éventuelle.
    final confirmer = find.widgetWithText(FilledButton, 'Déconnexion');
    if (confirmer.evaluate().isNotEmpty) {
      await tester.tap(confirmer.last);
      await tester.pumpAndSettle();
    }
    expect(app.auth.isLoggedIn, isFalse);
    expect(app.serveur.sessionsValides, isEmpty);
    expect(find.byType(NvConnexionScreen), findsOneWidget);
    expect(CompteFictif.login, isNotEmpty);
    await fermerApplication(tester);
  });
}
