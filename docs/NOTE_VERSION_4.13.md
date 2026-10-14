# Prestige Inventaire 4.13.0 — Note de version

*Pour le pharmacien et l'équipe qui compte. Cette version applique la revue de la nouvelle interface
et la maquette que vous avez validée. Les écrans d'origine ne changent pas : ils restent disponibles
dans les Réglages (code administrateur).*

Version : **4.13.0** (code 9). Elle s'installe par-dessus la 4.12.0 sans désinstaller. Rien n'est
perdu : réglages, saisies en attente, collecte et rapports sont repris tels quels.

Captures (terminal Sunmi V2s et téléphone) : `docs/captures_4.13/`.

---

## 1. Accueil

- En haut : **« Prestige Inventaire »**, le nom de la pharmacie, puis **« Bienvenu(e), Prénom Nom »**.
  Puces Local / Distant et Licence, bouton de déconnexion.
- La carte « Inventaire en cours » et la liste « Inventaires ouverts » ne sont plus sur l'accueil.
- **« Créer un inventaire »** : visible pour l'administrateur et le pharmacien (voir § 8).
- **« Voir les inventaires (N) »** : touchez la flèche ▼, la liste se déroule par le bas ; ▲ pour la
  replier. Chaque ligne montre le nom, le nombre de rayons et de produits comptés, le **pourcentage**
  et un bouton :
  - **Commencer →** (bleu clair) : rien de compté (0 %) ;
  - **Poursuivre →** (orange) : commencé (de 0,1 à 99,9 %) ;
  - **Revérifier →** (vert) : tout est compté (100 %).
  Le pourcentage est calculé **quand vous déroulez la liste**, un inventaire après l'autre (un petit
  sablier sur la ligne en attente), puis gardé : l'écran n'est jamais bloqué et rien n'est calculé au
  lancement. Tirez la liste vers le bas pour tout recalculer. Les saisies faites sur le téléphone
  comptent tout de suite.
- En bas : **« Collecte »** avec le nombre de produits scannés.
- Barre du bas : **Accueil · Scanner · Analyse · Réglages** (l'onglet Écarts devient Analyse).
- Si des saisies attendent d'être envoyées, le bandeau « … pas encore envoyée(s) — Envoyer » reste
  affiché sur l'accueil.

## 2. Choisir un inventaire avant de saisir (comme l'ancienne version)

Le bouton d'une ligne ouvre l'écran **de l'inventaire choisi** :

- la carte **« Inventaire en cours »** : nom, référence, pourcentage, barre avec le compte
  (« 110 / 130 ») sur la même ligne, saisies sur ce téléphone, bouton **« Actualiser »** ;
- **Saisie guidée** et **Scan continu** (et « Reprendre : rayon … » après une saisie) ;
- **Écarts** : grisé avec « Pas encore d'écart » s'il n'y en a aucun ;
- **Restant à faire** : grisé avec « Super ! tout a été saisi » à 100 %.

## 3. Saisie guidée

- Le compte **« 15 / 126 »** est sur la même ligne que la barre de progression.
- **Envoi manuel** : à droite du nuage, une **icône orange (flèche d'envoi)** avec une **pastille rouge**
  qui compte les saisies non envoyées. Un toucher envoie.
- Le **bouton du filtre** est à droite du champ de saisie (bleu plein quand un filtre est actif).
- Sous le champ, une **ligne toujours réservée** : « Filtre : n° 10 à 40 · 31 produits » en bleu, avec
  **« ✕ Retirer »** ; sinon « Pas encore de filtre appliqué ». L'écran ne bouge plus quand on pose ou
  retire un filtre.
- Le **nom du produit a toujours deux lignes réservées** : un nom court ou long ne fait plus bouger
  l'écran ; Précédent, Récapitulatif et Suivant restent exactement à la même place.
- La quantité, les boutons Précédent / ☰ / Suivant et le pavé sont en bas, toujours visibles.
- Le menu **⋮** s'ouvre en bas de l'écran : Récapitulatif du rayon, Aller au produit, Voir les oublis,
  Changer de rayon, Envoyer les saisies maintenant, Écarts du rayon, Imprimer / PDF des écarts du rayon,
  Exporter le rayon, Historique des cumuls, Quitter la saisie.
- **Toutes les fenêtres** (quitter, déjà compté, grande quantité, fin de rayon, code administrateur,
  reconnexion, déconnexion…) ont le nouveau style.

## 4. Filtre du rayon

- **De ET À obligatoires** : une valeur sans l'autre est refusée ; chiffres seulement ; « De » ≤ « À » ;
  de 1 au nombre de produits. « 1 à N » (tout le rayon) = aucun filtre.
- Même règle pour l'ordre alphabétique.
- **« Effacer le filtre »** dans la fenêtre.
- **« Annuler »** remet le filtre tel qu'il était : une valeur tapée par erreur n'est plus gardée.
- Les champs n'affichent plus « Rattrapage / Oublis » : les **oublis** (produits pas encore comptés)
  sont un vrai filtre à part, par le raccourci de la fenêtre ou « Voir les oublis ».

## 5. Onglet Scanner, collecte

- **Scanner** ouvre « Scanner pour… » : **Collecte**, ou **Scan continu dans un inventaire** (liste
  déroulante, dernier inventaire présélectionné) puis **« Commencer le scan → »**.
- **Collecte**, en bas : « Que faire de cette collecte ? »
  - **Verser dans un inventaire** : choix de l'inventaire puis **Remplacer** ou **Additionner** (comme
    avant ; la question est toujours posée, Remplacer par défaut sauf si le cumul est activé) ;
  - **Créer un inventaire avec ces produits** : l'inventaire est créé, les produits reconnus y sont
    versés, et un **rapport** liste les codes non reconnus (consultable et imprimable). *Le serveur met
    dans tout nouvel inventaire tous les produits actifs de l'officine ; seuls les produits de la
    collecte y sont comptés.*

## 6. Analyse (onglet)

Choisissez l'inventaire (celui en cours est proposé), puis l'emplacement :

- **« Tous les emplacements »** (proposé d'office) : en haut l'écart total, le nombre de produits en
  écart et l'avancement ; puis chaque emplacement avec son **écart en francs** et son **nombre de
  produits en écart**. Le calcul avance emplacement par emplacement (Annuler possible, ce qui est lu
  reste affiché). Touchez une ligne pour voir l'aperçu de cet emplacement.
- **Un emplacement** : l'aperçu habituel (valeur avant / après, camembert, impression), inchangé.

## 7. Récapitulatif du rayon, réglages d'affichage

- Récapitulatif : **Tous / Déjà comptés / Pas comptés**, avec les nombres ; les produits sont numérotés ;
  toucher une ligne revient à la saisie sur ce produit.
- Nouveau réglage **« Masquer la quantité déjà comptée »** (désactivé par défaut, code administrateur) :
  la quantité déjà comptée est cachée en saisie et dans les écarts (la correction ne la pré-remplit plus),
  et retirée des PDF / CSV des écarts.
- Le réglage **« Afficher le stock théorique »** s'applique maintenant aussi aux PDF / CSV des écarts, au
  récapitulatif (écran et PDF) et à l'analyse (valeur avant).

## 8. Création d'inventaire réservée

- L'application lit le profil donné par le serveur à la connexion : **administrateur et pharmacien
  peuvent toujours créer** un inventaire.
- Les autres comptes : seulement si le réglage **« Autoriser la création d'inventaire aux autres
  comptes »** est activé (code administrateur ; désactivé par défaut). Sinon le bouton n'apparaît pas.
- Serveur plus ancien qui ne donne pas le profil : la création demande le **code administrateur** du
  terminal.
- Corrigé : un inventaire créé depuis le terminal (accueil ou collecte) apparaît tout de suite, il est
  sélectionné et visible en saisie guidée comme en scan continu.

## 9. Envoi manuel

- Si une saisie attend depuis plus longtemps que le **délai de rappel** (Réglages → Envoi), un message
  **bloquant** « **Veuillez sauvegarder vos saisies** » s'affiche, avec **« Envoyer maintenant »**. Il
  revient tant que les saisies ne sont pas parties (2 minutes après un essai qui a échoué, par exemple
  sans réseau).
- **Délai réglé à 0** : pas de message ; les saisies non envoyées partent **toutes seules toutes les
  15 minutes**.
- La progression d'envoi est nouvelle (anneau, « 31 sur 50 saisies envoyées », barre) ; « Continuer la
  saisie » ferme la fenêtre, **l'envoi continue en arrière-plan**.

## 10. Taille de l'écran (nouveau réglage)

Réglages → Réglages protégés → **Taille de l'écran : Automatique / Compact / Très compact** (code
administrateur). Pour les petits écrans comme le **Sunmi V2s** : Compact réduit toute l'interface de
10 %, Très compact de 20 % (fenêtres et menus compris), dans les deux interfaces. Appliqué au prochain
lancement, ou tout de suite avec **« Relancer maintenant »** (retour à l'accueil, rien n'est perdu).

## 11. Corrections

- Le **clavier du téléphone s'ouvre** quand on touche l'icône clavier du champ de scan (saisie guidée,
  scan continu, collecte, écarts, restants ; aussi dans les écrans d'origine qui utilisent le même champ).
- La fenêtre de quantité de la collecte remonte au-dessus du clavier du téléphone s'il est ouvert.

## Ce qui ne change pas

Mêmes routes du serveur, mêmes règles : un serveur injoignable n'est jamais pris pour une absence de
licence ; session expirée → « Se reconnecter » sans quitter l'écran ; toute saisie est gardée sur le
terminal avant d'être envoyée. Écrans d'origine strictement inchangés (fenêtres comprises).
