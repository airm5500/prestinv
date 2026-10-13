# Prestige Inventaire 4.12.0 — Note de version « Nouvelle interface »

*Pour le pharmacien et l'équipe qui compte. L'application s'affiche avec une nouvelle présentation,
aux couleurs communes des applications Prestige (bleu nuit et ambre), pensée pour le terminal Sunmi,
le téléphone et la tablette. Depuis la 4.12.0, c'est la **présentation par défaut** ; les écrans
d'origine restent disponibles à tout moment depuis les Réglages (code administrateur).*

Version : **4.12.0** (code 8). Elle s'installe par-dessus la 4.11.0, la 4.10.0 (ou plus ancienne) sans
désinstaller. Rien n'est perdu : réglages, saisies en attente, collecte et rapports sont repris tels quels.

### Nouveau en 4.12.0

- **La nouvelle interface s'affiche par défaut** : sur les nouvelles installations, et sur les
  terminaux mis à jour où personne n'avait encore fait de choix (cas de la 4.11.0, où elle était
  seulement proposée).
- **Votre choix est respecté** : un terminal sur lequel les écrans d'origine avaient été choisis
  (interrupteur désactivé avec le code administrateur) les garde après la mise à jour.
- **Accueil : « Actualiser l'avancement »** sur la carte de l'inventaire en cours (voir § 5.4).

Historique : 4.11.0 (code 7) — nouvelle interface proposée, désactivée par défaut.

Aperçus réels (polices et couleurs de l'application) : `docs/maquettes/apercus/refonte_*.png`, et la
planche avant / après `refonte_0_avant_apres.png`.

---

## 1. La nouvelle interface, par défaut

Rien à faire : après installation ou mise à jour en 4.12.0, la nouvelle présentation s'affiche dès
l'écran de connexion — sauf sur un terminal où les écrans d'origine avaient été **choisis** (voir § 2),
qui les garde.

Le choix est gardé sur l'appareil : chaque terminal peut rester sur les écrans d'origine ou passer à
la nouvelle interface à son rythme.

## 2. Revenir aux écrans d'origine (et inversement)

À tout moment, sans réinstaller et sans rien perdre :

1. Barre du bas → **Réglages** (sur tablette : **Réglages** dans le menu de gauche).
2. Rubrique **Interface** → désactivez **« Nouvelle interface »** → **code administrateur** (le même
   que pour modifier l'adresse du serveur).
3. Revenez à l'accueil : les écrans d'origine reviennent, exactement comme avant. Ce choix est
   mémorisé : il est conservé aux redémarrages et aux mises à jour suivantes.

Pour revenir à la nouvelle interface depuis les écrans d'origine : **Configuration** (roue dentée en
haut de l'accueil, ou sur l'écran de connexion) → **« Nouvelle interface (désactivée) »** → activer →
code administrateur.

Les saisies faites dans l'une ou l'autre présentation sont les **mêmes** : une saisie commencée dans la
nouvelle interface se retrouve dans « À envoyer » de l'ancienne, et inversement.

Si un problème grave était constaté sur tout le parc, l'informaticien peut aussi reconstruire la
version précédente (balise `prestinv-avant-refonte`, voir `docs/BALISES.md`) : les données gardent les
mêmes emplacements, rien n'est perdu.

## 3. Ce qui change à l'écran (nouvelle interface)

| Écran | Ce que vous voyez |
|---|---|
| **Accueil** | L'inventaire **en cours** en tête (saisies sur ce téléphone, envoyées, rayons terminés dès qu'ils ont été consultés), **« N saisies pas encore envoyées » avec Envoyer**, un grand bouton ambre **« Reprendre : rayon … »** au dernier rayon ouvert, puis Saisie guidée, Scan continu, Écarts, Restants, Collecte. Les autres inventaires ouverts sont listés dessous : touchez-en un pour le choisir. **Nouveau** crée un inventaire. Barre du bas : Accueil · Scanner · Écarts · Réglages. |
| **Choisir un rayon** | Chaque rayon avec son état (**pas commencé / commencé / terminé**, avec un symbole, jamais la couleur seule) et ses saisies en attente d'envoi ; filtres Tous / À faire / En cours / Terminés ; recherche. |
| **Saisie guidée** | En-tête « rayon — Produit 39 / 52 » avec barre d'avancement ; cadre vert « Scanner prêt » ; fiche produit (stock théorique si autorisé, déjà compté, prix d'achat) ; grand chiffre ; **état d'envoi du produit précédent** ; Précédent / Aller au produit / Suivant ; pavé avec **OK ambre**. Filtres, oublis, récapitulatif, écarts du rayon, export CSV et historique des cumuls sont dans le menu ⋮. |
| **Scan continu** | Cadre vert « Scannez le produit suivant », bandeau **« N en attente · M envoyées » avec Envoyer**, et le **journal des dernières saisies** avec leur état (**en attente, envoi…, envoyé ✓, erreur, à vérifier** pour un code inconnu). Toucher une ligne la corrige. |
| **Quantité après un scan** | Feuille en bas de l'écran : produit, CIP, rayon, prix ; si le produit est **déjà compté** : « Déjà compté : 6. Vous saisissez 4. » et deux boutons **Remplacer → 4 / Ajouter → 10** ; −1 / +1 ; pavé. |
| **Écarts** | Chiffres clés en haut (**manquants et surplus en F CFA**, « à vérifier 29 / 37 »), liste **triée par valeur** (écart × prix d'achat), bande **rouge / verte et signe** ; filtres Par valeur / Manquants / Surplus / Rayon. Correction : théorique, compté, nouveau, écart **en direct**, quantité pré-remplie (remplacée à la première touche), **Précédent · Garder · Suivant**, touche **Corriger**. Impression PDF. |
| **Restants** | Liste des produits jamais comptés, filtre emplacement et stock théorique, scan ; saisie au pavé. |
| **À envoyer** | Saisies non confirmées par inventaire, avec leur état et le motif d'un refus ; Envoyer maintenant. |
| **Collecte hors ligne** | Scan, quantité au pavé, liste, **Verser dans un inventaire**, rapports, CSV, impression ; versement : choix Remplacer / Ajouter en cartes, progression, rapport. |
| **Serveur injoignable** | Message clair (« votre licence n'est pas en cause »), Réessayer, **Passer en Distant / en Local** si l'autre adresse est renseignée, saisies en attente rappelées, collecte hors ligne accessible. |
| **Réglages** | Les mêmes réglages, rangés par rubriques (connexion au serveur sous code, inventaire, envoi, session, **scan et sons** sur sa propre page, interface). |
| **Tablette** (grand écran) | Menu bleu à gauche ; écarts en **tableau** avec le bilan en valeur et la correction à droite ; listes sur deux ou trois colonnes. |
| **Thème sombre** | Réglages → Interface → Apparence : comme le téléphone, clair ou sombre. |

Partout : boutons d'au moins 48 dp (utilisables au doigt et avec des gants fins), contrastes renforcés,
lecture par TalkBack (libellés sur les boutons, les états et les chiffres), et **la douchette reste
toujours prête** comme en 4.10 (focus gardé après OK, après une fenêtre, après une erreur ; scans en
rafale sans perte ; touches latérales Sunmi).

## 4. Ce qui ne change pas

- Les **données** : même file des saisies (enregistrée sur le téléphone avant tout envoi), mêmes envois
  (Direct ou Collecte), mêmes contrôles (0 à 99 999, champ vide refusé, seuil « grande quantité »,
  « déjà compté » vérifié auprès du serveur, jamais d'écrasement silencieux).
- Les **réglages** et le **code administrateur**.
- Le **serveur** : aucune modification, aucune nouvelle requête.
- Les **écrans d'origine** : identiques quand l'interrupteur est désactivé.

## 5. Petites différences de comportement (nouvelle interface seulement)

1. **Produit déjà compté** : la question « Remplacer ou Ajouter » se ferme par **Annuler** (rien n'est
   enregistré). Dans les écrans d'origine, toucher à côté de la fenêtre revenait à **remplacer**.
2. **Boutons Remplacer / Ajouter sur la feuille de quantité** : si la vérification auprès du serveur
   trouve une autre quantité que celle affichée (un collègue vient de compter), la question est reposée
   avec la bonne valeur.
3. **Écarts de tout l'inventaire** : impression PDF et export CSV ajoutés (ils n'existaient que pour un
   rayon) ; la quantité recomptée est **pré-remplie** avec la quantité comptée (« Garder » la confirme).
4. **Accueil — avancement** : sur la carte de l'inventaire en cours, le bouton **« Actualiser
   l'avancement »** calcule l'état de tous les rayons **quand vous le demandez** (mêmes requêtes que
   « Choisir un rayon ») : progression « Rayon 3/12 », bouton **Annuler**, un seul calcul à la fois
   (un double appui ne relance rien), motif clair en cas d'échec (serveur injoignable, session expirée
   avec « Se reconnecter ») sans effacer le dernier avancement connu. Le résultat est gardé sur le
   terminal avec son heure (« Avancement à 10:42 »). Il n'est **jamais recalculé automatiquement**
   (deux requêtes par rayon aujourd'hui : voir la demande au serveur `docs/DEMANDE_SERVEUR_COMPTAGE.md`).
   Sans calcul demandé, l'avancement affiché reste celui lu à l'ouverture de « Choisir un rayon ».
5. L'**inventaire en cours** choisi sur l'accueil est mémorisé sur le terminal.

## 6. Pour l'informaticien

- Code : `lib/ui/` (thème, composants, écrans), aiguillages `HomeScreen` / `LoginScreen`,
  `lib/interface_version.dart`. Les écrans d'origine (`lib/screens/`) ne sont pas modifiés, hormis le
  renommage des deux classes aiguillées et l'ajout de l'interrupteur dans leur Configuration.
- **Valeur par défaut (4.12.0)** : `InterfaceVersion.parDefaut = true`. Préférence
  `interface_nouvelle_version_v1` : absente → nouvelle interface ; `false` (choix explicite, écrit
  uniquement par l'interrupteur après le code administrateur) → écrans d'origine ; `true` → nouvelle.
  Imposer les écrans d'origine à tout un parc : écrire `false` dans cette préférence (ou désactiver
  l'interrupteur sur chaque terminal).
- **Avancement à la demande** : `lib/ui/avancement.dart` (mêmes requêtes que « Choisir un rayon »,
  résultat gardé sous `nv_avancement_v1_<inventaire>`).
- Tests (CI) : `test/nv_*.dart` — rendu sans débordement de chaque écran en 360 × 640, 360 × 800,
  tablette portrait et paysage, clair et sombre ; logique branchée sur la même file des saisies ;
  focus de la douchette ; interrupteur (valeur par défaut, choix explicite respecté, code
  administrateur) ; avancement à la demande (`test/nv_avancement_test.dart`).
- **Tests d'origine** (164, antérieurs à la refonte) : ils passent tous. Ils vérifient les écrans
  d'origine, atteints par les aiguillages : `test/flutter_test_config.dart` les place avant chaque test
  dans la situation « ancienne interface choisie » (sans cela, deux d'entre eux — accueil
  d'`a_envoyer_test` et `licence_lancement_test` — afficheraient la nouvelle interface, désormais par
  défaut). Leurs assertions ne changent pas, à une exception voulue : `test/interface_version_test.dart`
  vérifie la valeur par défaut de l'interrupteur, qui passe d'« éteint » à « allumé ».
- Aperçus (hors CI) : `flutter test test_apercus/refonte_apercus_test.dart --update-goldens`. Polices
  Roboto et icônes Material du SDK Flutter (chargées sans réseau). Sur la planche avant / après, les
  libellés des grands boutons de l'**accueil d'origine** apparaissent en rectangles : leur style ne
  précise pas de police et le moteur de test, contrairement à Android (Roboto), n'en a pas par défaut.
- Version : `pubspec.yaml` 4.12.0+8 ; balises de retour : `prestinv-avant-defaut-nouvelle` (4.11.0+7,
  nouvelle interface proposée mais désactivée par défaut) et `prestinv-avant-refonte` (4.10.0+6).
