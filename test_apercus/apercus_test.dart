// Aperçus PNG RÉELS des nouveaux écrans (polices Roboto et icônes Material chargées), rendus par
// Flutter comme sur un Sunmi V2s (360 dp de large). Hors CI ; pour régénérer :
//   flutter test test_apercus/apercus_test.dart --update-goldens
// Fichiers : docs/maquettes/apercus/app_scan_*.png et app_versement_*.png.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/screens/creation_inventaire_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/screens/rapport_versement_screen.dart';
import 'package:prestinv/screens/versement_screen.dart';

import '../test/helpers/banc_essai.dart';
import '../test/helpers/douchette_essai.dart';
import '../test/helpers/faux_prestige_http.dart';

const _dossier = '../docs/maquettes/apercus';

Future<void> _polices() async {
  final racine = Platform.environment['FLUTTER_ROOT'] ?? '';
  final fonts = '$racine/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File('$fonts/$f').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    roboto.addFont(lire(f));
  }
  await roboto.load();
  final icones = FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'));
  await icones.load();
}

FauxPrestige _serveur() {
  final s = FauxPrestige(nombre: 0);
  s.inventaires = {'INV1': 'Inventaire annuel 2026', 'INV2': 'Réserve S3 — octobre'};
  s.produits.addAll([
    FauxProduit(1, '3400930000001', 'DOLIPRANE 1000 MG CPR B/8', 'R1', 24),
    FauxProduit(2, '3400935959001', 'AMOXICILLINE 500 GÉL B/12', 'R1', 10, saisi: 6)..dtUpdated = '2026-10-13T08:55:00',
    FauxProduit(3, '3400936000002', 'EFFERALGAN 500 CPR EFF', 'R1', 7),
    FauxProduit(4, '3400937000003', 'SPASFON LYOC 80 MG', 'R2', 3),
    FauxProduit(5, '3400938000004', 'BÉTADINE DERMIQUE 10 %', 'R2', 30),
  ]);
  return s;
}

Widget _cadre(Banc b, Widget ecran) => RepaintBoundary(key: const ValueKey('apercu'), child: monter(b, ecran));

void _taille(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1440);
  tester.view.devicePixelRatio = 2;
}

Future<void> _photo(WidgetTester tester, String nom) async {
  await expectLater(find.byKey(const ValueKey('apercu')), matchesGoldenFile('$_dossier/$nom.png'));
}

void main() {
  setUpAll(() async {
    WidgetsApp.debugAllowBannerOverride = false; // pas de bandeau « DEBUG » sur les aperçus
    await _polices();
  });
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  testWidgets('app_scan_1_journal / app_scan_2_quantite', (tester) async {
    _taille(tester);
    final b = await preparerBanc(serveur: _serveur(), mode: SendMode.direct, cumul: true);
    await tester.pumpWidget(_cadre(b, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire annuel 2026', isQuickMode: true)));
    await tester.pumpAndSettle();
    for (final (cip, q) in [('3400938000004', '30'), ('3400937000003', '0'), ('3400936000002', '7')]) {
      await douchette(tester, cip);
      await tester.pumpAndSettle();
      await taperQuantite(tester, q);
      await tester.pumpAndSettle();
    }
    await douchette(tester, '3401597413');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    // Envois suivants en panne réseau : ils restent « en attente » (gardés sur le terminal).
    b.serveur.routesInjoignables.add('details');
    await douchette(tester, '3400935959001');
    await tester.pumpAndSettle();
    await taperQuantite(tester, '4');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OUI (Additionner)'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await douchette(tester, '3400930000001');
    await tester.pumpAndSettle();
    await taperQuantite(tester, '24');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await _photo(tester, 'app_scan_1_journal');

    await douchette(tester, '3400935959001');
    await tester.pumpAndSettle();
    await _photo(tester, 'app_scan_2_quantite');
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await demonter(tester);
  });

  testWidgets('app_scan_3_guidee', (tester) async {
    _taille(tester);
    final b = await preparerBanc(serveur: _serveur());
    await tester.pumpWidget(_cadre(b, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire annuel 2026')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sélectionner un emplacement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RAYON UN'));
    await tester.pumpAndSettle();
    await taperQuantite(tester, '12', ok: false);
    await tester.pumpAndSettle();
    await _photo(tester, 'app_scan_3_guidee');
    await demonter(tester);
  });

  testWidgets('app_versement_0_nouvel_inventaire', (tester) async {
    _taille(tester);
    final b = await preparerBanc(serveur: _serveur());
    await tester.pumpWidget(_cadre(b, const CreationInventaireScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve <S3>');
    await tester.tap(find.byKey(const ValueKey('bouton-creer')));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _photo(tester, 'app_versement_0_nouvel_inventaire');
    await demonter(tester);
  });

  testWidgets('app_versement_1_choix / app_versement_2_mode', (tester) async {
    _taille(tester);
    final b = await preparerBanc(serveur: _serveur());
    await CollecteStore.ecrire([
      CollectedItem(code: '3400930000001', quantity: 12, dateScan: DateTime(2026, 10, 13, 9)),
      CollectedItem(code: '3400935959001', quantity: 4, dateScan: DateTime(2026, 10, 13, 9, 1)),
      CollectedItem(code: '9999999999999', quantity: 3, dateScan: DateTime(2026, 10, 13, 9, 2)),
    ]);
    await tester.pumpWidget(_cadre(b, const VersementScreen()));
    await tester.pumpAndSettle();
    await _photo(tester, 'app_versement_1_choix');
    await tester.tap(find.byKey(const ValueKey('versement-inv-INV1')));
    await tester.pumpAndSettle();
    await _photo(tester, 'app_versement_2_mode');
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await demonter(tester);
  });

  testWidgets('app_versement_3_rapport', (tester) async {
    _taille(tester);
    final b = await preparerBanc(serveur: _serveur());
    final v = Versement(
      id: 'V1',
      inventaireId: 'INV1',
      inventaireLibelle: 'Inventaire annuel 2026',
      mode: ModeDejaCompte.ajouter,
      debut: DateTime(2026, 10, 13, 9, 30),
      fin: DateTime(2026, 10, 13, 9, 31),
      statut: StatutVersement.termine,
      lignes: [
        LigneVersement(code: '3400930000001', quantiteCollectee: 12, etat: EtatLigneVersement.versee, ligneId: 1, cip: '3400930000001', nom: 'DOLIPRANE 1000 MG CPR B/8', quantiteCible: 12),
        LigneVersement(
            code: '3400935959001', quantiteCollectee: 4, etat: EtatLigneVersement.versee, ligneId: 2, cip: '3400935959001', nom: 'AMOXICILLINE 500 GÉL B/12', quantiteExistante: 6, quantiteCible: 10),
        LigneVersement(code: '9999999999999', quantiteCollectee: 3, etat: EtatLigneVersement.nonReconnue, raison: 'introuvable dans cet inventaire'),
        LigneVersement(code: '3400936', quantiteCollectee: 2, etat: EtatLigneVersement.nonReconnue, raison: 'correspondance partielle seulement (3400936000002)'),
      ],
    );
    await tester.pumpWidget(_cadre(b, RapportVersementScreen(versement: v)));
    await tester.pumpAndSettle();
    expect(b.serveur.appels, isEmpty);
    await _photo(tester, 'app_versement_3_rapport');
    await demonter(tester);
  });
}
