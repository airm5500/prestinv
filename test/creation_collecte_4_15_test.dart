// 4.15 — Création d'un inventaire DEPUIS LA COLLECTE (Scanner › Collecte), nouvelle ET ancienne interface,
// widgets contre le faux serveur.
//
// Décision du pharmacien : « si j'ai 4 produits de 4 emplacements différents ? On doit faire comme sur
// Prestige : emplacement = tous, et il crée l'inventaire des 4 produits ; à l'ouverture de l'inventaire on a
// juste les emplacements de ces produits ». Vérifié :
//  - plus de choix d'emplacement ni de type : récapitulatif « N produits, M emplacements », emplacements
//    listés, codes non retrouvés signalés ;
//  - création : emplacements des produits (`valeurs`), lignes non retenues, puis SEULS les produits
//    collectés retenus ; le nouvel inventaire n'a que ces emplacements et ces produits ;
//  - serveur sans la route de retenue : création REFUSÉE avec un message clair (4.15.1) ;
//  - panne pendant la recherche : message, Réessayer ; aucun produit : rien à créer ;
//  - produits non ajoutés après la création : « Ajouter les produits » (rien n'est recréé) ;
//  - ancienne interface : « Verser la collecte » › « Nouvel inventaire… » fait de même (avant : tous les
//    produits de tous les emplacements) ;
//  - création classique (accueil) : inchangée.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/screens/creation_inventaire_screen.dart';
import 'package:prestinv/screens/versement_screen.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

Future<Banc> banc() async {
  final b = await preparerBanc(serveur: serveurRealiste());
  ApiService.oublierRoutesAbsentes();
  b.auth.connecterPourTest(login: 'Awa K.');
  return b;
}

/// 4 produits, 3 emplacements : DOLIPRANE (RÉSERVE), AMOXICILLINE + SPASFON (ANTIBIOTIQUES), BÉTADINE
/// (CANNES) ; un code inconnu.
const codesCollecte = ['3400930000001', '3400935959001', '3400938000004', '3400937000003', '9999999999999'];

/// Monte [ecran] au-dessus d'une page d'accueil : le résultat (inventaire créé) est récupéré.
Widget hote(Widget ecran, void Function(Inventory?) resultat) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const ValueKey('ouvrir'),
            onPressed: () async => resultat(await Navigator.of(context).push<Inventory>(MaterialPageRoute(builder: (_) => ecran))),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );

Future<void> creerEtConfirmer(WidgetTester tester) async {
  await toucher(tester, find.byKey(const ValueKey('bouton-creer')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('confirmer-creation')));
  await tester.pumpAndSettle();
}

bool actif(WidgetTester tester) => tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('bouton-creer'))).onPressed != null;

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  group('Nouvelle interface', () {
    testWidgets('récapitulatif « 4 produits, 3 emplacements » ; inventaire de ces produits SEULEMENT', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      Inventory? cree;
      await tester.pumpWidget(monterNv(b, hote(const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: codesCollecte), (i) => cree = i)));
      await tester.tap(find.byKey(const ValueKey('ouvrir')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('type-famille')), findsNothing, reason: 'pas de choix du type');
      expect(find.byKey(const ValueKey('autre-emplacement')), findsNothing, reason: 'plus de choix d\'emplacement');
      expect(find.text('4 produits, 3 emplacements'), findsOneWidget);
      for (final id in ['S2B2', 'S1A0T2', 'S3']) {
        expect(find.byKey(ValueKey('recap-emplacement-$id')), findsOneWidget);
      }
      expect(find.text('2 produits'), findsOneWidget, reason: 'ANTIBIOTIQUES');
      expect(find.byKey(const ValueKey('recap-non-retrouves')), findsOneWidget);
      expect(find.textContaining('9999999999999'), findsOneWidget);
      expect(find.text('Seulement ces produits'), findsOneWidget);
      await creerEtConfirmer(tester);

      expect(b.serveur.creations.single, ('Collecte du 15-10-2026', 'Emplacement'));
      expect(b.serveur.creationsValeurs.single!.toSet(), {'S2B2', 'S1A0T2', 'S3'});
      expect(b.serveur.creationsRetenue.single, 0);
      expect(cree?.id, 'NEW1');
      final inv = b.serveur.crees['NEW1']!;
      expect(inv.lignesRetenues.map((l) => l.cip).toSet(), {'3400930000001', '3400935959001', '3400938000004', '3400937000003'});
      expect(inv.lignes.length, greaterThan(4), reason: 'les autres produits de ces emplacements restent non retenus');
      await demonter(tester);
    });

    testWidgets('serveur sans la route de retenue : création REFUSÉE, message clair, bouton inactif (4.15.1)', (tester) async {
      tailleEcran(tester, sunmiV2s); // petit écran : message entier, rien ne déborde
      final b = await banc();
      b.serveur.sansRouteRetenue = true;
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: codesCollecte)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('serveur-sans-retenue')), findsOneWidget);
      expect(find.text(CreationInventaire.messageServeurAncien), findsOneWidget);
      expect(actif(tester), isFalse);
      expect(b.serveur.creations, isEmpty, reason: 'plus jamais d\'inventaire avec tous les produits des emplacements');
      await demonter(tester);
    });

    testWidgets('aucun produit retrouvé : rien à créer, bouton inactif', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: ['9999999999999'])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('collecte-aucun')), findsOneWidget);
      expect(actif(tester), isFalse);
      expect(b.serveur.creations, isEmpty);
      await demonter(tester);
    });

    testWidgets('serveur en panne pendant la recherche : message, Réessayer, puis récapitulatif', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      b.serveur.codes['fiche'] = 500;
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: codesCollecte)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('collecte-erreur')), findsOneWidget);
      expect(actif(tester), isFalse);
      b.serveur.codes.remove('fiche');
      await toucher(tester, find.byKey(const ValueKey('collecte-reessayer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('collecte-erreur')), findsNothing);
      expect(find.text('4 produits, 3 emplacements'), findsOneWidget);
      expect(actif(tester), isTrue);
      await demonter(tester);
    });

    testWidgets('produits non ajoutés après la création : « Ajouter les produits », rien n\'est recréé', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      Inventory? cree;
      await tester.pumpWidget(monterNv(b, hote(const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: codesCollecte), (i) => cree = i)));
      await tester.tap(find.byKey(const ValueKey('ouvrir')));
      await tester.pumpAndSettle();
      b.serveur.routesInjoignables.add('retenue');
      await creerEtConfirmer(tester);
      expect(find.byKey(const ValueKey('produits-a-ajouter')), findsOneWidget);
      expect(find.text('Ajouter les produits'), findsOneWidget);
      expect(find.byKey(const ValueKey('erreur-creation')), findsOneWidget);
      expect(cree, isNull, reason: 'l\'écran reste ouvert');
      b.serveur.routesInjoignables.remove('retenue');
      await toucher(tester, find.byKey(const ValueKey('bouton-creer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirmer-creation')), findsNothing, reason: 'pas de nouvelle confirmation');
      expect(cree?.id, 'NEW1');
      expect(b.serveur.creations, hasLength(1), reason: 'jamais recréé');
      expect(b.serveur.crees['NEW1']!.lignesRetenues, hasLength(4));
      await demonter(tester);
    });

    testWidgets('création classique (accueil) : inchangée, type au choix, ni emplacement ni retenue', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('type-famille')), findsOneWidget);
      expect(find.byKey(const ValueKey('recap-collecte')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve novembre');
      await creerEtConfirmer(tester);
      expect(b.serveur.creations.single, ('Réserve novembre', 'Emplacement'));
      expect(b.serveur.creationsValeurs.single, isNull);
      expect(b.serveur.creationsRetenue.single, isNull);
      expect(b.serveur.retenues, isEmpty);
      await demonter(tester);
    });
  });

  group('Ancienne interface', () {
    testWidgets('écran de création depuis la collecte : récapitulatif, inventaire de ces produits', (tester) async {
      ecranTerminal(tester);
      final b = await banc();
      await tester.pumpWidget(monter(b, const CreationInventaireScreen(libelleInitial: 'Collecte ancienne', codesCollectes: codesCollecte)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('type-famille')), findsNothing);
      expect(find.text('4 produits, 3 emplacements'), findsOneWidget);
      expect(find.byKey(const ValueKey('recap-non-retrouves')), findsOneWidget);
      await creerEtConfirmer(tester);
      expect(b.serveur.creationsValeurs.single!.toSet(), {'S2B2', 'S1A0T2', 'S3'});
      expect(b.serveur.creationsRetenue.single, 0);
      expect(b.serveur.crees['NEW1']!.lignesRetenues, hasLength(4));
      await demonter(tester);
    });

    testWidgets('« Verser la collecte » › « Nouvel inventaire… » : les produits à verser (avant : tous les emplacements)', (tester) async {
      ecranTerminal(tester);
      final b = await banc();
      await CollecteStore.ecrire([
        for (final c in ['3400930000001', '3400938000004']) CollectedItem(code: c, quantity: 2, dateScan: DateTime(2026, 10, 15, 9)),
      ]);
      await tester.pumpWidget(monter(b, const VersementScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('versement-nouvel-inventaire')));
      await tester.pumpAndSettle();
      expect(find.text('2 produits, 2 emplacements'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Collecte deux produits');
      await creerEtConfirmer(tester);
      expect(b.serveur.creationsValeurs.single!.toSet(), {'S1A0T2', 'S3'});
      expect(b.serveur.crees['NEW1']!.lignesRetenues.map((l) => l.cip).toSet(), {'3400930000001', '3400938000004'});
      // L'inventaire créé est proposé au versement (choix Remplacer / Ajouter).
      expect(find.byKey(const ValueKey('confirmer-versement')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirmer-versement')));
      await tester.pumpAndSettle();
      final lignes = b.serveur.crees['NEW1']!.lignesRetenues;
      expect(lignes.map((l) => l.saisi).toList(), [2, 2]);
      await demonter(tester);
    });

    testWidgets('serveur sans la route de retenue : création REFUSÉE, message clair (4.15.1)', (tester) async {
      ecranTerminal(tester);
      final b = await banc();
      b.serveur.sansRouteRetenue = true;
      await tester.pumpWidget(monter(b, const CreationInventaireScreen(libelleInitial: 'Collecte ancienne', codesCollectes: codesCollecte)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('serveur-sans-retenue')), findsOneWidget);
      expect(find.text(CreationInventaire.messageServeurAncien), findsOneWidget);
      expect(actif(tester), isFalse);
      expect(b.serveur.creations, isEmpty);
      await demonter(tester);
    });

    testWidgets('création classique : inchangée (tous les produits)', (tester) async {
      ecranTerminal(tester);
      final b = await banc();
      await tester.pumpWidget(monter(b, const CreationInventaireScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('type-famille')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve novembre');
      await creerEtConfirmer(tester);
      expect(b.serveur.creationsValeurs.single, isNull);
      expect(b.serveur.creationsRetenue.single, isNull);
      await demonter(tester);
    });
  });
}
