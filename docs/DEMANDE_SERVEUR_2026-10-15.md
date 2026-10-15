# Demande au serveur Prestige — application Inventaire, 15/10/2026

**De** : application Prestige Inventaire (dépôt `prestinv`, version 4.15.0+14).
**Pour** : la session du serveur (dépôt `prestige`, branche `claude/new-session-xm8ptu`).
**En réponse à** : `REPONSE_DEMANDES_MOBILES.md` du 15/10/2026 (demandes 8, 10, 20, 21, 27, 30, 37 et
« À vérifier par l'application Inventaire »).

Ce document ne remplace pas `docs/DEMANDE_SERVEUR_COMPTAGE.md` (gardé tel quel) : il ne contient que ce
qui reste à faire après la 4.15.0.

---

## 1. Ce que l'application utilise désormais (rien à faire, pour information)

| N° | Route | Utilisation dans l'application | Repli (serveur sans la route) |
|---|---|---|---|
| 10 | `user/auth` → `role`, `droits.creerInventaire` | Le droit du serveur décide qui voit « Créer un inventaire » (vrai : autorisé ; faux : refusé, quel que soit le réglage du terminal). La présence de `role` / `droits` signale un serveur à jour : les routes nouvelles ne sont essayées que sur lui (aucune requête de plus sur un ancien serveur). | Règles de la 4.13 (profil `xtypeuser`, réglage protégé, code administrateur) |
| 10 | `POST v1/inventaire/creation` → 403 `{interdit:true, msg}` | Message « Droit manquant : Créer un inventaire » (plus « session expirée ») | — |
| 20 | `lgInventaireId` dans la réponse de création | Identifiant utilisé directement (plus de relecture de la liste) | Relecture de la liste, comme avant |
| 21 | lectures `ws/inventaires*` : 500 en cas de panne | « Erreur du serveur (code 500) : … non chargés. Réessayez » — jamais une liste vide | — |
| 30 | `GET v1/ws/inventaires/{id}/rayons/etat` | Liste des emplacements d'un inventaire (seulement ceux qui ont des produits **retenus**) et état de tous les rayons en **une** requête (au lieu d'une ou deux par rayon) | `ws/inventaires/rayons` et une ou deux lectures par rayon |
| 37 | `POST v1/inventaire/{id}/versement` | Versement de la collecte par lots de 200, clé `cle` gardée sur le terminal **avant** l'envoi (réponse perdue → même clé, même contenu à la reprise) ; codes `inconnu` / `ambigu` repris produit par produit | Ancien chemin produit par produit (`POST inventaire/ligne/quantite`) |
| 8 | `PUT ws/inventaires/details` : 404, 409, 400, 403 `interdit` | Refus lisible (« Inventaire clôturé… », « Cette ligne n'existe plus… »), saisie marquée refusée (jamais renvoyée en boucle) ; 403 `interdit` : refus, pas de reconnexion | — |

**Contradiction 3 (PUT details exige une session)** : vérifié dans l'application. Depuis la 4.9, toute
quantité est écrite sur le terminal **avant** l'envoi ; un 401 la garde « en attente » et affiche « Session
expirée — reconnectez-vous » ; elle part après la reconnexion. Tests :
`test/integration/routes_recentes_test.dart` (« 401 : la saisie est GARDÉE »),
`test/integration/services_serveur_test.dart`, `test/e2e/pannes_test.dart`. Les terminaux **antérieurs à la
4.9** peuvent perdre une saisie sur un 401 : ils doivent être mis à jour (aucune correction possible côté
application installée).

---

## 2. Inventaire créé depuis une collecte : ce que fait l'application en 4.15.0

Décision du pharmacien : « si j'ai 4 produits de 4 emplacements différents ? On doit faire comme sur
Prestige : emplacement = tous, et il crée l'inventaire des 4 produits ; à l'ouverture de l'inventaire on a
juste 4 emplacements, dynamiquement uniquement ceux des 4 produits ».

Lu dans le serveur : Prestige le fait avec l'**inventaire unitaire** (`add.js` : `POST v1/inventaire/creation`
`{str_TYPE_TRANSACTION:"UNITAIRE", valeurs:[], bool_INVENTAIRE:0}` → toutes les lignes créées **non
retenues**, puis « Ajouter des articles » (`addArticle.js`) → `POST v1/inventaire/lignes/retenue`). Les
lectures `ws/inventaires/details*`, l'état des rayons, le versement en lot et la clôture ne voient que les
lignes retenues (`bool_INVENTAIRE = 1`).

L'application fait de même, en restreignant d'abord aux emplacements des produits :

1. chaque code collecté → `GET v1/produit-search/fiche?search_value=<code>` → `lg_FAMILLE_ID` et
   `lg_ZONE_GEO_ID_REEL` (CIP ou EAN-13 identique, sinon résultat unique trouvé par un autre code ; jamais
   une correspondance partielle) ;
2. `POST v1/inventaire/lignes/retenue {lg_INVENTAIRE_ID:"", ids:[]}` (essai sans effet, sauf serveur à jour)
   → la route existe ;
3. `POST v1/inventaire/creation {str_NAME, str_TYPE_TRANSACTION:"Emplacement", valeurs:[emplacements des
   produits], bool_INVENTAIRE:0}` ;
4. `POST v1/inventaire/lignes/retenue {lg_INVENTAIRE_ID, produits:[lg_FAMILLE_ID…], retenue:true}` (200 par
   requête).

Résultat : l'inventaire ne contient (pour la saisie, les écarts, la clôture) **que** les produits collectés,
et `ws/inventaires/rayons` ne renvoie **que** leurs emplacements, sur **tous** les terminaux.
Serveur sans `lignes/retenue` (404) : l'application le dit **avant** de créer et l'inventaire contient tous
les produits actifs **de ces emplacements** (jamais de toute l'officine).

---

## 3. Ce qui manque (demandes)

### A. Créer un inventaire limité à une liste de produits en UNE requête, atomique

**Constat** : la méthode ci-dessus demande 3 requêtes et n'est pas atomique : si la retenue échoue (coupure
juste après la création), l'inventaire existe **sans produit à compter** ; l'application le signale
(« Inventaire créé sans ses produits — Ajouter les produits », sans rien recréer), mais un autre terminal
peut l'ouvrir entre-temps (vide). De plus, la création insère **tous** les produits des emplacements
concernés (non retenus) : quelques milliers de lignes inutiles pour 4 produits.

**Demande** (ajout rétrocompatible, reprend `DEMANDE_SERVEUR_COMPTAGE.md` §H) : champ facultatif
**`produits`** dans `POST v1/inventaire/creation` :

```json
POST /api/v1/inventaire/creation
{"str_NAME":"Collecte du 15-10-2026 09.30","str_TYPE_TRANSACTION":"Emplacement",
 "produits":["<lg_FAMILLE_ID>","3400930000001","8050457"]}
→ {"success":1,"lignes":2,"lgInventaireId":"…","libelle":"…","inconnus":["8050457"]}
```

- `produits` non vide : l'inventaire ne contient **que** ces produits (une ligne par produit, à
  l'emplacement de stock de l'utilisateur, stock théorique repris), retenues, dans la **même transaction** ;
  chaque élément est un `lg_FAMILLE_ID` ou un code tel que scanné (CIP, EAN-13, EAN fabricant, code article
  grossiste — mêmes règles que le versement en lot, demande 37) ;
- `inconnus` : éléments non retrouvés (ou ambigus) ; tous inconnus → refus actuel, aucun inventaire ;
- `produits` absent : comportement actuel inchangé ; `valeurs` toujours possible en plus (intersection) ;
- limite : 500 produits (413 au-delà, comme le versement) ;
- droit `P_CREER_INVENTAIRE` comme aujourd'hui.

**Détection côté application** : réponse avec `inconnus` (même vide) → route prise en compte ; sinon
méthode actuelle (§2).

### B. `ws/inventaires/rayons` et `inventaire/criteres` : seulement les rayons à compter

**Constat** : `fetchRayon` (et `criteresInventaire`) groupent **toutes** les lignes, retenues ou non. Pour
un inventaire **unitaire** créé dans Prestige (toutes les lignes, quelques-unes retenues), un terminal
relié à un serveur sans `rayons/etat` affiche **tous** les emplacements de l'officine, presque tous vides.
`rayons/etat` renvoie aussi ces rayons, avec `totalProduits = 0` (l'application 4.15 les masque).

**Demande** : ajouter `AND o.boolINVENTAIRE = true` à `fetchRayon` (et `HAVING totalProduits > 0`, ou un
paramètre `aCompter=1`, à `rayons/etat`). Sans effet sur les inventaires ordinaires (toutes leurs lignes
sont retenues).

### C. `POST v1/inventaire/lignes/retenue` : droit et session

**Constat** : la route ne vérifie **aucun droit** : toute session peut retenir ou écarter des lignes de
n'importe quel inventaire ouvert (et donc changer ce qui sera clôturé). Sans session, elle répond 200
`{success:false, msg:"Veuillez vous connecter"}` au lieu de 401.

**Demande** : droit `P_CREER_INVENTAIRE` (ou celui du menu « Travaux d'inventaire ») → 403
`{interdit:true, msg}` ; inventaire clôturé → 409 `INVENTAIRE_CLOTURE` ; sans session → 401 (règle des routes
nouvelles). L'application gère déjà ces trois réponses.

### D. Versement en lot (37) : formes du code

**Constat** : la correspondance est exacte (`int_CIP`, `int_EAN13`, EAN fabricant, code article). Un EAN-13
français `34009 + CIP7 + clé` d'un produit enregistré sous son CIP7, un GTIN-14 (`0` + EAN-13) ou un
DataMatrix complet reviennent `inconnu` ; l'application les reprend alors produit par produit (aucune perte,
mais une requête par code).

**Demande** (facultative) : essayer aussi, dans l'ordre, l'EAN-13 tiré d'un GTIN-14 et le CIP7 tiré d'un
EAN-13 `34009…` (comme `CodeScan.candidats` de l'application) avant de répondre `inconnu`.

### E. Demande 27 : lecture de l'auteur

Toujours attendue : `auteurId`, `auteurLogin`, `auteurNom` dans les 7 routes `ws/inventaires/details*`
(l'écriture est faite). L'application les affichera dans l'historique et les écarts dès qu'ils existent
(champs ignorés aujourd'hui).

---

## 4. Tests côté serveur suggérés

1. A : `produits` de 1, 4 (4 emplacements), 500 éléments mêlant `lg_FAMILLE_ID`, CIP, EAN-13 → exactement ces
   lignes, retenues ; `ws/inventaires/rayons` → leurs emplacements seulement ; coupure simulée au milieu →
   aucun inventaire ; 501 éléments → 413.
2. B : inventaire unitaire (toutes lignes, 3 retenues sur 2 emplacements) → `rayons` = ces 2 emplacements ;
   inventaire ordinaire → inchangé.
3. C : profil sans le droit → 403 `interdit` ; inventaire clôturé → 409 ; sans session → 401.
4. D : `3400935955838` d'un produit au CIP7 `3595583` → `ok`.
