// Douchette TOUJOURS PRÊTE : en saisie guidée et rapide, le champ de scan garde le focus après OK,
// après une fenêtre, après une erreur ; un scan fait juste après OK n'est plus perdu (avant : le focus
// allait au champ Quantité en lecture seule, qui ignorait la douchette — analyse §2.6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';

Future<void> ouvrirRayon(WidgetTester tester, String libelle) async {
  await tester.tap(find.text('Sélectionner un emplacement'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(libelle));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  testWidgets('saisie guidée : après OK le champ de scan a le focus, et un scan juste après OK est traité', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test')));
    await tester.pumpAndSettle();
    await ouvrirRayon(tester, 'RAYON UN');
    expect(champScanAFocus(tester), isTrue, reason: 'focus dès l\'ouverture du rayon');

    // Saisie au pavé à l'écran puis OK : produit suivant, focus toujours sur le champ de scan.
    await taperQuantite(tester, '7');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.quantite, 7);
    expect(champScanAFocus(tester), isTrue, reason: 'après OK');
    expect(find.byType(NumericKeyboard), findsOneWidget, reason: 'le pavé reste visible');

    // Scan IMMÉDIATEMENT après OK (douchette) : le produit scanné s'ouvre (avant : scan perdu).
    final cible = b.serveur.produits.firstWhere((p) => p.rayon == 'R1' && p.id != b.disque.saisies.single.ligneId);
    await douchette(tester, cible.cip);
    await tester.pumpAndSettle();
    expect(find.text('Saisie Rapide'), findsOneWidget);
    expect(find.text(cible.nom), findsWidgets);
    await taperQuantite(tester, '3');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.firstWhere((s) => s.ligneId == cible.id).quantite, 3);
    expect(champScanAFocus(tester), isTrue, reason: 'après la fenêtre de quantité');
    await demonter(tester);
  });

  testWidgets('saisie guidée : après une fenêtre (Annuler) et après une erreur, le focus revient au champ de scan', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1')));
    await tester.pumpAndSettle();
    await ouvrirRayon(tester, 'RAYON UN');

    final p = b.serveur.produits.firstWhere((p) => p.rayon == 'R1');
    await douchette(tester, p.cip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(champScanAFocus(tester), isTrue, reason: 'après Annuler');

    // Erreur : code d'un autre emplacement / inconnu.
    await douchette(tester, '1234567890123');
    await tester.pumpAndSettle();
    expect(find.textContaining('introuvable dans cet emplacement'), findsOneWidget);
    expect(champScanAFocus(tester), isTrue, reason: 'après une erreur');

    // Erreur de saisie (OK sur champ vide) : le focus reste au champ de scan.
    await tester.pump(const Duration(seconds: 5)); // fin du message (il couvre le pavé)
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'OK').last);
    await tester.pumpAndSettle();
    expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);
    expect(champScanAFocus(tester), isTrue, reason: 'après OK refusé');
    await demonter(tester);
  });

  testWidgets('saisie rapide : focus au champ de scan à l\'ouverture, après OK, après Annuler, après une erreur réseau', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    expect(champScanAFocus(tester), isTrue);

    await douchette(tester, b.serveur.produits[0].cip);
    await tester.pumpAndSettle();
    await taperQuantite(tester, '2');
    await tester.pumpAndSettle();
    expect(champScanAFocus(tester), isTrue, reason: 'après OK');

    await douchette(tester, b.serveur.produits[1].cip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(champScanAFocus(tester), isTrue, reason: 'après Annuler');

    b.serveur.injoignable = true;
    await douchette(tester, b.serveur.produits[2].cip);
    await tester.pumpAndSettle();
    expect(find.textContaining('Serveur injoignable'), findsOneWidget);
    expect(champScanAFocus(tester), isTrue, reason: 'après une erreur réseau');
    // Le code non recherché reste au journal, à relancer.
    expect(find.textContaining('toucher pour relancer'), findsOneWidget);
    b.serveur.injoignable = false;
    await tester.tap(find.textContaining('toucher pour relancer'));
    await tester.pumpAndSettle();
    expect(find.text(b.serveur.produits[2].nom), findsWidgets);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await demonter(tester);
  });

  testWidgets('clavier à l\'écran (recherche par nom) : affiché seulement à la demande, le pavé guidé reste visible sinon', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1')));
    await tester.pumpAndSettle();
    await ouvrirRayon(tester, 'RAYON UN');
    expect(find.byType(NumericKeyboard), findsOneWidget);
    await tester.tap(find.byTooltip('Clavier (chercher par nom)'));
    await tester.pumpAndSettle();
    expect(find.byType(NumericKeyboard), findsNothing, reason: 'clavier texte affiché : pavé masqué comme avant');
    await tester.tap(find.byTooltip('Masquer le clavier (scan)'));
    await tester.pumpAndSettle();
    expect(find.byType(NumericKeyboard), findsOneWidget);
    expect(champScanAFocus(tester), isTrue);
    await demonter(tester);
  });
}
