// Captures PNG RÉELLES de la 4.13 (maquette validée par le pharmacien), polices Roboto + icônes
// Material du SDK chargées, en taille Sunmi V2s (720 × 1440 px, densité 2) et téléphone (1080 × 2400 px,
// densité 2,625), en taille de l'écran « Automatique » (Compact appliqué d'office sur le V2s depuis la
// 4.13.1). Hors CI ; pour régénérer :
//   flutter test test_apercus/captures_4_13_test.dart --update-goldens
// Fichiers : docs/captures_4.13/<appareil>_<écran>.png.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product_filter.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/analyse_screen.dart';
import 'package:prestinv/ui/ecrans/inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/taille_ecran.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/helpers/banc_essai.dart';
import '../test/helpers/douchette_essai.dart';
import '../test/helpers/faux_prestige_http.dart';
import '../test/helpers/nouvelle_interface.dart';

const _dossier = '../docs/captures_4.13';
final _inv = Inventory(id: '13102026-150642943', libelle: 'Inventaire COMPT3');

/// Appareils des captures.
const _appareils = <(String, Size, double)>[
  ('sunmi_v2s', Size(720, 1440), 2.0),
  ('telephone', Size(1080, 2400), 2.625),
];

const _court = 'GLUCO DR GLUCOMÈTRE 4000';
const _long = 'BIODERMA PHOTODERM SPOT-AGE CRÈME SPF50+ ANTI-TACHES 40 ML';

/// Officine fictive : 4 inventaires, rayon COMPT3 – ACCESSOIRES de 60 produits (noms d'officine).
FauxPrestige _serveur() {
  final s = FauxPrestige(nombre: 0);
  s.inventaires = {
    _inv.id: _inv.libelle,
    'INV-RES': 'Inventaire réserve – TOUS',
    'INV-PARA': 'Inventaire parapharmacie',
    'INV-SEPT': 'Inventaire général sept.',
  };
  s.rayons
    ..clear()
    ..addAll({'COMPT3': 'ACCESSOIRES', 'COMPT1': 'ANTALGIQUES', 'RESA': 'RÉSERVE A', 'FRIGO': 'FRIGO'});
  final noms = [
    _court, _long, 'TENSIOMÈTRE POIGNET OMRON RS2', 'THERMOMÈTRE FLEXIBLE', 'BANDE CRÊPE 10 CM', 'COMPRESSES STÉRILES 10×10 B/50',
  ];
  var id = 1;
  for (var i = 0; i < 60; i++) {
    final p = FauxProduitPrix(id++, '34009${(871239 + i).toString().padLeft(8, '0')}', i < noms.length ? noms[i] : 'ACCESSOIRE ${(i + 1).toString().padLeft(2, '0')}',
        'COMPT3', 2 + i % 5,
        prixAchat: 25000.0 - i * 300);
    if (i < 45) {
      p
        ..dtUpdated = '2026-10-13T10:00:00'
        ..saisi = i % 6 == 0 ? p.theorique - 1 : p.theorique;
    }
    s.produits.add(p);
  }
  for (final (r, n, comptes) in [('COMPT1', 24, 24), ('RESA', 19, 16), ('FRIGO', 6, 6)]) {
    for (var i = 0; i < n; i++) {
      final p = FauxProduitPrix(id++, '34009${(500000 + id).toString().padLeft(8, '0')}', '$r PRODUIT ${i + 1}', r, 10, prixAchat: 3500);
      if (i < comptes) {
        p
          ..dtUpdated = '2026-10-13T09:00:00'
          ..saisi = i % 4 == 0 ? 8 : (i % 7 == 0 ? 11 : 10);
      }
      s.produits.add(p);
    }
  }
  return s;
}

Future<Banc> _banc() async {
  final b = await preparerBanc(serveur: _serveur(), mode: SendMode.collect);
  b.auth.connecterPourTest(login: 'aya.k', prenom: 'Aya Marie', nom: 'Kouassi', officine: 'PHARMACIE DU PLATEAU');
  await CollecteStore.ecrire([for (var i = 0; i < 42; i++) CollectedItem(code: '340093000${i.toString().padLeft(4, '0')}', quantity: 1 + i % 5, dateScan: DateTime(2026, 10, 13, 9, i))]);
  // Trois saisies non envoyées (pastille rouge de la saisie guidée).
  for (final i in [46, 47, 48]) {
    await b.queue.enregistrer(inventaireId: _inv.id, inventaireLibelle: _inv.libelle, ligneId: i, quantite: 3, rayonId: 'COMPT3', rayonLibelle: 'ACCESSOIRES');
  }
  return b;
}

/// Avancement déjà connu (calculé plus tôt) des autres inventaires : 0 %, 15 % et 100 %, pour montrer
/// les trois boutons (le faux serveur a les mêmes lignes pour tous les inventaires).
Future<void> _avancementsConnus() async {
  final prefs = await SharedPreferences.getInstance();
  final calc = AvancementCalcul();
  for (final (id, total, comptes) in [('INV-RES', 109, 0), ('INV-PARA', 109, 16), ('INV-SEPT', 109, 109)]) {
    final r = AvancementRayons(
      inventaireId: id,
      calculeA: DateTime(2026, 10, 13, 10, 42),
      statuts: {'COMPT3': comptes == 0 ? 0 : (comptes == total ? 2 : 1)},
      total: 1,
      totalProduits: total,
      comptes: {for (var i = 0; i < comptes; i++) 9000 + i},
      ecarts: 0,
    );
    await prefs.setString(AvancementCalcul.cle(id), json.encode(r.toJson()));
    await calc.charger(id);
  }
  calc.dispose();
}

/// Comme main() : taille de l'écran Automatique à la racine (4.13.1 : Compact appliqué d'office sur le
/// Sunmi V2s, taille normale sur le téléphone).
Widget _cadre(Banc b, Widget ecran) => RepaintBoundary(key: const ValueKey('apercu'), child: RacineTailleEcran(child: monterNv(b, ecran)));

Future<void> _photo(WidgetTester tester, String appareil, String nom) =>
    expectLater(find.byKey(const ValueKey('apercu')), matchesGoldenFile('$_dossier/${appareil}_$nom.png'));

Future<void> _finir(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    WidgetsApp.debugAllowBannerOverride = false;
    await chargerPolicesReelles();
  });
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
    AvancementCalcul.viderCache();
  });

  for (final (appareil, pixels, densite) in _appareils) {
    testWidgets('$appareil : accueil replié / déroulé, feuille Scanner', (tester) async {
      tailleEcran(tester, Size(pixels.width / densite, pixels.height / densite), densite: densite);
      final b = await _banc();
      await _avancementsConnus();
      await tester.pumpWidget(_cadre(b, const NvAccueilScreen()));
      await tester.pumpAndSettle();
      await _photo(tester, appareil, '1_accueil_replie');
      await deroulerInventaires(tester);
      await _photo(tester, appareil, '2_accueil_deroule');
      await tester.tap(find.text('Scanner'));
      await tester.pumpAndSettle();
      await _photo(tester, appareil, '8_feuille_scanner');
      await demonter(tester);
    });

    testWidgets('$appareil : inventaire choisi (Hub)', (tester) async {
      tailleEcran(tester, Size(pixels.width / densite, pixels.height / densite), densite: densite);
      final b = await _banc();
      await tester.pumpWidget(_cadre(b, NvInventaireScreen(inventaire: _inv)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nv-actualiser-avancement')));
      await _finir(tester);
      await _photo(tester, appareil, '3_inventaire_choisi');
      await demonter(tester);
    });

    testWidgets('$appareil : saisie guidée sans / avec filtre, nom court / long, fenêtre du filtre', (tester) async {
      tailleEcran(tester, Size(pixels.width / densite, pixels.height / densite), densite: densite);
      final b = await _banc();
      await tester.pumpWidget(_cadre(b, NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'COMPT3')));
      await tester.pumpAndSettle();
      // Session précédente non terminée (saisies en attente) : la question est écartée pour la photo.
      if (find.text('Non').evaluate().isNotEmpty) {
        await tester.tap(find.text('Non'));
        await tester.pumpAndSettle();
      }
      Future<void> aller(String nom) async {
        final p = b.entry.products.firstWhere((x) => x.produitName == nom);
        b.entry.jumpToProduct(p, _inv.id);
        await tester.pumpAndSettle();
      }

      await aller(_court);
      await _photo(tester, appareil, '4_saisie_sans_filtre_nom_court');
      await aller(_long);
      await _photo(tester, appareil, '5_saisie_sans_filtre_nom_long');
      // Filtre par numéro couvrant les deux produits (la liste du rayon est triée par nom).
      final tous = b.entry.allProducts;
      final i1 = tous.indexWhere((x) => x.produitName == _court) + 1, i2 = tous.indexWhere((x) => x.produitName == _long) + 1;
      final de = (i1 < i2 ? i1 : i2), a = ((i1 > i2 ? i1 : i2) + 20).clamp(1, tous.length - 1);
      await b.entry.applyFilter(ProductFilter(type: FilterType.numeric, from: '$de', to: '$a'), _inv.id);
      await tester.pumpAndSettle();
      await aller(_court);
      await _photo(tester, appareil, '6_saisie_filtre_nom_court');
      await aller(_long);
      await _photo(tester, appareil, '6_saisie_filtre_nom_long');
      await tester.tap(find.byKey(const ValueKey('nv-filtre')));
      await tester.pumpAndSettle();
      await _photo(tester, appareil, '7_filtre');
      await tester.tap(find.byKey(const ValueKey('nv-annuler-filtre')));
      await tester.pumpAndSettle();
      await b.entry.applyFilter(ProductFilter(), _inv.id);
      await demonter(tester);
    });

    testWidgets('$appareil : analyse, tous les emplacements', (tester) async {
      tailleEcran(tester, Size(pixels.width / densite, pixels.height / densite), densite: densite);
      final b = await _banc();
      await tester.pumpWidget(_cadre(b, NvAnalyseScreen(inventaireInitial: _inv)));
      await _finir(tester);
      await _photo(tester, appareil, '9_analyse_tous');
      await demonter(tester);
    });
  }
}
