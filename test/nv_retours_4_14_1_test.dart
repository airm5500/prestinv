// 4.14.1 — Retours de test du pharmacien (nouvelle interface, widgets contre le faux serveur) :
//  1. saisie guidée : bouton d'envoi = icône SEULE (sans fond ni contour, comme le nuage voisin),
//     orange, pastille rouge du nombre, zone de toucher ≥ 48 dp ;
//  2. création d'un inventaire depuis la collecte : l'emplacement des produits collectés est
//     présélectionné, modifiable (autre emplacement trouvé, « Autre emplacement… »), et SEUL cet
//     emplacement est envoyé au serveur (avant : tous) ; rien n'est créé sans emplacement ;
//     panne → message et « Réessayer ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

Future<Banc> banc() async {
  final b = await preparerBanc(serveur: serveurRealiste());
  b.auth.connecterPourTest(login: 'Awa K.');
  return b;
}

/// ANTIBIOTIQUES ×2 (AMOXICILLINE, SPASFON), RÉSERVE ×1 (DOLIPRANE).
const codesCollecte = ['3400935959001', '3400937000003', '3400930000001'];

Future<void> creerEtConfirmer(WidgetTester tester) async {
  await toucher(tester, find.byKey(const ValueKey('bouton-creer')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('confirmer-creation')));
  await tester.pumpAndSettle();
}

bool choisi(WidgetTester tester, String id) =>
    tester.widget<SoftCard>(find.byKey(ValueKey('emplacement-$id'))).semantique!.endsWith(', choisi');

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  group('Saisie guidée : bouton d\'envoi', () {
    testWidgets('icône seule (aucun fond ni contour), orange, pastille rouge, cible 48 dp', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await b.queue.enregistrer(inventaireId: 'INV1', ligneId: 2, quantite: 6, nom: 'AMOXICILLINE', rayonId: 'S2B2', rayonLibelle: 'ANTIBIOTIQUES');
      await tester.pumpWidget(monterNv(b, NvSaisieGuideeScreen(inventaire: Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026'), rayonId: 'S2B2')));
      await tester.pumpAndSettle();
      final bouton = find.byKey(const ValueKey('nv-envoyer-badge'));
      expect(bouton, findsOneWidget);
      // Ni Material coloré ni bordure entre l'icône et l'en-tête (avant : carré orange).
      final materiels = tester.widgetList<Material>(find.ancestor(of: bouton, matching: find.byType(Material))).toList();
      expect(materiels.where((m) => m.color == Pal.amber), isEmpty, reason: 'plus de carré orange');
      expect(find.descendant(of: bouton, matching: find.byType(DecoratedBox)), findsNothing);
      expect(find.descendant(of: bouton, matching: find.byType(Material)), findsNothing);
      final icone = tester.widget<Icon>(find.descendant(of: bouton, matching: find.byType(Icon)));
      expect(icone.icon, Icons.send_rounded);
      expect(icone.color, Pal.amber, reason: 'orange, comme le nuage « en attente »');
      final taille = tester.getSize(bouton);
      expect(taille.width, greaterThanOrEqualTo(48));
      expect(taille.height, greaterThanOrEqualTo(48));
      expect(find.descendant(of: find.byKey(const ValueKey('nv-badge-attente')), matching: find.text('1')), findsOneWidget);
      // Toucher l'icône envoie, comme avant : e2e/parcours_4_13_test (« icône d'envoi avec pastille »).
      await demonter(tester);
    });
  });

  group('Création d\'inventaire depuis la collecte', () {
    testWidgets('emplacement le plus fréquent présélectionné ; un seul emplacement envoyé', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: codesCollecte)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('type-famille')), findsNothing, reason: 'pas de choix du type depuis la collecte');
      expect(choisi(tester, 'S2B2'), isTrue);
      expect(choisi(tester, 'S3'), isFalse);
      expect(find.text('2 produit(s) de la collecte'), findsOneWidget);
      expect(find.textContaining('1 produit(s) de la collecte rangé(s) ailleurs'), findsOneWidget);
      await creerEtConfirmer(tester);
      expect(b.serveur.creations.single, ('Collecte du 15-10-2026', 'Emplacement'));
      expect(b.serveur.creationsValeurs.single, ['S2B2']);
      await demonter(tester);
    });

    testWidgets('emplacement modifiable : autre emplacement trouvé, puis « Autre emplacement… » (recherche)', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: codesCollecte)));
      await tester.pumpAndSettle();
      await toucher(tester, find.byKey(const ValueKey('emplacement-S3')));
      await tester.pumpAndSettle();
      expect(choisi(tester, 'S3'), isTrue);
      expect(choisi(tester, 'S2B2'), isFalse);

      await toucher(tester, find.byKey(const ValueKey('autre-emplacement')));
      await tester.pumpAndSettle();
      expect(find.text('Choisir l\'emplacement'), findsOneWidget);
      expect(find.byKey(const ValueKey('choix-emplacement-R3')), findsOneWidget, reason: 'tous les emplacements de l\'officine');
      await tester.enterText(find.byKey(const ValueKey('recherche-emplacement')), 'cann');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('choix-emplacement-S2B2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('choix-emplacement-S1A0T2')));
      await tester.pumpAndSettle();
      expect(choisi(tester, 'S1A0T2'), isTrue);
      expect(find.text('Choisi dans la liste des emplacements'), findsOneWidget);
      await creerEtConfirmer(tester);
      expect(b.serveur.creationsValeurs.single, ['S1A0T2']);
      await demonter(tester);
    });

    testWidgets('aucun produit retrouvé : rien de présélectionné, création impossible sans emplacement', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: ['9999999999999'])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emplacements-aucun')), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('bouton-creer'))).onPressed, isNull);
      expect(b.serveur.creations, isEmpty);
      await demonter(tester);
    });

    testWidgets('serveur en panne pendant la recherche : message, Réessayer, puis présélection', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      b.serveur.codes['fiche'] = 500;
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026', codesCollectes: codesCollecte)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emplacements-erreur')), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('bouton-creer'))).onPressed, isNull);
      b.serveur.codes.remove('fiche');
      await toucher(tester, find.byKey(const ValueKey('emplacements-reessayer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emplacements-erreur')), findsNothing);
      expect(choisi(tester, 'S2B2'), isTrue);
      await demonter(tester);
    });

    testWidgets('création classique (accueil) : inchangée, type au choix, aucun emplacement envoyé', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, const NvCreationInventaireScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('type-famille')), findsOneWidget);
      expect(find.byKey(const ValueKey('autre-emplacement')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve novembre');
      await creerEtConfirmer(tester);
      expect(b.serveur.creations.single, ('Réserve novembre', 'Emplacement'));
      expect(b.serveur.creationsValeurs.single, isNull);
      await demonter(tester);
    });
  });
}
