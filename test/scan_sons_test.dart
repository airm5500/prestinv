// Retour sonore / vibration distincts : succès (bip court), déjà compté (double bip, la question
// Remplacer / Ajouter suit le réglage « Cumul » existant), erreur (bip long). Son et vibration se
// coupent dans la Configuration (réglages enregistrés).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/retour_scan.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/banc_essai.dart';

void main() {
  test('RetourScan : le son et la vibration suivent les réglages', () async {
    final f = installerFauxRetour();
    await RetourScan.jouer(TypeRetour.succes, son: true, vibration: true);
    await RetourScan.jouer(TypeRetour.dejaCompte, son: false, vibration: true);
    await RetourScan.jouer(TypeRetour.erreur, son: true, vibration: false);
    await RetourScan.jouer(TypeRetour.erreur, son: false, vibration: false);
    expect(f.bips, ['succes', 'erreur']);
    expect(f.vibrations, ['succes', 'dejaCompte']);
  });

  test('RetourScan : un lecteur en panne ne gêne jamais la saisie', () async {
    RetourScan.lecteur = _LecteurEnPanne();
    await RetourScan.jouer(TypeRetour.erreur, son: true, vibration: true); // ne lève pas
  });

  testWidgets('Configuration : couper le son et la vibration, quantité proposée — enregistrés', (tester) async {
    ecranTerminal(tester);
    installerFauxRetour();
    final b = await preparerBanc();
    expect(b.config.sonScan, isTrue);
    expect(b.config.vibrationScan, isTrue);
    expect(b.config.quantiteScanDefaut, 1);
    await tester.pumpWidget(monter(b, const ConfigScreen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('reglage-quantite-scan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reglage-son-scan')));
    await tester.tap(find.byKey(const ValueKey('reglage-vibration-scan')));
    await tester.enterText(find.byKey(const ValueKey('reglage-quantite-scan')), '');
    await tester.pump();
    await tester.ensureVisible(find.text('VALIDER LA CONFIGURATION'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VALIDER LA CONFIGURATION'));
    await tester.pumpAndSettle();
    expect(b.config.sonScan, isFalse);
    expect(b.config.vibrationScan, isFalse);
    expect(b.config.quantiteScanDefaut, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('scanSon'), isFalse);
    expect(prefs.getBool('scanVibration'), isFalse);
    expect(prefs.getInt('scanQuantiteDefaut'), -1);
    // Relu au démarrage suivant.
    final relu = AppConfig();
    await relu.load();
    expect(relu.sonScan, isFalse);
    expect(relu.quantiteScanDefaut, isNull);
    await demonter(tester);
  });
}

class FauxLecteurRetour implements LecteurRetour {
  final List<String> bips = [];
  final List<String> vibrations = [];
  @override
  Future<void> bip(TypeRetour type) async => bips.add(type.name);
  @override
  Future<void> vibrer(TypeRetour type) async => vibrations.add(type.name);
}

FauxLecteurRetour installerFauxRetour() {
  final f = FauxLecteurRetour();
  RetourScan.lecteur = f;
  return f;
}

class _LecteurEnPanne implements LecteurRetour {
  @override
  Future<void> bip(TypeRetour type) => throw Exception('pas de haut-parleur');
  @override
  Future<void> vibrer(TypeRetour type) => throw Exception('pas de vibreur');
}
