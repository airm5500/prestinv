// Journal des derniers scans (maquette B) : les 10 dernières saisies avec produit, quantité et état
// d'envoi (en attente / envoyé / erreur), les codes introuvables « à vérifier », et la correction rapide
// de la dernière saisie (la nouvelle quantité remplace l'ancienne, une seule ligne dans la file).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/scan/journal_scans.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';

void main() {
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  test('entreesJournal : 10 au plus, la plus récente d\'abord, états calculés', () async {
    var t = DateTime(2026, 10, 13, 9);
    final b = await preparerBanc();
    final q = SaisieQueue(store: b.disque, clock: () => t);
    await q.load();
    for (var i = 1; i <= 12; i++) {
      t = t.add(const Duration(minutes: 1));
      await q.enregistrer(inventaireId: 'INV1', ligneId: i, quantite: i, nom: 'P$i', origine: OrigineSaisie.rapide);
    }
    final e = entreesJournal(q, 'INV1', [ScanSansSaisie('999', t.add(const Duration(seconds: 30)), 'pas dans cet inventaire')]);
    expect(e.length, 10);
    expect(e.first.scan!.code, '999');
    expect(e[1].saisie!.ligneId, 12);
    expect(e.last.saisie!.ligneId, 4);
    expect(e.where((x) => x.saisie != null).every((x) => x.etat == EtatJournal.enAttente), isTrue);
  });

  testWidgets('journal : produits, quantités et états (en attente → envoyé, refus → erreur)', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    expect(find.text('Scannez le produit suivant'), findsWidgets);

    for (var i = 0; i < 12; i++) {
      await douchette(tester, b.serveur.produits[i].cip);
      await tester.pumpAndSettle();
      await taperQuantite(tester, '${i + 2}');
      await tester.pumpAndSettle();
    }
    // 10 dernières seulement, la plus récente en haut.
    expect(find.byKey(ValueKey('journal-${b.serveur.produits[11].id}')), findsOneWidget);
    expect(find.byKey(ValueKey('journal-${b.serveur.produits[2].id}')), findsOneWidget);
    expect(find.byKey(ValueKey('journal-${b.serveur.produits[1].id}')), findsNothing);
    expect(find.byKey(ValueKey('journal-${b.serveur.produits[0].id}')), findsNothing);
    final yHaut = tester.getTopLeft(find.byKey(ValueKey('journal-${b.serveur.produits[11].id}'))).dy;
    final yBas = tester.getTopLeft(find.byKey(ValueKey('journal-${b.serveur.produits[2].id}'))).dy;
    expect(yHaut, lessThan(yBas));
    expect(find.text('en attente'), findsNWidgets(10));
    expect(find.text('13'), findsOneWidget); // quantité de la dernière saisie
    expect(find.textContaining('12 en attente'), findsOneWidget);

    // Envoi : états « envoyé ».
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('envoyé'), findsNWidgets(10));

    // Une saisie refusée par le serveur : « erreur » avec le motif.
    b.serveur.codes['details'] = 400;
    await douchette(tester, b.serveur.produits[20].cip);
    await tester.pumpAndSettle();
    b.serveur.codes.remove('details'); // la recherche passe par detailsAll : on remet seulement après
    await taperQuantite(tester, '5');
    await tester.pumpAndSettle();
    b.serveur.codes['details'] = 400;
    await b.queue.envoyer(inventaireId: 'INV1');
    await tester.pumpAndSettle();
    expect(find.text('erreur'), findsOneWidget);
    expect(find.textContaining('refusé la quantité'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('correction rapide de la dernière saisie : la nouvelle quantité remplace l\'ancienne', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.direct);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    final p = b.serveur.produits[4];
    await douchette(tester, p.cip);
    await tester.pumpAndSettle();
    await taperQuantite(tester, '3');
    await tester.pumpAndSettle();
    expect(p.saisi, 3); // mode Direct : parti

    await tester.tap(find.byKey(const ValueKey('corriger-derniere')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bandeau-correction')), findsOneWidget);
    expect(find.textContaining('saisie actuelle 3'), findsOneWidget);
    // La quantité actuelle est proposée ; on tape 30.
    await taperQuantite(tester, '30');
    await tester.pumpAndSettle();
    final saisies = b.disque.saisies;
    expect(saisies.length, 1, reason: 'même ligne : la correction remplace');
    expect(saisies.single.quantite, 30);
    expect(saisies.single.version, 2);
    expect(p.saisi, 30, reason: 'correction envoyée au serveur');
    expect(find.text('30'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('toucher une ligne du journal la corrige aussi ; Annuler ne change rien', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    for (final i in [0, 1]) {
      await douchette(tester, b.serveur.produits[i].cip);
      await tester.pumpAndSettle();
      await taperQuantite(tester, '${i + 7}');
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(ValueKey('journal-${b.serveur.produits[0].id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('saisie actuelle 7'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(b.disque.saisies.firstWhere((s) => s.ligneId == b.serveur.produits[0].id).quantite, 7);
    await demonter(tester);
  });
}
