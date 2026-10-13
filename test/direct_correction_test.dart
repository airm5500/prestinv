// Mode Direct : une correction faite PENDANT l'envoi de la valeur précédente part bien ensuite ;
// « Serveur à jour » n'apparaît que quand la DERNIÈRE valeur est confirmée. (Correction P3.)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/faux_serveur.dart';

void main() {
  test('file : 5 envoyé, corrigé en 50 pendant l\'envoi → le serveur finit à 50, ligne « envoyée » à 50', () async {
    final f = await FileDeTest.creer();
    addTearDown(f.nettoyer);
    final serveur = FauxServeur()..verrou = Completer<void>();
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 7, 5);
    final premier = q.envoyerLigne('INV1', 7);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(serveur.enCours, 1);
    await saisir(q, 7, 50); // correction pendant l'envoi
    final second = q.envoyerLigne('INV1', 7);
    expect(q.estAJour('INV1'), isFalse);
    serveur.verrou!.complete();
    await Future.wait([premier, second]);
    expect(serveur.requetes, [(7, 5), (7, 50)]);
    expect(serveur.quantites[7], 50);
    final s = q.ligne('INV1', 7)!;
    expect(s.envoyee, isTrue);
    expect(s.quantiteEnvoyee, 50);
    expect(q.estAJour('INV1'), isTrue);
  });

  testWidgets('écran de saisie guidée en mode Direct : correction pendant l\'envoi bien envoyée, icône à jour seulement à la fin',
      (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.direct);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test')));
    await tester.pumpAndSettle();

    // Choix du rayon.
    await tester.tap(find.text('Sélectionner un emplacement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RAYON UN'));
    await tester.pumpAndSettle();
    final premier = b.entry.currentProduct!;

    b.serveur.verrouPut = Completer<void>();
    await taperQuantite(tester, '5');
    await tester.pumpAndSettle();
    expect(b.entry.currentProduct!.id, isNot(premier.id)); // passé au suivant
    expect(b.disque.saisies.single.quantite, 5); // enregistrée avant l'envoi

    // Retour au produit et correction pendant que « 5 » est encore en route.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(b.entry.currentProduct!.id, premier.id);
    await taperQuantite(tester, '50');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done), findsNothing);

    b.serveur.verrouPut!.complete();
    await tester.pumpAndSettle();
    expect(b.serveur.puts.map((p) => p.$2).toList(), [5, 50]);
    expect(b.serveur.produit(premier.id).saisi, 50);
    expect(b.queue.ligne('INV1', premier.id)!.envoyee, isTrue);
    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('double appui sur OK : un seul produit avancé, une seule saisie', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sélectionner un emplacement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RAYON UN'));
    await tester.pumpAndSettle();
    final debut = b.entry.currentProductIndex;
    await taperQuantite(tester, '3', ok: false);
    final ok = find.widgetWithText(ElevatedButton, 'OK').last;
    await tester.tap(ok);
    await tester.tap(ok);
    await tester.pumpAndSettle();
    expect(b.entry.currentProductIndex, debut + 1);
    expect(b.disque.saisies.length, 1);
    await demonter(tester);
  });
}
