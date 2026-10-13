// Retour sonore / vibration distincts : succès (bip court), déjà compté (double bip, la question
// Remplacer / Ajouter suit le réglage « Cumul » existant), erreur (bip long). Son et vibration se
// coupent dans la Configuration (réglages enregistrés).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/retour_scan.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';

void main() {
  setUp(reinitialiserDouchette);

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

  testWidgets('scan : trouvé = bip court, déjà compté = double bip, introuvable = bip long', (tester) async {
    ecranTerminal(tester);
    final f = installerFauxRetour();
    final b = await preparerBanc(mode: SendMode.collect);
    b.serveur.produits[1]
      ..saisi = 6
      ..dtUpdated = '2026-10-13T08:55:00'; // compté par un collègue
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();

    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    expect(f.bips.last, 'succes');
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await douchette(tester, b.serveur.produits[1].cip);
    await tester.pumpAndSettle();
    expect(f.bips.last, 'dejaCompte');
    expect(find.textContaining('Déjà compté : 6'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await douchette(tester, '1111111111111');
    await tester.pumpAndSettle();
    expect(f.bips.last, 'erreur');
    expect(f.vibrations, ['succes', 'dejaCompte', 'erreur']);
    await demonter(tester);
  });

  testWidgets('déjà compté + cumul activé : double bip puis la question « Additionner ? » (inchangée)', (tester) async {
    ecranTerminal(tester);
    final f = installerFauxRetour();
    final b = await preparerBanc(mode: SendMode.collect, cumul: true);
    b.serveur.produits[2]
      ..saisi = 6
      ..dtUpdated = '2026-10-13T08:55:00';
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await douchette(tester, b.serveur.produits[2].cip);
    await tester.pumpAndSettle();
    expect(f.bips.last, 'dejaCompte');
    expect(find.textContaining('Remplacer ou Ajouter vous sera demandé'), findsOneWidget);
    await taperQuantite(tester, '4');
    await tester.pumpAndSettle();
    expect(find.text('⚠️ Déjà compté'), findsOneWidget);
    await tester.tap(find.text('OUI (Additionner)'));
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.quantite, 10);
    await demonter(tester);
  });

  testWidgets('son coupé dans les réglages : plus aucun bip, la vibration reste', (tester) async {
    ecranTerminal(tester);
    final f = installerFauxRetour();
    final b = await preparerBanc(mode: SendMode.collect, prefsEnPlus: {'scanSon': false});
    expect(b.config.sonScan, isFalse);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await douchette(tester, '1111111111111');
    await tester.pumpAndSettle();
    expect(f.bips, isEmpty);
    expect(f.vibrations, ['erreur']);
    await demonter(tester);
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

class _LecteurEnPanne implements LecteurRetour {
  @override
  Future<void> bip(TypeRetour type) => throw Exception('pas de haut-parleur');
  @override
  Future<void> vibrer(TypeRetour type) => throw Exception('pas de vibreur');
}
