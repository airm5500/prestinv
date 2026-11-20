// NON-RÉGRESSION — Prestige Inventaire V3 5.0.1 : version de l'APK lue DIRECTEMENT dans pubspec.yaml par Gradle.
// Un build lancé depuis Android Studio sans commande flutter prend flutter.versionName / flutter.versionCode dans un
// android/local.properties périmé (même défaut constaté sur Prestige Mobile : APK 4.10.0+36 au lieu de 5.0.0+49).
//  - android/app/build.gradle.kts : versionPubspec = expression appliquée à ../../pubspec.yaml ; l'expression est
//    reprise ici telle qu'écrite dans Gradle et appliquée au vrai pubspec.yaml (même résultat que l'APK) ;
//  - repli sur les valeurs de Flutter seulement si pubspec.yaml est absent ou sans « version: X.Y.Z+N » ;
//  - nom du fichier APK : PrestigeInventaireV3-release-<versionName>.apk ; la CI le vérifie.
// L'APK lui-même est contrôlé par la CI (ci.yml : version de l'APK = pubspec.yaml, badging).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _lire(String p) => File(p).readAsStringSync();

/// Gradle sans commentaires de ligne (les expressions régulières de Gradle ne contiennent pas « // »).
String _sansCommentaires(String s) => s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '').replaceAll(RegExp(r'//.*'), '');

/// Expression régulière de versionPubspec, telle qu'écrite dans build.gradle.kts (chaîne brute Kotlin """…""").
RegExp _expressionGradle(String gradle) {
  final m = RegExp(r'Regex\("""(.*?)""", RegexOption\.MULTILINE\)').firstMatch(gradle);
  expect(m, isNotNull, reason: 'Regex("""…""", RegexOption.MULTILINE) introuvable dans build.gradle.kts');
  return RegExp(m!.group(1)!, multiLine: true);
}

/// Ce que Gradle met dans l'APK : pubspec.yaml s'il donne X.Y.Z+N, sinon les valeurs de Flutter (local.properties).
(String, int) _versionApk(RegExp expression, String? pubspec, Map<String, String> localProperties) {
  final m = pubspec == null ? null : expression.firstMatch(pubspec);
  if (m != null) return (m.group(1)!, int.parse(m.group(2)!));
  return (localProperties['flutter.versionName']!, int.parse(localProperties['flutter.versionCode']!));
}

void main() {
  final gradle = _lire('android/app/build.gradle.kts');
  final code = _sansCommentaires(gradle);
  final pubspec = _lire('pubspec.yaml');
  final version = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec)!.group(1)!;

  group('Version lue dans pubspec.yaml (build Android Studio sans commande flutter)', () {
    test('Gradle lit ../../pubspec.yaml (depuis android/app : le pubspec.yaml du projet)', () {
      expect(code, contains('val versionPubspec: Pair<String, Int>? = file("../../pubspec.yaml")'));
      expect(File('android/app/../../pubspec.yaml').resolveSymbolicLinksSync(), File('pubspec.yaml').resolveSymbolicLinksSync());
      expect(code.indexOf('val versionPubspec'), lessThan(code.indexOf('android {')), reason: 'lue avant defaultConfig');
    });

    test('defaultConfig : pubspec.yaml d\'abord, valeurs de Flutter en repli seulement', () {
      expect(code, contains('versionCode = versionPubspec?.second ?: flutter.versionCode'));
      expect(code, contains('versionName = versionPubspec?.first ?: flutter.versionName'));
      expect(RegExp(r'^\s*versionCode\s*=', multiLine: true).allMatches(code), hasLength(1), reason: 'defaultConfig seulement');
    });

    test('l\'expression de Gradle appliquée au vrai pubspec.yaml donne la version attendue de l\'APK', () {
      final (nom, numero) = _versionApk(_expressionGradle(gradle), pubspec, {});
      expect('$nom+$numero', version);
      expect('$nom+$numero', '5.0.2+24');
    });

    test('local.properties périmé (4.10.0+36) : ignoré, la version vient de pubspec.yaml', () {
      final perime = {'flutter.versionName': '4.10.0', 'flutter.versionCode': '36'};
      expect(_versionApk(_expressionGradle(gradle), pubspec, perime), ('5.0.2', 24));
    });

    test('repli : pubspec.yaml absent ou sans « version: X.Y.Z+N » → valeurs de Flutter', () {
      final e = _expressionGradle(gradle);
      final flutter = {'flutter.versionName': '9.9.9', 'flutter.versionCode': '99'};
      expect(_versionApk(e, null, flutter), ('9.9.9', 99));
      expect(_versionApk(e, 'name: x\nversion: 1.2.3\n', flutter), ('9.9.9', 99), reason: 'sans +N');
      expect(_versionApk(e, 'name: x\n  version: 1.2.3+4\n', flutter), ('9.9.9', 99), reason: 'clé indentée (pas la version)');
      expect(_versionApk(e, 'name: x\nversion: 1.2.3+4\nenvironment:\n', flutter), ('1.2.3', 4));
      expect(_versionApk(e, 'version: 10.20.30+400   \n', flutter), ('10.20.30', 400), reason: 'espaces en fin de ligne');
      expect(_versionApk(e, 'description: "version: 7.7.7+7"\nversion: 1.0.0+2\n', flutter), ('1.0.0', 2));
    });

  });

  group('Nom du fichier APK', () {
    test('Prestige Inventaire V3 : PrestigeInventaireV3-release-<versionName>.apk (plus « prestigeinv-release-… »)', () {
      expect(code, contains(r'outputImpl.outputFileName = "PrestigeInventaireV3-${variant.buildType.name}-${variant.versionName}.apk"'));
      expect(code, isNot(contains('"prestigeinv-')));
    });

    test('CI : fichier nommé vérifié ; icône de l\'APK = PNG (sans cadre)', () {
      final ci = _lire('.github/workflows/ci.yml');
      expect(ci, contains(r'ls build/app/outputs/apk/release/PrestigeInventaireV3-release-${version%+*}.apk'));
      expect(ci, contains(r"""grep -qE "^application: .*icon='[^']*\.png'" badging-inventaire.txt"""),
          reason: '5.0.1 : icône sans cadre (PNG), jamais l\'icône adaptative XML');
    });

    test('note de version 5.0.1', () {
      final n = _lire('docs/NOTE_VERSION_5.0.1.md');
      for (final t in ['5.0.1+23', 'icônes sans cadre, comme les anciennes', 'pubspec.yaml', 'Android Studio',
        'PrestigeInventaireV3-release-5.0.1.apk', 'local.properties']) {
        expect(n, contains(t), reason: t);
      }
      expect(_lire('docs/VERSIONS_SUNMI.md'), contains('5.0.1+23'));
    });

    test('note de version 5.0.2 (titre de connexion sur une ligne ; serveur éteint : saisies gardées)', () {
      final n = _lire('docs/NOTE_VERSION_5.0.2.md');
      for (final t in ['5.0.2+24', 'Prestige Inventaire v3', 'une seule ligne', '360 dp', 'en attente d\'envoi (serveur injoignable)',
        '500', '503', 'refusée', 'sans doublon', 'android:label']) {
        expect(n, contains(t), reason: t);
      }
      expect(_lire('docs/VERSIONS_SUNMI.md'), contains('5.0.2+24'));
    });
  });
}
