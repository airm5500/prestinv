// Outils d'essai de la douchette : frappe « matérielle » (comme la douchette Sunmi en émulation de
// clavier : caractères très rapides puis Entrée), touches latérales de scan, retour sonore enregistré.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/scan/retour_scan.dart';

LogicalKeyboardKey _touche(String ch) {
  if (RegExp(r'^\d$').hasMatch(ch)) return LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + int.parse(ch));
  final c = ch.toLowerCase();
  if (RegExp(r'^[a-z]$').hasMatch(c)) return LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + c.codeUnitAt(0) - 97);
  // Séparateur GS, ponctuation… : touche quelconque portant le caractère.
  return LogicalKeyboardKey.keyG;
}

/// Tape [texte] au clavier matériel (sans pomper entre les touches : rafale de douchette) puis Entrée.
Future<void> douchette(WidgetTester tester, String texte, {bool entree = true}) async {
  for (final ch in texte.split('')) {
    final k = _touche(ch);
    await tester.sendKeyDownEvent(k, character: ch);
    await tester.sendKeyUpEvent(k);
  }
  if (entree) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  }
}

/// Appui sur une touche latérale de scan Sunmi (code Android) : événement tel que le moteur Android le
/// produit pour une touche hors de sa table (touche logique = plan Android + code).
Future<bool> toucheSunmi(WidgetTester tester, int codeAndroid) async {
  final logique = ToucheScan.depuisCodeAndroid(codeAndroid);
  final physique = PhysicalKeyboardKey(LogicalKeyboardKey.androidPlane | codeAndroid);
  final traite = HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(physicalKey: physique, logicalKey: logique, timeStamp: Duration.zero));
  HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(physicalKey: physique, logicalKey: logique, timeStamp: Duration.zero));
  await tester.pump();
  return traite;
}

/// Touche simple (Entrée, Retour arrière, Échap…).
Future<void> touche(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyDownEvent(k);
  await tester.sendKeyUpEvent(k);
}

/// Retour sonore / vibration enregistrés au lieu d'être joués.
class FauxLecteurRetour implements LecteurRetour {
  final List<String> bips = [];
  final List<String> vibrations = [];

  @override
  Future<void> bip(TypeRetour type) async => bips.add(type.name);

  @override
  Future<void> vibrer(TypeRetour type) async => vibrations.add(type.name);
}

FauxLecteurRetour installerFauxRetour() {
  final f = FauxLecteurRetour();
  RetourScan.lecteur = f;
  return f;
}

/// Nœud du champ de scan de l'écran (pour vérifier qu'il garde le focus).
FocusNode noeudChampScan(WidgetTester tester) {
  final champ = tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('champ-scan')), matching: find.byType(TextField)));
  return champ.focusNode!;
}

/// Le champ de scan de l'écran a-t-il le focus ?
bool champScanAFocus(WidgetTester tester) => noeudChampScan(tester).hasFocus;

/// Remet la douchette à zéro entre deux essais.
void reinitialiserDouchette() => Douchette.instance.reinitialiser();
