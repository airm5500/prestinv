# Prestige Inventaire 4.14 — Note de version

*Pour le pharmacien et l'équipe qui compte.*

# 4.14.1 (code 12) — Retours de test du pharmacien

Elle s'installe par-dessus la 4.14.0 sans désinstaller ; rien n'est perdu (réglages, saisies en attente,
collecte, rapports).

## 1. Saisie guidée : bouton d'envoi plus discret

En envoi manuel, l'icône d'envoi à droite du nuage n'est plus un **carré orange** : c'est une **icône
seule** (avion en papier « envoyer »), **orange**, sans fond ni contour, comme le nuage voisin. La
**pastille rouge** indique toujours le nombre de saisies non envoyées ; la zone à toucher reste de
**48 × 48 dp** ; le toucher envoie comme avant.

## 2. « Créer un inventaire » depuis la collecte : un seul emplacement

**Problème constaté** : un produit scanné en collecte, puis « Créer un inventaire avec ces produits » →
l'inventaire contenait **tous les emplacements** de l'officine.

**Cause** : l'application demandait la création au serveur (`POST /inventaire/creation`) avec le libellé
et le type seulement, **sans préciser d'emplacement** ; dans ce cas le serveur met tous les produits
actifs de l'officine.

**Correction** : depuis la collecte (bouton « Créer un inventaire avec ces produits », ou « Nouvel
inventaire… » de l'écran de versement), l'écran de création ne propose plus le type mais
l'**emplacement** :

- l'application recherche l'emplacement des produits collectés et **présélectionne le plus fréquent**
  (« ANTIBIOTIQUES — 2 produit(s) de la collecte ») ;
- les autres emplacements trouvés sont proposés juste en dessous (un toucher pour changer) ;
  **« Autre emplacement… »** ouvre la liste de tous les emplacements de l'officine, avec recherche ;
- le bandeau rappelle ce qui sera créé (« Seulement « ANTIBIOTIQUES » ») et combien de produits de la
  collecte sont rangés ailleurs (ils seront signalés « non reconnus » au versement, comme avant) ;
- le serveur ne reçoit que **cet emplacement** : l'inventaire contient ses produits actifs, puis la
  collecte y est versée et le rapport s'affiche ;
- sans emplacement choisi (produits introuvables, serveur injoignable), « Créer l'inventaire » reste
  grisé : message clair et **Réessayer** ; session expirée → « Se reconnecter ».

La création depuis l'accueil est **inchangée** (tous les produits actifs, type au choix).

**Limite actuelle du serveur** : il ne sait pas encore créer un inventaire limité à une **liste de
produits** ; l'inventaire contient donc tout l'emplacement choisi. La demande est décrite pour l'équipe
serveur (`docs/DEMANDE_SERVEUR_COMPTAGE.md`, section H) ; l'application l'utilisera dès qu'elle existera.

## 3. Scan par l'appareil photo : plus de formats de codes-barres

Un « simple code-barre » (étiquette interne, certains fournisseurs) n'était pas lu alors que l'EAN
l'était. Formats lus désormais : **EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, Code 93, ITF
(2 parmi 5 entrelacé), Codabar, DataMatrix, QR**.

Le code lu est remis en forme avant la recherche (puis suit le même chemin que la douchette) :
UPC-A et **UPC-E → EAN-13** ; astérisques de début et de fin du Code 39 et lettres de début et de fin
(A à D) du Codabar retirées ; caractères de contrôle et espaces retirés (le séparateur des DataMatrix
GS1 est conservé). L'aperçu affiche un conseil : **« Approchez le code, bien éclairé »** (avec la place
de la lampe torche quand le téléphone en a une).

## Tests ajoutés (4.14.1)

- `test/integration/creation_collecte_test.dart` (vrai HTTP) : paramètres reçus par le serveur —
  création classique sans `valeurs`, création depuis la collecte avec `valeurs = [emplacement]` ;
  emplacement d'un produit, liste des emplacements, regroupement et présélection, 40 codes au plus ;
  session expirée, 500, coupure, refus lisible.
- `test/nv_retours_4_14_1_test.dart` : icône d'envoi sans fond ni contour (48 dp, pastille) ;
  présélection, changement d'emplacement (trouvé ou « Autre emplacement… » avec recherche), création
  impossible sans emplacement, panne puis Réessayer, création classique inchangée.
- `test/e2e/parcours_4_13_test.dart` : collecte → création → un seul emplacement reçu par le serveur.
- `test/unitaires/scan_camera_test.dart` : formats, UPC-E → EAN-13 (quatre règles, clé), délimiteurs,
  caractères de contrôle, mêmes candidats que la douchette ; `test/scan_camera_test.dart` : conseil affiché.
- Ergonomie : « Création d'inventaire depuis la collecte » ajoutée au catalogue (4 appareils × 2 échelles
  × 3 tailles).

---

# 4.14.0 (code 11)

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
