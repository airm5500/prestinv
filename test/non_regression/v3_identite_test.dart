// NON-RÉGRESSION — Prestige Inventaire V3 (5.0.0) : NOUVELLE application Android, seule l'identité change.
//  - Gradle : applicationId com.dici.prestigeinventaire.v3, namespace INCHANGÉ (MainActivity, R) ; version 5.0.0+22
//    lue dans pubspec.yaml.
//  - Manifeste : nom « Prestige Inventaire V3 », icône et icône ronde ; visibilité de l'ANCIENNE application
//    (com.dici.prestinv) seulement, jamais QUERY_ALL_PACKAGES ; canal natif : présence seulement.
//  - Icônes : héritées, rondes et adaptatives (fond blanc, avant-plan contenu dans la zone de sécurité de 66 dp : le
//    badge « V3 » n'est coupé par aucun masque), toutes les densités ; écran de démarrage et logo : image V3.
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

    test('applicationId com.dici.prestigeinventaire.v3 ; namespace inchangé ; version 5.0.0+22', () {
      expect(gradle, contains('applicationId = "com.dici.prestigeinventaire.v3"'));
      expect(gradle, contains('namespace = "com.dici.prestinv"'));
      expect(RegExp(r'^\s*applicationId\s*=\s*"com\.dici\.prestinv"', multiLine: true).hasMatch(gradle), isFalse,
          reason: 'ancien identifiant : plus construit (fiche Sunmi gardée telle quelle)');
      expect(gradle, isNot(contains('applicationIdSuffix')));
      expect(File('android/app/src/main/kotlin/com/dici/prestinv/MainActivity.kt').existsSync(), isTrue);
      expect(RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(_lire('pubspec.yaml'))!.group(1), '5.0.0+22');
    });

    test('manifeste : nom « Prestige Inventaire V3 », icônes, visibilité de l\'ancienne application seulement', () {
      final m = _lire('android/app/src/main/AndroidManifest.xml');
      expect(m, contains('android:label="Prestige Inventaire V3"'));
      expect(m, contains('android:icon="@mipmap/launcher_icon"'));
      expect(m, contains('android:roundIcon="@mipmap/launcher_icon_round"'));
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

    test('icône adaptative : fond blanc, avant-plan, versions ronde et carrée', () {
      for (final n in ['launcher_icon', 'launcher_icon_round']) {
        final x = _lire('$res/mipmap-anydpi-v26/$n.xml');
        expect(x, contains('<background android:drawable="@color/launcher_icon_background" />'));
        expect(x, contains('<foreground android:drawable="@mipmap/launcher_icon_foreground" />'));
      }
      expect(_lire('$res/values/couleurs_prestigeinventaire.xml'), contains('<color name="launcher_icon_background">#FFFFFF</color>'));
    });

    for (final e in _densites.entries) {
      testWidgets('${e.key} : icônes héritées ${(48 * e.value).round()} px, avant-plan ${(108 * e.value).round()} px dans la zone de sécurité',
          (tester) async {
        for (final n in ['launcher_icon', 'launcher_icon_round']) {
          final (w, h, _) = await _png(tester, '$res/mipmap-${e.key}/$n.png');
          expect([w, h], [(48 * e.value).round(), (48 * e.value).round()], reason: n);
        }
        final (px, hauteur, rgba) = await _png(tester, '$res/mipmap-${e.key}/launcher_icon_foreground.png');
        expect(px, (108 * e.value).round());
        expect(hauteur, px);
        final rayonSur = 33 * e.value;
        var hors = 0, visibles = 0;
        for (var y = 0; y < px; y++) {
          for (var x = 0; x < px; x++) {
            if (rgba[(y * px + x) * 4 + 3] <= 8) continue;
            visibles++;
            if (math.sqrt(math.pow(x + 0.5 - px / 2, 2) + math.pow(y + 0.5 - px / 2, 2)) > rayonSur) hors++;
          }
        }
        expect(visibles, greaterThan(px * px ~/ 8), reason: 'avant-plan non vide');
        expect(hors, 0, reason: 'pixels visibles hors de la zone de sécurité : le masque couperait le badge');
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
