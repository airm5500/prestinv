# Versions publiées sur le magasin Sunmi — Prestige Inventaire (V3 depuis 5.0.0)

Ce fichier est **lu par le test** `test/non_regression/version_sunmi_test.dart` : la ligne `minimum_sunmi:`
ci-dessous est la dernière version publiée sur le magasin Sunmi. Garder son format exact
(`minimum_sunmi: X.Y.Z+N`).

minimum_sunmi: 4.8.5+4

## Dernières versions publiées sur Sunmi

| Version | versionCode | Date de publication | Remarque |
|---|---|---|---|
| 4.8.5 | 4 | à compléter | dernière version publiée connue |

Version en préparation (pas encore publiée) : **5.0.3+25** (`pubspec.yaml`) : une réponse qui n'est pas celle du
serveur Prestige (page HTML d'un portail captif, d'un relais ou d'une box, texte, JSON d'un autre service, redirection
vers une page de connexion) n'est plus jamais prise pour un envoi réussi : la saisie reste en attente sur le terminal
(« serveur injoignable »), renvoyée seule, sans doublon (voir `docs/NOTE_VERSION_5.0.3.md`).

Avant : **5.0.2+24** : titre « Prestige Inventaire v3 » sur une
seule ligne aux écrans de lancement et de connexion (nom du lanceur inchangé) ; serveur éteint ou en erreur (5xx)
pendant l'inventaire : saisies gardées en attente sur le terminal, envoyées seules au retour du serveur, bandeau « N
saisies en attente d'envoi (serveur injoignable) » (voir `docs/NOTE_VERSION_5.0.2.md`).

Avant : **5.0.1+23** : icônes du lanceur sans cadre, comme
les anciennes (PNG transparents, plus d'icône adaptative ni ronde), version de l'APK lue directement dans
`pubspec.yaml` par Gradle (build depuis Android Studio) et APK nommé `PrestigeInventaireV3-release-<version>.apk` (voir
`docs/NOTE_VERSION_5.0.1.md`).

Avant : **5.0.0+22** : **Prestige Inventaire V3**, NOUVELLE
application (`com.dici.prestigeinventaire.v3`, « Prestige Inventaire V3 », icône avec le badge « V3 »), même
fonctionnement que la 4.16.3+21 (voir `docs/NOTE_VERSION_5.0.0.md`). Elle est publiée sur une **nouvelle fiche** du
magasin Sunmi : aucune version n'y a encore été publiée, la première sera 5.0.0+22 (au-dessus de 4.8.5 / 4 et de la
livraison de test précédente 4.16.3+21 : les règles ci-dessous restent appliquées).

L'**ancienne fiche** (`com.dici.prestinv`, « Prestige Inventaire ») garde la version déjà en ligne : rien n'y est
republié. Pour information : dernier commit construit avec l'ancien identifiant
`3e46c1ed7857e1b43fe7b87fff5e1cd0ccb9ec15` (4.16.3+21).

**Google Play (4.16.0)** : le même numéro sert à Google Play (piste « Test interne », `docs/android/README.md`). Le
`+N` doit rester plus grand que celui de **chaque** canal (Sunmi et Play). L'APK Sunmi, construit sur le PC du
pharmacien, garde sa signature (clé debug locale) et l'API cible de Flutter ; seul l'App Bundle Play est en API 36. Images du magasin : `docs/store_sunmi/`.

## Les 3 règles (permanentes)

1. **Une seule source : `pubspec.yaml`** (`version: X.Y.Z+N`). Gradle la reprend
   (5.0.1 : lue directement dans `pubspec.yaml` par `android/app/build.gradle.kts`, `versionPubspec`, même depuis
   Android Studio sans commande flutter ; `flutter.versionCode` / `flutter.versionName` en repli seulement),
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
