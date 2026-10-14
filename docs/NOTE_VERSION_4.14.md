# Prestige Inventaire 4.14.0 — Note de version

*Pour le pharmacien et l'équipe qui compte.*

Version : **4.14.0** (code 11). Elle s'installe par-dessus la 4.13.1 sans désinstaller. Rien n'est
perdu : réglages, saisies en attente, collecte et rapports sont repris tels quels.

## Nouveau : scan par l'appareil photo (téléphones sans douchette)

Les téléphones n'ont pas de douchette : ils peuvent maintenant lire les codes avec leur **appareil
photo**. L'option est **désactivée par défaut** : tant qu'elle n'est pas activée, **rien ne change**
(terminaux Sunmi, utilisateurs actuels, mise en page des écrans).

### Où l'activer

- **Nouvelle interface** : Réglages → rubrique **Réglages protégés** → **« Scan par l'appareil photo »**.
- **Ancienne interface** : Configuration → rubrique **Scan (douchette)** → **« Scan par l'appareil photo »**.

Comme les autres réglages sensibles, il demande le **code administrateur** et il est enregistré tout de
suite (il reste actif au prochain lancement).

### Ce que voit l'utilisateur

Quand le réglage est actif, un **bouton appareil photo** (carré de 52 dp, « Scanner avec l'appareil
photo » pour les lecteurs d'écran) apparaît **à droite du champ de scan** :

| Écran | Nouvelle interface | Ancienne interface | Aperçu |
|---|---|---|---|
| Saisie guidée | ✔ (avant le bouton de filtre) | ✔ (après le choix de l'emplacement) | se **ferme après une lecture** |
| Scan continu / saisie rapide | ✔ | ✔ | reste **ouvert**, enchaîne les lectures |
| Collecte | ✔ | ✔ | reste **ouvert**, enchaîne les lectures |

Le bouton toucher ouvre un **aperçu plein écran** : cadre de visée, bouton **lampe torche** (si le
téléphone en a une), bouton **Fermer** (en haut à gauche ; le retour d'Android ferme aussi). Codes lus :
**EAN-13, EAN-8, Code 128, DataMatrix, QR** (et UPC-A, forme sous laquelle certains téléphones lisent un
EAN-13 commençant par 0 : il est remis en EAN-13).

- **Même résultat que la douchette** : le code lu est remis à l'application **exactement par le même
  chemin que la douchette** (comme un code tapé par la douchette suivi d'Entrée) : même recherche du
  produit, mêmes contrôles (emplacement, « déjà compté », Remplacer / Ajouter, grande quantité…), même
  feuille de quantité, même **bip et vibration**, même journal (« à vérifier » pour un code inconnu).
- **Scan continu et collecte** : après une lecture, la feuille de quantité s'ouvre **par-dessus
  l'aperçu** ; après OK, l'aperçu est de nouveau prêt pour le produit suivant. Le dernier code lu est
  rappelé en bas (« Lu (3) : 3400930000001 ») et le cadre s'allume en vert à chaque lecture.
- **Anti-doublon** : l'appareil photo voit le même code plusieurs fois par seconde. Le **même code est
  ignoré pendant environ 1,5 s** après avoir été vu (y compris pendant que la feuille de quantité était
  ouverte) : pour recompter la même boîte, l'écarter un instant du cadre. Un autre code est pris tout de
  suite. (La douchette n'a pas besoin de cette règle : un appui = une lecture.)
- **Taille de l'écran** (Automatique / Compact / Très compact) : l'aperçu et le bouton la respectent ; la
  zone de quantité de la saisie guidée reste épinglée au-dessus du pavé.

### Autorisation « Caméra »

- **Premier usage** : un message explique que l'appareil photo sert uniquement à lire les codes (aucune
  photo n'est prise ni enregistrée), puis Android demande l'autorisation.
- **Refus** : message clair (« Appareil photo non autorisé… La saisie continue normalement ») ; **rien
  n'est bloqué** : douchette, pavé et recherche au clavier fonctionnent comme avant. Le bouton redemande
  l'autorisation au prochain toucher.
- **Refus définitif** (« Ne plus demander ») : le message propose **« Ouvrir les paramètres »** d'Android.
- **Téléphone sans appareil photo** : le bouton n'est pas affiché.
- L'application reste **installable sur un appareil sans appareil photo** (fonction déclarée facultative).

## Détails techniques

- Dépendance **`mobile_scanner` 6.0.2**, version figée (déjà validée dans prestige_vente_app : CameraX
  1.3, ML Kit groupé, minSdk 21, compileSdk 34) : compatible Android 11 / Sunmi, sans modifier la
  configuration Gradle. Aucune règle R8 nécessaire (seul le module de lecture de codes ML Kit est
  embarqué, pas la reconnaissance de texte qui demandait des règles dans prestige_vente_app).
- `AndroidManifest.xml` : la permission `CAMERA` et `android.hardware.camera` `required="false"` y étaient
  déjà ; ajout de `android.hardware.camera.autofocus` `required="false"` (la permission CAMERA l'implique
  sinon comme obligatoire pour les magasins d'applications).
- `MainActivity.kt` : canal `prestinv/appareil` (« y a-t-il un appareil photo ? »), sans autorisation.
- Code : `lib/scan/camera/` (réglage lu par `AppConfig.scanCamera`, bouton, aperçu, moteur
  mobile_scanner). La lecture passe par `Douchette.injecterLecture` : aucune logique de saisie dupliquée.
- iOS non concerné par cette livraison (pas de construction iOS ; à prévoir si besoin : texte
  `NSCameraUsageDescription` et iOS 15.5 minimum pour mobile_scanner 6).

## Tests ajoutés

- `test/unitaires/scan_camera_test.dart` : réglage désactivé par défaut (nouvelle installation et mise à
  jour), enregistré ; **lecture par l'appareil photo simulé ≡ lecture de la douchette** (mêmes actions
  reçues pour EAN-13, EAN-8, DataMatrix GS1, Code 128, codes courts, avec et sans quantité attendue) ;
  anti-doublon (horloge simulée) ; contenu des codes (UPC-A, séparateur GS).
- `test/scan_camera_test.dart` (widgets) : réglage désactivé → aucun bouton (deux interfaces) ; sans
  appareil photo → aucun bouton ; saisie guidée, scan continu, collecte (nouvelle interface) et saisie
  guidée, saisie rapide, collecte d'origine : **même résultat douchette / appareil photo** (saisies,
  messages, bips, vibrations) ; aperçu fermé ou gardé ouvert ; anti-doublon ; lecture ignorée sous la
  feuille ; lampe et Fermer (cibles ≥ 48 dp, libellés) ; autorisation (explication, refus, « Plus tard »,
  refus définitif → paramètres) ; appareil photo qui ne démarre pas ; réglage protégé par le code.
- `test/e2e/parcours_camera_test.dart` : application entière — Réglages (code administrateur) → scan
  continu à l'appareil photo → envoi au serveur ; saisie guidée ; ancienne interface (Configuration →
  saisie rapide → envoi direct).
- Ergonomie : 9 écrans avec bouton ou aperçu ajoutés au catalogue (`ecransAppareilPhoto`) sur les 4
  appareils × texte 1,0 / 1,3 × 3 tailles d'écran ; 5 situations de saisie de quantité avec l'appareil
  photo (`clavier_quantite_test.dart`).
- Tous les tests existants restent verts et inchangés (réglage désactivé : aucune différence).
