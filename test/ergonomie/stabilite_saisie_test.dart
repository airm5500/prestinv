// ERGONOMIE — saisie guidée : L'ÉCRAN NE BOUGE JAMAIS (revue du pharmacien, 4.13).
//  - nom de produit court (une ligne) ou long (deux lignes et plus) : deux lignes toujours réservées
//    (calculées avec l'échelle du texte) → champ de scan, ligne du filtre, nom, chiffres, quantité,
//    Précédent / Suivant exactement à la même place ;
//  - filtre appliqué puis retiré : la ligne du filtre est réservée → rien ne bouge non plus.
// Sur tout le parc d'appareils, aux deux échelles de texte et aux trois tailles d'écran.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/models/product_filter.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';

import '../helpers/banc_essai.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/ergonomie.dart';
import 'catalogue_ecrans.dart';

const _court = 'SPASFON LYOC 80 MG';
const _long = 'BIODERMA PHOTODERM SPOT-AGE CRÈME SPF50+ ANTI-TACHES 40 ML (FORMAT VOYAGE)';

const _cles = ['champ-scan', 'nv-filtre', 'nv-ligne-filtre', 'nv-zone-nom', 'nv-deja-compte', 'nv-zone-quantite', 'nv-precedent', 'nv-recap', 'nv-suivant'];

Map<String, Rect> _positions(WidgetTester tester) => {
      for (final k in _cles)
        if (find.byKey(ValueKey(k)).evaluate().isNotEmpty) k: tester.getRect(find.byKey(ValueKey(k)).first),
    };

void _memes(Map<String, Rect> a, Map<String, Rect> b, String quoi) {
  expect(b.keys.toSet(), a.keys.toSet(), reason: '$quoi : mêmes éléments affichés');
  for (final k in a.keys) {
    final r1 = a[k]!, r2 = b[k]!;
    expect((r1.top - r2.top).abs() < 0.5 && (r1.left - r2.left).abs() < 0.5 && (r1.height - r2.height).abs() < 0.5, isTrue,
        reason: '$quoi : « $k » a bougé ($r1 → $r2)');
  }
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });
  tearDown(() => InterfaceVersion.useNew.value = false);

  for (final appareil in appareils) {
    for (final echelle in echellesTexte) {
      for (final taille in taillesEcran) {
        testWidgets('$appareil, texte ×$echelle${suffixeTaille(taille)} : nom court / long, filtre posé / retiré → rien ne bouge', (tester) async {
          configurer(tester, appareil, echelle);
          final s = serveurRealiste()..produits.add(FauxProduitPrix(20, '3400930000020', _long, 'S2B2', 5, prixAchat: 9900));
          final b = await preparerBanc(serveur: s);
          b.auth.connecterPourTest(login: 'Awa K.');
          InterfaceVersion.useNew.value = true;
          await tester.pumpWidget(aLaTaille(taille, monterNv(b, NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'))));
          await tester.pumpAndSettle();
          Future<void> aller(String nom) async {
            b.entry.jumpToProduct(b.entry.products.firstWhere((p) => p.produitName == nom), 'INV1');
            await tester.pumpAndSettle();
          }

          await aller(_court);
          final reference = _positions(tester);
          expect(reference.keys, containsAll(['nv-zone-nom', 'nv-precedent', 'nv-suivant', 'nv-zone-quantite']));
          // Deux lignes réservées au nom, à l'échelle du texte (19 × 1,2 × 2 dp de l'interface).
          final f = taille.facteur;
          expect(reference['nv-zone-nom']!.height, closeTo(19 * echelle * 1.2 * 2 * f, 0.6));

          await aller(_long);
          _memes(reference, _positions(tester), 'nom long');
          expect(tester.takeException(), isNull);

          await b.entry.applyFilter(ProductFilter(type: FilterType.numeric, from: '2', to: '4'), 'INV1');
          await tester.pumpAndSettle();
          expect(find.textContaining('Filtre : n° 2 à 4'), findsOneWidget);
          await aller(_long);
          _memes(reference, _positions(tester), 'filtre appliqué');

          await tester.tap(find.byKey(const ValueKey('nv-retirer-filtre')));
          await tester.pumpAndSettle();
          expect(find.text('Pas encore de filtre appliqué'), findsOneWidget);
          await aller(_court);
          _memes(reference, _positions(tester), 'filtre retiré');
          await demonter(tester);
          reinitialiserVue(tester);
        });
      }
    }
  }
}
