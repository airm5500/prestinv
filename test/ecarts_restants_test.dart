// Écarts et Restants : « fait / validé » seulement après confirmation du serveur ; échec = message,
// saisie gardée sur l'appareil ; OK sur champ vide refusé (plus de 0 implicite) ; OK verrouillé
// pendant l'envoi. (Corrections P4 / P5.)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/screens/global_variance_screen.dart';
import 'package:prestinv/screens/uncounted_screen.dart';
import 'package:prestinv/screens/variance_screen.dart';

import 'helpers/banc_essai.dart';

void main() {
  group('Écarts (tout l\'inventaire)', () {
    Future<Banc> ouvrir(WidgetTester tester) async {
      ecranTerminal(tester);
      final b = await preparerBanc();
      b.serveur.produits[0]
        ..saisi = 2
        ..dtUpdated = '2026-10-13'; // théorique 1 → écart +1
      await tester.pumpWidget(monter(b, const GlobalVarianceScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(b.serveur.produits[0].nom));
      await tester.pumpAndSettle();
      return b;
    }

    testWidgets('succès : enregistré, envoyé, puis marqué vérifié', (tester) async {
      final b = await ouvrir(tester);
      await taperQuantite(tester, '9');
      await tester.pumpAndSettle();
      expect(b.serveur.produits[0].saisi, 9);
      expect(b.queue.ligne('INV1', b.serveur.produits[0].id)!.envoyee, isTrue);
      expect(find.byIcon(Icons.check_circle), findsOneWidget); // validé dans la liste
      await demonter(tester);
    });

    testWidgets('échec réseau : PAS marqué vérifié, message, saisie gardée (envoi automatique plus tard)', (tester) async {
      final b = await ouvrir(tester);
      b.serveur.routesInjoignables.add('details');
      await taperQuantite(tester, '9');
      await tester.pumpAndSettle();
      expect(find.textContaining('Non enregistrée sur le serveur'), findsOneWidget);
      expect(find.text('Correction Écart'), findsOneWidget); // toujours sur le même produit, non validé
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.text('Saisi: 2'), findsOneWidget); // la valeur affichée n'a pas changé
      final s = b.queue.ligne('INV1', b.serveur.produits[0].id)!;
      expect(s.enAttente, isTrue);
      expect(s.quantite, 9);
      expect(s.envoiAuto, isTrue);

      // Réseau revenu : la reprise automatique l'envoie (même en mode Collecte).
      b.serveur.routesInjoignables.clear();
      await b.queue.relancer();
      expect(b.serveur.produits[0].saisi, 9);
      await demonter(tester);
    });

    testWidgets('OK sur un champ vide : refusé, rien n\'est envoyé', (tester) async {
      final b = await ouvrir(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'OK').last);
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);
      expect(b.serveur.puts, isEmpty);
      expect(b.disque.saisies, isEmpty);
      await demonter(tester);
    });

    testWidgets('OK verrouillé pendant l\'envoi : un seul envoi pour deux appuis', (tester) async {
      final b = await ouvrir(tester);
      b.serveur.verrouPut = Completer<void>();
      await taperQuantite(tester, '7', ok: false);
      await tester.tap(find.widgetWithText(ElevatedButton, 'OK').last);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CircularProgressIndicator), findsWidgets); // sablier à la place de OK
      await tester.tap(find.byType(ElevatedButton).last, warnIfMissed: false);
      b.serveur.verrouPut!.complete();
      await tester.pumpAndSettle();
      expect(b.serveur.puts.length, 1);
      await demonter(tester);
    });
  });

  group('Écarts d\'un emplacement', () {
    Future<Banc> ouvrir(WidgetTester tester) async {
      ecranTerminal(tester);
      final b = await preparerBanc();
      for (final p in b.serveur.produits.where((p) => p.rayon == 'R1').take(2)) {
        p
          ..saisi = p.theorique + 3
          ..dtUpdated = '2026-10-13';
      }
      await tester.pumpWidget(monter(b, const VarianceScreen(inventoryId: 'INV1', rayonId: 'R1', rayonName: 'RAYON UN')));
      await tester.pumpAndSettle();
      return b;
    }

    testWidgets('champ vidé puis OK : refusé (avant : 0 envoyé)', (tester) async {
      final b = await ouvrir(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(ElevatedButton, 'DEL'));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(ElevatedButton, 'OK'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);
      expect(b.serveur.puts, isEmpty);
      await demonter(tester);
    });

    testWidgets('succès : « Correction envoyée » et produit suivant ; échec : on reste, message', (tester) async {
      final b = await ouvrir(tester);
      expect(find.text('Produit 1 sur 2'), findsOneWidget);
      b.serveur.routesInjoignables.add('details');
      await taperQuantite(tester, '4');
      await tester.pumpAndSettle();
      expect(find.text('Produit 1 sur 2'), findsOneWidget);
      expect(b.serveur.puts, isEmpty);

      // Réseau revenu : la valeur est toujours dans le champ, un nouvel OK suffit.
      b.serveur.routesInjoignables.clear();
      await tester.tap(find.widgetWithText(ElevatedButton, 'OK'));
      await tester.pumpAndSettle();
      expect(b.serveur.puts.single.$2, 4);
      expect(find.text('Produit 2 sur 2'), findsOneWidget);
      await demonter(tester);
    });
  });

  group('Restants', () {
    Future<Banc> ouvrir(WidgetTester tester) async {
      ecranTerminal(tester);
      final b = await preparerBanc();
      await tester.pumpWidget(monter(b, const UncountedScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(b.serveur.produits[0].nom));
      await tester.pumpAndSettle();
      return b;
    }

    testWidgets('OK sur champ vide refusé ; succès : retiré de la liste seulement après confirmation', (tester) async {
      final b = await ouvrir(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'OK'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);
      expect(b.serveur.puts, isEmpty);

      await taperQuantite(tester, '0'); // 0 saisi EXPLICITEMENT : accepté
      await tester.pumpAndSettle();
      expect(b.serveur.produits[0].saisi, 0);
      expect(find.text(b.serveur.produits[0].nom), findsNothing);
      await demonter(tester);
    });

    testWidgets('échec : le produit reste dans les restants, motif affiché, saisie gardée', (tester) async {
      final b = await ouvrir(tester);
      b.serveur.routesInjoignables.add('details');
      await taperQuantite(tester, '6');
      await tester.pumpAndSettle();
      expect(find.textContaining('Non enregistrée sur le serveur'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text(b.serveur.produits[0].nom), findsOneWidget);
      expect(b.queue.ligne('INV1', b.serveur.produits[0].id)!.enAttente, isTrue);
      await demonter(tester);
    });
  });
}
