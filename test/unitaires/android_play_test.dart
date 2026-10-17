// Google Play (4.16.0) — projet Android et envoi, sans SDK Android :
//  - signature : clé d'envoi lue dans les variables d'environnement puis android/key.properties (jamais commité) ;
//    repli sur la clé DEBUG avec un avertissement quand elle manque (APK Sunmi construits sur le PC du pharmacien et
//    APK de la CI : même signature qu'avant) ;
//  - API cible : 36 pour le build Google Play SEULEMENT (propriété prestinvTargetSdk passée par play.yml) ; APK
//    locaux et ci.yml : valeur de Flutter, comme avant (comportements d'Android 16 inchangés) ;
//  - permissions : stockage limité à Android 12, appareil photo facultatif ;
//  - workflow play.yml : conventions communes aux 4 applications (noms des secrets, android/DEMANDE_PLAY), aucun
//    secret affiché, action d'envoi épinglée par SHA, piste « internal », repli « draft », nettoyage ;
//  - l'APK de ci.yml reste produit comme avant (et ci.yml contrôle le build Play API 36 sans clé).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String lire(String chemin) => File(chemin).readAsStringSync();

void main() {
  final gradle = lire('android/app/build.gradle.kts');

  group('Signature', () {
    test('clé d\'envoi : variables d\'environnement, puis key.properties ; quatre réglages', () {
      for (final (env, prop) in [
        ('ANDROID_KEYSTORE_PATH', 'storeFile'),
        ('ANDROID_KEYSTORE_PASSWORD', 'storePassword'),
        ('ANDROID_KEY_ALIAS', 'keyAlias'),
        ('ANDROID_KEY_PASSWORD', 'keyPassword'),
      ]) {
        expect(gradle, contains('reglageCle("$env", "$prop")'));
      }
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('System.getenv(variable)'), reason: 'la CI passe avant le fichier local');
    });

    test('repli sur la clé DEBUG si la clé manque ou si le fichier n\'existe pas, avec avertissement', () {
      expect(gradle, contains('fichierCle != null && fichierCle.exists()'));
      expect(gradle, contains('if (cleEnvoiComplete) {\n                signingConfigs.getByName("release")'));
      expect(gradle, contains('signingConfigs.getByName("debug")'));
      expect(gradle, contains('logger.warn('));
      expect(gradle, isNot(contains(RegExp(r'storePassword\s*=\s*"'))), reason: 'aucun mot de passe en clair');
    });

    test('key.properties et fichiers de clé jamais commités', () {
      final ignore = lire('android/.gitignore');
      expect(ignore, contains('key.properties'));
      expect(ignore, contains('**/*.jks'));
      expect(ignore, contains('**/*.keystore'));
      expect(File('android/key.properties').existsSync(), isFalse);
    });
  });

  group('API cible', () {
    test('36 pour Google Play seulement (propriété prestinvTargetSdk) ; sinon la valeur de Flutter, comme avant', () {
      expect(gradle, contains('findProperty("prestinvTargetSdk")'));
      expect(gradle, contains('targetSdk = apiCiblePlay ?: flutter.targetSdkVersion'));
      expect(gradle, contains('compileSdk = apiCiblePlay ?: flutter.compileSdkVersion'));
      expect(gradle, isNot(contains('targetSdk = 36')), reason: 'APK Sunmi : comportements d\'Android 16 inchangés');
      expect(gradle, contains('applicationId = "com.dici.prestinv"'));
      expect(gradle, contains('versionCode = flutter.versionCode'));
      expect(lire('android/gradle.properties'), contains('android.suppressUnsupportedCompileSdk=36'));
    });

    test('play.yml construit en 36 et le contrôle ; ci.yml : APK pas en 36, App Bundle 36 de contrôle sans clé', () {
      final play = lire('.github/workflows/play.yml');
      expect(play, contains('flutter build appbundle --release --android-project-arg=prestinvTargetSdk=36'));
      expect(play, contains('android:targetSdkVersion="36"'));
      final ci = lire('.github/workflows/ci.yml');
      expect(ci, contains('flutter build apk --release'));
      expect(ci, contains('API cible de l\'APK (inchangée, pas 36)'));
      expect(ci, contains('flutter build appbundle --release --android-project-arg=prestinvTargetSdk=36'));
    });
  });

  group('Manifeste', () {
    final manifeste = lire('android/app/src/main/AndroidManifest.xml');

    test('permissions : Internet, vibration, appareil photo ; stockage seulement jusqu\'à Android 12', () {
      final permissions = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"([^>]*)>').allMatches(manifeste).toList();
      expect(permissions.map((m) => m.group(1)).toSet(), {
        'android.permission.INTERNET',
        'android.permission.VIBRATE',
        'android.permission.CAMERA',
        'android.permission.WRITE_EXTERNAL_STORAGE',
        'android.permission.READ_EXTERNAL_STORAGE',
      });
      for (final m in permissions.where((m) => m.group(1)!.contains('EXTERNAL_STORAGE'))) {
        expect(m.group(2), contains('android:maxSdkVersion="32"'));
      }
    });

    test('appareil photo facultatif (installable sans), nom affiché, HTTP vers le serveur local', () {
      expect(manifeste, contains('<uses-feature android:name="android.hardware.camera" android:required="false" />'));
      expect(manifeste, contains('android:label="Prestige Inventaire"'));
      expect(manifeste, contains('android:networkSecurityConfig="@xml/network_security_config"'));
      expect(manifeste, isNot(contains('screenOrientation')), reason: 'aucune orientation imposée (ignorée sur grand écran en Android 16)');
    });
  });

  group('Workflow Google Play', () {
    final play = lire('.github/workflows/play.yml');

    test('conventions communes aux 4 applications : secrets et fichier déclencheur ; branche claude/refonte', () {
      for (final s in ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD', 'PLAY_SERVICE_ACCOUNT_JSON']) {
        expect(play, contains('secrets.$s'));
      }
      expect(play, contains('android/DEMANDE_PLAY'));
      expect(play, contains('PACKAGE_NAME: com.dici.prestinv'));
      expect(play, contains("- 'claude/refonte'"));
      expect(File('android/DEMANDE_PLAY').existsSync(), isFalse, reason: 'écrit seulement sur demande du pharmacien');
    });

    test('envoi : action épinglée par SHA, piste internal, completed puis draft, artefact AAB, nettoyage', () {
      expect(RegExp(r'uses: r0adkll/upload-google-play@[0-9a-f]{40}').allMatches(play), hasLength(2));
      expect(play, contains('tracks: internal'));
      expect(play, contains('status: completed'));
      expect(play, contains('status: draft'));
      expect(play, contains('name: prestige-inventaire-aab'));
      expect(play, contains('CN=Android Debug'), reason: 'un bundle signé en debug est refusé avant l\'envoi');
      expect(play, contains('rm -rf "\$RUNNER_TEMP/cle_android"'));
      expect(play, contains('umask 077'));
      expect(play, isNot(contains(RegExp(r'echo "\$(KS|KSP|KP|SA|ANDROID_KEYSTORE_PASSWORD|ANDROID_KEY_PASSWORD)"'))), reason: 'aucun secret affiché');
      expect(play, isNot(contains('prestige_app')));
    });

    test('l\'APK de ci.yml reste produit comme avant', () {
      final ci = lire('.github/workflows/ci.yml');
      expect(ci, contains('flutter build apk --release'));
      expect(ci, contains('name: prestinv-apk'));
    });
  });
}
