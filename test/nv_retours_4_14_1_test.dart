// 4.14.1 — Retours de test du pharmacien (nouvelle interface, widgets contre le faux serveur) :
//  1. saisie guidée : bouton d'envoi = icône SEULE (sans fond ni contour, comme le nuage voisin),
//     orange, pastille rouge du nombre, zone de toucher ≥ 48 dp ;
//  2. (création d'un inventaire depuis la collecte limitée à UN emplacement : remplacée en 4.15 par
//     l'inventaire des seuls produits collectés — test/creation_collecte_4_15_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/theme.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

Future<Banc> banc() async {
  final b = await preparerBanc(serveur: serveurRealiste());
  b.auth.connecterPourTest(login: 'Awa K.');
  return b;
}



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
      // Toucher l'icône envoie, comme avant : test ci-dessous et e2e/parcours_4_13_test.
      await demonter(tester);
    });

    // Remis après la 4.14.1. Ce test « n'aboutissait pas » : la saisie posée dans la file AVANT
    // l'ouverture de l'écran déclenche, à l'ouverture, la fenêtre bloquante « Saisie non terminée —
    // Voulez-vous les envoyer maintenant ? » ; son voile (ModalBarrier) recouvre l'en-tête, si bien que
    // le toucher arrivait sur le voile et non sur l'icône (avertissement « would not hit test »), sans
    // envoi. Ni la cible (48 dp), ni ensureVisible, ni une animation n'étaient en cause. On répond
    // donc d'abord à cette fenêtre (« Non »), puis on touche l'icône ; le toucher est rendu fatal s'il
    // manque sa cible.
    testWidgets('toucher l\'icône d\'envoi envoie les saisies en attente (fenêtre de reprise d\'abord fermée)', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await b.queue.enregistrer(inventaireId: 'INV1', ligneId: 2, quantite: 6, nom: 'AMOXICILLINE', rayonId: 'S2B2', rayonLibelle: 'ANTIBIOTIQUES');
      await tester.pumpWidget(monterNv(b, NvSaisieGuideeScreen(inventaire: Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026'), rayonId: 'S2B2')));
      await tester.pumpAndSettle();
      expect(find.text('Saisie non terminée'), findsOneWidget, reason: 'fenêtre de reprise affichée par-dessus l\'icône');
      await tester.tap(find.text('Non'));
      await tester.pumpAndSettle();
      expect(find.text('Saisie non terminée'), findsNothing);
      expect(b.queue.enAttente(), 1);

      final ancien = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = ancien);
      final bouton = find.byKey(const ValueKey('nv-envoyer-badge'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('nv-envoi-saisies')), findsOneWidget, reason: 'progression de l\'envoi');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(b.queue.enAttente(), 0);
      expect(b.serveur.produit(2).saisi, 6, reason: 'quantité reçue par le serveur');
      expect(b.serveur.puts.length + b.serveur.postsQuantite.length, 1, reason: 'un seul envoi');
      expect(find.byKey(const ValueKey('nv-badge-attente')), findsNothing);
      await demonter(tester);
    });
  });
  // Création d'un inventaire depuis la collecte : remplacée en 4.15 (inventaire des seuls produits
  // collectés, sur leurs emplacements) — voir test/creation_collecte_4_15_test.dart.
}
