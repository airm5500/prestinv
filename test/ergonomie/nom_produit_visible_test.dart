// ERGONOMIE — 4.15.2, retour du pharmacien : « on ne peut pas avoir le nom en haut et encore un nom dans le
// champ de saisie ». Le rappel du nom du produit sous « Quantité comptée » (ajouté le 13/10 pour l'anomalie
// A5, sans demande) est retiré. Vérifié sur chaque appareil (Sunmi V2s, V3 / V3H / V3mix, téléphone
// 360×640, tablette), texte ×1,0 et ×1,3, aux trois tailles d'écran, avec un nom court et un nom long,
// dans la saisie guidée de la nouvelle interface, montée comme main() (RacineTailleEcran) :
//  - le nom n'apparaît qu'UNE fois à l'écran (dans la carte produit, en haut) ;
//  - ce nom est ENTIÈREMENT visible : sous l'en-tête, au-dessus de la quantité épinglée, sans défilement ;
//  - la quantité tapée (grande) reste visible au-dessus du pavé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/ui/clavier.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/taille_ecran.dart';

import '../helpers/banc_essai.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/ergonomie.dart';
import 'catalogue_ecrans.dart';

const _long = 'BIODERMA PHOTODERM SPOT-AGE CRÈME SPF50+ ANTI-TACHES 40 ML (FORMAT VOYAGE)';
const _court = 'AMOXICILLINE 500 GÉL B/12';

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });
  tearDown(() => InterfaceVersion.useNew.value = false);

  for (final a in appareils) {
    for (final echelle in echellesTexte) {
      for (final taille in TailleEcran.values) {
        for (final nom in [_court, _long]) {
          final quel = nom == _long ? 'nom long' : 'nom court';
          testWidgets('${a.nom}, texte ×$echelle, ${taille.libelle}, $quel : nom une seule fois, en haut, entier ; quantité visible', (tester) async {
            configurer(tester, a, echelle);
            TailleEcranReglage.enregistree = taille;
            TailleEcranReglage.appliquerMaintenant();
            addTearDown(TailleEcranReglage.reinitialiser);
            final s = serveurRealiste()..produits.add(FauxProduitPrix(20, '3400930000020', _long, 'S2B2', 5, prixAchat: 9900));
            final b = await preparerBanc(serveur: s);
            b.auth.connecterPourTest(login: 'Awa K.');
            InterfaceVersion.useNew.value = true;
            await tester.pumpWidget(RacineTailleEcran(child: monterNv(b, NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'))));
            await tester.pumpAndSettle();
            b.entry.jumpToProduct(b.entry.products.firstWhere((p) => p.produitName == nom), 'INV1');
            await tester.pumpAndSettle();
            await taperNv(tester, '12', ok: false);
            await tester.pumpAndSettle();

            // Une seule fois, dans la carte produit.
            expect(find.byKey(const ValueKey('nv-produit-compact')), findsNothing);
            final noms = find.text(nom);
            expect(noms, findsOneWidget, reason: 'le nom n\'apparaît qu\'une fois');
            expect(find.descendant(of: find.byKey(const ValueKey('nv-carte-produit')), matching: noms), findsOneWidget);
            final quantiteZone = tester.getRect(find.byKey(const ValueKey('nv-zone-quantite')));
            expect(find.descendant(of: find.byKey(const ValueKey('nv-zone-quantite')), matching: find.textContaining(nom.substring(0, 8))), findsNothing,
                reason: 'aucun rappel du nom dans le champ de quantité');

            // Nom entier, visible sans défilement : sous l'en-tête (haut de la liste), au-dessus de la quantité.
            final rectNom = tester.getRect(noms);
            final liste = tester.getRect(find.ancestor(of: noms, matching: find.byType(Scrollable)).first);
            expect(rectNom.top, greaterThanOrEqualTo(liste.top - 0.5), reason: 'nom sous l\'en-tête');
            expect(rectNom.bottom, lessThanOrEqualTo(quantiteZone.top + 0.5), reason: 'nom au-dessus de la quantité épinglée');

            // Quantité tapée visible, au-dessus du pavé.
            final q = tester.getRect(find.byKey(const ValueKey('nv-quantite')));
            expect(tester.widget<Text>(find.byKey(const ValueKey('nv-quantite'))).data, '12');
            final pave = tester.getRect(find.byType(NvPave));
            expect(q.bottom, lessThanOrEqualTo(pave.top + 0.5), reason: 'quantité au-dessus du pavé');
            expect(q.top, greaterThanOrEqualTo(0));
            await demonter(tester);
          });
        }
      }
    }
  }
}
