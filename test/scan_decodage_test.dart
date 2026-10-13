// Décodage des codes scannés : mêmes règles que prestige_vente_app (product_lookup.codeCandidates) —
// DataMatrix GS1 avec ou sans séparateur GS, EAN-13 34009 → CIP7, GTIN-14 → EAN-13, UPC-A → EAN-13,
// espaces et caractères parasites. Code introuvable : « Code lu : X — introuvable dans cet inventaire »,
// bip long, et la saisie continue avec le code suivant.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/scan/code_scan.dart';

void main() {
  group('CodeScan.candidats (règles de prestige_vente_app)', () {
    test('EAN-13 34009 → CIP7 essayé ensuite', () {
      expect(CodeScan.candidats('3400935955838'), ['3400935955838', '3595583']);
    });

    test('GTIN-14 commençant par 0 → EAN-13 → CIP7', () {
      expect(CodeScan.candidats('03400935955838'), ['03400935955838', '3400935955838', '3595583']);
    });

    test('UPC-A (12 chiffres) → EAN-13 avec 0 devant', () {
      expect(CodeScan.candidats('123456789012'), ['123456789012', '0123456789012']);
    });

    test('DataMatrix GS1 AVEC séparateur GS : GTIN → EAN-13 → CIP7 en premier', () {
      final c = CodeScan.candidats('0103400935955838\u001d17281002\u001d10LOT1');
      expect(c.first, '3400935955838');
      expect(c, contains('3595583'));
    });

    test('DataMatrix GS1 SANS séparateur (01 + 17 + 10) : GTIN reconnu', () {
      final c = CodeScan.candidats('010340093595583817281031101234AB');
      expect(c.take(2), ['3400935955838', '3595583']);
    });

    test('DataMatrix avec préfixe de symbologie ]d2 et GS rendu visible « ␝ »', () {
      expect(CodeScan.candidats(']d20103400935955838␝10LOT1').first, '3400935955838');
    });

    test('espaces et caractères parasites (retour chariot, tabulation) retirés', () {
      expect(CodeScan.candidats('  3400935955838\r\n'), ['3400935955838', '3595583']);
      expect(CodeScan.candidats('3400 9359 55838\t'), ['3400935955838', '3595583']);
      expect(CodeScan.nettoyer('\u0002ABC\u0003'), 'ABC');
    });

    test('CIP7 et EAN-13 local : essayés tels quels', () {
      expect(CodeScan.candidats('8050457'), ['8050457']);
      expect(CodeScan.candidats('3000000258453'), ['3000000258453']);
    });

    test('texte : gardé (recherche par nom)', () {
      expect(CodeScan.candidats('DOLIPRANE'), ['DOLIPRANE']);
      expect(CodeScan.ressembleACode('DOLIPRANE'), isFalse);
      expect(CodeScan.ressembleACode('8050457'), isTrue);
      expect(CodeScan.ressembleACode('1000'), isFalse);
      expect(CodeScan.candidats('   '), isEmpty);
    });

    test('message introuvable', () {
      expect(CodeScan.messageIntrouvable('3401597413'), 'Code lu : 3401597413 — introuvable dans cet inventaire');
      expect(CodeScan.messageIntrouvable('01034\u001d10A'), 'Code lu : 01034␝10A — introuvable dans cet inventaire');
    });
  });
}
