// Version « X.Y.Z+N » affichée, discrète, en bas de l'écran de connexion et dans les Réglages, dans les
// DEUX interfaces (d'origine et nouvelle), LUE À L'EXÉCUTION dans le paquet installé (package_info_plus,
// simulé ici depuis pubspec.yaml) — aucune constante de version dupliquée dans le code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/version_app.dart';

import 'helpers/banc_essai.dart';
import 'helpers/nouvelle_interface.dart';
import 'helpers/version_installee.dart';

void main() {
  late String version; // X.Y.Z+N de pubspec.yaml

  setUp(() => version = simulerVersionInstallee());
  tearDown(() => InterfaceVersion.useNew.value = false);

  Finder texteVersion(Finder dans) => find.descendant(of: dans, matching: find.text('Version $version'));

  testWidgets('VersionAffichee : « Version X.Y.Z+N » lue dans le paquet installé', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VersionAffichee())));
    await tester.pump();
    expect(version, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    expect(find.text('Version $version'), findsOneWidget);
    expect(VersionApp.complete, version);
  });

  testWidgets('la version affichée suit le paquet installé (pas de constante dans le code)', (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'Prestige Inventaire', packageName: 'x', version: '9.8.7', buildNumber: '65', buildSignature: '');
    VersionApp.oublier();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VersionAffichee())));
    await tester.pump();
    expect(find.text('Version 9.8.7+65'), findsOneWidget);
  });

  testWidgets('connexion (interface d\'origine) : version discrète en bas', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const LoginScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AncienLoginScreen), findsOneWidget);
    final v = find.byKey(const Key('version_app'));
    expect(tester.widget<Text>(v).data, 'Version $version');
    expect(tester.getTopLeft(v).dy, greaterThan(tester.getBottomLeft(find.text('CONNEXION')).dy));
    await demonter(tester);
  });

  testWidgets('connexion (nouvelle interface) : version discrète en bas', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    InterfaceVersion.useNew.value = true;
    await tester.pumpWidget(monterNv(b, const LoginScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(NvConnexionScreen), findsOneWidget);
    final v = find.byKey(const Key('version_app'));
    expect(tester.widget<Text>(v).data, 'Version $version');
    expect(tester.getTopLeft(v).dy, greaterThan(tester.getBottomLeft(find.byKey(const ValueKey('nv-mode-connexion'))).dy));
    await demonter(tester);
  });

  testWidgets('Configuration (interface d\'origine) : version en bas', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const ConfigScreen()));
    await tester.pumpAndSettle();
    final v = find.byKey(const ValueKey('reglages-version'));
    await tester.scrollUntilVisible(v, 300, scrollable: find.byType(Scrollable).first);
    expect(texteVersion(v), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('Réglages (nouvelle interface) : version en bas', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    InterfaceVersion.useNew.value = true;
    await tester.pumpWidget(monterNv(b, const NvConfigScreen()));
    await tester.pumpAndSettle();
    final v = find.byKey(const ValueKey('reglages-version'));
    await tester.scrollUntilVisible(v, 300, scrollable: find.byType(Scrollable).first);
    expect(texteVersion(v), findsOneWidget);
    await demonter(tester);
  });
}
