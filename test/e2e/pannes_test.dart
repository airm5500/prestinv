// DE BOUT EN BOUT — PANNES, dans les deux interfaces : serveur coupé ou en erreur au lancement
// (≠ « aucune licence »), aucune licence, licence en cache, session expirée en cours de travail
// (→ reconnexion sans quitter l'écran), serveur coupé en cours de travail (→ message réseau,
// Réessayer), saisie faite hors ligne puis envoyée automatiquement au retour du serveur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/license_register_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/screens/serveur_injoignable_screen.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/licence_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

/// Nouvelle interface (null : valeur par défaut) ou ancienne (false).
const interfaces = <String, bool?>{'nouvelle interface': null, 'ancienne interface': false};

void taille(WidgetTester tester, bool? interface) => interface == false ? ecranTerminal(tester) : tailleEcran(tester, telephone360);

Type ecranInjoignable(bool? i) => i == false ? ServeurInjoignableScreen : NvServeurInjoignableScreen;
Type ecranLicence(bool? i) => i == false ? LicenseRegisterScreen : NvLicenceScreen;
Type ecranConnexion(bool? i) => i == false ? AncienLoginScreen : NvConnexionScreen;

/// Reconnexion dans la fenêtre « Session expirée » (commune aux deux interfaces).
Future<void> reconnecterDansFenetre(WidgetTester tester) async {
  expect(find.textContaining('Reconnectez-vous pour continuer'), findsOneWidget);
  await tester.enterText(find.widgetWithText(TextField, 'Mot de passe').last, CompteFictif.motDePasse);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Se reconnecter').last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(chargerPolicesReelles);

  for (final MapEntry(key: nom, value: i) in interfaces.entries) {
    group(nom, () {
      testWidgets('serveur coupé au lancement : « serveur injoignable » (jamais « licence »), réessai auto → connexion', (tester) async {
        taille(tester, i);
        final serveur = FauxServeurPrestige()..couper();
        await lancerApplication(tester, serveur: serveur, nouvelleInterface: i);
        expect(find.byType(ecranInjoignable(i)), findsOneWidget);
        expect(find.byType(ecranLicence(i)), findsNothing);
        expect(find.textContaining('non activée'), findsNothing);
        serveur.retablir();
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
        expect(find.byType(ecranConnexion(i)), findsOneWidget);
        await fermerApplication(tester);
      });

      for (final code in [500, 503, 401, 403]) {
        testWidgets('licence : réponse $code au lancement → « serveur injoignable », PAS « aucune licence »', (tester) async {
          taille(tester, i);
          final serveur = FauxServeurPrestige()..scripter('licence/find', ReponseScriptee.code(code));
          await lancerApplication(tester, serveur: serveur, nouvelleInterface: i);
          expect(find.byType(ecranInjoignable(i)), findsOneWidget);
          expect(find.byType(ecranLicence(i)), findsNothing);
          await fermerApplication(tester);
        });
      }

      testWidgets('aucune licence enregistrée (le serveur répond, sans licence) : écran de licence', (tester) async {
        taille(tester, i);
        final serveur = FauxServeurPrestige()..licence = null;
        await lancerApplication(tester, serveur: serveur, nouvelleInterface: i);
        expect(find.byType(ecranLicence(i)), findsOneWidget);
        expect(find.byType(ecranInjoignable(i)), findsNothing);
        await fermerApplication(tester);
      });

      testWidgets('serveur coupé mais licence déjà connue (cache) : on peut travailler (écran de connexion)', (tester) async {
        taille(tester, i);
        final serveur = FauxServeurPrestige();
        // Premier lancement : licence lue et mise en cache sur l'appareil.
        await lancerApplication(tester, serveur: serveur, nouvelleInterface: i);
        final cache = (await SharedPreferences.getInstance()).getString('cached_license');
        expect(cache, isNotNull);
        await fermerApplication(tester);
        // Second lancement, serveur coupé, avec ce cache.
        serveur.couper();
        await lancerApplication(tester, serveur: serveur, nouvelleInterface: i, prefs: {'cached_license': cache!});
        expect(find.byType(ecranConnexion(i)), findsOneWidget);
        expect(find.byType(ecranInjoignable(i)), findsNothing);
        await fermerApplication(tester);
      });
    });
  }

  group('Session expirée en cours de travail → reconnexion sans quitter l\'écran', () {
    testWidgets('nouvelle interface : choix du rayon', (tester) async {
      tailleEcran(tester, telephone360);
      final app = await lancerApplication(tester);
      await seConnecter(tester);
      expect(find.byType(NvAccueilScreen), findsOneWidget);
      app.serveur.expirerSessions();
      await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
      await tester.pumpAndSettle();
      expect(find.byType(NvChoixRayonScreen), findsOneWidget);
      expect(find.text('Session expirée'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-reconnecter')));
      await tester.pumpAndSettle();
      await reconnecterDansFenetre(tester);
      expect(app.auth.sessionCookie, 'JSESSIONID=essai-2');
      expect(find.text('S2B2 – ANTIBIOTIQUES'), findsOneWidget, reason: 'rayons rechargés');
      expect(find.byType(NvChoixRayonScreen), findsOneWidget);
      await fermerApplication(tester);
    });

    testWidgets('ancienne interface : liste des inventaires', (tester) async {
      ecranTerminal(tester);
      final app = await lancerApplication(tester, nouvelleInterface: false);
      await seConnecter(tester);
      app.serveur.expirerSessions();
      await tester.tap(find.text('SAISIE GUIDEE\n(Mode Guidé)'));
      await tester.pumpAndSettle();
      expect(find.byType(InventoryListScreen), findsOneWidget);
      expect(find.text('Session expirée'), findsOneWidget);
      await tester.tap(find.text('Se reconnecter'));
      await tester.pumpAndSettle();
      await reconnecterDansFenetre(tester);
      expect(app.auth.sessionCookie, 'JSESSIONID=essai-2');
      expect(find.text('Inventaire annuel 2026'), findsOneWidget);
      await fermerApplication(tester);
    });
  });

  group('Serveur coupé en cours de travail → message réseau, Réessayer', () {
    testWidgets('nouvelle interface', (tester) async {
      tailleEcran(tester, telephone360);
      final app = await lancerApplication(tester);
      await seConnecter(tester);
      app.serveur.couper();
      await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
      await tester.pumpAndSettle();
      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.textContaining('Serveur injoignable'), findsWidgets);
      app.serveur.retablir();
      await tester.tap(find.byKey(const ValueKey('nv-reessayer')));
      await tester.pumpAndSettle();
      expect(find.text('S2B2 – ANTIBIOTIQUES'), findsOneWidget);
      await fermerApplication(tester);
    });

    testWidgets('ancienne interface', (tester) async {
      ecranTerminal(tester);
      final app = await lancerApplication(tester, nouvelleInterface: false);
      await seConnecter(tester);
      app.serveur.couper();
      await tester.tap(find.text('SAISIE GUIDEE\n(Mode Guidé)'));
      await tester.pumpAndSettle();
      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.textContaining('Serveur injoignable'), findsWidgets);
      app.serveur.retablir();
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Inventaire annuel 2026'), findsOneWidget);
      await fermerApplication(tester);
    });
  });

  group('Saisie hors ligne puis reprise automatique (mode Direct)', () {
    testWidgets('nouvelle interface : saisie gardée pendant la coupure, envoyée seule au retour du serveur', (tester) async {
      tailleEcran(tester, telephone360);
      final app = await lancerApplication(tester, mode: SendMode.direct);
      await seConnecter(tester);
      await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
      await tester.pumpAndSettle();
      await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
      await tester.pumpAndSettle();
      expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
      final nomProduit = tester.widget<Text>(find.byKey(const ValueKey('nv-produit-courant'))).data!;
      final ligne = app.serveur.catalogue.produits.firstWhere((p) => p.nom == nomProduit);

      app.serveur.couper();
      await taperNv(tester, '7');
      await tester.pumpAndSettle();
      expect(app.saisies.ligne('INV1', ligne.id)!.enAttente, isTrue, reason: 'gardée sur l\'appareil');
      expect(app.disque.saisies.single.quantite, 7, reason: 'écrite sur le « disque » (survit à un redémarrage)');
      expect(app.serveur.catalogue.produit(ligne.id).saisi, isNot(7));

      app.serveur.retablir();
      await tester.pump(const Duration(seconds: 16)); // reprise automatique (toutes les 15 s)
      await tester.pumpAndSettle();
      expect(app.serveur.catalogue.produit(ligne.id).saisi, 7);
      expect(app.saisies.enAttente(), 0);
      await fermerApplication(tester);
    });

    testWidgets('ancienne interface : idem dans la saisie guidée d\'origine', (tester) async {
      ecranTerminal(tester);
      final app = await lancerApplication(tester, nouvelleInterface: false, mode: SendMode.direct);
      await seConnecter(tester);
      await tester.tap(find.text('SAISIE GUIDEE\n(Mode Guidé)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inventaire annuel 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sélectionner un emplacement'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ANTIBIOTIQUES').last);
      await tester.pumpAndSettle();
      app.serveur.couper();
      await taperQuantite(tester, '7');
      await tester.pumpAndSettle();
      final s = app.disque.saisies.single;
      expect(s.enAttente, isTrue);
      app.serveur.retablir();
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(app.serveur.catalogue.produit(s.ligneId).saisi, 7);
      expect(app.saisies.enAttente(), 0);
      expect(find.byType(AncienHomeScreen), findsNothing);
      await fermerApplication(tester);
    });
  });
}
