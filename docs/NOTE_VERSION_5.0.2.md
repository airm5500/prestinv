# Prestige Inventaire V3 5.0.2+24 : titre de connexion sur une ligne ; serveur éteint pendant l'inventaire

Deux corrections demandées par le pharmacien après la 5.0.1+23. Même application (`com.dici.prestigeinventaire.v3`),
même nom sur le lanceur (« Prestige Inventaire V3 », `android:label` inchangé), même icône.

## 1. Écran de connexion : « Prestige Inventaire v3 » sur une seule ligne

Avant : le titre « Prestige Inventaire V3 » (22 à 36 points selon l'écran) passait sur deux lignes sur un terminal
Sunmi (360 dp de large) et sur les petits écrans.

5.0.2 :

- Les écrans de **lancement** et de **connexion** (nouvelle interface et interface d'origine) affichent
  **« Prestige Inventaire v3 »** (v minuscule), constante `titreConnexion` (`lib/identite_appli.dart`).
- Taille réduite (18 sur la connexion de la nouvelle interface, 22 au lancement, 26 sur la connexion d'origine) et
  **une seule ligne** dans tous les cas (`TexteUneLigne` : `maxLines: 1`, `softWrap: false`, et réduction
  proportionnelle `FittedBox(fit: BoxFit.scaleDown)` si la largeur manque : écran de 320 dp, police d'Android
  agrandie). Jamais de retour à la ligne, jamais de débordement, jamais sous le bouton « Configuration ».
- **Inchangés** : le nom du lanceur Android (`android:label` « Prestige Inventaire V3 », vérifié par la CI),
  l'identifiant `com.dici.prestigeinventaire.v3`, la constante `nomAppli` (« Prestige Inventaire V3 » : accueil,
  inventaire, licence, menu, permission de l'appareil photo, titre de la tâche Android).

Contrôlé sur écran de 320 dp, Sunmi V2s (360 dp), Sunmi V3 / V3H / V3mix (360 dp), téléphone 360 × 640 dp et
tablette 1920 × 1200, texte × 1,0 et × 1,3 (`test/ergonomie/titre_connexion_test.dart`).

## 2. Serveur éteint pendant l'inventaire : les saisies restent sur le terminal et partent seules au retour

Les quantités saisies sont toujours écrites sur le terminal avant tout envoi (`saisies_v1.jsonl`). Trou constaté :
une réponse **500** du serveur (Payara qui s'arrête) était comptée comme un refus après 3 essais : la saisie passait
en « refusée », la relance automatique s'arrêtait, et il fallait la renvoyer à la main depuis « À envoyer ».

5.0.2 (`lib/saisie/saisie_queue.dart`, `lib/api/api_service.dart`, `lib/collecte/versement.dart`) :

- **Serveur éteint, injoignable ou en erreur** : 500 et autres 5xx, 502 / 503 / 504, délai dépassé, connexion
  refusée ou coupée, relais (407), 408, 425, 429 : la saisie **reste « en attente »** dans la file locale, quel que
  soit le nombre d'essais. Elle n'est jamais « refusée » pour cette raison.
- **Relance automatique espacée** tant que le serveur ne répond pas : 15 s, 30 s, 1 min, puis toutes les 2 min au
  plus. Toute réponse du serveur remet l'espacement à zéro : l'envoi reprend **seul** au retour du serveur (au plus
  2 min après), dans l'**ordre de saisie**, **sans doublon** (le serveur reçoit la quantité totale, une seule requête
  par ligne à la fois, dernière valeur gagnante).
- Une erreur 500 isolée sur une ligne ne bloque pas les suivantes ; deux erreurs de suite interrompent l'envoi (le
  serveur s'arrête : on n'insiste pas), repris plus tard.
- **Mode Collecte (envoi manuel)** inchangé : rien ne part sans « Envoyer ». Un envoi demandé puis interrompu par la
  panne reprend seul au retour du serveur (comme après une session expirée).
- **Refus métier** du serveur (4xx explicite avec message : 400, 404 JSON « ligne inconnue », 409, 422, inventaire
  clôturé) : « refusée » tout de suite, visible dans « À envoyer », comme avant. 401 / 403 : reconnexion, comme avant.
- Saisies déjà passées en « refusée » par une erreur du serveur avec une version précédente : remises en attente au
  premier lancement de la 5.0.2 (aucune perte).
- Versement de la collecte : une erreur 500 interrompt le versement comme une coupure (la quantité reste dans la
  file et part seule), au lieu de marquer la ligne en erreur.
- **Bandeau non bloquant**, dans les deux interfaces (sous l'en-tête des écrans de la nouvelle interface, en haut de
  la saisie d'origine) : **« N saisies en attente d'envoi (serveur injoignable) »**. Aucune fenêtre : la saisie
  continue normalement. Le bandeau disparaît dès que le serveur a reçu les saisies.

## 3. Contrôles

- `test/ergonomie/titre_connexion_test.dart` (nouveau) : trois écrans × cinq largeurs (320 dp à tablette) × texte
  × 1,0 / × 1,3 : une seule ligne, dans l'écran, lisible, sans erreur de rendu.
- `test/reseau/serveur_eteint_file_test.dart` (nouveau, vrai serveur HTTP local) : 500 × 6, 501, 502, 503, 504, 407,
  408, 429, coupure, délai dépassé, serveur arrêté puis redémarré, redémarrage de l'application pendant la panne,
  relances espacées, mode Collecte, refus métier 400 / 404 / 409 / 422 gardés, anciennes saisies « refusées » par un
  500 remises en attente ; ordre conservé, aucun doublon.
- `test/e2e/serveur_eteint_test.dart` (nouveau, application entière, deux interfaces) : 500 puis PC éteint pendant
  la saisie guidée ; bandeau, saisie qui continue, envoi automatique au retour.
- `test/saisie_file_test.dart` : le test « 5xx → refusée après 3 échecs » décrivait le défaut corrigé ; il vérifie
  désormais que la saisie reste en attente et part au retour du serveur.
- `test/e2e/v3_premier_lancement_test.dart` : la connexion affiche `titreConnexion`.
- `test/non_regression/v3_identite_test.dart`, `version_gradle_test.dart` : version 5.0.2+24, titre de connexion,
  `android:label` inchangé, cette note.

Version **5.0.2+24** (`pubspec.yaml`) ; voir `docs/VERSIONS_SUNMI.md`.
