// ERGONOMIE — petits écrans en taille « Automatique » (4.13.1, décision du pharmacien) : sur un petit
// écran (Sunmi V2s 720 × 1440 px, densité 2 → 360 × 720 dp ; Sunmi V3 / téléphone 360 × 640 dp),
// Automatique applique Compact. Conséquence vérifiée ici, comme main() (RacineTailleEcran au-dessus de
// MaterialApp) : en saisie guidée, la CARTE PRODUIT est entière au-dessus de la quantité épinglée, sans
// défilement (en 4.13.0, sur V2s en Automatique, le bas de la carte — Stock théorique, Déjà compté,
// Prix achat — était coupé et demandait de faire défiler). Les téléphones courants (1080 × 2400 px)
// restent en taille normale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/taille_ecran.dart';

import '../helpers/banc_essai.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/ergonomie.dart';
import 'catalogue_ecrans.dart';

const _long = 'BIODERMA PHOTODERM SPOT-AGE CRÈME SPF50+ ANTI-TACHES 40 ML (FORMAT VOYAGE)';

/// Monte la saisie guidée (produit au nom long) à la racine de taille de l'application ; renvoie la
/// largeur vue par l'interface.
Future<double> _monter(WidgetTester tester, TailleEcran reglage) async {
  TailleEcranReglage.enregistree = reglage;
  TailleEcranReglage.appliquerMaintenant();
  addTearDown(TailleEcranReglage.reinitialiser);
  final s = serveurRealiste()..produits.add(FauxProduitPrix(20, '3400930000020', _long, 'S2B2', 5, prixAchat: 9900));
  final b = await preparerBanc(serveur: s);
  b.auth.connecterPourTest(login: 'Awa K.');
  InterfaceVersion.useNew.value = true;
  await tester.pumpWidget(RacineTailleEcran(child: monterNv(b, NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'))));
  await tester.pumpAndSettle();
  b.entry.jumpToProduct(b.entry.products.firstWhere((p) => p.produitName == _long), 'INV1');
  await tester.pumpAndSettle();
  return MediaQuery.sizeOf(tester.element(find.byType(NvSaisieGuideeScreen))).width;
}

/// La carte produit est-elle entière, entre le haut de la liste et la quantité épinglée ?
String? _carteCoupee(WidgetTester tester) {
  final carte = tester.getRect(find.byKey(const ValueKey('nv-carte-produit')));
  final quantite = tester.getRect(find.byKey(const ValueKey('nv-zone-quantite')));
  if (carte.bottom > quantite.top + 0.5) {
    return 'carte produit coupée : bas à ${carte.bottom.toStringAsFixed(1)} dp, quantité à ${quantite.top.toStringAsFixed(1)} dp';
  }
  return null;
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });
  tearDown(() => InterfaceVersion.useNew.value = false);

  final v2s = appareils.firstWhere((a) => a.nom == 'Sunmi V2s');
  const telephone = Appareil('Téléphone 1080×2400', Size(1080, 2400), 2.625);

  testWidgets('${v2s.nom}, Automatique : Compact appliqué, carte produit entière en saisie guidée (sans défilement)', (tester) async {
    configurer(tester, v2s, 1.0);
    final largeur = await _monter(tester, TailleEcran.automatique);
    expect(largeur, closeTo(v2s.dp.width / TailleEcran.compact.facteur, 0.01), reason: 'Compact appliqué d\'office');
    expect(_carteCoupee(tester), isNull);
    expect(tester.takeException(), isNull);
    await demonter(tester);
  });

  testWidgets('${v2s.nom} : sans Compact (facteur 1,0), la carte serait coupée — raison du réglage automatique', (tester) async {
    configurer(tester, v2s, 1.0);
    final s = serveurRealiste()..produits.add(FauxProduitPrix(20, '3400930000020', _long, 'S2B2', 5, prixAchat: 9900));
    final b = await preparerBanc(serveur: s);
    b.auth.connecterPourTest(login: 'Awa K.');
    InterfaceVersion.useNew.value = true;
    await tester.pumpWidget(aLaTaille(TailleEcran.automatique, monterNv(b, NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'))));
    await tester.pumpAndSettle();
    b.entry.jumpToProduct(b.entry.products.firstWhere((p) => p.produitName == _long), 'INV1');
    await tester.pumpAndSettle();
    expect(_carteCoupee(tester), isNotNull);
    await demonter(tester);
  });

  for (final reglage in [TailleEcran.compact, TailleEcran.tresCompact]) {
    testWidgets('${v2s.nom}, ${reglage.libelle} (choix manuel prioritaire) : carte produit entière', (tester) async {
      configurer(tester, v2s, 1.0);
      final largeur = await _monter(tester, reglage);
      expect(largeur, closeTo(v2s.dp.width / reglage.facteur, 0.01));
      expect(_carteCoupee(tester), isNull);
      await demonter(tester);
    });
  }

  testWidgets('$telephone, Automatique : taille normale (aucune réduction), carte produit entière', (tester) async {
    configurer(tester, telephone, 1.0);
    final largeur = await _monter(tester, TailleEcran.automatique);
    expect(largeur, closeTo(telephone.dp.width, 0.01), reason: 'téléphone courant : pas de Compact');
    expect(_carteCoupee(tester), isNull);
    await demonter(tester);
  });
}
