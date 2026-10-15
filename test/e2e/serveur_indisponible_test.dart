// DE BOUT EN BOUT — 4.15.2 / 4.15.3, retours du pharmacien, nouvelle ET ancienne interface : connexion,
// lancement (licence), lecture après connexion ; deux cas distincts :
//  - Prestige non déployé (404 de Payara, 502 / 503) → « Serveur indisponible : Prestige est en cours de
//    démarrage ou de redéploiement. Veuillez réessayer dans un instant. » (et non « erreur 404 ») ;
//  - aucune réponse (PC serveur éteint, connexion refusée) → « Serveur injoignable. Vérifiez le Wi-Fi et que
//    le PC serveur est allumé. » ;
// puis le serveur revient et tout fonctionne.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/license_register_screen.dart';
import 'package:prestinv/screens/serveur_injoignable_screen.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/licence_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';

import '../helpers/banc_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';

const pageHtml404 = '<html><body><h1>HTTP Status 404 - Not Found</h1></body></html>';

void main() {
  setUpAll(chargerPolicesReelles);

  for (final nouvelle in [true, false]) {
    final nom = nouvelle ? 'nouvelle interface' : 'ancienne interface';
    void ecran(WidgetTester tester) => nouvelle ? tailleEcran(tester, telephone360) : ecranTerminal(tester);

    group(nom, () {
      for (final (cas, reponse) in [
        ('404 (redéploiement)', ReponseScriptee(code: 404, corps: pageHtml404, fois: 1)),
        ('503', ReponseScriptee.code(503, fois: 1)),
      ]) {
        testWidgets('connexion pendant le redéploiement ($cas) : « Serveur indisponible… », puis connexion', (tester) async {
          ecran(tester);
          final app = await lancerApplication(tester, nouvelleInterface: nouvelle);
          app.serveur.scripter('user/auth', reponse);
          await seConnecter(tester);
          expect(find.text(ApiService.messageIndisponible), findsOneWidget);
          expect(find.textContaining('404'), findsNothing, reason: 'plus d\'« erreur 404 »');
          expect(find.textContaining('mot de passe'), findsNothing, reason: 'jamais confondu avec un mot de passe faux');
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          await seConnecter(tester);
          expect(find.byType(nouvelle ? NvAccueilScreen : AncienHomeScreen), findsOneWidget);
          await fermerApplication(tester);
        });
      }

      testWidgets('connexion PC serveur éteint (connexion refusée) : « Serveur injoignable… », distinct du cas 2', (tester) async {
        ecran(tester);
        final app = await lancerApplication(tester, nouvelleInterface: nouvelle);
        app.serveur.couper();
        await seConnecter(tester);
        expect(find.text(ApiService.messageInjoignable), findsOneWidget);
        expect(find.textContaining('Serveur indisponible'), findsNothing);
        app.serveur.retablir();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await seConnecter(tester);
        expect(find.byType(nouvelle ? NvAccueilScreen : AncienHomeScreen), findsOneWidget);
        await fermerApplication(tester);
      });

      testWidgets('lancement, PC serveur éteint : « Serveur injoignable », pas « indisponible »', (tester) async {
        ecran(tester);
        final serveur = FauxServeurPrestige()..couper();
        await lancerApplication(tester, serveur: serveur, nouvelleInterface: nouvelle);
        expect(find.byType(nouvelle ? NvServeurInjoignableScreen : ServeurInjoignableScreen), findsOneWidget);
        expect(find.text('Serveur injoignable'), findsOneWidget);
        expect(find.textContaining('Serveur indisponible'), findsNothing);
        await fermerApplication(tester);
      });

      testWidgets('lancement pendant le redéploiement (licence en 404) : serveur indisponible, PAS « aucune licence »', (tester) async {
        ecran(tester);
        final serveur = FauxServeurPrestige();
        serveur.scripter('licence/find', ReponseScriptee(code: 404, corps: pageHtml404));
        await lancerApplication(tester, serveur: serveur, nouvelleInterface: nouvelle);
        expect(find.byType(nouvelle ? NvServeurInjoignableScreen : ServeurInjoignableScreen), findsOneWidget);
        expect(find.byType(nouvelle ? NvLicenceScreen : LicenseRegisterScreen), findsNothing);
        expect(find.textContaining('Serveur indisponible'), findsWidgets);
        expect(find.text('Serveur indisponible'), findsOneWidget, reason: 'titre dédié, deux interfaces');
        expect(find.textContaining('démarrage ou de redéploiement'), findsWidgets);
        await fermerApplication(tester);
      });
    });
  }

  testWidgets('nouvelle interface : liste des inventaires en 503 après la connexion → « Serveur indisponible », Réessayer', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester);
    app.serveur.scripter('ws/inventaires', ReponseScriptee.code(503, fois: 2));
    await seConnecter(tester);
    await deroulerInventaires(tester);
    expect(find.textContaining('Serveur indisponible'), findsWidgets);
    expect(find.textContaining('démarrage ou de redéploiement'), findsWidgets);
    expect(find.textContaining('code 503'), findsNothing);
    await fermerApplication(tester);
  });
}
