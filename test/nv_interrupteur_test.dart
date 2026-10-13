// Interrupteur « Nouvelle interface » : ACTIVÉ par défaut depuis la 4.12.0 (nouvelles installations et
// installations existantes sans choix enregistré), choix explicite de l'ancienne interface respecté ;
// écrans d'origine STRICTEMENT utilisés quand il est désactivé ; présent dans la Configuration d'origine
// et dans les Réglages de la nouvelle, changement protégé par le code administrateur ; aiguillages
// accueil / connexion / lancement / licence / serveur injoignable ; retour arrière immédiat ; apparence
// claire / sombre mémorisée.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/license_register_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/screens/serveur_injoignable_screen.dart';
import 'package:prestinv/services/pin_securise.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/lancement_screen.dart';
import 'package:prestinv/ui/ecrans/licence_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/banc_essai.dart';
import 'helpers/coffre_memoire.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
    InterfaceVersion.useNew.value = false;
  });
  tearDown(() => InterfaceVersion.useNew.value = false);

  test('nouvelle interface par défaut : installation nouvelle, ou existante sans choix enregistré', () async {
    expect(InterfaceVersion.parDefaut, isTrue);
    for (final prefs in [<String, Object>{}, <String, Object>{'localApiAddress': '10.0.0.5', 'sendMode': SendMode.collect.index}]) {
      SharedPreferences.setMockInitialValues(prefs);
      InterfaceVersion.useNew.value = false;
      await InterfaceVersion.load();
      expect(InterfaceVersion.useNew.value, isTrue, reason: 'aucun choix enregistré : $prefs');
    }
  });

  test('choix explicite respecté : ancienne interface choisie → écrans d\'origine, même après mise à jour', () async {
    SharedPreferences.setMockInitialValues({InterfaceVersion.key: false, 'localApiAddress': '10.0.0.5'});
    InterfaceVersion.useNew.value = true;
    await InterfaceVersion.load();
    expect(InterfaceVersion.useNew.value, isFalse);

    SharedPreferences.setMockInitialValues({InterfaceVersion.key: true});
    InterfaceVersion.useNew.value = false;
    await InterfaceVersion.load();
    expect(InterfaceVersion.useNew.value, isTrue);
  });

  testWidgets('au lancement sans choix : accueil et connexion de la nouvelle interface', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(); // préférences d'une installation existante, sans choix d'interface
    await InterfaceVersion.load();
    expect(InterfaceVersion.useNew.value, isTrue);
    await tester.pumpWidget(monter(b, const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(NvAccueilScreen), findsOneWidget);
    expect(find.byType(AncienHomeScreen), findsNothing);
    await tester.pumpWidget(monter(b, const LoginScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(NvConnexionScreen), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('au lancement, ancienne interface choisie : écrans d\'origine', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(prefsEnPlus: {InterfaceVersion.key: false});
    InterfaceVersion.useNew.value = true;
    await InterfaceVersion.load();
    await tester.pumpWidget(monter(b, const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AncienHomeScreen), findsOneWidget);
    expect(find.byType(NvAccueilScreen), findsNothing);
    await demonter(tester);
  });

  test('désactivé : lancement, licence et serveur injoignable = écrans d\'origine', () {
    expect(InterfaceVersion.lancement(), isA<Scaffold>());
    expect(InterfaceVersion.licence(), isA<LicenseRegisterScreen>());
    expect(InterfaceVersion.serveurInjoignable(() async {}), isA<ServeurInjoignableScreen>());
  });

  test('activé : nouveaux écrans d\'entrée, avec le thème de la nouvelle interface', () {
    InterfaceVersion.useNew.value = true;
    Widget dans(Widget w) => (w as NvTheme).child;
    expect(dans(InterfaceVersion.lancement()), isA<NvLancementScreen>());
    expect(dans(InterfaceVersion.licence()), isA<NvLicenceScreen>());
    expect(dans(InterfaceVersion.serveurInjoignable(() async {})), isA<NvServeurInjoignableScreen>());
    expect(InterfaceVersion.home(), isA<HomeScreen>());
  });

  testWidgets('aiguillages : accueil et connexion d\'origine, puis nouveaux, puis retour arrière immédiat', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AncienHomeScreen), findsOneWidget);
    expect(find.text('Inventaire - Accueil'), findsOneWidget);
    expect(find.byType(NvAccueilScreen), findsNothing);

    InterfaceVersion.useNew.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(NvAccueilScreen), findsOneWidget);
    expect(find.byType(AncienHomeScreen), findsNothing);

    InterfaceVersion.useNew.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(AncienHomeScreen), findsOneWidget);

    await tester.pumpWidget(monter(b, const LoginScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AncienLoginScreen), findsOneWidget);
    expect(find.text('CONNEXION'), findsOneWidget);
    InterfaceVersion.useNew.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(NvConnexionScreen), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('Configuration d\'origine : interrupteur proposé ; le changer demande le code administrateur', (tester) async {
    ecranTerminal(tester);
    final coffre = CoffreMemoire();
    CodeAdmin.instance = CodeAdmin(coffre: coffre, iterations: 1000);
    await CodeAdmin.instance.definir('7391');
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const ConfigScreen()));
    await tester.pumpAndSettle();
    final interrupteur = find.byKey(const ValueKey('interrupteur-nouvelle-interface'));
    await tester.scrollUntilVisible(interrupteur, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Nouvelle interface (désactivée)'), findsOneWidget);

    // Mauvais code : rien ne change.
    await tester.tap(interrupteur);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(InterfaceVersion.useNew.value, isFalse);

    // Bon code : activée et mémorisée.
    await tester.tap(interrupteur);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '7391');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(InterfaceVersion.useNew.value, isTrue);
    expect((await SharedPreferences.getInstance()).getBool(InterfaceVersion.key), isTrue);
    await demonter(tester);
  });

  testWidgets('nouvelle Configuration : retour aux écrans d\'origine (code) et apparence sombre mémorisée', (tester) async {
    tailleEcran(tester, telephone360);
    activerNouvelleInterface();
    final b = await preparerBanc();
    var demandes = 0;
    await tester.pumpWidget(monterNv(b, NvConfigScreen(verifierPin: (_) async {
      demandes++;
      return true;
    })));
    await tester.pumpAndSettle();
    final interrupteur = find.byKey(const ValueKey('interrupteur-nouvelle-interface'));
    await tester.scrollUntilVisible(interrupteur, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(interrupteur);
    await tester.pumpAndSettle();
    expect(demandes, 1);
    expect(InterfaceVersion.useNew.value, isFalse, reason: 'retour aux écrans d\'origine');

    await tester.scrollUntilVisible(find.text('Sombre'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sombre'));
    await tester.pumpAndSettle();
    expect(NvApparence.valeur.value, Apparence.sombre);
    expect(Theme.of(tester.element(find.text('Réglages').first)).brightness, Brightness.dark);
    expect((await SharedPreferences.getInstance()).getString(NvApparence.cle), 'sombre');
    await NvApparence.choisir(Apparence.systeme);
    expect(tester.takeException(), isNull);
    await demonter(tester);
  });

  testWidgets('Réglages de la nouvelle interface : retour à l\'ancienne protégé par le code, choix gardé au redémarrage', (tester) async {
    tailleEcran(tester, telephone360);
    final coffre = CoffreMemoire();
    CodeAdmin.instance = CodeAdmin(coffre: coffre, iterations: 1000);
    await CodeAdmin.instance.definir('7391');
    final b = await preparerBanc();
    await InterfaceVersion.load(); // aucun choix : nouvelle interface
    expect(InterfaceVersion.useNew.value, isTrue);
    await tester.pumpWidget(monterNv(b, const NvConfigScreen()));
    await tester.pumpAndSettle();
    final interrupteur = find.byKey(const ValueKey('interrupteur-nouvelle-interface'));
    await tester.scrollUntilVisible(interrupteur, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Nouvelle interface'), findsWidgets);

    // Mauvais code : la nouvelle interface reste.
    await tester.tap(interrupteur);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(InterfaceVersion.useNew.value, isTrue);
    expect((await SharedPreferences.getInstance()).getBool(InterfaceVersion.key), isNull, reason: 'aucun choix enregistré');

    // Bon code : ancienne interface choisie, mémorisée, et respectée au redémarrage.
    await tester.tap(interrupteur);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '7391');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(InterfaceVersion.useNew.value, isFalse);
    expect((await SharedPreferences.getInstance()).getBool(InterfaceVersion.key), isFalse);
    InterfaceVersion.useNew.value = true;
    await InterfaceVersion.load();
    expect(InterfaceVersion.useNew.value, isFalse, reason: 'choix explicite respecté');
    await demonter(tester);
  });
}
