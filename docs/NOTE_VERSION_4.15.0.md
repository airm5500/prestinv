# Prestige Inventaire 4.15.0 (code 14) — Note de version

*Pour le pharmacien et l'équipe qui compte.*

Elle s'installe par-dessus la 4.14.2 sans désinstaller ; rien n'est perdu (réglages, saisies en attente,
collecte, rapports de versement, versement interrompu à reprendre). Elle fonctionne avec le serveur
Prestige actuel **et** avec le serveur à jour (réponse aux demandes des applications mobiles du
15/10/2026) : sur un serveur qui n'a pas les nouvelles routes, tout se passe comme avant.

## 1. Inventaire créé depuis la collecte : seulement les produits collectés (deux interfaces)

**Votre retour sur la 4.14.1** : la création depuis la collecte était limitée à **un seul** emplacement
(le plus fréquent). « Si j'ai 4 produits de 4 emplacements différents ? On doit faire comme sur Prestige :
emplacement = tous, et il crée l'inventaire des 4 produits ; à l'ouverture, juste les emplacements de ces
4 produits. »

**Désormais** (Scanner › Collecte › « Créer un inventaire avec ces produits » dans la nouvelle interface ;
Collecte › « Verser la collecte » › « Nouvel inventaire… » dans l'ancienne) :

- plus de choix d'emplacement ni de type : l'application retrouve chaque produit collecté sur le serveur
  et affiche un **récapitulatif** : « **4 produits, 4 emplacements** », la liste des emplacements (avec le
  nombre de produits de chacun) et, s'il y en a, les **codes non retrouvés** (ils ne seront pas dans
  l'inventaire et sont signalés « non reconnus » au versement) ;
- « Créer » : l'inventaire ne contient **que ces produits** (comme l'« inventaire unitaire » de Prestige :
  les autres produits de ces emplacements y sont mais **non retenus**, invisibles de la saisie, des
  écarts et de la clôture) ; à l'ouverture, **seuls leurs emplacements** sont proposés, sur tous les
  terminaux ;
- la collecte y est ensuite versée (nouvelle interface : directement ; ancienne : choix Remplacer /
  Ajouter comme avant), puis le rapport s'affiche.

**Serveur trop ancien** (sans la route qui retient les produits) : *remplacé en 4.15.1* — la création
depuis la collecte y est désormais **refusée** (voir `docs/NOTE_VERSION_4.15.1.md`).

**Panne** : recherche des produits en échec → message et « Réessayer » (rien n'est créé) ; si la liaison
se coupe juste après la création, l'écran l'indique (« Inventaire … créé sans ses produits ») et le bouton
devient « **Ajouter les produits** » : rien n'est recréé.

## 2. Serveur à jour : moins d'attente, droits du serveur

Si le serveur Prestige est à jour (reconnu à la connexion, sans requête de plus) :

- **Droit « Créer un inventaire »** : c'est le droit donné dans Prestige qui décide qui voit « Créer un
  inventaire » (le réglage « Autoriser la création aux autres comptes » ne sert plus que pour un serveur
  ancien). Un compte sans le droit reçoit « Votre compte n'a pas le droit « Créer un inventaire » dans
  Prestige » — et non plus « session expirée ».
- **Choix du rayon** : l'état de tous les rayons (pas commencé / commencé / terminé) est lu en **une**
  seule requête au lieu d'une ou deux par rayon ; les rayons sans produit à compter ne sont plus
  proposés.
- **Versement de la collecte** : envoyé par lots de 200 produits en une requête (au lieu d'une par
  produit). Une coupure pendant l'envoi ne compte **jamais deux fois**, même en « Ajouter » : le lot est
  gardé sur le terminal et renvoyé à l'identique à la reprise. Les codes que le serveur ne reconnaît pas
  sont recherchés comme avant (CIP7, EAN…).
- **Identifiant du nouvel inventaire** donné par le serveur (plus besoin de relire la liste).

## 3. Messages plus justes

- Quantité refusée par le serveur à jour : « Inventaire clôturé sur le serveur : quantité non
  enregistrée », « Cette ligne n'existe plus dans l'inventaire… » au lieu de « code 409 / 404 ».
- Lecture en panne côté serveur : « Erreur du serveur (code 500) : … non chargés. Réessayez » — jamais
  une liste vide.
- Vérifié (« Contradiction 3 » du serveur) : une quantité envoyée sans session valide reste sur le
  terminal (« Session expirée — reconnectez-vous ») et part après la reconnexion. Les terminaux en
  version **antérieure à 4.9** peuvent perdre une saisie dans ce cas : **mettez-les à jour**.

## Ce qui reste demandé au serveur

Demandes regroupées dans prestige_vente_app/docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md (§ 4) : création d'un inventaire limité à une liste de produits en **une**
requête atomique (aujourd'hui trois requêtes), liste des rayons limitée aux produits retenus, droit sur la
route qui retient les produits, formes du code dans le versement en lot, lecture de l'auteur des saisies.

## Tests

Nouveaux tests (voir `test/README.md`) : `test/creation_collecte_4_15_test.dart` (deux interfaces),
`test/unitaires/regles_4_15_test.dart`, `test/integration/creation_collecte_test.dart` (réécrit),
`test/integration/routes_recentes_test.dart`, `test/performance/collecte_4_15_test.dart`,
`test/reseau/collecte_4_15_reseau_test.dart`, parcours de bout en bout et écrans d'ergonomie (Sunmi
V2s compris) mis à jour.
