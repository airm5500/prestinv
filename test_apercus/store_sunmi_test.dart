// Images pour le magasin d'applications Sunmi (hors CI) : captures d'écran PURES de la nouvelle
// interface (pas de cadre d'appareil, pas de texte ajouté), vrai thème (lib/ui/theme.dart), polices
// Roboto et icônes Material du SDK Flutter (sans réseau), sans bandeau de débogage, en PNG RGB 8 bits
// SANS canal alpha.
//
// Données de démonstration neutres : « Pharmacie Démo », produits courants désignés par leur DCI,
// identifiants de terminal (« comptoir1 »), aucun nom de personne, aucune donnée de client.
//
// Régénérer (depuis la racine du dépôt) :
//   flutter test test_apercus/store_sunmi_test.dart
// Fichiers : docs/store_sunmi/terminal/ (1080 × 1920, 411 × 731 dp), docs/store_sunmi/terminal/720x1440/ (Sunmi V2s
// natif) et docs/store_sunmi/tablette/ (1920 × 1200), nommés 1_connexion.png … 5_ecarts.png.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/navigation.dart';

import '../test/helpers/banc_essai.dart';
import '../test/helpers/douchette_essai.dart';
import '../test/helpers/faux_prestige_http.dart';
import '../test/helpers/nouvelle_interface.dart';

/// Format d'image : dossier, taille en pixels, densité (taille en dp = pixels / densité).
class Format {
  final String dossier;
  final int largeur;
  final int hauteur;
  final double densite;
  const Format(this.dossier, this.largeur, this.hauteur, this.densite);
  Size get dp => Size(largeur / densite, hauteur / densite);
  bool get tablette => dp.width >= 900;
}

const formats = [
  // 1080 × 1920 portrait, densité 2,625 (420 dpi) : 411 × 731 dp, comme un terminal ou téléphone 1080p.
  Format('docs/store_sunmi/terminal', 1080, 1920, 2.625),
  // 720 × 1440 : Sunmi V2s natif (360 × 720 dp, densité 2).
  Format('docs/store_sunmi/terminal/720x1440', 720, 1440, 2),
  // 1920 × 1200 paysage, densité 1,5 : 1280 × 800 dp (tablette).
  Format('docs/store_sunmi/tablette', 1920, 1200, 1.5),
];

/// Taille de la vue de test (en pixels exacts, pour une image aux dimensions demandées).
void taille(WidgetTester tester, Format f) {
  tester.view.physicalSize = Size(f.largeur.toDouble(), f.hauteur.toDouble());
  tester.view.devicePixelRatio = f.densite;
}

const _inv = 'INV1';
const _libelle = 'Inventaire annuel 2026';
final _inventaire = Inventory(id: _inv, libelle: _libelle);

/// Serveur de démonstration : 5 rayons, produits courants, une partie déjà comptée.
FauxPrestige serveurDemo() {
  final s = FauxPrestige(nombre: 0);
  s.inventaires = {_inv: _libelle, 'INV2': 'Réserve — contrôle d\'octobre'};
  s.rayons
    ..clear()
    ..addAll({'R01': 'ANTALGIQUES', 'R02': 'ANTIBIOTIQUES', 'R03': 'DERMATOLOGIE', 'R04': 'GASTRO-ENTÉROLOGIE', 'R05': 'RÉSERVE'});
  FauxProduitPrix p(int id, String nom, String rayon, int theorique, double prix, {int? saisi, String? heure}) =>
      FauxProduitPrix(id, '34009${(100000 + id * 7919).toString().padLeft(8, '0')}', nom, rayon, theorique, saisi: saisi, prixAchat: prix)
        ..dtUpdated = heure == null ? null : '2026-10-13T$heure:00';
  s.produits.addAll([
    p(1, 'PARACÉTAMOL 1 G CPR B/8', 'R01', 48, 650, saisi: 46, heure: '09:12'),
    p(2, 'IBUPROFÈNE 400 MG CPR B/30', 'R01', 22, 1350, saisi: 22, heure: '09:14'),
    p(3, 'PARACÉTAMOL 500 MG GÉL B/16', 'R01', 35, 700, saisi: 35, heure: '09:15'),
    p(4, 'ASPIRINE 500 MG CPR EFF B/20', 'R01', 12, 900, saisi: 13, heure: '09:18'),
    p(10, 'AMOXICILLINE 500 MG GÉL B/12', 'R02', 30, 1450, saisi: 26, heure: '10:02'),
    p(11, 'AMOXICILLINE + AC. CLAV. 1 G SACHETS', 'R02', 18, 4200, saisi: 14, heure: '10:05'),
    p(12, 'AZITHROMYCINE 250 MG CPR B/6', 'R02', 9, 3100, saisi: 9, heure: '10:07'),
    p(13, 'CIPROFLOXACINE 500 MG CPR B/10', 'R02', 14, 2650),
    p(14, 'DOXYCYCLINE 100 MG CPR B/14', 'R02', 11, 1900),
    p(15, 'MÉTRONIDAZOLE 250 MG CPR B/20', 'R02', 25, 850),
    p(16, 'CÉFIXIME 200 MG CPR B/8', 'R02', 7, 5200),
    p(20, 'CRÈME HYDRATANTE 200 ML', 'R03', 16, 2900, saisi: 18, heure: '09:40'),
    p(21, 'SOLUTION ANTISEPTIQUE 125 ML', 'R03', 24, 1250, saisi: 24, heure: '09:42'),
    p(22, 'POMMADE CICATRISANTE 40 G', 'R03', 10, 2300),
    p(30, 'OMÉPRAZOLE 20 MG GÉL B/14', 'R04', 20, 1800),
    p(31, 'SACHETS DE RÉHYDRATATION B/10', 'R04', 40, 600),
    p(32, 'SIROP ANTIACIDE 250 ML', 'R04', 8, 2100),
    p(40, 'GEL HYDROALCOOLIQUE 100 ML', 'R05', 60, 750, saisi: 54, heure: '08:51'),
    p(41, 'COMPRESSES STÉRILES 10X10 B/50', 'R05', 30, 1650, saisi: 30, heure: '08:55'),
    p(42, 'SÉRUM PHYSIOLOGIQUE 5 ML B/40', 'R05', 45, 1100, saisi: 47, heure: '08:58'),
    p(43, 'THERMOMÈTRE DIGITAL', 'R05', 6, 3500, saisi: 4, heure: '09:01'),
  ]);
  return s;
}

FauxProduit _produit(FauxPrestige s, int id) => s.produit(id);

Future<Banc> banc({SendMode mode = SendMode.direct, Map<String, Object> prefs = const {}}) async {
  final b = await preparerBanc(serveur: serveurDemo(), mode: mode, cumul: false, prefsEnPlus: {
    InterfaceVersion.key: true,
    ...prefs,
  });
  // ignore: invalid_use_of_visible_for_testing_member
  b.auth.connecterPourTest(login: 'comptoir1', prenom: 'Comptoir 1', officine: 'Pharmacie Démo');
  return b;
}

/// Saisies de la session (toutes envoyées) : quelques produits par scan, puis le rayon ANTIBIOTIQUES.
Future<void> saisiesDemo(Banc b) async {
  Future<void> e(int id, int q, {String? rayon, String? rayonLib, OrigineSaisie o = OrigineSaisie.rapide}) {
    final p = _produit(b.serveur, id);
    return b.queue.enregistrer(
        inventaireId: _inv, inventaireLibelle: _libelle, ligneId: id, cip: p.cip, nom: p.nom, quantite: q, rayonId: rayon, rayonLibelle: rayonLib, origine: o);
  }

  await e(40, 54);
  await e(41, 30);
  await e(42, 47);
  await e(43, 4);
  await e(10, 26, rayon: 'R02', rayonLib: 'ANTIBIOTIQUES', o: OrigineSaisie.guidee);
  await e(11, 14, rayon: 'R02', rayonLib: 'ANTIBIOTIQUES', o: OrigineSaisie.guidee);
  await e(12, 9, rayon: 'R02', rayonLib: 'ANTIBIOTIQUES', o: OrigineSaisie.guidee);
  await b.queue.envoyer();
}

// --- PNG RGB (sans alpha) ---

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc(List<int> octets) {
  var c = 0xFFFFFFFF;
  for (final o in octets) {
    c = _crcTable[(c ^ o) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

List<int> _bloc(String type, List<int> donnees) {
  final t = ascii.encode(type);
  final longueur = ByteData(4)..setUint32(0, donnees.length);
  final crc = ByteData(4)..setUint32(0, _crc([...t, ...donnees]));
  return [...longueur.buffer.asUint8List(), ...t, ...donnees, ...crc.buffer.asUint8List()];
}

/// PNG 8 bits RGB (type de couleur 2), pixels composés sur fond blanc s'ils ne sont pas opaques.
Uint8List pngRgb(Uint8List rgba, int largeur, int hauteur) {
  final brut = BytesBuilder(copy: false);
  for (var y = 0; y < hauteur; y++) {
    final ligne = Uint8List(1 + largeur * 3); // filtre 0
    for (var x = 0; x < largeur; x++) {
      final i = (y * largeur + x) * 4;
      final a = rgba[i + 3];
      for (var c = 0; c < 3; c++) {
        final v = rgba[i + c];
        // Fond blanc sous un éventuel pixel transparent (l'écran est entièrement peint en pratique).
        ligne[1 + x * 3 + c] = a == 255 ? v : (v * a + 255 * (255 - a)) ~/ 255;
      }
    }
    brut.add(ligne);
  }
  final ihdr = ByteData(13)
    ..setUint32(0, largeur)
    ..setUint32(4, hauteur)
    ..setUint8(8, 8) // profondeur
    ..setUint8(9, 2) // RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ..._bloc('IHDR', ihdr.buffer.asUint8List()),
    ..._bloc('IDAT', ZLibCodec(level: 9).encode(brut.takeBytes())),
    ..._bloc('IEND', const []),
  ]);
}

Widget cadre(Banc b, Widget ecran) => RepaintBoundary(key: const ValueKey('ecran'), child: monterNv(b, ecran));

Future<void> capturer(WidgetTester tester, Format f, String nom) async {
  await tester.pumpAndSettle();
  final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('ecran')));
  final image = (await tester.runAsync(() => ro.toImage(pixelRatio: f.densite)))!;
  final octets = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  expect((image.width, image.height), (f.largeur, f.hauteur), reason: '${f.dossier}/$nom');
  final fichier = File('${f.dossier}/$nom.png');
  fichier.parent.createSync(recursive: true);
  fichier.writeAsBytesSync(pngRgb(octets.buffer.asUint8List(), image.width, image.height));
  image.dispose();
  expect(tester.takeException(), isNull, reason: 'rendu sans débordement : ${f.dossier}/$nom');
}

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

  for (final f in formats) {
    group(f.dossier, () {
      testWidgets('1_connexion', (tester) async {
        taille(tester, f);
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

      testWidgets('2_accueil', (tester) async {
        taille(tester, f);
        final maintenant = DateTime.now();
        final avancement = AvancementRayons(
          inventaireId: _inv,
          calculeA: DateTime(maintenant.year, maintenant.month, maintenant.day, 10, 42),
          total: 5,
          statuts: const {'R01': 2, 'R02': 1, 'R03': 1, 'R04': 0, 'R05': 2},
        );
        final b = await banc(prefs: {
          AvancementCalcul.cle(_inv): json.encode(avancement.toJson()),
          InventaireCourant.cle: _inv,
        });
        await saisiesDemo(b);
        await tester.pumpWidget(cadre(b, const NvAccueilScreen()));
        await capturer(tester, f, '2_accueil');
        await demonter(tester);
      });

      testWidgets('3_saisie_guidee', (tester) async {
        taille(tester, f);
        final b = await banc();
        await saisiesDemo(b);
        await tester.pumpWidget(cadre(b, NvSaisieGuideeScreen(inventaire: _inventaire, rayonId: 'R02')));
        await tester.pumpAndSettle();
        Future<void> allerA(String nom) async {
          // Même action que « Suivant » (le bouton peut être hors de l'écran du terminal).
          final cible = b.entry.products.indexWhere((p) => p.produitName.contains(nom));
          while (b.entry.currentProductIndex < cible) {
            b.entry.nextProduct(_inv);
            await tester.pumpAndSettle();
          }
          while (b.entry.currentProductIndex > cible) {
            b.entry.previousProduct(_inv);
            await tester.pumpAndSettle();
          }
          expect(b.entry.currentProduct?.produitName, contains(nom));
        }

        // CÉFIXIME compté et envoyé (état du produit précédent), puis CIPROFLOXACINE en cours de frappe.
        await allerA('CÉFIXIME');
        await taperNv(tester, '7');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await allerA('CIPROFLOXACINE');
        await taperNv(tester, '14', ok: false);
        await capturer(tester, f, '3_saisie_guidee');
        await demonter(tester);
      });

      testWidgets('4_scan_continu', (tester) async {
        taille(tester, f);
        final b = await banc();
        await saisiesDemo(b);
        await tester.pumpWidget(cadre(b, NvScanContinuScreen(inventaire: _inventaire)));
        await tester.pumpAndSettle();
        for (final (id, q) in [(30, 20), (31, 38)]) {
          await douchette(tester, _produit(b.serveur, id).cip);
          await tester.pumpAndSettle();
          await taperNv(tester, '$q');
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 4));
        }
        await capturer(tester, f, '4_scan_continu');
        await demonter(tester);
      });

      testWidgets('5_ecarts', (tester) async {
        taille(tester, f);
        final b = await banc();
        await tester.pumpWidget(cadre(b, NvEcartsScreen(inventaire: _inventaire)));
        await tester.pumpAndSettle();
        if (f.tablette) {
          // Tablette : tableau à gauche, correction à droite (recomptage en cours de frappe).
          await tester.tap(find.text('THERMOMÈTRE DIGITAL').first);
          await tester.pumpAndSettle();
          await taperNv(tester, '6', ok: false);
        }
        await capturer(tester, f, '5_ecarts');
        await demonter(tester);
      });
    });
  }
}
