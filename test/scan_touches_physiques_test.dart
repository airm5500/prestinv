// Touches physiques : gâchettes / boutons latéraux de scan Sunmi (codes Android 520 à 523, 285 à 288,
// F1 à F4), clavier physique éventuel (chiffres, Retour arrière, Entrée = OK, Échap = Annuler). Les
// touches sont lues au niveau du clavier matériel (HardwareKeyboard), même sans champ focalisé ; un
// champ de saisie ordinaire (filtre, recherche avec clavier) reçoit toujours sa saisie normalement.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';

Future<void> ouvrirRayon(WidgetTester tester, String libelle) async {
  await tester.tap(find.text('Sélectionner un emplacement'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(libelle));
  await tester.pumpAndSettle();
}

String qteFeuille(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('qte-scan'))).controller!.text;

void main() {
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  test('codes des touches de scan Sunmi reconnus (et seulement eux)', () {
    for (final c in [520, 521, 522, 523, 285, 286, 287, 288]) {
      expect(ToucheScan.est(ToucheScan.depuisCodeAndroid(c)), isTrue, reason: 'code $c');
    }
    expect(ToucheScan.est(LogicalKeyboardKey.f1), isTrue);
    expect(ToucheScan.est(LogicalKeyboardKey.f4), isTrue);
    expect(ToucheScan.est(LogicalKeyboardKey.f5), isFalse);
    expect(ToucheScan.est(LogicalKeyboardKey.enter), isFalse);
    expect(ToucheScan.est(ToucheScan.depuisCodeAndroid(66)), isFalse);
  });

  testWidgets('touche latérale de scan : consommée, le champ de scan reprend le focus, le code lu suit', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(champScanAFocus(tester), isFalse);

    for (final c in [520, 521, 522, 523, 285, 286, 287, 288]) {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(await toucheSunmi(tester, c), isTrue, reason: 'touche $c consommée');
      await tester.pump();
      expect(champScanAFocus(tester), isTrue, reason: 'focus après la touche $c');
    }
    // Touche F1 (réglage « touche personnalisée » de certains modèles).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await touche(tester, LogicalKeyboardKey.f1);
    await tester.pump();
    expect(champScanAFocus(tester), isTrue, reason: 'focus après F1');
    // Sans aucun champ focalisé, la lecture marche quand même (HardwareKeyboard).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    expect(find.text(b.serveur.produits[0].nom), findsWidgets);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await demonter(tester);
  });

  testWidgets('fenêtre de quantité au clavier physique : chiffres, Retour arrière, Entrée = OK', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    expect(qteFeuille(tester), '1', reason: 'quantité proposée');

    // Chiffres tapés à la main (lentement) : arrivent dans la quantité, remplacent la proposition.
    await douchette(tester, '2', entree: false);
    await tester.pump(const Duration(milliseconds: 400));
    await douchette(tester, '5', entree: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(qteFeuille(tester), '25');
    await touche(tester, LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(qteFeuille(tester), '2');
    await douchette(tester, '8'); // 8 puis Entrée
    await tester.pumpAndSettle();
    expect(find.text('Saisie Rapide'), findsNothing);
    expect(b.disque.saisies.single.quantite, 28);
    await demonter(tester);
  });

  testWidgets('Échap ferme la fenêtre de quantité sans rien enregistrer', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    await touche(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Saisie Rapide'), findsNothing);
    expect(b.disque.saisies, isEmpty);
    expect(champScanAFocus(tester), isTrue);
    await demonter(tester);
  });

  testWidgets('saisie guidée au clavier physique : chiffres + Entrée = OK, produit suivant', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1')));
    await tester.pumpAndSettle();
    await ouvrirRayon(tester, 'RAYON UN');
    await douchette(tester, '12');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.quantite, 12);
    await douchette(tester, '3');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.length, 2);
    expect(champScanAFocus(tester), isTrue);
    await demonter(tester);
  });

  testWidgets('champ de saisie ordinaire (Aller au produit) : la saisie n\'est pas interceptée', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1')));
    await tester.pumpAndSettle();
    await ouvrirRayon(tester, 'RAYON UN');
    await tester.tap(find.byIcon(Icons.find_in_page));
    await tester.pumpAndSettle();
    expect(find.text('Aller au produit'), findsOneWidget);
    Douchette.instance.historique.clear();
    await douchette(tester, '12');
    await tester.pump();
    expect(Douchette.instance.historique, isEmpty, reason: 'rien n\'est lu par la douchette');
    expect(b.disque.saisies, isEmpty);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await demonter(tester);
  });

  testWidgets('4.16.3 : « Aller au produit » (ancienne interface) saute au produit, sans message « Position N : nom »', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1')));
    await tester.pumpAndSettle();
    await ouvrirRayon(tester, 'RAYON UN');
    expect(b.entry.products.length, greaterThan(1));
    expect(b.entry.currentProductIndex, 0);
    final cible = b.entry.products[1];
    for (final saisie in ['2', cible.produitCip]) {
      await tester.tap(find.byIcon(Icons.find_in_page));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Position, Nom ou Code'), saisie);
      await tester.tap(find.text('Aller'));
      await tester.pump();
      expect(b.entry.currentProductIndex, 1, reason: 'saut par « $saisie »');
      expect(b.entry.currentProduct!.id, cible.id);
      expect(find.textContaining(RegExp(r'^Position \d+ :')), findsNothing, reason: 'message retiré');
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpAndSettle();
      b.entry.jumpToProduct(b.entry.products.first, 'INV1');
      await tester.pumpAndSettle();
    }
    // Introuvable : le message d'erreur reste.
    await tester.tap(find.byIcon(Icons.find_in_page));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Position, Nom ou Code'), 'ZZZ-INTROUVABLE');
    await tester.tap(find.text('Aller'));
    await tester.pump();
    expect(find.text('Aucun produit trouvé.'), findsOneWidget);
    expect(b.entry.currentProductIndex, 0);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await demonter(tester);
  });
}
