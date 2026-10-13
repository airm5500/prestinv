// Outils d'essai de la nouvelle interface (lib/ui/…) : serveur réaliste (rayons, prix d'achat), montage
// avec le thème de la nouvelle interface, tailles d'écran (Sunmi V2s 360 dp, tablette), polices
// réelles (Roboto et icônes Material du SDK Flutter, sans réseau), frappe sur le pavé ambre.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/ui/theme.dart';

import 'banc_essai.dart';
import 'faux_prestige_http.dart';

/// Produit avec un prix d'achat réaliste (le faux serveur d'origine renvoie 100 F pour tous).
class FauxProduitPrix extends FauxProduit {
  final double prixAchat;
  FauxProduitPrix(super.id, super.cip, super.nom, super.rayon, super.theorique, {super.saisi, this.prixAchat = 1000});

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'produitPrixAchat': prixAchat, 'produitPrixUni': (prixAchat * 1.3).roundToDouble()};
}

/// Serveur avec trois rayons et des produits nommés comme en officine.
FauxPrestige serveurRealiste() {
  final s = FauxPrestige(nombre: 0);
  s.inventaires = {'INV1': 'Inventaire annuel 2026', 'INV2': 'Réserve S3 — octobre'};
  s.rayons
    ..clear()
    ..addAll({'S1A0T2': 'CANNES', 'S2B2': 'ANTIBIOTIQUES', 'S3': 'RÉSERVE'});
  final ps = <FauxProduit>[
    FauxProduitPrix(1, '3400930000001', 'DOLIPRANE 1000 MG CPR B/8', 'S3', 24, prixAchat: 850),
    FauxProduitPrix(2, '3400935959001', 'AMOXICILLINE 500 GÉL B/12', 'S2B2', 10, saisi: 6, prixAchat: 1450)..dtUpdated = '2026-10-13T08:55:00',
    FauxProduitPrix(3, '3400936000002', 'EFFERALGAN 500 CPR EFF', 'S3', 40, saisi: 38, prixAchat: 950)..dtUpdated = '2026-10-13T09:30:00',
    FauxProduitPrix(4, '3400937000003', 'SPASFON LYOC 80 MG', 'S2B2', 3, prixAchat: 2100),
    FauxProduitPrix(5, '3400938000004', 'BÉTADINE DERMIQUE 10 %', 'S1A0T2', 30, prixAchat: 1800),
    FauxProduitPrix(6, '3400936311000', 'AUGMENTIN 1 G SACHETS', 'S2B2', 22, saisi: 14, prixAchat: 7700)..dtUpdated = '2026-10-13T10:12:00',
    FauxProduitPrix(7, '3400939000005', 'INSULINE LANTUS SOLOSTAR', 'S3', 9, saisi: 4, prixAchat: 28400)..dtUpdated = '2026-10-13T10:12:00',
    FauxProduitPrix(8, '3400939100006', 'VOLTARENE EMULGEL 1 %', 'S1A0T2', 3, saisi: 11, prixAchat: 3600)..dtUpdated = '2026-10-13T10:05:00',
    FauxProduitPrix(9, '3400939200007', 'DAFALGAN CODEINE CPR', 'S2B2', 30, saisi: 26, prixAchat: 2460)..dtUpdated = '2026-10-13T09:58:00',
    FauxProduitPrix(10, '3400939300008', 'BILAN BIOLOGIQUE TOTAL', 'S1A0T2', 12, prixAchat: 1250),
    FauxProduitPrix(11, '3400939400009', 'SMECTA SACHETS B/30', 'S1A0T2', 15, saisi: 12, prixAchat: 2450)..dtUpdated = '2026-10-13T09:40:00',
    FauxProduitPrix(12, '3400939500000', 'ORTHOPÉDIE GENOUILLÈRE T2', 'S1A0T2', 4, prixAchat: 9800),
  ];
  s.produits.addAll(ps);
  return s;
}

/// Monte [ecran] avec les providers de l'application et le thème de la nouvelle interface.
Widget monterNv(Banc b, Widget ecran) => monter(b, NvTheme(child: ecran));

/// Taille d'écran en dp (densité 2 par défaut).
void tailleEcran(WidgetTester tester, Size dp, {double densite = 2}) {
  tester.view.physicalSize = Size(dp.width * densite, dp.height * densite);
  tester.view.devicePixelRatio = densite;
}

const telephone360 = Size(360, 800);
const sunmiV2s = Size(360, 640);
const tablette = Size(1280, 800);
const tabletteMoyenne = Size(800, 1280);

/// Polices réelles (Roboto, icônes Material) du SDK Flutter, chargées sans réseau. Sans elles, les
/// tests utilisent une police où chaque lettre est un carré (plus large que Roboto).
Future<bool> chargerPolicesReelles() async {
  final racine = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dossier = Directory('$racine/bin/cache/artifacts/material_fonts');
  if (racine.isEmpty || !dossier.existsSync()) return false;
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File('${dossier.path}/$f').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    roboto.addFont(lire(f));
  }
  await roboto.load();
  final icones = FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'));
  await icones.load();
  return true;
}

/// Touche le pavé de la nouvelle interface ([chiffres] puis la validation si [ok]).
Future<void> taperNv(WidgetTester tester, String chiffres, {bool ok = true}) async {
  for (final c in chiffres.split('')) {
    await tester.tap(find.byKey(ValueKey('touche-$c')).last);
    await tester.pump();
  }
  if (ok) {
    await tester.tap(find.byKey(const ValueKey('touche-OK')).last);
    await tester.pump();
  }
}

/// Nouvelle interface active pendant le test (remise à l'état d'origine ensuite).
void activerNouvelleInterface() {
  InterfaceVersion.useNew.value = true;
  addTearDown(() => InterfaceVersion.useNew.value = false);
}
