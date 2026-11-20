# Prestige Inventaire V3 5.0.1+23 : icônes sans cadre, comme les anciennes ; version lue dans pubspec.yaml

Retour du pharmacien (photo du lanceur d'un terminal Sunmi) après la 5.0.0+22. Même application
(`com.dici.prestigeinventaire.v3`, « Prestige Inventaire V3 »), même fonctionnement que la 5.0.0+22 : **seules
l'icône du lanceur, la lecture de la version par Gradle et le nom du fichier APK changent**.

## 1. Icônes sans cadre, comme les anciennes

En 5.0.0, l'icône était une **icône adaptative** (Android 8 et plus) : fond blanc et dessin réduit dans la zone de
sécurité. Sur le lanceur Sunmi, le carton « V3 » apparaissait donc **plus petit, dans un carré blanc arrondi**.
L'ancienne Prestige Inventaire (4.16.3, commit 3e46c1e) n'avait que des **PNG transparents** : le dessin directement
sur le fond d'écran, grand, sans cadre. Le pharmacien préfère l'ancienne présentation.

5.0.1 : **icônes sans cadre, comme les anciennes.**

- Plus d'icône adaptative : `android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml` et
  `launcher_icon_round.xml` retirés, ainsi que le fond blanc (`values/couleurs_prestigeinventaire.xml`) et les
  `launcher_icon_foreground.png`.
- Plus d'icône ronde : `android:roundIcon` retiré du manifeste (l'ancienne application n'en avait pas),
  `launcher_icon_round.png` retirés.
- `mipmap-{m,h,xh,xxh,xxxh}dpi/launcher_icon.png` (48, 72, 96, 144, 192 px) : **fond transparent**, dessin (carton,
  liste, loupe et badge bleu « V3 ») **pleine toile, centré**, à la taille des anciennes icônes : 0,91 × 0,98 de la
  toile (ancienne : 0,89 × 1,00 ; même moyenne, 0,94). Coins transparents, bords sans liseré blanc (couleur des
  pixels semi-transparents reprise du dessin voisin), badge « V3 » lisible dès 48 px (mdpi).
- Rien d'autre ne change : écran de démarrage, logo des écrans (`assets/images/icon.png`) et icônes du magasin.

Aperçu (anciennes, 5.0.0 et 5.0.1 sur fond sombre et orange) : `apercu_lanceur.png` (captures du magasin V3).

Sur un lanceur Android récent qui impose une forme à toutes les icônes (Pixel, par exemple), une icône sans version
adaptative est montrée réduite dans un cercle blanc : c'était déjà le cas de l'ancienne Prestige Inventaire. Le
lanceur Sunmi montre l'icône telle quelle.

## 2. Version de l'APK lue directement dans pubspec.yaml (build depuis Android Studio)

Un APK construit dans **Android Studio**, sans commande `flutter` avant, peut sortir avec une version périmée : Gradle
prenait `flutter.versionName` / `flutter.versionCode` dans `android/local.properties`, réécrit seulement par une
commande `flutter` (pub get, build). Le défaut a été constaté sur Prestige Mobile (APK 4.10.0+36 au lieu de 5.0.0+49).

5.0.1 : `android/app/build.gradle.kts` lit la version **directement dans `pubspec.yaml`** (`version: X.Y.Z+N` →
versionName X.Y.Z, versionCode N), quel que soit l'outil qui lance le build. Les valeurs de Flutter ne servent plus
qu'en repli (pubspec.yaml absent ou sans `version: X.Y.Z+N`). Toujours aucun numéro en dur.

**Nom du fichier APK** : `PrestigeInventaireV3-release-5.0.1.apk` (avant : `prestigeinv-release-…`), dans
`build/app/outputs/apk/release/`. La commande `flutter build apk` copie toujours aussi l'APK sous
`build/app/outputs/flutter-apk/app-release.apk`.

## 3. Contrôles

- `test/non_regression/v3_identite_test.dart` : plus de `mipmap-anydpi-v26` ni de fond adaptatif, plus de
  `roundIcon` ni de `launcher_icon_round` / `launcher_icon_foreground` ; chaque `launcher_icon.png` : taille exacte,
  coins transparents, cadre du dessin proche de celui de l'ancienne icône, badge « V3 » présent (bleu, en haut à
  droite), aucun liseré blanc.
- `test/non_regression/version_gradle_test.dart` : l'expression de `build.gradle.kts` appliquée à `pubspec.yaml`
  donne la version de l'APK ; repli sur Flutter ; nom du fichier APK.
- `test/non_regression/version_sunmi_test.dart` : Gradle reprend pubspec.yaml (lecture directe, repli Flutter), aucun
  numéro en dur.
- CI (`ci.yml`) : badging de l'APK (identifiant, nom, version) et icône de l'application = PNG (jamais un XML
  adaptatif) ; fichier `PrestigeInventaireV3-release-<version>.apk` produit.

Version **5.0.1+23** (`pubspec.yaml`) ; voir `docs/VERSIONS_SUNMI.md`.
