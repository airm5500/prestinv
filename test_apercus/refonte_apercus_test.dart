// Aperçus PNG RÉELS de la nouvelle interface (étape 4), avec le VRAI thème de l'application (charte
// bleu nuit / ambre, lib/ui/theme.dart) et les polices Roboto + icônes Material du SDK Flutter (sans
// réseau). Hors CI ; pour régénérer :
//   flutter test test_apercus/refonte_apercus_test.dart --update-goldens
// Fichiers : docs/maquettes/apercus/refonte_*.png (360 × 800 dp, tablette 1280 × 800 dp) et la
// planche avant / après refonte_0_avant_apres.png.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/config/theme_origine.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/screens/global_variance_screen.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/ui/ecrans/a_envoyer_screen.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/analyse_screen.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/licence_screen.dart';
import 'package:prestinv/ui/ecrans/restants_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

import '../test/helpers/banc_essai.dart';
import '../test/helpers/douchette_essai.dart';
import '../test/helpers/nouvelle_interface.dart';

const _dossier = '../docs/maquettes/apercus';
final _inv = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

Widget _cadre(Banc b, Widget ecran, {bool nv = true}) =>
    RepaintBoundary(key: const ValueKey('apercu'), child: nv ? monterNv(b, ecran) : monter(b, ecran));

Future<void> _photo(WidgetTester tester, String nom) async {
  await expectLater(find.byKey(const ValueKey('apercu')), matchesGoldenFile('$_dossier/$nom.png'));
}

/// Saisies sur l'appareil : 3 envoyées, 2 en attente (réseau coupé), 1 rayon CANNES ouvert en dernier.
Future<void> _saisies(Banc b) async {
  Future<void> e(int id, String cip, String nom, int q, {String? rayon, String? rayonLib, OrigineSaisie o = OrigineSaisie.rapide}) =>
      b.queue.enregistrer(inventaireId: 'INV1', inventaireLibelle: 'Inventaire annuel 2026', ligneId: id, cip: cip, nom: nom, quantite: q, rayonId: rayon, rayonLibelle: rayonLib, origine: o);
  await e(5, '3400938000004', 'BÉTADINE DERMIQUE 10 %', 30, rayonLib: 'S1A0T2');
  await e(4, '3400937000003', 'SPASFON LYOC 80 MG', 0, rayonLib: 'S2B2');
  await e(3, '3400936000002', 'EFFERALGAN 500 CPR EFF', 7, rayonLib: 'S3');
  await b.queue.envoyer();
  b.serveur.injoignable = true;
  await e(2, '3400935959001', 'AMOXICILLINE 500 GÉL B/12', 10, rayonLib: 'S2B2');
  await e(1, '3400930000001', 'DOLIPRANE 1000 MG CPR B/8', 24, rayonLib: 'S3');
  await e(10, '3400939300008', 'BILAN BIOLOGIQUE TOTAL', 8, rayon: 'S1A0T2', rayonLib: 'CANNES', o: OrigineSaisie.guidee);
}

/// Thème d'origine tel qu'affiché sur Android : un texte de bouton sans police précisée y est en Roboto
/// (le moteur de test, lui, dessine des carrés). Seule la police est précisée, rien d'autre ne change.
ThemeData _themeOrigineRoboto() {
  final t = themeOrigine();
  return t.copyWith(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: t.elevatedButtonTheme.style!.copyWith(textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Roboto'))),
    ),
  );
}

void main() {
  setUpAll(() async {
    WidgetsApp.debugAllowBannerOverride = false;
    await chargerPolicesReelles();
  });
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });
  tearDown(() => InterfaceVersion.useNew.value = false);

  Future<Banc> banc({SendMode mode = SendMode.direct, bool cumul = true}) async {
    final b = await preparerBanc(serveur: serveurRealiste(), mode: mode, cumul: cumul);
    // ignore: invalid_use_of_visible_for_testing_member
    b.auth.connecterPourTest(login: 'Awa K.');
    return b;
  }

  for (final (nom, taille) in [('', telephone360), ('_tablette', tablette)]) {
    testWidgets('accueil$nom', (tester) async {
      tailleEcran(tester, taille, densite: taille == tablette ? 1.5 : 2);
      final b = await banc();
      await _saisies(b);
      b.serveur.injoignable = false;
      InterfaceVersion.useNew.value = true;
      await tester.pumpWidget(_cadre(b, const HomeScreen(), nv: false));
      await tester.pumpAndSettle();
      await _photo(tester, 'refonte_1_accueil$nom');
      await demonter(tester);
    });
  }

  testWidgets('accueil sombre', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await _saisies(b);
    b.serveur.injoignable = false;
    await NvApparence.choisir(Apparence.sombre);
    await tester.pumpWidget(_cadre(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_1_accueil_sombre');
    await NvApparence.choisir(Apparence.systeme);
    await demonter(tester);
  });

  testWidgets('rayons', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await _saisies(b);
    b.serveur.injoignable = false;
    b.serveur.produits.firstWhere((p) => p.rayon == 'S1A0T2').dtUpdated = '2026-10-13';
    await tester.pumpWidget(_cadre(b, NvChoixRayonScreen(inventaire: _inv)));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_2_rayons');
    await demonter(tester);
  });

  for (final (nom, taille) in [('', telephone360), ('_tablette', tablette)]) {
    testWidgets('saisie guidée$nom', (tester) async {
      tailleEcran(tester, taille, densite: taille == tablette ? 1.5 : 2);
      final b = await banc(mode: SendMode.direct, cumul: false);
      await tester.pumpWidget(_cadre(b, NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S1A0T2')));
      await tester.pumpAndSettle();
      await taperNv(tester, '30');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await taperNv(tester, '8', ok: false);
      await tester.pumpAndSettle();
      await _photo(tester, 'refonte_3_saisie_guidee$nom');
      await demonter(tester);
    });
  }

  for (final (nom, taille) in [('', telephone360), ('_tablette', tablette)]) {
    testWidgets('scan continu$nom', (tester) async {
      tailleEcran(tester, taille, densite: taille == tablette ? 1.5 : 2);
      final b = await banc();
      await _saisies(b);
      await tester.pumpWidget(_cadre(b, NvScanContinuScreen(inventaire: _inv)));
      await tester.pumpAndSettle();
      b.serveur.injoignable = false;
      await douchette(tester, '3401597413');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await _photo(tester, 'refonte_4_scan_continu$nom');
      if (nom.isEmpty) {
        await douchette(tester, '3400935959001');
        await tester.pumpAndSettle();
        await taperNv(tester, '4', ok: false);
        await tester.pumpAndSettle();
        await _photo(tester, 'refonte_5_quantite_scan');
        await tester.tap(find.byKey(const ValueKey('nv-feuille-annuler')));
        await tester.pumpAndSettle();
      }
      await demonter(tester);
    });
  }

  for (final (nom, taille) in [('', telephone360), ('_tablette', tablette)]) {
    testWidgets('écarts$nom', (tester) async {
      tailleEcran(tester, taille, densite: taille == tablette ? 1.5 : 2);
      final b = await banc();
      await tester.pumpWidget(_cadre(b, NvEcartsScreen(inventaire: _inv)));
      await tester.pumpAndSettle();
      if (nom.isNotEmpty) {
        await tester.tap(find.text('INSULINE LANTUS SOLOSTAR').first);
        await tester.pumpAndSettle();
        await taperNv(tester, '9', ok: false);
        await tester.pumpAndSettle();
      }
      await _photo(tester, 'refonte_6_ecarts$nom');
      if (nom.isEmpty) {
        await tester.tap(find.text('AUGMENTIN 1 G SACHETS'));
        await tester.pumpAndSettle();
        await taperNv(tester, '20', ok: false);
        await tester.pumpAndSettle();
        await _photo(tester, 'refonte_6_ecarts_correction');
        await tester.tap(find.byKey(const ValueKey('nv-fermer-correction')));
        await tester.pumpAndSettle();
      }
      await demonter(tester);
    });
  }

  testWidgets('restants', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await tester.pumpWidget(_cadre(b, NvRestantsScreen(inventaire: _inv)));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_7_restants');
    await demonter(tester);
  });

  testWidgets('à envoyer', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await _saisies(b);
    await tester.pumpWidget(_cadre(b, const NvAEnvoyerScreen()));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_8_a_envoyer');
    await demonter(tester);
  });

  testWidgets('collecte', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await CollecteStore.ecrire([
      CollectedItem(code: '3400930000001', quantity: 12, dateScan: DateTime(2026, 10, 13, 9)),
      CollectedItem(code: '3400935959001', quantity: 4, dateScan: DateTime(2026, 10, 13, 9, 1)),
      CollectedItem(code: '9999999999999', quantity: 3, dateScan: DateTime(2026, 10, 13, 9, 2)),
    ]);
    await tester.pumpWidget(_cadre(b, const NvCollecteScreen()));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_9_collecte');
    await demonter(tester);
  });

  testWidgets('connexion, licence, serveur injoignable, réglages, analyse', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await _saisies(b);
    await tester.pumpWidget(_cadre(b, const NvConnexionScreen()));
    await tester.pumpAndSettle();
    // Logo (image de l'application) chargé avant la photo.
    await tester.runAsync(() => precacheImage(const AssetImage('assets/images/icon.png'), tester.element(find.byType(NvConnexionScreen))));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_10_connexion');
    await tester.pumpWidget(_cadre(b, NvServeurInjoignableScreen(reessayer: () async {})));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_11_serveur_injoignable');
    await tester.pumpWidget(_cadre(b, Builder(builder: (context) {
      context.read<LicenseProvider>();
      return const NvLicenceScreen();
    })));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_12_licence');
    await tester.pumpWidget(_cadre(b, const NvConfigScreen()));
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_13_reglages');
    b.serveur.injoignable = false;
    await tester.pumpWidget(_cadre(b, const NvAnalyseScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nv-analyse-inventaire')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventaire annuel 2026').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nv-analyse-rayon')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S1A0T2 - CANNES').last);
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_14_analyse');
    await demonter(tester);
  });

  testWidgets('planche avant / après', (tester) async {
    tailleEcran(tester, const Size(4 * 360 + 3 * 24 + 48, 2 * 800 + 2 * 40 + 48), densite: 1);
    Future<Banc> bancSaisies({bool saisies = true}) async {
      final b = await banc();
      if (saisies) await _saisies(b);
      b.serveur.injoignable = false;
      return b;
    }

    final avant = await bancSaisies();
    final apres = await bancSaisies();
    final avantGuidee = await bancSaisies(saisies: false);
    final apresGuidee = await bancSaisies(saisies: false);
    Widget ecran(Banc b, Widget w, {required bool nv}) => SizedBox(
          width: 360,
          height: 800,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(360, 800), devicePixelRatio: 1),
            // Avant : thème réel des écrans d'origine (themeOrigine, celui de main.dart).
            child: ClipRect(child: nv ? monterNv(b, w) : monter(b, Theme(data: _themeOrigineRoboto(), child: w))),
          ),
        );
    Widget libelle(String t) => SizedBox(
        height: 40, child: Center(child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink, fontFamily: 'Roboto'))));
    final colonnes = <(String, Banc, Widget, Banc, Widget)>[
      ('Accueil', avant, const AncienHomeScreen(), apres, const NvAccueilScreen()),
      ('Saisie guidée', avantGuidee, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire annuel 2026'), apresGuidee,
          NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S1A0T2')),
      ('Scan continu', avant, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire annuel 2026', isQuickMode: true), apres,
          NvScanContinuScreen(inventaire: _inv)),
      ('Écarts', avant, const GlobalVarianceScreen(inventoryId: 'INV1', inventoryName: 'Inventaire annuel 2026'), apres, NvEcartsScreen(inventaire: _inv)),
    ];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: const ValueKey('apercu'),
        child: Container(
          color: const Color(0xFFE9ECF2),
          padding: const EdgeInsets.all(24),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (t, ba, a, bn, n) in colonnes) ...[
              if (t != 'Accueil') const SizedBox(width: 24),
              Column(children: [
                libelle('$t — avant'),
                ecran(ba, a, nv: false),
                libelle('$t — après'),
                ecran(bn, n, nv: true),
              ]),
            ],
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Saisie guidée d'origine : choix du rayon CANNES (comme sur le terminal).
    await tester.tap(find.text('Sélectionner un emplacement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANNES').last);
    await tester.pumpAndSettle();
    await _photo(tester, 'refonte_0_avant_apres');
    await demonter(tester);
  });
}
