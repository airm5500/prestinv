// NON-RÉGRESSION — Prestige Inventaire V3 (5.0.0) : NOUVELLE application Android, seule l'identité change.
//  - Gradle : applicationId com.dici.prestigeinventaire.v3, namespace INCHANGÉ (MainActivity, R) ; version 5.0.2+24
//    lue dans pubspec.yaml.
//  - Manifeste : nom « Prestige Inventaire V3 », icône (5.0.1 : plus d'icône ronde) ; visibilité de l'ANCIENNE application
//    (com.dici.prestinv) seulement, jamais QUERY_ALL_PACKAGES ; canal natif : présence seulement.
//  - Icônes (5.0.1) : SANS cadre, comme l'ancienne : PNG transparents seulement (ni adaptative, ni ronde), dessin
//    pleine toile à l'encombrement de l'ancienne icône, badge « V3 », aucun liseré blanc ; écran de démarrage et
//    logo : image V3.
//  - Nom affiché : constante nomAppli, plus de « Prestige Inventaire » en dur dans les écrans.
//  - CI et Google Play : badging de l'APK (identifiant, nom, version), PACKAGE_NAME ; note de version.
// L'APK lui-même est contrôlé par la CI (ci.yml, aapt2 dump badging) : aucun SDK Android ici.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/identite_appli.dart';

String _lire(String p) => File(p).readAsStringSync();

const _densites = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

/// Ancienne icône (Prestige Inventaire 4.16.3, commit 3e46c1e, PNG transparent sans cadre) : moyenne largeur / hauteur
/// du cadre du dessin (alpha > 8), rapportée à la toile, par densité (0,89 × 1,00 environ).
const _ancienneMoyenne = {'mdpi': 0.958, 'hdpi': 0.944, 'xhdpi': 0.948, 'xxhdpi': 0.944, 'xxxhdpi': 0.943};

/// Image PNG décodée par le moteur : largeur, hauteur, pixels RGBA.
Future<(int, int, Uint8List)> _png(WidgetTester tester, String chemin) async {
  return (await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(File(chemin).readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    final octets = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    return (image.width, image.height, octets);
  }))!;
}

void main() {
  group('Identité Android', () {
    final gradle = _lire('android/app/build.gradle.kts');

    test('applicationId com.dici.prestigeinventaire.v3 ; namespace inchangé ; version 5.0.2+24', () {
      expect(gradle, contains('applicationId = "com.dici.prestigeinventaire.v3"'));
      expect(gradle, contains('namespace = "com.dici.prestinv"'));
      expect(RegExp(r'^\s*applicationId\s*=\s*"com\.dici\.prestinv"', multiLine: true).hasMatch(gradle), isFalse,
          reason: 'ancien identifiant : plus construit (fiche Sunmi gardée telle quelle)');
      expect(gradle, isNot(contains('applicationIdSuffix')));
      expect(File('android/app/src/main/kotlin/com/dici/prestinv/MainActivity.kt').existsSync(), isTrue);
      expect(RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(_lire('pubspec.yaml'))!.group(1), '5.0.2+24');
    });

    test('manifeste : nom « Prestige Inventaire V3 », icône sans icône ronde, visibilité de l\'ancienne application seulement', () {
      final m = _lire('android/app/src/main/AndroidManifest.xml');
      expect(m, contains('android:label="Prestige Inventaire V3"'));
      expect(m, contains('android:icon="@mipmap/launcher_icon"'));
      expect(m, isNot(contains('android:roundIcon')), reason: '5.0.1 : comme l\'ancienne application');
      expect(m, contains('<package android:name="com.dici.prestinv" />'));
      expect(m, isNot(contains('QUERY_ALL_PACKAGES')));
    });

    test('canal natif : présence de l\'ancienne application seulement (jamais ouverte)', () {
      final k = _lire('android/app/src/main/kotlin/com/dici/prestinv/MainActivity.kt');
      expect(k, contains('"ancienneAppliInstallee" -> result.success(packageManager.getLaunchIntentForPackage("com.dici.prestinv") != null)'));
      expect(k, isNot(contains('startActivity')));
      expect(AncienneAppli.paquet, 'com.dici.prestinv');
    });
  });

  group('Icônes (Prestige Inventaire V3)', () {
    const res = 'android/app/src/main/res';

    test('5.0.1 : SANS cadre, comme l\'ancienne icône : ni icône adaptative ni fond blanc ni icône ronde', () {
      final anydpi = Directory('$res/mipmap-anydpi-v26');
      expect(anydpi.existsSync() && anydpi.listSync().isNotEmpty, isFalse,
          reason: 'icône adaptative = dessin réduit dans un carré blanc sur le lanceur Sunmi');
      for (final d in Directory(res).listSync().whereType<Directory>()) {
        for (final f in d.listSync().whereType<File>()) {
          final nom = f.uri.pathSegments.last;
          expect(nom.startsWith('launcher_icon') && nom.endsWith('.xml'), isFalse, reason: f.path);
          expect(nom, isNot(anyOf('launcher_icon_round.png', 'launcher_icon_foreground.png')), reason: f.path);
        }
      }
      expect(File('$res/values/couleurs_prestigeinventaire.xml').existsSync(), isFalse, reason: 'fond blanc de l\'icône adaptative');
      final m = _lire('android/app/src/main/AndroidManifest.xml');
      expect(m, contains('android:icon="@mipmap/launcher_icon"'));
      expect(m, isNot(contains('roundIcon')), reason: 'l\'ancienne application n\'avait pas d\'icône ronde');
    });

    for (final e in _densites.entries) {
      final px = (48 * e.value).round();
      testWidgets('${e.key} : launcher_icon.png $px px transparent, dessin pleine toile comme l\'ancienne icône, badge « V3 »',
          (tester) async {
        final (w, h, rgba) = await _png(tester, '$res/mipmap-${e.key}/launcher_icon.png');
        expect([w, h], [px, px]);
        int alpha(int x, int y) => rgba[(y * px + x) * 4 + 3];
        // Coins transparents (aucun fond, aucun cadre).
        for (final (x, y) in [(0, 0), (px - 1, 0), (0, px - 1), (px - 1, px - 1), (1, 1), (px - 2, px - 2)]) {
          expect(alpha(x, y), 0, reason: 'coin ($x, $y)');
        }
        // Cadre du dessin (alpha > 8) : même encombrement que l'ancienne icône de la même densité (4.16.3, 3e46c1e).
        var x0 = px, y0 = px, x1 = -1, y1 = -1;
        var badge = 0, texteBadge = 0, liseres = 0;
        for (var y = 0; y < px; y++) {
          for (var x = 0; x < px; x++) {
            final o = (y * px + x) * 4;
            final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2], a = rgba[o + 3];
            if (a > 8) {
              x0 = math.min(x0, x);
              y0 = math.min(y0, y);
              x1 = math.max(x1, x);
              y1 = math.max(y1, y);
            }
            final coinBadge = x >= px * 0.6 && y < px * 0.3;
            if (coinBadge && a > 200 && b > r + 80 && b > g + 60) badge++;
            if (coinBadge && a > 200 && math.min(r, math.min(g, b)) > 200) texteBadge++;
            // Liseré blanc : pixel semi-transparent quasi blanc hors du badge (bordé de blanc par dessin).
            if (!coinBadge && a > 0 && a < 200 && math.min(r, math.min(g, b)) > 235) liseres++;
          }
        }
        final largeur = (x1 - x0 + 1) / px, hauteur = (y1 - y0 + 1) / px;
        expect((largeur + hauteur) / 2, closeTo(_ancienneMoyenne[e.key]!, 0.03),
            reason: 'dessin ${largeur.toStringAsFixed(3)} × ${hauteur.toStringAsFixed(3)} de la toile '
                '(ancienne : ${_ancienneMoyenne[e.key]}) — 5.0.0 adaptative : environ 0,6 dans un cadre');
        expect(math.max(largeur, hauteur), greaterThan(0.9), reason: 'dessin grand, pas réduit');
        expect((x0 - (px - 1 - x1)).abs(), lessThanOrEqualTo(math.max(2, px ~/ 24)), reason: 'centré horizontalement');
        expect((y0 - (px - 1 - y1)).abs(), lessThanOrEqualTo(math.max(2, px ~/ 24)), reason: 'centré verticalement');
        expect(badge, greaterThan(px * px ~/ 60), reason: 'badge bleu « V3 » en haut à droite');
        expect(texteBadge, greaterThan(0), reason: 'texte blanc du badge (bordure et « V3 »)');
        expect(liseres, 0, reason: 'aucun liseré blanc sur les bords (fond d\'écran sombre)');
      });
    }

    testWidgets('écran de démarrage et logo de l\'application : image V3 (mêmes tailles qu\'avant)', (tester) async {
      for (final (d, px) in [('mdpi', 128), ('hdpi', 192), ('xhdpi', 256), ('xxhdpi', 384), ('xxxhdpi', 512)]) {
        final (w, h, _) = await _png(tester, '$res/drawable-$d/splash.png');
        expect([w, h], [px, px], reason: d);
      }
      final (w, _, _) = await _png(tester, 'assets/images/icon.png');
      expect(w, 512);
      // Même image : le logo et l'écran de démarrage xxxhdpi sont identiques.
      expect(File('assets/images/icon.png').readAsBytesSync(), File('$res/drawable-xxxhdpi/splash.png').readAsBytesSync());
    });
  });

  group('Nom affiché', () {
    test('nomAppli = « Prestige Inventaire V3 »', () => expect(nomAppli, 'Prestige Inventaire V3'));

    // 5.0.2 : titre des écrans de lancement / connexion « Prestige Inventaire v3 » (v minuscule, une ligne) ; le nom
    // du lanceur (android:label), l'identifiant et nomAppli ne changent pas.
    test('5.0.2 : titre de connexion « Prestige Inventaire v3 », lanceur toujours « Prestige Inventaire V3 »', () {
      expect(titreConnexion, 'Prestige Inventaire v3');
      expect(_lire('android/app/src/main/AndroidManifest.xml'), contains('android:label="Prestige Inventaire V3"'));
      for (final f in ['lib/ui/ecrans/connexion_screen.dart', 'lib/ui/ecrans/lancement_screen.dart', 'lib/screens/login_screen.dart']) {
        expect(_lire(f), contains('titreConnexion'), reason: f);
      }
      expect(_lire('lib/screens/login_screen.dart'), isNot(contains('Text(nomAppli')), reason: 'connexion d\'origine');
    });

    test('écrans : plus de « Prestige Inventaire » en dur', () {
      final trouves = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final code = f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
        if (code.contains("'Prestige Inventaire'")) trouves.add(f.path);
      }
      expect(trouves, isEmpty);
    });
  });

  group('CI, Google Play et note de version', () {
    test('ci.yml : badging de l\'APK (identifiant, nom, version de pubspec.yaml)', () {
      final ci = _lire('.github/workflows/ci.yml');
      expect(ci, contains("grep -q \"^package: name='com.dici.prestigeinventaire.v3' versionCode='\${version#*+}' versionName='\${version%+*}'\" badging-inventaire.txt"));
      expect(ci, contains("grep -q \"^application-label:'Prestige Inventaire V3'\" badging-inventaire.txt"));
      expect(ci, contains("launchable-activity: name='com.dici.prestinv.MainActivity'"));
    });

    test('play.yml : PACKAGE_NAME com.dici.prestigeinventaire.v3, envoi toujours gardé', () {
      final play = _lire('.github/workflows/play.yml');
      expect(play, contains('PACKAGE_NAME: com.dici.prestigeinventaire.v3'));
      expect(play, isNot(contains('PACKAGE_NAME: com.dici.prestinv\n')));
      expect(File('android/DEMANDE_PLAY').existsSync(), isFalse);
      expect(_lire('docs/android/README.md'), contains('com.dici.prestigeinventaire.v3'));
    });

    test('note de version 5.0.0 : nouvelle appli, ancienne fiche, reconfiguration, saisies hors ligne, dernier commit', () {
      final n = _lire('docs/NOTE_VERSION_5.0.0.md');
      for (final t in [
        'com.dici.prestigeinventaire.v3',
        'com.dici.prestinv',
        'Prestige Inventaire V3',
        'hors ligne',
        'reconfigur',
        '3e46c1ed7857e1b43fe7b87fff5e1cd0ccb9ec15',
      ]) {
        expect(n, contains(t), reason: t);
      }
      expect(_lire('docs/VERSIONS_SUNMI.md'), contains('5.0.0+22'));
    });
  });
}
