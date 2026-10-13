// Scans très rapides enchaînés : chaque code lu attend son tour dans une file, dans l'ordre ; aucun
// n'est perdu, même lu pendant qu'une fenêtre de quantité est ouverte ou qu'une recherche est en cours.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/file_scans.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';

Future<void> validerQuantiteProposee(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'OK').last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  test('FileScans : ordre conservé, un seul traitement à la fois, attente si l\'écran n\'est pas prêt', () async {
    final traites = <String>[];
    var enCours = 0;
    var maxEnCours = 0;
    var pret = false;
    final f = FileScans(
      pret: () => pret,
      attente: const Duration(milliseconds: 5),
      traiter: (c) async {
        enCours++;
        if (enCours > maxEnCours) maxEnCours = enCours;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        traites.add(c);
        enCours--;
      },
    );
    for (var i = 0; i < 30; i++) {
      f.ajouter('CODE$i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(traites, isEmpty, reason: 'écran pas prêt : rien n\'est traité ni perdu');
    expect(f.enAttente, 30);
    pret = true;
    while (traites.length < 30) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(traites, [for (var i = 0; i < 30; i++) 'CODE$i']);
    expect(maxEnCours, 1);
    f.dispose();
  });

  testWidgets('rafale de 6 scans sans pause : 6 fenêtres l\'une après l\'autre, dans l\'ordre, 6 saisies', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();

    final produits = b.serveur.produits.take(6).toList();
    for (final p in produits) {
      await douchette(tester, p.cip); // aucune image entre deux scans
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('5 scan(s) à traiter'), findsOneWidget);

    for (final p in produits) {
      expect(find.text('Saisie Rapide'), findsOneWidget);
      expect(find.text(p.nom), findsWidgets, reason: 'ordre des scans conservé');
      await validerQuantiteProposee(tester); // quantité proposée : 1
    }
    expect(find.text('Saisie Rapide'), findsNothing);
    final saisies = b.disque.saisies;
    expect(saisies.length, 6);
    expect(saisies.map((s) => s.ligneId).toSet(), produits.map((p) => p.id).toSet());
    expect(saisies.every((s) => s.quantite == 1), isTrue);
    await demonter(tester);
  });

  testWidgets('scans lus PENDANT la fenêtre de quantité : gardés et traités ensuite (la quantité en cours n\'est pas touchée)', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();

    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    await taperQuantite(tester, '4', ok: false);
    // Deux scans pendant que la fenêtre est ouverte.
    await douchette(tester, b.serveur.produits[1].cip);
    await douchette(tester, b.serveur.produits[2].cip);
    await tester.pump();
    final qte = tester.widget<TextField>(find.byKey(const ValueKey('qte-scan')));
    expect(qte.controller!.text, '4', reason: 'un code lu ne s\'écrit pas dans la quantité');
    await tester.tap(find.widgetWithText(ElevatedButton, 'OK').last);
    await tester.pumpAndSettle();
    expect(find.text(b.serveur.produits[1].nom), findsWidgets);
    await validerQuantiteProposee(tester);
    expect(find.text(b.serveur.produits[2].nom), findsWidgets);
    await validerQuantiteProposee(tester);
    expect(b.disque.saisies.length, 3);
    expect(b.disque.saisies.firstWhere((s) => s.ligneId == b.serveur.produits[0].id).quantite, 4);
    await demonter(tester);
  });

  testWidgets('scans lus pendant une recherche lente (réseau) : aucun perdu', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    b.serveur.delai = const Duration(milliseconds: 800);
    await douchette(tester, b.serveur.produits[3].cip);
    await tester.pump(const Duration(milliseconds: 100));
    await douchette(tester, b.serveur.produits[4].cip);
    await tester.pump(const Duration(milliseconds: 100));
    await douchette(tester, b.serveur.produits[5].cip);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    for (final i in [3, 4, 5]) {
      expect(find.text(b.serveur.produits[i].nom), findsWidgets);
      await tester.tap(find.widgetWithText(ElevatedButton, 'OK').last);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }
    expect(b.disque.saisies.length, 3);
    await demonter(tester);
  });

  testWidgets('douchette en « remplissage direct » (texte posé dans le champ, sans Entrée) : code pris en compte', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('champ-scan')), matching: find.byType(TextField)), b.serveur.produits[7].cip);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text(b.serveur.produits[7].nom), findsWidgets);
    await validerQuantiteProposee(tester);
    expect(b.disque.saisies.single.ligneId, b.serveur.produits[7].id);
    await demonter(tester);
  });

  testWidgets('même produit scanné deux fois de suite : la 2ᵉ fenêtre indique « Déjà compté »', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await douchette(tester, b.serveur.produits[0].cip);
    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    await taperQuantite(tester, '2');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bandeau-deja-compte')), findsOneWidget);
    expect(find.textContaining('Déjà compté : 2'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await demonter(tester);
  });
}
