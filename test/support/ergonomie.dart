// Outils des tests d'ERGONOMIE et de COHÉRENCE D'AFFICHAGE : profils d'appareils réels (taille en
// pixels physiques + densité), échelles de texte, relevé des débordements / exceptions de rendu,
// règles d'accessibilité Flutter (cibles tactiles ≥ 48 dp, contraste du texte), clavier système
// simulé (viewInsets). Pas d'images de référence (« goldens ») : uniquement des règles mesurables.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Appareil cible : taille physique (px) et densité (px par dp).
class Appareil {
  final String nom;
  final Size pixels;
  final double densite;
  const Appareil(this.nom, this.pixels, this.densite);

  /// Taille en dp (ce que voit la mise en page).
  Size get dp => Size(pixels.width / densite, pixels.height / densite);

  @override
  String toString() => '$nom (${pixels.width.toInt()}×${pixels.height.toInt()} px, ×$densite = ${dp.width.round()}×${dp.height.round()} dp)';
}

/// Parc à couvrir. Densités réalistes : V2s 720×1440 en xhdpi (×2), V3 / V3H / V3mix 1080×1920 en
/// xxhdpi (×3), téléphone d'entrée de gamme 360×640 dp, tablette 1920×1200 en hdpi (×1,5).
const appareils = <Appareil>[
  Appareil('Sunmi V2s', Size(720, 1440), 2.0),
  Appareil('Sunmi V3 / V3H / V3mix', Size(1080, 1920), 3.0),
  Appareil('Téléphone 360×640 dp', Size(720, 1280), 2.0),
  Appareil('Tablette', Size(1920, 1200), 1.5),
];

/// Échelles de texte (réglage « Taille de police » d'Android).
const echellesTexte = <double>[1.0, 1.3];

/// Place la vue de test dans la configuration [a] / [echelle].
/// La vue est remise par défaut à la fin du test, même en cas d'échec (sinon un clavier simulé ou une
/// échelle de texte « fuiraient » dans les tests suivants).
void configurer(WidgetTester tester, Appareil a, double echelle) {
  addTearDown(() => reinitialiserVue(tester));
  tester.view.physicalSize = a.pixels;
  tester.view.devicePixelRatio = a.densite;
  tester.platformDispatcher.textScaleFactorTestValue = echelle;
}

/// Remet la vue par défaut.
void reinitialiserVue(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.view.resetViewInsets();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

/// Exécute [action] en relevant toute erreur de rendu (débordement « RenderFlex overflowed »,
/// contrainte impossible, exception dans build/layout/paint) au lieu de s'arrêter à la première.
Future<List<String>> releverErreursRendu(WidgetTester tester, Future<void> Function() action) async {
  final erreurs = <String>[];
  final precedent = FlutterError.onError;
  FlutterError.onError = (d) => erreurs.add(d.exceptionAsString().split('\n').first);
  try {
    await action();
  } finally {
    FlutterError.onError = precedent;
  }
  final e = tester.takeException();
  if (e != null) erreurs.add('$e'.split('\n').first);
  return erreurs;
}

const ciblesTactiles = 'cibles tactiles ≥ 48 dp (androidTapTargetGuideline)';
const contraste = 'contraste du texte (textContrastGuideline)';

/// Règles d'accessibilité vérifiées sur chaque écran.
final reglesAccessibilite = <String, AccessibilityGuideline>{
  ciblesTactiles: androidTapTargetGuideline,
  contraste: textContrastGuideline,
};

/// Évalue les règles d'accessibilité ; renvoie les manquements (vide = conforme).
Future<List<String>> manquementsAccessibilite(WidgetTester tester, {Set<String> ignorer = const {}}) async {
  final manquements = <String>[];
  for (final e in reglesAccessibilite.entries) {
    if (ignorer.contains(e.key)) continue;
    final r = await e.value.evaluate(tester);
    if (!r.passed) manquements.add('${e.key} : ${r.reason?.trim()}');
  }
  return manquements;
}

/// Clavier système simulé : réserve [fraction] de la hauteur en bas de l'écran.
void ouvrirClavier(WidgetTester tester, {double fraction = 0.42}) {
  tester.view.viewInsets = FakeViewPadding(bottom: tester.view.physicalSize.height * fraction);
}

/// Le widget [f] est-il entièrement visible au-dessus du clavier simulé ?
String? horsDeVueSousClavier(WidgetTester tester, Finder f, {String quoi = 'champ'}) {
  if (f.evaluate().isEmpty) return '$quoi introuvable';
  final r = tester.getRect(f.first);
  final hauteurVisible = (tester.view.physicalSize.height - tester.view.viewInsets.bottom) / tester.view.devicePixelRatio;
  if (r.top < 0 || r.bottom > hauteurVisible + 0.5) {
    return '$quoi caché par le clavier : de ${r.top.toStringAsFixed(0)} à ${r.bottom.toStringAsFixed(0)} dp, zone visible 0–${hauteurVisible.toStringAsFixed(0)} dp';
  }
  return null;
}

/// Journal lisible d'un ensemble de constats (pour les messages d'échec).
String constats(List<String> l) => l.map((e) => '  - $e').join('\n');
