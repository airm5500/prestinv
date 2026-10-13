# Prestige Inventaire 4.10.0 — Note de version « Scan et collecte »

*Pour le pharmacien et l'équipe qui compte. Deux nouveautés : la douchette ne perd plus aucun scan
(et le terminal bipe), et la **collecte hors ligne peut enfin être versée dans un inventaire**, qu'on
peut créer depuis le terminal.*

Version : **4.10.0** (code 6). Elle s'installe par-dessus la 4.9.0 ou la 4.8.5 sans désinstaller.
Rien n'est perdu : réglages, saisies en attente et collecte en cours sont repris tels quels.

Aperçus réels (360 dp, Sunmi V2s) : `docs/maquettes/apercus/app_scan_*.png` et
`app_versement_*.png` (rendus sans les couleurs de l'application, qui restent celles d'aujourd'hui).

---

## 1. Ce qui change pour vous

### La douchette est toujours prête
- **Saisie guidée** : après **OK**, le terminal est immédiatement prêt à scanner. Avant, un scan fait
  juste après OK était **perdu** (le curseur allait dans la case Quantité, qui l'ignorait).
- Le champ « Rechercher / Scanner » garde la main **après OK, après une fenêtre, après une erreur**.
  Le clavier Android ne s'ouvre plus tout seul : il ne cache plus le pavé numérique. Pour chercher un
  produit **par son nom**, touchez l'icône **clavier** à droite du champ.
- **Scans en rafale** : si vous scannez plusieurs boîtes très vite (ou pendant que la fenêtre de
  quantité est ouverte), les codes **attendent leur tour** et s'ouvrent l'un après l'autre, dans
  l'ordre. Le compteur « N scan(s) à traiter » s'affiche en saisie rapide. **Aucun n'est perdu.**
- **Boutons de scan sur les côtés** des Sunmi : reconnus (ils remettent le champ de scan en place).
- **Clavier physique** (terminal à touches, clavier Bluetooth) : chiffres, **Retour arrière**,
  **Entrée = OK**, **Échap = Annuler** dans la fenêtre de quantité ; en saisie guidée, chiffres puis
  Entrée valident le produit et passent au suivant.

### Les codes lus comme dans l'application de vente
- Même lecture que Prestige Vente : **DataMatrix** des boîtes (avec ou sans séparateur), **EAN-13
  34009…** (le produit est retrouvé par son **CIP7**), GTIN-14, UPC-A, espaces parasites.
- **Code inconnu** : message clair « **Code lu : 3401597413 — introuvable dans cet inventaire** »,
  **bip long**, et on continue avec la boîte suivante. Le code reste dans le journal « à vérifier ».
- Serveur injoignable pendant la recherche : le code reste dans le journal ; **touchez-le** pour
  relancer la recherche quand le réseau revient.

### Bips et vibrations
| Ce qui se passe | Son | Vibration |
|---|---|---|
| Produit trouvé | bip court | brève |
| Produit **déjà compté** | **double bip** | deux brèves |
| Code introuvable, erreur réseau, quantité refusée | **bip long** | longue |

Le double bip s'accompagne du bandeau « **Déjà compté : 6** » dans la fenêtre de quantité. La question
**Remplacer / Ajouter** (« Additionner ? ») reste celle d'aujourd'hui : elle n'apparaît que si le
réglage **Cumul** est activé (sinon votre saisie **remplace**, comme avant).

Dans **Configuration → Scan (douchette)** : couper le **son** et/ou la **vibration**, et trois boutons
d'**essai**.

### Saisie rapide : le journal des dernières saisies
- L'écran de saisie rapide montre les **10 dernières saisies** : produit, quantité, et **état d'envoi**
  (**en attente** / **envoi…** / **envoyé** / **erreur** avec la raison), plus les codes **à vérifier**.
- **Corriger la dernière** : bouton en haut du journal (ou touchez n'importe quelle ligne) ; la
  nouvelle quantité **remplace** l'ancienne (une seule ligne, renvoyée au serveur).

### Quantité rapide
- Après un scan, la fenêtre propose **1** (réglable dans Configuration → « Quantité proposée après
  un scan » ; vide = aucune). **OK** valide 1 ; **le premier chiffre tapé remplace** la proposition
  (taper 7 donne 7, pas 17).
- Boutons **−1 / +1** ; quantités de **0 à 99 999** ; au-delà du seuil « grande quantité » (1 000 par
  défaut), confirmation, comme en saisie guidée.

### Créer un inventaire depuis le terminal
- Liste des inventaires → icône **Nouvel inventaire** (en haut à droite).
- **Libellé** obligatoire (3 à 100 caractères ; lettres, chiffres, espaces et ponctuation simple —
  pas de < > " ; \ etc.) et **type** : Emplacement (par défaut), Famille ou Grossiste.
- Une **confirmation** est demandée. **Ce que fait le serveur** (vérifié) : il crée l'inventaire avec
  **TOUS les produits actifs de l'officine**, chacun avec son **stock théorique**, **rien de compté**.
  On ne peut pas créer un inventaire vide par cette route. Le type ne change que le classement dans
  Prestige. Compter une minute pour une grosse officine.
- **Pas de doublon** : un double appui ne crée qu'un inventaire ; un libellé déjà porté par un
  inventaire **ouvert** est refusé (on vous propose d'utiliser celui-là) ; si le réseau coupe pendant
  la création, l'application relit la liste avant toute nouvelle tentative.
- L'inventaire créé apparaît **en tête de la liste** (« Nouveau — créé depuis ce terminal ») et
  s'ouvre comme les autres.

### Verser la collecte hors ligne dans un inventaire
Avant, la **Collecte libre** ne pouvait que s'exporter en CSV/PDF. Maintenant :
1. Collecte → icône **Verser dans un inventaire** (flèche vers le haut).
2. Choisir un **inventaire ouvert** (ou **Nouvel inventaire…**).
3. Choisir **une fois pour toutes** ce qu'on fait si un produit est **déjà compté** dans cet
   inventaire : **Remplacer** (la quantité collectée remplace) ou **Ajouter** (elle s'ajoute).
   Proposé par défaut : Remplacer, ou Ajouter si le réglage Cumul est activé.
4. **Barre de progression**. **Arrêter (sans rien perdre)** : ce qui est envoyé reste envoyé, le
   reste se **reprend** plus tard (bandeau orange « Versement interrompu… Reprendre » dans la Collecte).
5. **Rapport** : versés, déjà comptés **remplacés / ajoutés**, **codes non reconnus** (code, quantité,
   raison), erreurs. Boutons **PDF**, **CSV** et **Partager** (WhatsApp, e-mail…). Les rapports restent
   consultables (icône « Rapports de versement » de la Collecte).

Ce qui est garanti :
- Chaque code est cherché dans l'inventaire : CIP, **EAN-13**, EAN fabricant, code article grossiste,
  34009 → CIP7, DataMatrix. Une correspondance **seulement partielle** (début de CIP) est **refusée**
  (« non reconnu ») : jamais de devinette. Deux codes du même produit (CIP et EAN) sont **regroupés**.
- Le serveur reçoit toujours la **quantité totale**. Elle est **calculée une seule fois** : une
  reprise après coupure ou un double appui sur « Reprendre » **ne double jamais** une quantité, même
  en mode Ajouter.
- Les quantités passent par la **mémoire des saisies** (« À envoyer ») : une panne réseau ne perd
  rien, l'envoi repart tout seul.
- Le serveur enregistre **qui** a versé (route « avec auteur »).
- Une ligne de la collecte n'est marquée **« ✓ versé le … dans … »** qu'**après confirmation du
  serveur**. Les codes non reconnus et les erreurs **restent à verser**. Quand tout est versé :
  bandeau vert « Collecte entièrement versée ». Un nouveau scan d'un code déjà versé crée une nouvelle
  ligne (on ne reverse jamais deux fois la même).

---

## 2. Comment tester sur chaque modèle

**Réglage de la douchette Sunmi à vérifier d'abord** (Paramètres Android → **Scanner** / « Lecteur de
codes ») : sortie **« Simulation de saisie clavier »** (ou « Keyboard input ») et suffixe **Entrée**
(« Enter »/« Retour chariot »). Le mode « Remplissage direct » fonctionne aussi sur l'écran de scan,
mais la saisie clavier est la plus sûre (indispensable pendant que la fenêtre de quantité est ouverte).

Prévoir un **inventaire de test** (ou en créer un : voir test 7) et quelques boîtes, dont une boîte
**inconnue** de l'inventaire et une boîte avec **DataMatrix**.

| # | Test | Résultat attendu | V2s | V3H | V3 | V3 Mix | Téléphone |
|---|---|---|---|---|---|---|---|
| 1 | Saisie guidée : taper 5, OK, **scanner aussitôt** une boîte du rayon | la fenêtre de la boîte scannée s'ouvre | ☐ | ☐ | ☐ | ☐ | ☐ (douchette BT) |
| 2 | Saisie rapide : scanner **6 boîtes à la suite**, très vite | 6 fenêtres l'une après l'autre, dans l'ordre ; 6 lignes au journal | ☐ | ☐ | ☐ | ☐ | ☐ |
| 3 | Pendant une fenêtre ouverte, scanner 2 autres boîtes | la quantité en cours ne bouge pas ; les 2 boîtes suivent | ☐ | ☐ | ☐ | ☐ | ☐ |
| 4 | **Bouton latéral** de scan, puis scanner | lecture normale, champ de scan actif | ☐ | ☐ | ☐ | ☐ | — |
| 5 | Boîte inconnue ; boîte déjà comptée ; boîte normale | bip long + message ; double bip + « Déjà compté » ; bip court | ☐ | ☐ | ☐ | ☐ | ☐ |
| 6 | DataMatrix d'une boîte ; EAN 34009… d'un produit connu par son CIP7 | le bon produit s'ouvre | ☐ | ☐ | ☐ | ☐ | ☐ |
| 7 | Liste des inventaires → Nouvel inventaire « Test terminal » → Créer ; puis recréer le même | créé (en tête, s'ouvre) ; 2ᵉ fois : « libellé déjà utilisé », rien de créé | ☐ | | | | |
| 8 | Collecte : 3 codes (1 inconnu) → Verser → inventaire de test → Remplacer | rapport : 2 versés, 1 non reconnu ; quantités visibles sur le poste Prestige | ☐ | | | | |
| 9 | Verser 10 codes, **couper le Wi-Fi** au milieu, rallumer, **Reprendre** | aucune quantité doublée sur le poste ; rapport complet | ☐ | | | | |
| 10 | Configuration → couper le son → scanner un code inconnu | pas de bip, vibration seule | ☐ | ☐ | ☐ | ☐ | ☐ |
| 11 | Écran 360 dp (V2s) et tablette | rien de coupé, pas de bande jaune/noire | ☐ | | | | ☐ (tablette) |

Particularités par modèle :
- **V2s** (écran 5,99", 360 dp de large) : les écrans ont été vérifiés à 360 × 640.
- **V3 / V3H / V3 Mix** : boutons de scan latéraux reconnus (codes Android 520 à 523 selon le modèle ;
  285 à 288 sur certaines versions du système ; F1 à F4 si la touche est réglée en « touche
  personnalisée »). Si un bouton ne réagit pas, vérifier dans Paramètres → Scanner que la touche
  déclenche bien la lecture.
- **Téléphones** : douchette Bluetooth en mode clavier (HID) ; sans douchette, la saisie manuelle et la
  recherche par nom (icône clavier) fonctionnent comme avant.

**Après les tests** : supprimer l'inventaire de test sur le poste Prestige et remettre les quantités
modifiées des produits de test.

---

## 3. Ce qui ne change pas

- Le réglage **Remplacer / Ajouter** (Cumul) et la question « Déjà compté — Additionner ? » sont
  **inchangés** ; mode d'envoi **Direct par défaut pour les nouvelles installations** (réglage existant
  conservé sinon).
- Les saisies guidées / rapides / écarts / restants continuent d'utiliser la route d'envoi habituelle
  (sans auteur) : seul le **versement de la collecte** utilise la route qui enregistre l'auteur.
  Généraliser cette route est prévu à l'**étape serveur**.
- Apparence générale : inchangée (refonte visuelle = étape suivante).
- Export CSV de la collecte : même format qu'avant (Code;Quantite;Date).

## 4. Limites connues
- La création n'existe qu'**avec tous les produits** (la route ne sait pas créer un inventaire vide
  ou limité à certains rayons sans les identifiants du poste) ; pour un inventaire partiel, le créer
  sur le poste Prestige.
- Le contrôle « inventaire clôturé » pendant un versement est fait par l'application (le serveur ne le
  refuse pas lui-même) — comme pour les autres saisies, en attendant l'étape serveur.
- « Déjà compté » est lu une fois au début du versement : si un collègue compte le même produit
  pendant le versement en mode Ajouter, sa saisie peut être écrasée (même limite que le Cumul actuel).
