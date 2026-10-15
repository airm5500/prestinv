// UNITAIRES — scan par l'appareil photo (4.14), sans écran de l'application :
//  - réglage « Scan par l'appareil photo » DÉSACTIVÉ par défaut (nouvelle installation comme mise à jour),
//    enregistré quand l'administrateur l'active ;
//  - un code lu par l'appareil photo (moteur SIMULÉ) arrive à la cible de la douchette EXACTEMENT comme la
//    même lecture faite par la douchette (mêmes actions : code nettoyé, quantité, validation) ;
//  - anti-doublon (~1,5 s, horloge simulée) ;
//  - contenu d'un code lu par mobile_scanner (UPC-A → EAN-13, séparateur GS du DataMatrix GS1).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/camera/moteur_mobile_scanner.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/scan/camera/page_camera.dart';
import 'package:prestinv/scan/camera/scan_camera.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/camera_essai.dart';
import '../helpers/douchette_essai.dart';

/// Cible qui note tout ce qu'elle reçoit.
class _CibleNotee {
  final List<String> recu = [];
  late final CibleDouchette cible;
  _CibleNotee({required bool quantite}) {
    cible = CibleDouchette(
      active: () => true,
      onCode: (c) => recu.add('code:$c'),
      onChiffres: quantite ? (t) => recu.add('chiffres:$t') : null,
      onValider: quantite ? () => recu.add('valider') : null,
      onEffacer: quantite ? () => recu.add('effacer') : null,
    );
  }
}

void main() {
  group('Réglage', () {
    test('désactivé par défaut (nouvelle installation et application déjà utilisée)', () async {
      SharedPreferences.setMockInitialValues({});
      final neuve = AppConfig();
      await neuve.load();
      expect(neuve.scanCamera, isFalse);
      SharedPreferences.setMockInitialValues({'localApiAddress': '10.0.0.2', 'sendMode': 1, 'scanSon': true});
      final existante = AppConfig();
      await existante.load();
      expect(existante.scanCamera, isFalse);
      expect(AppConfig().scanCamera, isFalse, reason: 'avant même la lecture des préférences');
    });

    test('activé par l\'administrateur : enregistré et relu au lancement suivant', () async {
      SharedPreferences.setMockInitialValues({});
      final c = AppConfig();
      await c.load();
      await c.setReglagesProteges(scanCamera: true);
      expect(c.scanCamera, isTrue);
      final relu = AppConfig();
      await relu.load();
      expect(relu.scanCamera, isTrue);
      await relu.setReglagesProteges(masquerDejaCompte: true);
      expect(relu.scanCamera, isTrue, reason: 'les autres réglages protégés n\'y touchent pas');
    });
  });

  group('Injection identique à la douchette', () {
    setUp(reinitialiserDouchette);

    const lectures = [
      '3400930000001', // EAN-13
      '34009300', // EAN-8
      '  3400937000003\r', // parasites
      '0103400936311000172612311042A5\u001d21XYZ', // DataMatrix GS1 avec séparateur GS
      'ABC-128', // Code 128
      '12', // court (quantité si attendue, sinon ignoré)
      '00042', // 5 chiffres
    ];

    for (final quantite in [false, true]) {
      testWidgets('quantité attendue : $quantite', (tester) async {
        installerCameraSimulee();
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
        final nav = tester.state<NavigatorState>(find.byType(Navigator));

        var nonVides = 0;
        for (final l in lectures) {
          // 1) Douchette (caractères + Entrée).
          final parDouchette = _CibleNotee(quantite: quantite);
          Douchette.instance.ajouter(parDouchette.cible);
          await douchette(tester, l.replaceAll('\r', ''));
          await tester.pump();
          final historiqueDouchette = List.of(Douchette.instance.historique);
          Douchette.instance.retirer(parDouchette.cible);
          Douchette.instance.historique.clear();

          // 2) Appareil photo simulé (aperçu en continu), même lecture.
          final parCamera = _CibleNotee(quantite: quantite);
          Douchette.instance.ajouter(parCamera.cible);
          nav.push(MaterialPageRoute<void>(builder: (_) => const PageCamera(continu: true, surLecture: ScanCamera.versDouchette)));
          await tester.pumpAndSettle();
          MoteurCameraSimule.actif!.lire(l.replaceAll('\r', ''));
          await tester.pump();
          final historiqueCamera = List.of(Douchette.instance.historique);
          nav.pop();
          await tester.pumpAndSettle();
          Douchette.instance.retirer(parCamera.cible);
          Douchette.instance.historique.clear();

          expect(parCamera.recu, parDouchette.recu, reason: 'lecture « $l »');
          expect(historiqueCamera, historiqueDouchette, reason: 'lecture « $l »');
          if (parDouchette.recu.isNotEmpty) nonVides++;
        }
        expect(nonVides, greaterThanOrEqualTo(5), reason: 'les lectures arrivent bien à la cible');
      });
    }

    test('lecture injectée : le code est nettoyé comme celui de la douchette', () {
      reinitialiserDouchette();
      final c = _CibleNotee(quantite: false);
      Douchette.instance.ajouter(c.cible);
      Douchette.instance.injecterLecture(' 3400930000001\u0007 ');
      Douchette.instance.injecterLecture('12');
      expect(c.recu, ['code:3400930000001'], reason: 'caractère de contrôle retiré ; « 12 » seul n\'est pas un code');
      Douchette.instance.retirer(c.cible);
    });
  });

  group('Anti-doublon', () {
    test('même code ignoré ~1,5 s après avoir été vu ; autre code pris tout de suite', () {
      final h = HorlogeEssai();
      final a = AntiDoublon(horloge: () => h.t);
      expect(a.accepter('A'), isTrue);
      expect(a.accepter('A'), isFalse);
      h.avancer(const Duration(milliseconds: 1400));
      expect(a.accepter('A'), isFalse, reason: 'vu à nouveau : délai repoussé');
      h.avancer(const Duration(milliseconds: 1400));
      expect(a.accepter('A'), isFalse);
      h.avancer(const Duration(milliseconds: 1600));
      expect(a.accepter('A'), isTrue, reason: 'écarté plus de 1,5 s');
      expect(a.accepter('B'), isTrue);
      expect(a.accepter('A'), isTrue, reason: 'un autre code a été lu entre-temps');
      a.noter('C');
      expect(a.accepter('C'), isFalse, reason: 'vu sous la feuille de quantité');
      a.oublier();
      expect(a.accepter('C'), isTrue);
    });
  });

  group('Contenu d\'un code lu (mobile_scanner)', () {
    test('UPC-A → EAN-13 ; DataMatrix GS1 : séparateur GS repris des octets bruts ; formats lus', () {
      expect(MoteurMobileScanner.valeur(const Barcode(format: BarcodeFormat.upcA, rawValue: '012345678905')), '0012345678905');
      expect(MoteurMobileScanner.valeur(const Barcode(format: BarcodeFormat.ean13, rawValue: '3400930000001')), '3400930000001');
      final octets = Uint8List.fromList('010340093631100017261231'.codeUnits + [29] + '21XYZ'.codeUnits);
      expect(
        MoteurMobileScanner.valeur(Barcode(format: BarcodeFormat.dataMatrix, rawValue: '01034009363110001726123121XYZ', rawBytes: octets)),
        '010340093631100017261231\u001d21XYZ',
      );
      expect(MoteurMobileScanner.formats,
          containsAll([BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.code128, BarcodeFormat.dataMatrix, BarcodeFormat.qrCode]));
    });

    // 4.14.1 (retour du pharmacien) : un « simple code-barre » n'était pas lu alors que l'EAN l'était.
    test('formats linéaires ajoutés : Code 39, Code 93, ITF, Codabar, UPC-E (en plus des précédents)', () {
      expect(MoteurMobileScanner.formats, [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.itf,
        BarcodeFormat.codabar,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.qrCode,
      ]);
      expect(MoteurMobileScanner.formats, isNot(contains(BarcodeFormat.all)), reason: 'liste explicite : lecture rapide');
    });

    String? lu(BarcodeFormat f, String v) => MoteurMobileScanner.valeur(Barcode(format: f, rawValue: v));

    test('UPC-E → UPC-A → EAN-13 (6, 7 ou 8 chiffres ; clé recalculée ; quatre règles d\'expansion)', () {
      expect(MoteurMobileScanner.upcEVersUpcA('01234565'), '012345000065');
      expect(lu(BarcodeFormat.upcE, '01234565'), '0012345000065');
      expect(lu(BarcodeFormat.upcE, '0123456'), '0012345000065', reason: 'sans clé');
      expect(lu(BarcodeFormat.upcE, '123456'), '0012345000065', reason: 'sans système de numérotation');
      expect(MoteurMobileScanner.upcEVersUpcA('04252614'), '042100005264', reason: 'dernier chiffre 0-2');
      expect(MoteurMobileScanner.upcEVersUpcA('01234531'), '012300000451', reason: 'dernier chiffre 3');
      expect(MoteurMobileScanner.upcEVersUpcA('01234541'), '012340000053', reason: 'dernier chiffre 4');
      expect(MoteurMobileScanner.upcEVersUpcA('11234565'), '112345000062', reason: 'système 1');
      expect(MoteurMobileScanner.upcEVersUpcA('21234565'), isNull, reason: 'système 2 : pas un UPC-E');
      expect(lu(BarcodeFormat.upcE, 'ABC'), 'ABC', reason: 'illisible : rendu tel quel');
    });

    test('délimiteurs retirés (Code 39 *…*, Codabar A…B) ; ITF et Code 93 rendus tels quels', () {
      expect(lu(BarcodeFormat.code39, '*3400930000001*'), '3400930000001');
      expect(lu(BarcodeFormat.code39, 'ETQ-1234'), 'ETQ-1234');
      expect(lu(BarcodeFormat.codabar, 'A3400930000001B'), '3400930000001');
      expect(lu(BarcodeFormat.codabar, '123456'), '123456');
      expect(lu(BarcodeFormat.itf, '03400930000001'), '03400930000001');
      expect(lu(BarcodeFormat.code93, 'CIP3400930'), 'CIP3400930');
    });

    test('caractères de contrôle et espaces retirés ; séparateur GS (FNC1) conservé', () {
      expect(lu(BarcodeFormat.code128, '\u00003400930000001\r\n'), '3400930000001');
      expect(lu(BarcodeFormat.itf, ' 12345678 \t'), '12345678');
      expect(lu(BarcodeFormat.code128, '0103400930000001\u001d10LOT'), '0103400930000001\u001d10LOT');
      expect(lu(BarcodeFormat.ean13, '\u00073400930000001'), '3400930000001');
    });

    test('code linéaire lu → même recherche que la douchette (candidats)', () {
      // ITF-14 commençant par 0 → EAN-13 → CIP7, comme un code tapé par la douchette.
      expect(CodeScan.candidats(lu(BarcodeFormat.itf, '03400935955838')!), ['03400935955838', '3400935955838', '3595583']);
      expect(CodeScan.candidats(lu(BarcodeFormat.upcE, '01234565')!), contains('0012345000065'));
    });
  });
}
