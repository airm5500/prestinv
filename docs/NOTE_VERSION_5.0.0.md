# Prestige Inventaire V3 5.0.0+22 : nouvelle application (nouvel identifiant, nouveau nom, nouvelle icône)

Décision du pharmacien (20/11/2026). **Prestige Inventaire V3 est une NOUVELLE application Android**, publiée sur une
**nouvelle fiche** du magasin Sunmi (et, le moment venu, une nouvelle application dans la Play Console). Elle
s'installe **à côté** de l'ancienne « Prestige Inventaire » : les deux cohabitent sur le même terminal jusqu'à ce que
toutes les officines soient passées à la V3.

Seule l'identité change. **Le fonctionnement est identique à la 4.16.3+21** (mêmes écrans, mêmes règles, mêmes
échanges avec le serveur, mêmes permissions).

| | Ancienne application | Prestige Inventaire V3 |
|---|---|---|
| Identifiant Android (applicationId) | `com.dici.prestinv` | **`com.dici.prestigeinventaire.v3`** |
| Nom sous l'icône | Prestige Inventaire | **Prestige Inventaire V3** |
| Icône | carton et liste (ancienne) | carton, liste, loupe et badge bleu **« V3 »** (icône adaptative, fond blanc) |
| Version | dernière version déjà en ligne sur sa fiche | **5.0.0+22** |
| Fiche Sunmi | **gardée telle quelle** (voir ci-dessous) | nouvelle fiche |

## 1. L'ancienne fiche Sunmi reste telle qu'elle est

Certaines officines ont encore d'anciens serveurs Prestige. La fiche de l'ancienne Prestige Inventaire
(`com.dici.prestinv`) sur le magasin Sunmi **garde la version déjà en ligne** : rien n'y est republié. Les terminaux
de ces officines continuent avec l'ancienne application, sans changement.

Pour information seulement (aucune nouvelle publication de l'ancienne fiche n'est prévue) : dernier commit construit
avec l'ancien identifiant `com.dici.prestinv` : **`3e46c1ed7857e1b43fe7b87fff5e1cd0ccb9ec15`** (Prestige Inventaire
4.16.3+21, branche `claude/refonte`).

## 2. Passer un terminal à la V3

Android donne à chaque application **son propre espace de données**. La V3 **ne peut rien lire** de l'ancienne
application (c'est la règle d'Android). Au premier lancement, la V3 est donc **vide**, comme une installation neuve :

1. **Avant tout : envoyer les saisies hors ligne de l'ancienne application.** Ouvrir l'ancienne Prestige Inventaire,
   serveur joignable, et vérifier que plus rien n'attend : saisies « à envoyer » (bandeau d'envoi : « Tout est
   envoyé ») et **Collecte hors ligne** versée (« Aucun produit scanné »). **Une saisie restée dans l'ancienne
   application n'est pas reprise par la V3** ; si l'ancienne application est désinstallée avant, ces saisies sont
   perdues.
2. Installer Prestige Inventaire V3 depuis sa nouvelle fiche Sunmi (l'ancienne reste installée).
3. **Reconfigurer** la V3 sur chaque terminal (chaque appareil est à reconfigurer), comme une première installation :
   - au premier lancement, l'adresse par défaut (192.168.1.50) est souvent injoignable : « Configuration », code
     administrateur (le code par défaut 1234 doit être changé à la première utilisation), adresse locale / distante,
     port, contexte ;
   - réglages propres au terminal : mode d'envoi, cumul, stock théorique, scan (sons, vibration, appareil photo),
     taille de l'écran, interface (nouvelle par défaut), etc. ;
   - connexion de chaque utilisateur (« Rester connecté » : à refaire).
4. Quand tout va bien et que l'ancienne application n'a plus rien à envoyer, la désinstaller si l'officine n'en a plus
   besoin.

**Bandeau de la V3.** Si l'ancienne application est encore installée sur le terminal, l'écran de connexion de la V3
(nouvelle et ancienne interface) affiche une fois : « Ancienne application installée : envoyez ses saisies hors ligne
avant de la désinstaller. » (bouton « Compris » : plus jamais affiché sur ce terminal). Pour l'Inventaire, le texte
parle de « saisies » (et non de « ventes », mot de Prestige Mobile). La V3 sait seulement que l'ancienne application
est installée (visibilité du paquet `com.dici.prestinv` déclarée dans `<queries>`) : elle ne lit aucune de ses données
et ne l'ouvre jamais.

## 3. Ce qui change dans le projet

- `android/app/build.gradle.kts` : `applicationId = "com.dici.prestigeinventaire.v3"`. Le `namespace` reste
  `com.dici.prestinv` (paquet Kotlin de `MainActivity`, classe `R`). Les canaux natifs (`prestinv/retour`,
  `prestinv/appareil`) ne dépendent pas de l'identifiant. Aucun FileProvider, aucun lien profond, aucune configuration
  Firebase / google-services, aucune chaîne de notification ni WorkManager. Signature : inchangée (clé debug pour les
  APK Sunmi, clé d'envoi pour Google Play).
- `android/app/src/main/AndroidManifest.xml` : `android:label="Prestige Inventaire V3"`, `android:roundIcon`,
  `<package android:name="com.dici.prestinv" />` dans `<queries>`. `MainActivity.kt` : méthode
  `ancienneAppliInstallee` du canal `prestinv/appareil` (présence seulement).
- Icônes : `mipmap-*/launcher_icon.png`, `launcher_icon_round.png` (icône héritée), `launcher_icon_foreground.png`
  (avant-plan adaptatif dans la zone de sécurité de 66 dp : aucun masque ne coupe le badge « V3 »),
  `mipmap-anydpi-v26/*.xml`, fond blanc (`values/couleurs_prestigeinventaire.xml`) ; anciens `ic_launcher.png`
  inutilisés retirés. Écran de démarrage (`drawable-*/splash.png`, fond bleu nuit inchangé) et logo des écrans
  (`assets/images/icon.png`) : image V3.
- Nom affiché : constante `nomAppli` (`lib/identite_appli.dart`) : lancement, connexion (deux interfaces), licence,
  accueil, inventaire, menu latéral de la tablette, serveur injoignable, titre de la tâche Android, messages de
  l'appareil photo.

## 4. CI et Google Play

- `ci.yml` : badging de l'APK contrôlé (`com.dici.prestigeinventaire.v3`, « Prestige Inventaire V3 », version de
  `pubspec.yaml`, activité `com.dici.prestinv.MainActivity`).
- `play.yml` : `PACKAGE_NAME: com.dici.prestigeinventaire.v3`. L'AAB est toujours construit si la clé d'envoi existe ;
  l'envoi reste gardé (secrets + `android/DEMANDE_PLAY`). **Une nouvelle application Google Play exige un premier envoi
  À LA MAIN** de l'AAB dans la Play Console (`docs/android/README.md`, encadré « Prestige Inventaire V3 »).

## 5. Tests

- `test/non_regression/v3_identite_test.dart` : identifiant, namespace, nom, icônes (tailles, zone de sécurité de
  l'avant-plan à chaque densité), écran de démarrage et logo, visibilité de l'ancienne application, canal natif, CI,
  Play, note.
- `test/e2e/v3_premier_lancement_test.dart` : installation neuve sans aucune donnée → adresse par défaut injoignable →
  Configuration → code par défaut et changement obligatoire → adresse du serveur → connexion « Prestige Inventaire V3 »
  → accueil, requêtes vers la nouvelle adresse ; bandeau de l'ancienne application (deux interfaces : affiché,
  « Compris », plus jamais ; absent sans elle ou si la détection échoue).
- Tests mis à jour (nom et identifiant attendus) : `unitaires/android_play_test`, `helpers/version_installee.dart`.
- Captures de magasin (hors CI) : `test_apercus/store_v3_test.dart`.
