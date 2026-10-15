# Demande à l'équipe serveur — comptage d'inventaire (Prestige Inventaire)

*Destinataire : la session « prestige » qui maintient le serveur (dépôt `prestige`, branche
`claude/new-session-xm8ptu` lue pour ce document). Émetteur : l'application mobile **Prestige
Inventaire** (`prestinv`, 4.12.0). Date : 13/10/2026.*

Ce document ne demande **aucun renommage ni suppression** : toutes les évolutions sont des **ajouts**
(routes nouvelles, champs JSON supplémentaires) ou des **contrôles** dont la mise en service suit un
plan de transition. Les versions actuelles et anciennes de l'application doivent continuer à fonctionner
à chaque étape.

Sommaire : [0. Constat](#0-constat-lu-dans-le-code-et-vérifié-sur-le-serveur-de-test) ·
[1. Pourquoi](#1-pourquoi--le-besoin-du-pharmacien) · [2. Priorités](#2-ordre-de-priorité-proposé) ·
[A. État des rayons](#a--état-des-rayons-en-une-requête) · [B. Auteur de la saisie](#b--auteur-et-date-de-la-dernière-saisie-par-ligne) ·
[C. Sécuriser l'écriture](#c--sécuriser-put-wsinventairesdetails) · [D. Création](#d--création-dinventaire-v1inventairecreation) ·
[E. Licence](#e--activation-de-licence-avant-connexion) · [F. Versement en lot](#f--versement-de-collecte-en-lot-optionnel) ·
[G. Rôle de l'utilisateur](#g--rôle-de-lutilisateur-dans-la-réponse-de-connexion-413) ·
[H. Inventaire des produits collectés](#h--inventaire-limité-aux-produits-collectés-4141) ·
[3. Règles communes](#3-règles-communes-à-toutes-les-routes) · [4. Ce que l'app fait déjà](#4-ce-que-lapplication-fait-déjà-sans-attendre)

---

## 0. Constat (lu dans le code et vérifié sur le serveur de test)

Sources lues (lecture seule) : `rest/ErpRessource.java` (routes `ws/inventaires/*`),
`rest/InventaireRessource.java` (`ligne/quantite`, `creation`), `rest/service/impl/InventaireServiceImpl.java`,
`rest/LicenceRessource.java`, `rest/service/impl/LicenceServiceImpl.java`, `filter/AuthenticationFilter.java`,
DTO `DetailInventaireDTO`, `RayonDTO`, `UpdateInventaireDetailDTO`, `InventaireDTO`. Serveur de test local
(Payara 5, base `laborex`, copie d'une officine) : appels faits le 13/10/2026, **aucune donnée modifiée**
(les seules écritures tentées ont échoué avant toute écriture).

| Constat | Où | Vérifié |
|---|---|---|
| L'état d'un rayon (pas commencé / commencé / terminé) n'existe pas côté serveur : l'app fait **2 requêtes par rayon** (`detailsTouchedRayon`, puis `detailsUntouchedRayon`) qui renvoient **toutes les lignes** du rayon (nom, CIP, prix…) alors qu'il ne faut qu'un compte. | `ErpRessource` l.266-288 | 40 rayons = 80 requêtes |
| `PUT /v1/ws/inventaires/details` **n'enregistre pas l'auteur** (`str_UPDATED_ID` reste vide) et ne vérifie pas que l'inventaire est ouvert. | `InventaireServiceImpl.updateDetailQuantity` l.718-722 | 24 / 24 lignes sans auteur dans la base de test |
| `PUT /v1/ws/inventaires/details` est **exempté de session** (`SKIP_PATHS` contient `v1/ws/inventaires/details`, pour GET **et** PUT). | `AuthenticationFilter` l.39 | PUT sans cookie → traité |
| Ligne inconnue sur ce PUT → `NullPointerException` → **500**. | `updateDetailQuantity` l.720 | `{"id":999999999}` → 500 |
| `POST /v1/inventaire/ligne/quantite` exige la session et **enregistre l'auteur** (`str_UPDATED_ID`), refus lisibles `{"success":0,"errors":…}`. Pas de contrôle « inventaire clôturé ». | `InventaireRessource` l.134-151, `updateQuantiteLigne` l.436-463 | — |
| Les lectures de lignes ne renvoient **ni l'auteur** ni d'information sur lui (`DetailInventaireDTO` : id, produitName, produitCip, prix, quantiteInitiale, quantiteSaisie, dtUpdated, boolInventaire). | DTO | réponse réelle ci-dessous |
| `POST /v1/inventaire/creation` → **500** sur le serveur de test : `NullPointerException` dans `toolkits.utils.jdom.LoadRessource` (fichier de configuration chiffré `config_laborex_v1.xml` absent), levée par `new dataManager()` **avant** le `try` (l.408) : le `catch` ne la rattrape pas. La réponse ne contient pas l'identifiant créé. | `InventaireRessource.creerInventaire` | 500 `{"msg":"Une erreur interne est survenue…"}` |
| `GET /v1/licence/save/{clé}` : `SKIP_PATHS` contient `"v1/licence/save/"` mais la comparaison est **exacte** (`Set.contains`) : le chemin réel `v1/licence/save/ABC` n'est pas exempté → **401** avant connexion. `POST` → **405**. Même remarque pour l'entrée `"v1/ws/"`, sans effet. | `AuthenticationFilter.shouldSkipPath`, `LicenceRessource` l.32-37 | 401 / 405 |
| `LicenceServiceImpl.save` **supprime la licence existante puis enregistre n'importe quelle chaîne**, sans contrôle. | l.73-82 | — |
| Les routes de lecture qui échouent renvoient une **liste vide** (`catch → List.of()`), indiscernable de « aucun produit ». | `InventaireServiceImpl` (toutes les `fetch*`) | — |

Forme actuelle d'une ligne (réponse réelle de `detailsTouchedRayon`) :

```json
{"boolInventaire":true,"dtUpdated":"2026-08-21T17:40:19Z[UTC]","id":11,"produitCip":"8505691",
 "produitName":"BLEDILAIT 3 CROISSANCE ANF B/400G","produitPrixAchat":3079,"produitPrixUni":3690,
 "quantiteInitiale":2,"quantiteSaisie":1}
```

Tables concernées (colonnes réelles, `SHOW COLUMNS`) :

- `t_inventaire` : `lg_INVENTAIRE_ID` (PK), `str_NAME`, `str_DESCRIPTION`, `str_TYPE`, `str_STATUT`
  (`enable` = ouvert ; `is_Closed` après clôture, `InventaireManager` l.763-824), `dt_CREATED`, `dt_UPDATED`,
  `lg_USER_ID`, `lg_EMPLACEMENT_ID`.
- `t_inventaire_famille` : `lg_INVENTAIRE_FAMILLE_ID` (PK, auto), `lg_INVENTAIRE_ID` (index), `lg_FAMILLE_ID`
  (index), `int_NUMBER` (compté), `int_NUMBER_INIT` (théorique), `str_STATUT`, `dt_CREATED`, `dt_UPDATED`
  (**renseigné = compté**), `bool_INVENTAIRE`, `str_UPDATED_ID` (auteur, `varchar(40)`, défaut `''`),
  `lg_FAMILLE_STOCK_ID`.
- Rayon d'une ligne : `t_famille.lg_ZONE_GEO_ID` → `t_zone_geographique` (`lg_ZONE_GEO_ID`, `str_CODE`,
  `str_LIBELLEE`). Auteur : `t_user` (`lg_USER_ID`, `str_LOGIN`, `str_FIRST_NAME`, `str_LAST_NAME`).

---

## 1. Pourquoi — le besoin du pharmacien

1. **Suivre l'avancement par rayon.** Pendant un inventaire, le pharmacien veut voir d'un coup d'œil
   « ANTIBIOTIQUES : 38 / 52 comptés », savoir quels rayons sont terminés, lesquels sont à peine commencés,
   et répartir l'équipe en conséquence. Aujourd'hui l'application ne peut afficher que trois états
   (pas commencé / commencé / terminé), et seulement après avoir **téléchargé toutes les lignes de chaque
   rayon deux fois**. En 4.12.0, l'avancement de l'accueil n'est donc calculé **que sur demande** (bouton
   « Actualiser l'avancement », progression « Rayon 3/12 »).
2. **Savoir qui a compté chaque produit.** Pour contrôler et faire recompter un écart (« qui a compté
   l'AUGMENTIN ? »), le pharmacien doit connaître l'auteur et l'heure de la dernière saisie. La colonne
   `str_UPDATED_ID` existe mais reste vide sur le chemin d'écriture le plus utilisé (PUT). La fiche web
   le constate déjà (`InventaireServiceImpl` l.528 : « La colonne str_UPDATED_ID n'est alimentée que par
   certains chemins de saisie »).
3. **Ne pas ralentir les terminaux Sunmi.** Les terminaux (V2s : 2 Go de mémoire, Wi-Fi d'officine
   souvent chargé) passent plusieurs secondes à télécharger et décoder des listes complètes pour n'en
   garder qu'un booléen. Une seule requête de quelques kilo-octets règle le problème et soulage aussi le
   serveur pendant l'inventaire, quand plusieurs terminaux comptent en même temps.
4. **Sécuriser les écritures.** Aujourd'hui, n'importe quel poste du réseau de l'officine peut modifier
   une quantité d'inventaire sans être connecté, sans laisser de trace, y compris sur un inventaire déjà
   clôturé (ce qui fausse le stock valorisé après clôture).
5. **Créer un inventaire depuis le terminal** (y compris partiel : « seulement la réserve et les
   antibiotiques ») et **activer la licence** sur un terminal neuf, sans poste Prestige à côté.

---

## 2. Ordre de priorité proposé

| Prio | Point | Effort estimé | Risque de régression | Gain |
|---|---|---|---|---|
| 1 | **D1** — corriger le 500 de `creation` (`new dataManager()` dans le `try`, ou passage en JPA) **à vérifier chez le client** | faible | nul | création possible depuis le terminal |
| 2 | **B** — auteur enregistré par le PUT + champs auteur en lecture | faible | nul (ajouts) | traçabilité immédiate, pour **toutes** les versions de l'app |
| 3 | **A** — `GET …/inventaires/{id}/rayons/etat` | faible | nul (route nouvelle) | avancement en 1 requête |
| 4 | **C1** — PUT : 404 lisible au lieu de 500, refus « inventaire clôturé », journal des PUT sans session | faible | très faible | données justes après clôture |
| 5 | **E** — licence : POST d'activation avec exemption contrôlée | moyen | faible (GET conservé) | terminal neuf activable |
| 6 | **D2/D3** — identifiant créé dans la réponse, inventaire partiel par rayons | faible | nul | création fiable, inventaire partiel |
| 7 | **C2** — PUT : session exigée (après la période de compatibilité) | faible | **à planifier** | fin des écritures anonymes |
| 8 | **F** — versement en lot (optionnel) | moyen | nul (route nouvelle) | versement de collecte rapide |

---

## A — État des rayons en une requête

### Route

`GET /api/v1/ws/inventaires/{idInventaire}/rayons/etat` (dans `ErpRessource`, `@Path("ws/inventaires/{id}/rayons/etat")`).
**Session exigée** (ne pas l'ajouter à `SKIP_PATHS`). Paramètre facultatif `avecAuteurs=1`.

### Réponse 200

Tableau (même style que `ws/inventaires/rayons`), trié comme `rayons` (libellé croissant) :

```json
[
  {"rayonId":"16820161934106991889","code":"20","libelle":"LAIT ET FARINE BEBE",
   "totalProduits":24,"comptes":2,"restants":22,
   "derniereSaisie":"2026-08-21T17:40:25Z[UTC]",
   "auteurs":[{"id":"52141743589144800410","login":"operateur1","nom":"Opérateur 1","comptes":2}]},
  {"rayonId":"16820162135422878144","code":"A1","libelle":"ANTALGIQUES ET ANTIGRIPPAUX SACHETS",
   "totalProduits":52,"comptes":52,"restants":0,"derniereSaisie":"2026-10-13T10:42:03Z[UTC]"},
  {"rayonId":"16820161934468646618","code":"B2","libelle":"ANTIBIOTIQUES CP ET GELULES",
   "totalProduits":31,"comptes":0,"restants":31,"derniereSaisie":null}
]
```

- `totalProduits` = lignes `bool_INVENTAIRE = 1` du rayon (mêmes lignes que `ws/inventaires/details`) ;
  `comptes` = parmi elles, `dt_UPDATED IS NOT NULL` (même définition que `detailsTouchedRayon`) ;
  `restants = totalProduits - comptes` (même définition que `detailsUntouchedRayon`).
- **Même ensemble de rayons** que `GET ws/inventaires/rayons` (un rayon dont toutes les lignes ont
  `bool_INVENTAIRE = 0` apparaît avec `totalProduits = 0`).
- `derniereSaisie` = `MAX(dt_UPDATED)`, même format de date que `dtUpdated` aujourd'hui, `null` si rien.
- `auteurs` (seulement avec `avecAuteurs=1`) : lignes comptées regroupées par `str_UPDATED_ID` non vide ;
  `nom` = prénom + nom de `t_user`. Les comptages sans auteur (`str_UPDATED_ID` vide) ne sont pas listés
  (la somme des `auteurs[].comptes` peut donc être inférieure à `comptes`).

Requête SQL de référence (testée en lecture sur la base de test : 1 accès par index `lg_INVENTAIRE_ID`) :

```sql
SELECT z.lg_ZONE_GEO_ID AS rayonId, z.str_CODE AS code, z.str_LIBELLEE AS libelle,
       SUM(f.bool_INVENTAIRE = 1)                              AS totalProduits,
       SUM(f.bool_INVENTAIRE = 1 AND f.dt_UPDATED IS NOT NULL) AS comptes,
       MAX(CASE WHEN f.bool_INVENTAIRE = 1 THEN f.dt_UPDATED END) AS derniereSaisie
FROM t_inventaire_famille f
JOIN t_famille fa ON fa.lg_FAMILLE_ID = f.lg_FAMILLE_ID
JOIN t_zone_geographique z ON z.lg_ZONE_GEO_ID = fa.lg_ZONE_GEO_ID
WHERE f.lg_INVENTAIRE_ID = ?1
GROUP BY z.lg_ZONE_GEO_ID, z.str_CODE, z.str_LIBELLEE
ORDER BY z.str_LIBELLEE;
```

(Pour les auteurs : même jointure + `LEFT JOIN t_user u ON u.lg_USER_ID = f.str_UPDATED_ID`, groupé par
rayon et auteur.) Index conseillé si les inventaires dépassent quelques dizaines de milliers de lignes :
`(lg_INVENTAIRE_ID, bool_INVENTAIRE, dt_UPDATED)` sur `t_inventaire_famille` — facultatif.

### Erreurs

| Cas | Réponse |
|---|---|
| Pas de session | 401 (filtre actuel) |
| Inventaire inexistant | **410** `{"success":0,"code":"INVENTAIRE_INCONNU","message":"Cet inventaire n'existe plus."}` — **pas 404** (voir § 3) |
| Inventaire clôturé | 200 (lecture autorisée) ; ajouter l'en-tête `X-Inventaire-Statut: is_Closed` (facultatif) |
| Panne base | **500** avec `{"success":0,"message":…}` — **pas de liste vide** |

### Impact dans l'application

- Dès que la route répond 200 : « Actualiser l'avancement » et l'écran « Choisir un rayon » font **une
  requête** au lieu de 2 × N ; chaque rayon affiche « 38 / 52 comptés · dernière saisie 10:42 », et
  l'accueil peut alors se mettre à jour **à chaque affichage** (coût négligeable).
- Détection : premier appel ; **404 ou 405** → la route est mémorisée « absente » pour cette adresse de
  serveur (comme pour `ligne/quantite` aujourd'hui) et l'app garde le calcul actuel (2 requêtes par rayon,
  à la demande). 401 → reconnexion, pas de repli.
- Aucun changement pour les anciennes versions (elles n'appellent pas la route).

### Tests serveur à prévoir

1. Inventaire avec 3 rayons : un non commencé, un partiel, un terminé → `comptes` / `restants` exacts ;
   égalité avec le nombre de lignes de `detailsTouchedRayon` / `detailsUntouchedRayon` pour chaque rayon.
2. Lignes `bool_INVENTAIRE = 0` exclues des comptes ; rayon entièrement exclu → `totalProduits = 0`.
3. Produit présent dans 2 grossistes (`tFamilleGrossisteCollection`) : compté **une** fois (les routes
   `details*` utilisent `DISTINCT` à cause de cette jointure ; la nouvelle requête ne la fait pas).
4. `avecAuteurs=1` : regroupement par auteur, auteur vide ignoré, utilisateur supprimé → `nom` vide mais
   `id` présent.
5. Sans session → 401 ; inventaire inconnu → 410 ; panne simulée → 500 (jamais `[]`).
6. Temps de réponse sur un inventaire complet de l'officine (≈ 1 800 produits sur la base de test) :
   objectif < 300 ms.

---

## B — Auteur et date de la dernière saisie par ligne

### B1. Lecture : champs ajoutés (aucun renommé)

Dans `DetailInventaireDTO`, donc dans **toutes** les routes de lecture `ws/inventaires/details`,
`detailsAll`, `detailsTouchedRayon`, `detailsUntouchedRayon`, `detailsAllTouched`, `detailsAllUntouched`,
`detailsAllEcarts` :

| Champ ajouté | Source | Exemple |
|---|---|---|
| `auteurId` | `t_inventaire_famille.str_UPDATED_ID` (`null` si vide) | `"52141743589144800410"` |
| `auteurLogin` | `t_user.str_LOGIN` | `"operateur1"` |
| `auteurNom` | `t_user.str_FIRST_NAME` + `' '` + `str_LAST_NAME` (abrégé libre) | `"Opérateur 1"` |
| `dtUpdated` | **inchangé** (date de la dernière saisie, déjà présent) | `"2026-10-13T10:12:44Z[UTC]"` |

```json
{"boolInventaire":true,"dtUpdated":"2026-10-13T10:12:44Z[UTC]","id":11,"produitCip":"8505691",
 "produitName":"BLEDILAIT 3 CROISSANCE ANF B/400G","produitPrixAchat":3079,"produitPrixUni":3690,
 "quantiteInitiale":2,"quantiteSaisie":1,
 "auteurId":"52141743589144800410","auteurLogin":"operateur1","auteurNom":"Opérateur 1"}
```

JPQL : `LEFT JOIN TUser u ON u.lgUSERID = o.strUPDATEDID` et un constructeur supplémentaire du DTO (les
constructeurs existants restent). Rétrocompatibilité : l'application, toutes versions, ignore les champs
inconnus (`Product.fromJson` lit les clés par leur nom) ; la fiche web n'utilise pas ces DTO.

### B2. Écriture : l'auteur aussi par le PUT

Dans `InventaireServiceImpl.updateDetailQuantity`, comme dans `updateQuantiteLigne` :

```java
TUser auteur = sessionHelperService.getCurrentUser(); // session OU en-têtes X-User-Info
if (auteur != null) ligne.setStrUPDATEDID(auteur.getLgUSERID());
```

Tant que le PUT reste exempté de session (voir C), `auteur` est `null` pour un appel anonyme : on
**n'efface pas** un auteur déjà présent ; on écrit `''` seulement si la ligne n'en a jamais eu. Les
versions récentes de l'application envoient toujours leur cookie de session sur ce PUT (4.8.5 comprise) :
l'auteur sera donc renseigné pour elles dès le déploiement, **sans mise à jour de l'app**.

**Recommandation** : à terme, une seule route d'écriture, `POST /v1/inventaire/ligne/quantite`
(session, auteur, refus lisibles). L'application l'utilise déjà pour le versement de la collecte et la
généralisera à toutes les saisies dès que C1 est en place (voir « Impact »).

### Impact dans l'application

- Saisie guidée et feuille de quantité : « Déjà compté : 6 — par Opérateur 1 à 10:12 » ; Écarts : colonne
  / filtre « Compté par » et tri par heure ; récapitulatif d'un rayon : qui a compté quoi.
- Détection : présence de la clé `auteurId` dans les lignes (absente → rien n'est affiché, comme
  aujourd'hui).

### Tests serveur à prévoir

1. PUT avec session → `str_UPDATED_ID` = utilisateur de la session ; avec `X-User-Info` + jeton → idem.
2. PUT anonyme (période de compatibilité) → quantité enregistrée, auteur précédent **conservé**.
3. Lecture : les 7 routes renvoient `auteurId/auteurLogin/auteurNom` ; ligne jamais comptée → `null` ;
   utilisateur supprimé → `auteurId` seul.
4. Non-régression : mêmes champs qu'avant, mêmes valeurs, même ordre de tri, même nombre de lignes.

---

## C — Sécuriser `PUT /ws/inventaires/details`

### C1. Tout de suite (sans risque pour les anciennes versions)

1. **Ligne inconnue** : 404 lisible au lieu du 500 actuel :
   `{"success":0,"code":"LIGNE_INCONNUE","message":"Cette ligne d'inventaire n'existe plus."}`.
2. **Inventaire clôturé** (`t_inventaire.str_STATUT <> 'enable'`, ou ligne `str_STATUT = 'is_Closed'`) :
   **409 Conflict**, rien n'est écrit :
   `{"success":0,"code":"INVENTAIRE_CLOTURE","message":"Inventaire « Inventaire annuel 2026 » clôturé le 12/10/2026 : la quantité n'a pas été enregistrée."}`.
   Même contrôle dans `updateQuantiteLigne` (`POST ligne/quantite`), mais avec la forme de réponse de
   cette route : **200** `{"success":0,"errors":"Inventaire … clôturé …"}` (voir § 3 : sur cette route,
   un 404/405 signifie « route absente » pour l'app).
3. **Quantité** : refuser `null` ou négative (400 `{"code":"QUANTITE_INVALIDE"}`), comme `ligne/quantite`.
4. **Journal** des PUT reçus sans utilisateur identifié (adresse IP, `User-Agent`, en-tête
   `X-Prestinv-Version` s'il est présent) : c'est ce journal qui dira quand passer à C2.

Effet sur les anciennes versions : un refus (4xx) est déjà traité comme un échec par toutes les versions
(4.8.5 : message d'erreur ; ≥ 4.9 : saisie gardée « refusée » avec son motif dans « À envoyer »). Écrire
sur un inventaire clôturé était de toute façon une erreur.

### C2. Session exigée (après une période de compatibilité)

Retirer `"v1/ws/inventaires/details"` de `SKIP_PATHS` **pour le PUT seulement** (la lecture GET peut
rester exemptée dans un premier temps, ou suivre le même plan) : le filtre ne connaît que le chemin ;
le plus simple est de tester `requestContext.getMethod()` :

```java
if ("PUT".equals(requestContext.getMethod()) && "v1/ws/inventaires/details".equals(path) && currentUser == null) {
    // pendant la période de compatibilité : journaliser seulement ; ensuite : 401
}
```

Plan de transition proposé (aucune version ne casse sans avoir été prévenue) :

| Étape | Serveur | Application |
|---|---|---|
| T0 | C1 + journal des PUT anonymes | 4.13 : envoie `X-Prestinv-Version: 4.13.0` sur toutes ses requêtes ; toutes les saisies passent par `POST ligne/quantite` quand la route existe |
| T0 + 1 mois | Lire le journal : reste-t-il des PUT anonymes ? Quelles versions ? | Mettre à jour les terminaux concernés |
| T1 (≥ 2 mois, journal vide depuis 2 semaines) | PUT sans session → **401** `Constant.DECONNECTED_MESSAGE` | ≥ 4.9 : saisie gardée sur le terminal, « Se reconnecter », renvoi automatique ; aucune perte |
| Option | Version minimale : refuser (426 `{"code":"VERSION_TROP_ANCIENNE","minimum":"4.9.0"}`) les requêtes portant `X-Prestinv-Version` < minimum | Message « Mettez à jour l'application » |

Les versions **< 4.9** (avant la file persistante des saisies) affichent une erreur sur un 401 et
risquent de perdre la saisie si l'utilisateur quitte l'écran : c'est la seule raison du délai T0 → T1.

### Tests serveur à prévoir

1. PUT ligne inconnue → 404 + message (plus de 500) ; quantité négative → 400.
2. PUT / POST `ligne/quantite` sur inventaire clôturé → 409 / `success:0`, `int_NUMBER` et `dt_UPDATED`
   **inchangés** en base.
3. Période de compatibilité : PUT anonyme accepté **et** journalisé ; PUT avec session : non journalisé.
4. Après T1 : PUT anonyme → 401 ; avec session ou `X-User-Info` valide → 200.
5. Non-régression : GET `ws/inventaires/details` sans session inchangé tant qu'il reste exempté.

---

## D — Création d'inventaire (`/v1/inventaire/creation`)

### D1. Le 500 (à vérifier chez le client)

Sur le serveur de test : `NullPointerException` à `toolkits.utils.jdom.LoadRessource(jdom.java:239)` ←
`dal.dataManager.<init>(dataManager.java:126)` ← `InventaireRessource.creerInventaire` (l.408). Le
fichier de configuration chiffré de l'ancienne couche (`config_laborex_v1.xml`) n'existe pas sur ce
serveur. **Chez le client il existe probablement** (le poste Prestige crée des inventaires) : merci de
vérifier par un essai réel sur une copie de leur base, ou dans leur journal (`creerInventaire`).

Correction demandée dans tous les cas :

1. Mettre `new dataManager()` / `initEntityManager()` **dans** le `try` (aujourd'hui l'exception sort du
   `catch` et donne un 500 générique) → réponse `incident(...)` lisible ;
2. idéalement, faire passer la création par la couche JPA (`InventaireService`, `@PersistenceContext`),
   comme `create(...)` / `createReserveInventaireDetaille(...)`, pour ne plus dépendre du fichier ;
3. **atomicité** : une création interrompue ne doit pas laisser un inventaire partiel ouvert
   (`InventaireManager` l.63 le garde aujourd'hui : « Inventaire incomplet non supprime »).

### D2. Renvoyer l'identifiant créé (ajout)

```json
{"success":1,"lignes":1794,"nombre":"1794 article(s) inventorie(s)",
 "lgInventaireId":"16821173940271548214","libelle":"Inventaire annuel 2026"}
```

Impact app : aujourd'hui l'app relit la liste des inventaires ouverts et retrouve le nouveau par son
libellé (fragile si deux inventaires portent le même nom). Avec `lgInventaireId` : ouverture directe ; en
cas de réponse perdue (coupure réseau), l'app garde son contrôle actuel des doublons. Détection : présence
du champ.

### D3. Inventaire partiel (rayons choisis)

La route sait déjà le faire avec `str_TYPE_TRANSACTION = "Emplacement"` et `valeurs = [lg_ZONE_GEO_ID…]`
(`createInventaireMultiCriteres`, axe `EMPLACEMENT`) — une fois D1 corrigé. Demandes :

- confirmer ce contrat (et que `valeurs` = identifiants de `t_zone_geographique`, tels que renvoyés par
  `GET /v1/common/rayons`) ;
- refuser une valeur inconnue : `{"success":0,"message":"Rayon inconnu : …"}` plutôt que de l'ignorer ;
- renvoyer aussi `rayons` (nombre de rayons retenus) dans la réponse.

Exemple :

```json
POST /api/v1/inventaire/creation
{"str_NAME":"Réserve et antibiotiques","str_TYPE_TRANSACTION":"Emplacement",
 "valeurs":["16820161934468646618","16820162135422878144"]}
→ {"success":1,"lignes":83,"rayons":2,"lgInventaireId":"…","nombre":"83 article(s) inventorie(s)"}
```

Impact app : écran « Nouvel inventaire » → choix « Tout » / « Rayons choisis » (liste de
`GET /v1/common/rayons`). Tant que la création échoue sur le serveur, le choix n'est pas proposé.

### Tests serveur à prévoir

1. Création complète et partielle sur une copie de base **client** (avec le fichier de configuration) et
   **sans** le fichier (doit fonctionner après passage en JPA, ou renvoyer un incident lisible, jamais 500).
2. `lgInventaireId` présent et égal à la ligne créée dans `t_inventaire`.
3. Valeur de rayon inconnue → refus lisible, rien de créé ; aucun produit → refus actuel inchangé.
4. Coupure simulée en cours de création → aucun inventaire partiel laissé ouvert.

---

## E — Activation de licence avant connexion

Constat : l'écran d'activation s'affiche **avant** la connexion (pas de session), alors que
`GET /v1/licence/save/{clé}` exige une session (l'exemption `"v1/licence/save/"` ne s'applique pas :
comparaison exacte) et n'accepte que GET (l'app envoie POST → 405). De plus `save` supprime la licence
existante et enregistre n'importe quelle chaîne. `prestige_vente_app` appelle aujourd'hui ce même
`GET /licence/save/{clé}` : **il doit continuer à marcher**.

### Demande

Nouvelle route `POST /api/v1/licence/activation`, corps `{"cle":"…"}` (la clé ne passe plus dans l'URL,
donc plus dans les journaux d'accès), avec **exemption contrôlée** :

1. ajoutée à `SKIP_PATHS` (chemin exact, sans paramètre) ;
2. **sans session**, l'activation n'est acceptée **que si aucune licence MOBILE valide n'existe**
   (absente ou expirée) ; s'il en existe une valide, il faut une session administrateur (sinon 403
   `{"code":"LICENCE_DEJA_ACTIVE"}`) — un poste du réseau ne peut donc pas effacer une licence en cours ;
3. **valider la clé avant de toucher à l'existant** (format : 40 caractères hexadécimaux, empreinte
   attendue par `generateLicence` ; si la date de fin n'est pas déductible, l'exiger dans le corps :
   `{"cle":"…","dateFin":"2027-12-31"}` et recalculer l'empreinte) ; clé refusée → 422
   `{"code":"CLE_INVALIDE","message":"Cette clé de licence n'est pas valable pour cette officine."}`,
   licence existante **intacte** ;
4. limiter les essais (ex. 5 par minute et par adresse IP → 429) et journaliser chaque activation ;
5. réponse 200 : la licence enregistrée, même forme que `GET /v1/licence/find`
   (`{"id":…,"dateStart":…,"dateEnd":…,"typeLicence":"MOBILE"}`).

`GET /v1/licence/save/{clé}` reste **inchangé** (session exigée) pour `prestige_vente_app` et les
anciennes versions. Si l'équipe préfère ne rien exempter : le **documenter** (activation uniquement
depuis le poste Prestige) et l'application affichera cette consigne au lieu du champ de saisie.

Impact app : l'écran licence essaie `POST licence/activation` ; 404/405 → affiche « Activez la licence
depuis le poste Prestige (Paramètres → Licence), puis touchez Réessayer » (comportement actuel corrigé).

### Tests serveur à prévoir

1. Sans session, aucune licence → clé valide acceptée ; clé invalide → 422 et rien n'est écrit.
2. Sans session, licence valide existante → 403, licence inchangée ; avec session administrateur → 200.
3. 6e essai dans la minute → 429.
4. `GET licence/save/{clé}` avec session : comportement inchangé (non-régression `prestige_vente_app`).

---

## F — Versement de collecte en lot (optionnel)

Aujourd'hui, le versement d'une collecte hors ligne (codes scannés sans réseau, puis versés dans un
inventaire) fait, **par produit** : une recherche « déjà compté » (`detailsAllTouched?query=…`) puis une
écriture (`POST ligne/quantite`). 300 produits = 600 requêtes, avec un risque d'écraser une saisie faite
par un collègue entre la lecture et l'écriture.

### Route

`POST /api/v1/inventaire/{idInventaire}/versement` — session exigée.

```json
{"cle":"7f3c9a2e-terminal-0042-20261013T104500",
 "mode":"ajouter",
 "lignes":[
   {"code":"3400935959001","quantite":6},
   {"code":"3400930000001","quantite":24},
   {"code":"9999999999999","quantite":3}
 ]}
```

- `mode` : `remplacer` (pose la quantité) ou `ajouter` (ajoute à la quantité comptée, **dans la même
  transaction**, `int_NUMBER = int_NUMBER + ?` — plus de lecture puis écriture côté terminal).
- `code` : CIP (`t_famille.int_CIP`), EAN (`int_EAN13`, `code_ean_fabriquant`) ou code article grossiste,
  avec les mêmes règles que la recherche des routes `details*` (correspondance exacte, pas préfixe).
- Lot : 500 lignes au plus (413 au-delà).

### Réponse 200 — rapport par ligne

```json
{"success":1,"cle":"7f3c9a2e-terminal-0042-20261013T104500","dejaTraite":false,
 "lignes":[
   {"code":"3400935959001","statut":"ok","ligneId":2,"avant":6,"apres":12},
   {"code":"3400930000001","statut":"ok","ligneId":1,"avant":null,"apres":24},
   {"code":"9999999999999","statut":"inconnu","message":"Code absent de cet inventaire."}
 ],
 "resume":{"ok":2,"inconnus":1,"ambigus":0,"refuses":0}}
```

Statuts : `ok`, `inconnu` (code absent de l'inventaire), `ambigu` (le code désigne plusieurs lignes — ex.
le même produit dans deux rayons : **rien n'écrit**, `lignesPossibles:[{ligneId, rayon}]` pour que l'app
demande), `refuse` (quantité invalide, résultat > 99 999). Chaque écriture enregistre l'auteur
(`str_UPDATED_ID`) et `dt_UPDATED`.

### Idempotence

`cle` (fournie par l'app, unique par versement) : la **même clé** renvoie le **même rapport** sans rien
réécrire (`"dejaTraite":true`) — indispensable quand la réponse se perd sur le Wi-Fi et que l'app
renvoie, surtout en mode `ajouter`. Stockage proposé : table `t_inventaire_versement`
(`str_CLE` PK `varchar(80)`, `lg_INVENTAIRE_ID`, `lg_USER_ID`, `dt_CREATED`, `str_RAPPORT` `mediumtext`),
purge après 30 jours. Même clé avec un contenu différent → 409 `{"code":"CLE_REUTILISEE"}`.

### Erreurs

401 (session), 409 `INVENTAIRE_CLOTURE` (rien n'est écrit), 410 `INVENTAIRE_INCONNU`, 413 (lot trop
gros), 400 (`mode` inconnu, corps illisible).

### Impact app

Versement en un seul appel par paquet de 500, rapport affiché tel quel (mêmes catégories qu'aujourd'hui :
versés, non reconnus, à choisir). Détection : 404/405 → versement actuel ligne par ligne (inchangé).

### Tests serveur à prévoir

1. `ajouter` deux fois avec la même clé → une seule addition, 2e réponse `dejaTraite:true` identique.
2. `ajouter` concurrent (deux terminaux, même produit) → somme exacte (pas de perte).
3. Code ambigu → rien d'écrit, `lignesPossibles` correct ; code inconnu ; EAN et code grossiste reconnus.
4. Inventaire clôturé → 409, base inchangée ; lot de 501 → 413 ; auteur et `dt_UPDATED` renseignés.

---

## G — Rôle de l'utilisateur dans la réponse de connexion (4.13)

*Ajouté le 14/10/2026 pour Prestige Inventaire 4.13.0.*

### Besoin

Le pharmacien a décidé que **la création d'un inventaire depuis le terminal est réservée à
l'administrateur et au pharmacien** ; les autres comptes n'y ont accès que si un réglage du terminal
(protégé par le code administrateur) l'autorise. L'application doit donc connaître le **profil** de
l'utilisateur connecté.

### Ce que le serveur donne aujourd'hui (lu dans `rest/AccountResource.java`, branche `claude/new-session-xm8ptu`)

- `POST /v1/user/auth` ne renvoie **pas** le rôle, mais renvoie `"xtypeuser"` : **`"dashboard"`** pour
  l'utilisateur système (`lg_USER_ID = "00"`), le rôle `Pharmacien`, le super administrateur et
  l'administrateur (détection par préfixe `isSuperAdminRole` / `isAdminRole`), **`"mainmenumanager"`**
  pour tous les autres profils. C'est exactement la règle voulue : **l'application 4.13 s'en sert**
  (`AppUser.typeAccueil`, `lib/inventaire/autorisation_creation.dart`).
- `GET /v1/user/account` renvoie `accountInfo.lg_ROLE_ID` (désignation du rôle) et
  `accountInfo.retourTableauBord` (vrai pour super administrateur, pharmacien, administrateur) — une
  requête de plus, non utilisée.

Limites : `xtypeuser` est un détail d'affichage de l'application web (écran d'accueil) détourné de son
usage ; sur un serveur plus ancien, l'administrateur pouvait recevoir `"mainmenumanager"` (la détection
par préfixe est récente) ou le champ peut manquer. **Sans le champ, l'application demande le code
administrateur du terminal pour créer un inventaire** (décision du pharmacien).

### Demande (ajout, rétrocompatible)

Ajouter à la réponse de `POST /v1/user/auth` (succès) :

```json
{
  "success": true,
  "str_LOGIN": "…",
  "role": { "code": "PHARMACIEN", "libelle": "Pharmacien" },
  "droits": { "creerInventaire": true }
}
```

- `role.code` : `SYSTEME`, `SUPER_ADMINISTRATEUR`, `ADMINISTRATEUR`, `PHARMACIEN` ou `AUTRE` (valeur
  stable, indépendante du libellé saisi dans Prestige) ; `role.libelle` : désignation affichable.
- `droits.creerInventaire` (idéalement calculé à partir des privilèges `TPrivilege` du rôle, pour que
  l'officine puisse l'accorder à un profil sans modifier l'application).
- Le serveur doit **aussi** refuser `POST /v1/inventaire/creation` (403 lisible
  `{"success":0,"message":"Création réservée…"}`) pour un compte non autorisé : le terminal n'est pas la
  seule protection.
- Ne rien retirer : `xtypeuser` reste (anciennes versions de l'application).

### Impact dans l'application

Ordre de lecture : `droits.creerInventaire` s'il existe, sinon `role.code`, sinon `xtypeuser`, sinon
« profil inconnu » (code administrateur). Le réglage « Autoriser la création d'inventaire aux autres
comptes » reste prioritaire pour ouvrir l'accès.

### Tests serveur à prévoir

1. Connexion pharmacien, administrateur, super administrateur, caissier : `role.code` et
   `droits.creerInventaire` attendus ; `xtypeuser` inchangé.
2. `POST /inventaire/creation` par un caissier : 403 lisible, rien de créé.

---

## H — Inventaire limité aux produits collectés (4.14.1)

### Constat (retour de test du pharmacien)

Un produit scanné en **collecte**, puis « Créer un inventaire avec ces produits » : l'inventaire créé
contenait **tous les emplacements** de l'officine. Cause côté application (corrigée en 4.14.1) :
`POST /v1/inventaire/creation` était envoyé avec `str_NAME` et `str_TYPE_TRANSACTION` seulement, **sans
`valeurs`** ; `InventaireRessource.creerInventaire` → `createInventaireMultiCriteres` traite alors la
liste vide comme « tous » (joker `%%`).

Lu dans le serveur (branche `claude/new-session-xm8ptu`, lecture seule) :

| Route | Ce qu'elle permet | Pourquoi l'application ne s'en sert pas pour la collecte |
|---|---|---|
| `POST /v1/inventaire/creation` | axe Emplacement / Famille / Grossiste, plusieurs `valeurs` ; `createInventaireFamille` reçoit `lg_FAMILLE_ID = "%%"` en dur : **pas de filtre produit exposé** | utilisée en 4.14.1 avec **un seul emplacement** |
| `POST /v1/inventaire/import-csv` `{csvContent}` | liste de CIP | libellé figé « INVENTAIRE CSV », type `unitaire`, stock lu sur `lg_EMPLACEMENT_ID='1'` en dur (faux pour un dépôt), identifiant non renvoyé (impossible de retrouver l'inventaire si deux portent ce nom) |
| `GET /v1/articlemvt/inventaire?ids=…` | liste de `lg_FAMILLE_ID` | libellé imposé « INVENTAIRE ARTICLES EN MOUVEMENT DU … AU … », route de l'écran des mouvements |
| `POST /v1/reserve/create-inventaire-selection`, `POST /v1/produit-search/create-inventaire` | sélection / recherche | inventaire de **réserve** ou recherche texte unique : autre usage |

Ce que fait l'application en 4.14.1, sans attendre : l'écran de création cherche l'emplacement de chaque
code collecté (`GET /v1/produit-search/fiche?search_value=<code>` → `lg_ZONE_GEO_ID_REEL`), présélectionne
le plus fréquent (modifiable, liste complète par `GET /v1/referentiel-article/zones-geographiques`) et
envoie `str_TYPE_TRANSACTION = "Emplacement"`, `valeurs = [cet emplacement]`. L'inventaire contient donc
les produits actifs de **cet emplacement** (et non de toute l'officine) ; les produits de la collecte
rangés ailleurs sont signalés « non reconnus » au versement.

### Demande (ajout, rétrocompatible)

Accepter dans `POST /v1/inventaire/creation` un champ facultatif **`produits`** : liste de codes tels que
scannés (CIP7, EAN-13 / CIP13, code article — la même recherche que `produit-search/fiche`), ou
`lg_FAMILLE_ID`. S'il est présent et non vide, l'inventaire ne contient **que ces produits** (une ligne
par produit et par emplacement de stock de l'utilisateur, stock théorique repris comme aujourd'hui),
quel que soit l'axe ; `valeurs` reste possible pour restreindre en plus à des emplacements.

```json
POST /api/v1/inventaire/creation
{"str_NAME":"Collecte du 15-10-2026 09.30","str_TYPE_TRANSACTION":"Emplacement",
 "valeurs":["16820161934468646618"],
 "produits":["3400930000001","3595583","8050457"]}
→ {"success":1,"lignes":2,"lgInventaireId":"…","nombre":"2 article(s) inventorie(s)",
   "inconnus":["8050457"]}
```

- `inconnus` : codes non retrouvés (l'application les affiche dans le rapport de versement) ;
- aucun produit retrouvé → refus lisible actuel (`success:0`, « Aucun inventaire n'a été créé… ») ;
- ancien serveur : le champ est ignoré, l'inventaire est celui de l'emplacement (comportement 4.14.1) —
  l'application détecte la prise en compte par la présence de `inconnus` ou par `lignes` ≤ nombre de codes.

### Impact dans l'application

Dès que la route accepte `produits`, l'écran « Créer un inventaire avec ces produits » les envoie avec
l'emplacement choisi : l'inventaire ne contient plus que les produits collectés (plus de lignes « non
comptées » du reste du rayon). Aucune autre évolution d'écran.

### Tests serveur à prévoir

1. `produits` de 1, 50 et 500 codes (CIP7, EAN-13, code article mélangés) → exactement ces lignes.
2. Code inconnu → dans `inconnus`, rien d'autre créé pour lui ; tous inconnus → refus, aucun inventaire.
3. `produits` + `valeurs` (emplacement) → intersection ; `produits` absent → comportement actuel inchangé.
4. Dépôt (`lg_EMPLACEMENT_ID` ≠ 1) : stock repris de l'emplacement de stock de l'utilisateur.

---

## 3. Règles communes à toutes les routes

1. **404/405 signifient « route absente »** pour l'application (elle bascule alors sur son ancien
   fonctionnement et s'en souvient pour ce serveur). Ne pas les utiliser pour un cas métier sur
   `ligne/quantite` et les nouvelles routes : utiliser 409 / 410 / 422 ou `200 {"success":0,…}` selon la
   route (exception : C1.1, PUT existant, où l'app lit 404 comme un refus).
2. **Un échec n'est jamais une liste vide** : 500 avec `{"success":0,"message":…}`. (Remarque hors
   périmètre : les `fetch*` actuels renvoient `List.of()` sur exception ; l'app ne peut pas distinguer
   « aucun produit » d'une panne.)
3. **Ajouter, ne jamais renommer** : nouveaux champs et nouvelles routes uniquement ; formats de date
   identiques à l'existant (`dtUpdated`).
4. Messages en français, lisibles par l'utilisateur final, avec un `code` stable pour l'application.
5. Session : cookie `JSESSIONID` de `v1/user/auth` (ce que l'app envoie) ; les en-têtes `X-User-Info` /
   `X-Token-Exp` / `X-client` restent acceptés par le filtre.
6. Remarque (priorité basse) : `SKIP_PATHS` contient `"v1/ws/"` et `"v1/licence/save/"`, sans effet
   (comparaison exacte) ; les lectures `ws/inventaires`, `ws/inventaires/rayons`, `ws/inventaires/details`
   (prix d'achat compris) sont lisibles sans session : à traiter avec le même plan que C2 si souhaité.

## 4. Ce que l'application fait déjà, sans attendre

- Avancement **à la demande** (4.12.0) avec les routes actuelles, progression et annulation ; aucun
  calcul au lancement. Depuis la 4.13, il est aussi calculé **au déroulé** de la liste des inventaires
  de l'accueil (une ligne après l'autre, résultat gardé) et compté **en produits** (« 110 / 130 ») : les
  deux requêtes `detailsTouchedRayon` + `detailsUntouchedRayon` sont faites pour chaque rayon (avant :
  la seconde seulement pour les rayons entamés). La route A ramènerait cela à une requête.
- Profil (création d'inventaire) lu dans `xtypeuser` en attendant G.
- Création depuis la collecte (4.14.1) limitée à **un emplacement** (`valeurs`), présélectionné d'après
  les produits collectés, en attendant H.
- Saisies gardées sur le terminal avant tout envoi, renvoi automatique, « À envoyer », reconnexion sans
  quitter l'écran (401) : prête pour C2.
- Versement de la collecte par `POST ligne/quantite` (auteur enregistré), repli sur le PUT si la route
  manque ; contrôle « inventaire clôturé » fait par l'application en attendant C1.
- « Déjà compté » vérifié auprès du serveur avant d'écrire (jamais d'écrasement silencieux).

Contact côté application : session « prestinv » (dépôt `prestinv`, branche `claude/refonte`). Pour toute
question sur un format, l'application s'adapte au contrat que vous fixerez, tant qu'il reste
rétrocompatible.
