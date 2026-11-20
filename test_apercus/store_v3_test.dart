// Captures du MAGASIN (Sunmi App Store, Google Play) de Prestige Inventaire V3 (5.0.0), hors CI : captures d'écran
// PURES des vrais écrans de la nouvelle interface (faux serveur de démonstration de store_sunmi_test.dart), vrai thème,
// polices Roboto et icônes Material du SDK Flutter, sans bandeau de débogage, PNG RGB 8 bits sans alpha.
//   1. connexion ; 2. liste des inventaires ; 3. saisie par scan d'un produit ; 4. écarts / récapitulatif ;
//   5. rapport PDF des cumuls (PDF RÉEL produit par NvExports.pdfCumuls, page 1,
//      rastérisée ensuite (pdftoppm) et posée sur un fond d'aperçu avant impression, hors de ce test).
// Données de démonstration neutres (« Pharmacie Démo », DCI, CIP fictifs, poste « Comptoir 1 »), aucune personne.
// Terminal Sunmi V2s portrait 720 × 1440 (densité 2) et tablette paysage 1920 × 1200 (densité 1,5).
// Régénérer (depuis la racine du dépôt) :
//   CAPTURES=/dossier flutter test test_apercus/store_v3_test.dart
// → /dossier/inventaire/terminal/*.png, /dossier/inventaire/tablette/*.png (et cumuls.pdf pour l'étape 5).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/exports.dart';

import '../test/helpers/banc_essai.dart';
import '../test/helpers/douchette_essai.dart';
import '../test/helpers/nouvelle_interface.dart';
import '../test/helpers/version_installee.dart';
import 'store_sunmi_test.dart' show Format, taille, banc, saisiesDemo, cadre, capturer;

final _base = Platform.environment['CAPTURES'] ?? '/tmp/captures_store_v3';

final _formats = [
  Format('$_base/inventaire/terminal', 720, 1440, 2),
  Format('$_base/inventaire/tablette', 1920, 1200, 1.5),
];

final _inventaire = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

void main() {
  setUpAll(() async {
    WidgetsApp.debugAllowBannerOverride = false; // pas de bandeau « DEBUG »
    expect(await chargerPolicesReelles(), isTrue, reason: 'polices Roboto du SDK Flutter introuvables (FLUTTER_ROOT)');
  });
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
    InterfaceVersion.useNew.value = true;
    // ignore: invalid_use_of_visible_for_testing_member
    AvancementCalcul.viderCache();
  });
  tearDown(() => InterfaceVersion.useNew.value = false);

  for (final f in _formats) {
    group(f.dossier, () {
      testWidgets('1_connexion', (tester) async {
        taille(tester, f);
        simulerVersionInstallee(); // « Version 5.0.0+22 » (pubspec.yaml) en bas de la connexion
        final b = await banc();
        await tester.pumpWidget(cadre(b, const NvConnexionScreen()));
        await tester.pumpAndSettle();
        await tester.runAsync(() => precacheImage(const AssetImage('assets/images/icon.png'), tester.element(find.byType(NvConnexionScreen))));
        await tester.enterText(find.byKey(const ValueKey('nv-identifiant')), 'comptoir1');
        await tester.enterText(find.byKey(const ValueKey('nv-mot-de-passe')), 'demo2026');
        FocusManager.instance.primaryFocus?.unfocus();
        await capturer(tester, f, '1_connexion');
        await demonter(tester);
      });

      testWidgets('2_liste_inventaires', (tester) async {
        taille(tester, f);
        final b = await banc();
        await tester.pumpWidget(cadre(b, const NvAccueilScreen()));
        await tester.pumpAndSettle();
        await deroulerInventaires(tester);
        await capturer(tester, f, '2_liste_inventaires');
        await demonter(tester);
      });

      testWidgets('3_saisie_scan', (tester) async {
        taille(tester, f);
        final b = await banc();
        await saisiesDemo(b);
        await tester.pumpWidget(cadre(b, NvScanContinuScreen(inventaire: _inventaire)));
        await tester.pumpAndSettle();
        // Un produit déjà scanné et envoyé, puis le suivant scanné : quantité en cours de frappe.
        await douchette(tester, b.serveur.produit(30).cip);
        await tester.pumpAndSettle();
        await taperNv(tester, '20');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 4));
        await douchette(tester, b.serveur.produit(31).cip);
        await tester.pumpAndSettle();
        await taperNv(tester, '38', ok: false);
        await capturer(tester, f, '3_saisie_scan');
        await demonter(tester);
      });

      testWidgets('4_ecarts', (tester) async {
        taille(tester, f);
        final b = await banc();
        await tester.pumpWidget(cadre(b, NvEcartsScreen(inventaire: _inventaire)));
        await tester.pumpAndSettle();
        if (f.tablette) {
          await tester.tap(find.text('THERMOMÈTRE DIGITAL').first);
          await tester.pumpAndSettle();
        }
        await capturer(tester, f, '4_ecarts');
        await demonter(tester);
      });
    });
  }

  test('5 : PDF réel du rapport des cumuls (données fictives)', () async {
    final logs = <Map<String, dynamic>>[
      for (final (i, (cip, nom, avant, ajout, rayon)) in [
        ('3400900792491', 'PARACÉTAMOL 1 G CPR B/8', 46, 12, 'ANTALGIQUES'),
        ('3400901105184', 'AMOXICILLINE 500 MG GÉL B/12', 26, 4, 'ANTIBIOTIQUES'),
        ('3400901184779', 'SÉRUM PHYSIOLOGIQUE 5 ML B/40', 47, 20, 'RÉSERVE'),
        ('3400900871301', 'GEL HYDROALCOOLIQUE 100 ML', 54, 6, 'RÉSERVE'),
        ('3400901422342', 'IBUPROFÈNE 400 MG CPR B/30', 22, 8, 'ANTALGIQUES'),
        ('3400900951008', 'SACHETS DE RÉHYDRATATION B/10', 38, 10, 'GASTRO-ENTÉROLOGIE'),
        ('3400901263269', 'COMPRESSES STÉRILES 10X10 B/50', 30, 5, 'RÉSERVE'),
        ('3400901025642', 'SOLUTION ANTISEPTIQUE 125 ML', 24, 3, 'DERMATOLOGIE'),
      ].indexed)
        {
          'date': '2026-11-20T09:${(12 + i * 3).toString().padLeft(2, '0')}:0$i',
          'cip': cip,
          'name': nom,
          'oldQty': avant,
          'addedQty': ajout,
          'newQty': avant + ajout,
          'rayon': rayon,
          'comptePar': i.isEven ? 'Comptoir 1' : 'Comptoir 2',
        },
    ];
    final pdf = await NvExports.pdfCumuls(logs);
    final fichier = File('$_base/inventaire/cumuls.pdf')..parent.createSync(recursive: true);
    fichier.writeAsBytesSync(pdf);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });
}
