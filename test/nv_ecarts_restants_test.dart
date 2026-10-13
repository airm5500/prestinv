// Nouvelle interface — écarts (maquette C) et restants : tri par valeur en F CFA, « vérifié » seulement
// après confirmation du serveur, échec = message et saisie gardée, champ vide refusé, Garder, sortie
// obligée (Forcer la sortie) ; tablette : tableau + correction à droite ; restants retirés seulement
// après confirmation. Même logique que GlobalVarianceScreen / VarianceScreen / UncountedScreen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/restants_screen.dart';
import 'package:prestinv/ui/exports.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

final _inv = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

Product _p(int id, int theo, int compte, double pa) =>
    Product(id: id, produitCip: '$id', produitName: 'P$id', produitPrixAchat: pa, produitPrixUni: pa, quantiteInitiale: theo, quantiteSaisie: compte);

Future<Banc> ouvrirEcarts(WidgetTester tester, {Size taille = telephone360, Rayon? rayon}) async {
  tailleEcran(tester, taille, densite: taille == tablette ? 1.5 : 2);
  final b = await preparerBanc(serveur: serveurRealiste());
  await tester.pumpWidget(monterNv(
      b,
      Builder(
          builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NvEcartsScreen(inventaire: _inv, rayon: rayon))),
                    child: const Text('ouvrir'),
                  ),
                ),
              ))));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return b;
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  test('tri par valeur absolue (F CFA) ; filtres Manquants / Surplus ; montant affiché', () {
    final ps = [_p(1, 10, 9, 100), _p(2, 3, 11, 3600), _p(3, 9, 4, 28400), _p(4, 5, 5, 999)];
    expect(trierEcarts(ps, TriEcarts.valeur).map((p) => p.id), [3, 2, 1, 4]);
    expect(trierEcarts(ps, TriEcarts.manquants).map((p) => p.id), [3, 1]);
    expect(trierEcarts(ps, TriEcarts.surplus).map((p) => p.id), [2]);
    expect(valeurEcart(ps[2]), -142000);
    expect(francs(-142000), '−142 000 F');
    expect(francs(28800, signeExplicite: true), '+28 800 F');
  });

  testWidgets('écarts (téléphone) : liste triée par valeur, compteurs ; correction confirmée → vérifié', (tester) async {
    final b = await ouvrirEcarts(tester);
    expect(find.text('7 / 7'), findsOneWidget, reason: '7 écarts à vérifier');
    final noms = tester.widgetList<Text>(find.descendant(of: find.byType(Card), matching: find.byType(Text))).toList();
    expect(noms, isEmpty); // cartes maison (SoftCard), pas de Card Material
    final y1 = tester.getTopLeft(find.text('INSULINE LANTUS SOLOSTAR')).dy;
    final y2 = tester.getTopLeft(find.text('AUGMENTIN 1 G SACHETS')).dy;
    expect(y1, lessThan(y2), reason: '−142 000 F avant −61 600 F');

    await tester.tap(find.text('AUGMENTIN 1 G SACHETS'));
    await tester.pumpAndSettle();
    // Pré-rempli avec la quantité comptée, remplacé à la première touche.
    await taperNv(tester, '20', ok: false);
    await tester.pumpAndSettle();
    expect(find.text('−2'), findsOneWidget, reason: 'écart après correction en direct');
    await taperNv(tester, '');
    await tester.pumpAndSettle();
    expect(b.serveur.produit(6).saisi, 20);
    final s = b.queue.ligne('INV1', 6)!;
    expect((s.envoyee, s.origine, s.envoiAuto), (true, OrigineSaisie.ecarts, true));
    expect(find.byKey(const ValueKey('nv-ecart-produit')), findsOneWidget, reason: 'passage automatique au suivant');
    await tester.tap(find.byKey(const ValueKey('nv-fermer-correction')));
    await tester.pumpAndSettle();
    expect(find.text('6 / 7'), findsOneWidget);
    expect(find.textContaining('vérifié'), findsWidgets);
    await demonter(tester);
  });

  testWidgets('écarts : échec réseau → message, PAS vérifié, saisie gardée ; champ vide refusé ; Garder', (tester) async {
    final b = await ouvrirEcarts(tester);
    await tester.tap(find.text('AUGMENTIN 1 G SACHETS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('touche-DEL')));
    await tester.pump();
    await taperNv(tester, '');
    await tester.pumpAndSettle();
    expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);

    b.serveur.routesInjoignables.add('details');
    await taperNv(tester, '9');
    await tester.pumpAndSettle();
    expect(find.textContaining('Non enregistrée sur le serveur'), findsOneWidget);
    expect(b.queue.ligne('INV1', 6)!.enAttente, isTrue);
    expect(find.text('7 / 7'), findsOneWidget, reason: 'non vérifié');

    b.serveur.routesInjoignables.clear();
    await tester.tap(find.byKey(const ValueKey('nv-garder')));
    await tester.pumpAndSettle();
    expect(b.serveur.produit(6).saisi, 14, reason: 'Garder : quantité comptée confirmée telle quelle');
    await tester.tap(find.byKey(const ValueKey('nv-fermer-correction')));
    await tester.pumpAndSettle();
    expect(find.text('6 / 7'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('écarts : sortie avec des écarts non vérifiés → « Forcer la sortie »', (tester) async {
    await ouvrirEcarts(tester);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Quitter la correction ?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-forcer-sortie')));
    await tester.pumpAndSettle();
    expect(find.text('ouvrir'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('écarts du rayon (depuis la saisie guidée) : produits du rayon dont compté ≠ théorique', (tester) async {
    await ouvrirEcarts(tester, rayon: Rayon(id: 'S2B2', code: 'S2B2', libelle: 'ANTIBIOTIQUES'));
    expect(find.text('AUGMENTIN 1 G SACHETS'), findsOneWidget);
    expect(find.text('DAFALGAN CODEINE CPR'), findsOneWidget);
    expect(find.text('INSULINE LANTUS SOLOSTAR'), findsNothing, reason: 'autre rayon');
    expect(find.text('SPASFON LYOC 80 MG'), findsNothing, reason: 'compté = théorique');
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('ouvrir'), findsOneWidget, reason: 'pas d\'obligation dans le rayon (comme l\'écran d\'origine)');
    await demonter(tester);
  });

  testWidgets('écarts (tablette, maquette C) : menu latéral, tableau, correction à droite', (tester) async {
    final b = await ouvrirEcarts(tester, taille: tablette);
    expect(find.byKey(const ValueKey('menu-accueil')), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-tableau-ecarts')), findsOneWidget);
    expect(find.text('Écarts à contrôler'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-ligne-ecart-7')));
    await tester.pumpAndSettle();
    await taperNv(tester, '9');
    await tester.pumpAndSettle();
    expect(b.serveur.produit(7).saisi, 9);
    expect(find.text('vérifié'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await demonter(tester);
  });

  testWidgets('écarts : scan d\'un produit de la liste → sa correction s\'ouvre', (tester) async {
    await ouvrirEcarts(tester);
    await douchette(tester, '3400939100006'); // VOLTARENE
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('nv-ecart-produit'))).data, 'VOLTARENE EMULGEL 1 %');
    await tester.tap(find.byKey(const ValueKey('nv-fermer-correction')));
    await tester.pumpAndSettle();
    await demonter(tester);
  });

  group('Restants', () {
    testWidgets('saisie confirmée → retiré de la liste ; échec → gardé avec le motif ; champ vide refusé', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await preparerBanc(serveur: serveurRealiste());
      await tester.pumpWidget(monterNv(b, NvRestantsScreen(inventaire: _inv)));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsWidgets, reason: '5 produits restants');
      await tester.tap(find.text('SPASFON LYOC 80 MG'));
      await tester.pumpAndSettle();
      await taperNv(tester, '');
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);
      b.serveur.routesInjoignables.add('details');
      await taperNv(tester, '3');
      await tester.pumpAndSettle();
      expect(find.textContaining('Non enregistrée sur le serveur'), findsOneWidget);
      expect(b.queue.ligne('INV1', 4)!.origine, OrigineSaisie.restants);
      b.serveur.routesInjoignables.clear();
      await taperNv(tester, '');
      await tester.pumpAndSettle();
      expect(b.serveur.produit(4).saisi, 3);
      expect(find.byKey(const ValueKey('nv-restant-4')), findsNothing);
      await demonter(tester);
    });

    testWidgets('scan d\'un restant → saisie ; filtre stock théorique', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await preparerBanc(serveur: serveurRealiste());
      await tester.pumpWidget(monterNv(b, NvRestantsScreen(inventaire: _inv)));
      await tester.pumpAndSettle();
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('nv-restant-produit'))).data, 'DOLIPRANE 1000 MG CPR B/8');
      await tester.tap(find.byKey(const ValueKey('nv-restant-annuler')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nv-restants-stock')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inférieur à (<)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Valeur de référence'), '10');
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-restant-4')), findsOneWidget, reason: 'théo 3');
      expect(find.byKey(const ValueKey('nv-restant-1')), findsNothing, reason: 'théo 24');
      await demonter(tester);
    });
  });
}
