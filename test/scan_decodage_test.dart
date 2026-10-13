// Décodage des codes scannés : mêmes règles que prestige_vente_app (product_lookup.codeCandidates) —
// DataMatrix GS1 avec ou sans séparateur GS, EAN-13 34009 → CIP7, GTIN-14 → EAN-13, UPC-A → EAN-13,
// espaces et caractères parasites. Code introuvable : « Code lu : X — introuvable dans cet inventaire »,
// bip long, et la saisie continue avec le code suivant.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/faux_prestige_http.dart';

void main() {
  group('CodeScan.candidats (règles de prestige_vente_app)', () {
    test('EAN-13 34009 → CIP7 essayé ensuite', () {
      expect(CodeScan.candidats('3400935955838'), ['3400935955838', '3595583']);
    });

    test('GTIN-14 commençant par 0 → EAN-13 → CIP7', () {
      expect(CodeScan.candidats('03400935955838'), ['03400935955838', '3400935955838', '3595583']);
    });

    test('UPC-A (12 chiffres) → EAN-13 avec 0 devant', () {
      expect(CodeScan.candidats('123456789012'), ['123456789012', '0123456789012']);
    });

    test('DataMatrix GS1 AVEC séparateur GS : GTIN → EAN-13 → CIP7 en premier', () {
      final c = CodeScan.candidats('0103400935955838\u001d17281002\u001d10LOT1');
      expect(c.first, '3400935955838');
      expect(c, contains('3595583'));
    });

    test('DataMatrix GS1 SANS séparateur (01 + 17 + 10) : GTIN reconnu', () {
      final c = CodeScan.candidats('010340093595583817281031101234AB');
      expect(c.take(2), ['3400935955838', '3595583']);
    });

    test('DataMatrix avec préfixe de symbologie ]d2 et GS rendu visible « ␝ »', () {
      expect(CodeScan.candidats(']d20103400935955838␝10LOT1').first, '3400935955838');
    });

    test('espaces et caractères parasites (retour chariot, tabulation) retirés', () {
      expect(CodeScan.candidats('  3400935955838\r\n'), ['3400935955838', '3595583']);
      expect(CodeScan.candidats('3400 9359 55838\t'), ['3400935955838', '3595583']);
      expect(CodeScan.nettoyer('\u0002ABC\u0003'), 'ABC');
    });

    test('CIP7 et EAN-13 local : essayés tels quels', () {
      expect(CodeScan.candidats('8050457'), ['8050457']);
      expect(CodeScan.candidats('3000000258453'), ['3000000258453']);
    });

    test('texte : gardé (recherche par nom)', () {
      expect(CodeScan.candidats('DOLIPRANE'), ['DOLIPRANE']);
      expect(CodeScan.ressembleACode('DOLIPRANE'), isFalse);
      expect(CodeScan.ressembleACode('8050457'), isTrue);
      expect(CodeScan.ressembleACode('1000'), isFalse);
      expect(CodeScan.candidats('   '), isEmpty);
    });

    test('message introuvable', () {
      expect(CodeScan.messageIntrouvable('3401597413'), 'Code lu : 3401597413 — introuvable dans cet inventaire');
      expect(CodeScan.messageIntrouvable('01034\u001d10A'), 'Code lu : 01034␝10A — introuvable dans cet inventaire');
    });
  });

  group('DecodeurTouches', () {
    test('suite longue + Entrée = code ; 5 chiffres au plus + Entrée = quantité validée', () {
      final d = DecodeurTouches();
      for (final c in '3400935955838'.split('')) {
        d.caractere(c);
      }
      expect(d.entree(quantiteAttendue: true), [const ActionDouchette(TypeActionDouchette.code, '3400935955838')]);
      for (final c in '12'.split('')) {
        d.caractere(c);
      }
      expect(d.entree(quantiteAttendue: true),
          [const ActionDouchette(TypeActionDouchette.chiffres, '12'), const ActionDouchette(TypeActionDouchette.valider)]);
    });

    test('sans quantité attendue : une suite courte est une recherche (3 caractères au moins)', () {
      final d = DecodeurTouches();
      for (final c in '1234'.split('')) {
        d.caractere(c);
      }
      expect(d.entree(quantiteAttendue: false), [const ActionDouchette(TypeActionDouchette.code, '1234')]);
      d.caractere('1');
      expect(d.entree(quantiteAttendue: false), isEmpty);
    });

    test('douchette sans suffixe Entrée : code pris en compte à la fin de la saisie', () {
      final d = DecodeurTouches();
      for (final c in '8050457'.split('')) {
        d.caractere(c);
      }
      expect(d.finDeSaisie(quantiteAttendue: true), [const ActionDouchette(TypeActionDouchette.code, '8050457')]);
    });

    test('GS conservé dans le tampon, caractères de contrôle ignorés', () {
      final d = DecodeurTouches();
      for (final c in ['0', '1', '\u001d', '\u0002', '1', '0']) {
        d.caractere(c);
      }
      expect(d.tampon, '01\u001d10');
    });
  });

  testWidgets('scan d\'un EAN-13 34009 : le produit connu par son CIP7 est trouvé', (tester) async {
    ecranTerminal(tester);
    reinitialiserDouchette();
    installerFauxRetour();
    final b = await preparerBanc(mode: SendMode.collect);
    b.serveur.produits.add(FauxProduit(5001, '3595583', 'DOLIPRANE 1000', 'R1', 4));
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();

    await douchette(tester, '3400935955838');
    await tester.pumpAndSettle();
    expect(find.text('Saisie Rapide'), findsOneWidget);
    expect(find.text('DOLIPRANE 1000'), findsOneWidget);
    await taperQuantite(tester, '3');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.ligneId, 5001);
    await demonter(tester);
  });

  testWidgets('scan d\'un DataMatrix (GS) : produit trouvé par son GTIN', (tester) async {
    ecranTerminal(tester);
    reinitialiserDouchette();
    installerFauxRetour();
    final b = await preparerBanc(mode: SendMode.collect);
    b.serveur.produits.add(FauxProduit(5002, '3400935955838', 'EFFERALGAN 500', 'R1', 4));
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();

    await douchette(tester, '0103400935955838\u001d17281002\u001d10LOT1');
    await tester.pumpAndSettle();
    expect(find.text('EFFERALGAN 500'), findsOneWidget);
    await taperQuantite(tester, '2');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.ligneId, 5002);
    await demonter(tester);
  });

  testWidgets('code introuvable : message clair, bip long, la saisie continue', (tester) async {
    ecranTerminal(tester);
    reinitialiserDouchette();
    final retour = installerFauxRetour();
    final b = await preparerBanc(mode: SendMode.collect);
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();

    await douchette(tester, '9999999999999');
    await douchette(tester, b.serveur.produits[0].cip); // scan suivant, juste derrière
    await tester.pump();
    expect(find.text('Code lu : 9999999999999 — introuvable dans cet inventaire'), findsOneWidget);
    expect(retour.bips.first, 'erreur');
    await tester.pumpAndSettle();
    // Le scan suivant n'est pas bloqué : sa fenêtre de quantité s'ouvre.
    expect(find.text('Saisie Rapide'), findsOneWidget);
    expect(find.text(b.serveur.produits[0].nom), findsOneWidget);
    await taperQuantite(tester, '4');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.quantite, 4);
    // Le code inconnu reste au journal « à vérifier ».
    expect(find.text('Code 9999999999999'), findsOneWidget);
    expect(find.text('à vérifier'), findsOneWidget);
    await demonter(tester);
  });
}
