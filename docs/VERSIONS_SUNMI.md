# Versions publiées sur le magasin Sunmi — Prestige Inventaire

Ce fichier est **lu par le test** `test/non_regression/version_sunmi_test.dart` : la ligne `minimum_sunmi:`
ci-dessous est la dernière version publiée sur le magasin Sunmi. Garder son format exact
(`minimum_sunmi: X.Y.Z+N`).

minimum_sunmi: 4.8.5+4

## Dernières versions publiées sur Sunmi

| Version | versionCode | Date de publication | Remarque |
|---|---|---|---|
| 4.8.5 | 4 | à compléter | dernière version publiée connue |

Version en préparation (pas encore publiée) : **4.15.3+17** (`pubspec.yaml`), au-dessus de 4.8.5 / 4
(4.15.3 > 4.8.5 nombre par nombre : 15 > 8 ; 17 > 4) et de la livraison de test précédente 4.15.2+16. Images du magasin : `docs/store_sunmi/`.

## Les 3 règles (permanentes)

1. **Une seule source : `pubspec.yaml`** (`version: X.Y.Z+N`). Gradle la reprend
   (`versionCode = flutter.versionCode`, `versionName = flutter.versionName` dans `android/app/build.gradle.kts`),
   **aucun numéro en dur** (ni dans Gradle, ni dans le code : l'application lit sa version à l'exécution avec
   `package_info_plus`, voir `lib/version_app.dart`).
2. **X.Y.Z jamais inférieur** (comparaison nombre par nombre : 4.13.0 > 4.8.5) à la dernière version publiée
   sur Sunmi ; **+N strictement supérieur** au versionCode publié (sinon le magasin refuse la mise à jour).
3. **Chaque livraison augmente +N d'au moins 1** (même pour un APK de test remis à une pharmacie).

## Marche à suivre à chaque publication sur Sunmi

1. Avant de construire : augmenter `version:` dans `pubspec.yaml` (au moins +1 sur N ; X.Y.Z selon les nouveautés).
2. Construire l'APK (`flutter build apk --release`, ou télécharger l'artefact de la CI : `prestigeinv-release-X.Y.Z.apk`)
   et vérifier la version affichée en bas de l'écran de connexion et dans les Réglages / la Configuration
   (« Version X.Y.Z+N »), dans les deux interfaces.
3. Après la publication sur le magasin Sunmi : **mettre à jour ce fichier** — ajouter la ligne en haut du tableau
   (version, versionCode, date) et remplacer `minimum_sunmi:` par la version publiée.
4. Lancer `flutter test test/non_regression/version_sunmi_test.dart` : il échoue si `pubspec.yaml` n'est pas
   au-dessus de `minimum_sunmi`, si N n'est pas strictement supérieur, si le format `X.Y.Z+N` manque ou si Gradle
   contient un `versionCode` / `versionName` en dur. La livraison suivante devra donc d'abord augmenter N.
