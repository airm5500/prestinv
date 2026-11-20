// DE BOUT EN BOUT — Prestige Inventaire V3 (5.0.0) : PREMIER LANCEMENT d'une nouvelle installation, application entière
// (racineApplication, comme main()) contre le faux serveur Prestige, données FICTIVES.
// Android sépare les données de chaque application : la V3 (com.dici.prestigeinventaire.v3) ne voit RIEN de l'ancienne
// Prestige Inventaire (adresse du serveur, connexion, code administrateur, saisies hors ligne, réglages). Le parcours
// d'une installation neuve doit donc marcher à partir de rien, exactement comme pour l'ancienne :
//   adresse par défaut (192.168.1.50) injoignable → « Configuration » → code administrateur par défaut 1234 →
//   changement obligatoire → adresse du serveur de l'officine → Réessayer → connexion « Prestige Inventaire V3 » →
//   accueil (liste des inventaires), requêtes vers la nouvelle adresse.
// Bandeau « Ancienne application installée » (détection seulement, rien n'est lu) : affiché sur la connexion des deux
// interfaces si l'ancienne application est installée, jusqu'à « Compris », puis plus jamais ; jamais sans elle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/identite_appli.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';

const _adresse = 'serveur-officine.test';

Future<void> _laisser(WidgetTester tester, [int fois = 6]) async {
  for (var i = 0; i < fois; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(chargerPolicesReelles);
  tearDown(AncienneAppli.reinitialiser);

  testWidgets('nouvelle installation (aucune donnée) : serveur injoignable → configuration sous code → connexion → accueil',
      (tester) async {
    tailleEcran(tester, sunmiV2s);
    final serveur = FauxServeurPrestige()..couper();
    final app = await lancerApplication(tester, serveur: serveur, vierge: true, attendre: false);
    await _laisser(tester);
    expect((await SharedPreferences.getInstance()).getKeys().where((k) => k.startsWith('local')), isEmpty,
        reason: 'appareil vierge : rien de l\'ancienne application');
    expect(app.config.localApiAddress, '192.168.1.50', reason: 'adresse par défaut d\'une installation neuve');

    // 1. Adresse par défaut injoignable : explication, Configuration.
    expect(find.byType(NvServeurInjoignableScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Configuration'));
    await _laisser(tester);
    expect(find.byType(NvConfigScreen), findsOneWidget);

    // 2. Code administrateur par défaut → changement obligatoire → connexion modifiable.
    await toucher(tester, find.byKey(const ValueKey('nv-deverrouiller')));
    await _laisser(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Code'), '1234');
    await tester.tap(find.text('Valider'));
    await _laisser(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nouveau code'), '4827');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmer le code'), '4827');
    await tester.tap(find.text('Enregistrer'));
    await _laisser(tester);
    expect(find.text('Connexion modifiable'), findsOneWidget);

    // 3. Adresse du serveur de l'officine, configuration validée.
    await tester.enterText(find.widgetWithText(TextFormField, 'IP ou domaine').first, _adresse);
    await toucher(tester, find.byKey(const ValueKey('nv-valider-config')));
    await _laisser(tester);
    expect(app.config.localApiAddress, _adresse);

    // 4. Serveur joignable : Réessayer → connexion de la V3 → accueil.
    serveur.retablir();
    if (find.byKey(const ValueKey('nv-reessayer-serveur')).evaluate().isNotEmpty) {
      await toucher(tester, find.byKey(const ValueKey('nv-reessayer-serveur')));
    }
    await _laisser(tester, 12);
    expect(find.byType(NvConnexionScreen), findsOneWidget);
    // 5.0.2 : titre de la connexion « Prestige Inventaire v3 » (v minuscule), sur une ligne.
    expect(find.text(titreConnexion), findsWidgets, reason: 'nom de la V3 sur la connexion');
    expect(find.byKey(const ValueKey('bandeau-ancienne-appli')), findsNothing, reason: 'ancienne application absente');
    await seConnecter(tester);
    await _laisser(tester, 12);
    expect(find.byType(NvAccueilScreen), findsOneWidget);
    expect(serveur.requetes.last.hote, '$_adresse:8080', reason: 'requêtes vers l\'adresse saisie');
    expect(tester.takeException(), isNull);
    await fermerApplication(tester);
  });

  group('Bandeau « Ancienne application installée »', () {
    final bandeau = find.byKey(const ValueKey('bandeau-ancienne-appli'));

    for (final nouvelle in [true, false]) {
      testWidgets('${nouvelle ? 'nouvelle' : 'ancienne'} interface : bandeau sur la connexion, « Compris » → plus jamais',
          (tester) async {
        tailleEcran(tester, sunmiV2s);
        var detections = 0;
        AncienneAppli.detecteur = () async {
          detections++;
          return true;
        };
        await lancerApplication(tester, nouvelleInterface: nouvelle);
        await _laisser(tester);
        expect(find.byType(nouvelle ? NvConnexionScreen : LoginScreen), findsOneWidget);
        expect(bandeau, findsOneWidget);
        expect(find.text(AncienneAppli.message), findsOneWidget);
        await toucher(tester, find.byKey(const ValueKey('bandeau-ancienne-appli-compris')));
        await _laisser(tester, 2);
        expect(bandeau, findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(AncienneAppli.prefVu), isTrue);
        expect(detections, 1);

        // Écran reconstruit (lancement suivant) : plus de bandeau, plus de détection.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [BandeauAncienneAppli()]))));
        await _laisser(tester, 2);
        expect(bandeau, findsNothing);
        expect(detections, 1);
        await fermerApplication(tester);
      });
    }

    testWidgets('ancienne application absente, ou détection impossible : aucun bandeau, connexion normale', (tester) async {
      tailleEcran(tester, sunmiV2s);
      for (final d in <Future<bool> Function()>[() async => false, () async => throw Exception('canal absent')]) {
        AncienneAppli.detecteur = d;
        await lancerApplication(tester);
        await _laisser(tester);
        expect(InterfaceVersion.useNew.value, isTrue);
        expect(find.byType(NvConnexionScreen), findsOneWidget);
        expect(bandeau, findsNothing);
        await seConnecter(tester);
        await _laisser(tester, 12);
        expect(find.byType(NvAccueilScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await fermerApplication(tester);
      }
    });
  });
}
