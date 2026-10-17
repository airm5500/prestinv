# Prestige Inventaire 4.16.0 (code 18) — Google Play, piste « Test interne »

*Pour le pharmacien et l'équipe qui compte.*

Elle s'installe par-dessus la 4.15.3 sans désinstaller ; rien n'est perdu. **Aucun écran ne change.**

## Ce qui change

Prestige Inventaire peut être diffusé par **Google Play, piste « Test interne »** (équivalent de TestFlight : jusqu'à
100 testeurs choisis, sans examen de Google). Mode d'emploi complet : **`docs/android/README.md`** (même guide que
pour Prestige Pharmacien : mêmes secrets GitHub, même clé d'envoi possible pour les quatre applications, même fichier
de demande `android/DEMANDE_PLAY`). Identifiant Android : **`com.dici.prestinv`** (inchangé).

### Signature

- Jusqu'ici, la version « release » était signée avec la clé **debug** : Google Play refuse ce type de paquet.
- Nouvelle configuration : **clé d'envoi** lue dans les variables d'environnement (CI : secrets GitHub) puis dans
  `android/key.properties` (poste de travail ; jamais commité).
- **Sans clé : clé debug, comme avant**, avec un avertissement dans le journal. **Les APK des terminaux Sunmi,
  construits sur votre PC, ne changent pas de signature** : les mises à jour par-dessus restent possibles.

### API cible 36 (Android 16) : pour Google Play SEULEMENT

Google Play exige l'API cible 36 depuis le 31/08/2026 (Flutter 3.32.8 propose 35). Étude d'impact pour Inventaire :

| Changement lié à l'API 36 (sur un appareil **Android 16** seulement) | Impact pour Inventaire |
|---|---|
| Orientation et redimensionnement imposés ignorés sur les grands écrans (≥ 600 dp) | aucune orientation imposée dans l'application : rien |
| Affichage « bord à bord » obligatoire (option de retrait supprimée) | déjà imposé par Android 15 avec l'API 35 actuelle, et l'application n'utilise pas l'option de retrait : rien de nouveau |
| Geste « retour » prédictif par défaut | **risque** : la saisie guidée, le versement et la création retiennent le retour pour ne rien perdre (confirmation de sortie) ; à éprouver sur un vrai téléphone Android 16 |
| Touches du terminal (douchette Sunmi, touche latérale) | inchangées (les terminaux Sunmi ne sont pas sous Android 16) |

Ces changements ne s'appliquent qu'aux appareils **sous Android 16** : les terminaux Sunmi actuels n'en sont pas. Par
précaution, l'API 36 n'est appliquée **qu'au build Google Play** (`play.yml`, propriété Gradle `prestinvTargetSdk=36`).
Les **APK construits sur votre PC** et par la CI gardent l'API cible de Flutter (35) : comportement **identique** à
aujourd'hui sur tout appareil, et **aucune plateforme « Android 16 » à installer** sur le PC. Les testeurs Google Play
essaient, eux, la version API 36 : signalez tout comportement du bouton « retour » qui vous surprendrait.

### Autres exigences de Google Play

- **Permissions** : stockage **limité à Android 12** (`maxSdkVersion="32"`). À partir d'Android 13 ces autorisations
  n'étaient déjà plus accordées : l'export CSV / PDF écrit directement dans Téléchargements, comme avant. Appareil
  photo : facultatif (installable sans).
- **Réseau** : connexion HTTP au serveur de l'officine par adresse IP, inchangée, acceptée par Google Play.

### CI et envoi

- `.github/workflows/play.yml` (nouveau) : à chaque envoi de code sur `claude/refonte`, si les quatre secrets de la
  clé existent, contrôle de leur forme sans rien afficher, **App Bundle signé** en API 36, contrôlé (pas de clé debug,
  API 36), publié en artefact **`prestige-inventaire-aab`**. **Envoi en Test interne** seulement quand
  `android/DEMANDE_PLAY` est modifié (1re ligne = version de `pubspec.yaml`) et que `PLAY_SERVICE_ACCOUNT_JSON`
  existe ; application encore en brouillon côté Play → envoi en brouillon avec un message clair.
- **Le premier App Bundle doit être envoyé à la main** dans la Play Console (exigence de Google) : guide, étape 6.
- `ci.yml` : l'APK est produit comme avant ; nouveaux contrôles : l'APK n'est **pas** en API 36, et l'App Bundle
  API 36 est construit **sans clé** à chaque envoi (contrôle seulement, jamais publié) pour voir tout de suite une
  incompatibilité.

### Attention : Play et APK installés à la main

Une version installée depuis Play est signée par Google : elle ne peut pas être mise à jour par un APK du PC, ni
l'inverse. Sur un appareil, choisir l'une ou l'autre source ; pour passer à Play : désinstaller, installer depuis
Play, ressaisir l'adresse du serveur et les réglages. Les terminaux Sunmi restent sur l'APK du PC.

## Tests

`test/unitaires/android_play_test.dart` (signature, API cible Play seulement, permissions, workflow) ; toutes les
catégories rejouées (unitaires, intégration, bout en bout, ergonomie, performance, réseau).
