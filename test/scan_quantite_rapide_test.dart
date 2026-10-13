// Saisie de quantité rapide après un scan : pavé numérique, quantité proposée 1 par défaut (réglable,
// remplacée dès qu'on tape un chiffre), −1 / +1, bornes 0 à 99 999, seuil « grande quantité ».
// Affichage sans débordement sur 360 dp (Sunmi V2s) et sur tablette.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';

String qte(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('qte-scan'))).controller!.text;

Future<void> ok(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'OK').last);
  await tester.pumpAndSettle();
}

Future<Banc> ouvrirScan(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  final b = await preparerBanc(mode: SendMode.collect, prefsEnPlus: prefs);
  await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
  await tester.pumpAndSettle();
  return b;
}

void main() {
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  testWidgets('quantité proposée 1 : OK direct = 1 ; un chiffre tapé la remplace', (tester) async {
    ecranTerminal(tester);
    final b = await ouvrirScan(tester);
    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    expect(qte(tester), '1');
    expect(find.text('Quantité (proposée)'), findsOneWidget);
    await ok(tester);
    expect(b.disque.saisies.single.quantite, 1);

    await douchette(tester, b.serveur.produits[1].cip);
    await tester.pumpAndSettle();
    await taperQuantite(tester, '7', ok: false);
    expect(qte(tester), '7', reason: 'le 7 remplace la proposition (et non 17)');
    await taperQuantite(tester, '5', ok: false);
    expect(qte(tester), '75');
    await ok(tester);
    expect(b.disque.saisies.firstWhere((s) => s.ligneId == b.serveur.produits[1].id).quantite, 75);
    await demonter(tester);
  });

  testWidgets('quantité proposée réglée à 6 ; « aucune » : OK sur champ vide refusé', (tester) async {
    ecranTerminal(tester);
    var b = await ouvrirScan(tester, prefs: {'scanQuantiteDefaut': 6});
    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    expect(qte(tester), '6');
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await demonter(tester);

    reinitialiserDouchette();
    b = await ouvrirScan(tester, prefs: {'scanQuantiteDefaut': -1});
    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    expect(qte(tester), '');
    await ok(tester);
    expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);
    expect(find.text('Saisie Rapide'), findsOneWidget, reason: 'la fenêtre reste ouverte');
    expect(b.disque.saisies, isEmpty);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await demonter(tester);
  });

  testWidgets('−1 / +1 bornés à 0 et 99 999 ; 5 chiffres au plus ; 0 accepté (produit absent)', (tester) async {
    ecranTerminal(tester);
    final b = await ouvrirScan(tester);
    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('qte-moins')));
    await tester.pump();
    expect(qte(tester), '0');
    await tester.tap(find.byKey(const ValueKey('qte-moins')));
    await tester.pump();
    expect(qte(tester), '0', reason: 'jamais négatif');
    await tester.tap(find.byKey(const ValueKey('qte-plus')));
    await tester.tap(find.byKey(const ValueKey('qte-plus')));
    await tester.pump();
    expect(qte(tester), '2');
    await taperQuantite(tester, '999999', ok: false);
    expect(qte(tester), '29999', reason: '5 chiffres au plus');
    await tester.tap(find.widgetWithText(ElevatedButton, 'DEL').last);
    await tester.tap(find.widgetWithText(ElevatedButton, 'DEL').last);
    await tester.tap(find.widgetWithText(ElevatedButton, 'DEL').last);
    await tester.tap(find.widgetWithText(ElevatedButton, 'DEL').last);
    await tester.tap(find.widgetWithText(ElevatedButton, 'DEL').last);
    await tester.pump();
    await taperQuantite(tester, '99999', ok: false);
    await tester.tap(find.byKey(const ValueKey('qte-plus')));
    await tester.pump();
    expect(qte(tester), '99999', reason: 'jamais au-delà de 99 999');
    await tester.tap(find.byKey(const ValueKey('qte-moins')));
    await tester.pump();
    await ok(tester);
    // Au-delà du seuil « grande quantité » (1 000) : confirmation demandée.
    expect(find.text('Alerte Grande Quantité'), findsOneWidget);
    await tester.tap(find.text('Oui'));
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.quantite, 99998);

    await douchette(tester, b.serveur.produits[1].cip);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'DEL').last);
    await taperQuantite(tester, '0');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.firstWhere((s) => s.ligneId == b.serveur.produits[1].id).quantite, 0);
    await demonter(tester);
  });

  for (final (nom, taille) in [('V2s 360 × 640', const Size(360, 640)), ('tablette 1024 × 768', const Size(1024, 768))]) {
    testWidgets('affichage sans débordement : $nom (journal + fenêtre de quantité)', (tester) async {
      tester.view.physicalSize = taille * 2;
      tester.view.devicePixelRatio = 2;
      final b = await ouvrirScan(tester);
      for (var i = 0; i < 4; i++) {
        await douchette(tester, b.serveur.produits[i].cip);
        await tester.pumpAndSettle();
        await ok(tester);
      }
      await douchette(tester, '9999999999999');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      // Fenêtre avec « Déjà compté » (le plus long titre).
      await douchette(tester, b.serveur.produits[0].cip);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bandeau-deja-compte')), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'OK').last);
      await ok(tester);
      expect(tester.takeException(), isNull);
      await demonter(tester);
    });
  }
}
