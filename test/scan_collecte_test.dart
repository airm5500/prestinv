// Saisie rapide (Scan) + mode Collecte : 50 scans → 50 quantités gardées (plus d'écrasement de la
// liste en mémoire), toujours là après un « redémarrage », puis toutes envoyées. (Correction P1.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

import 'helpers/banc_essai.dart';

void main() {
  testWidgets('50 scans en mode Collecte : aucune saisie perdue, reprise après redémarrage, envoi complet', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test', isQuickMode: true)));
    await tester.pumpAndSettle();

    for (var i = 1; i <= 50; i++) {
      final p = b.serveur.produits[i - 1];
      await tester.enterText(find.byType(TextField).first, p.cip);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Saisie Rapide'), findsOneWidget, reason: 'fenêtre de quantité du scan $i');
      await taperQuantite(tester, '${i + 3}');
      await tester.pumpAndSettle();
      expect(find.text('Saisie Rapide'), findsNothing);
    }

    // Mode Collecte : rien n'est parti tout seul…
    expect(b.serveur.puts, isEmpty);
    // … mais les 50 quantités sont sur le « disque », pas seulement la dernière.
    final surDisque = b.disque.saisies;
    expect(surDisque.length, 50);
    for (var i = 1; i <= 50; i++) {
      final s = surDisque.firstWhere((s) => s.ligneId == b.serveur.produits[i - 1].id);
      expect(s.quantite, i + 3);
      expect(s.enAttente, isTrue);
      expect(s.rayonId, isNull); // saisie rapide : aucun rayon choisi, sauvegardée quand même
    }
    await demonter(tester);

    // « Redémarrage » : nouvelle file sur le même disque, puis Envoyer.
    ApiService.clientParDefaut = b.serveur.client;
    final apres = SaisieQueue(store: b.disque)..serveurFactory = b.queue.serveurFactory;
    await apres.load();
    expect(apres.enAttente(inventaireId: 'INV1'), 50);
    final bilan = await apres.envoyer(inventaireId: 'INV1');
    expect(bilan.envoyees, 50);
    expect(b.serveur.puts.length, 50);
    for (var i = 1; i <= 50; i++) {
      expect(b.serveur.produits[i - 1].saisi, i + 3);
    }
    ApiService.clientParDefaut = null;
  });

  testWidgets('bouton Envoyer de la saisie rapide : envoie toutes les saisies de l\'inventaire', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 3; i++) {
      await tester.enterText(find.byType(TextField).first, b.serveur.produits[i].cip);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await taperQuantite(tester, '$i');
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(b.serveur.puts.length, 3);
    expect(b.queue.enAttente(), 0);
    await demonter(tester);
  });
}
