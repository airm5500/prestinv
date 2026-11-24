# Prestige Inventaire V3 5.0.4+26 : heure du serveur fausse (refus 423) — saisies gardées, message du serveur

Adaptation au serveur Prestige du 24/11 (branche `plan/24112026`, lu en lecture seule). Même application
(`com.dici.prestigeinventaire.v3`), même nom sur le lanceur (« Prestige Inventaire V3 »), même icône, mêmes écrans.

## 1. Le nouveau refus du serveur

Quand l'heure du serveur est fausse, le serveur refuse **toute écriture** (POST / PUT / DELETE / PATCH, sauf la
connexion, la déconnexion et les routes de l'horloge) avec **HTTP 423** et le corps :

```json
{"success": false, "horlogeBloquee": true, "msg": "Opération refusée : l'heure du serveur est fausse. ..."}
```

Les lectures (GET) restent permises. Rien n'est enregistré. Seuls l'administrateur ou la tâche Windows du serveur
remettent l'heure : l'application ne propose aucun contournement.

Jusqu'à la 5.0.3, ce 423 était lu comme un refus 4xx en JSON : la saisie passait en **« refusée »** (jamais renvoyée
seule, à renvoyer à la main dans « À envoyer »).

## 2. Ce qui change (`lib/api/api_service.dart`, `lib/saisie/saisie_queue.dart`)

- Nouveau résultat d'envoi `ResultatEnvoi.horlogeBloquee` (HTTP 423 ; message = `msg` du serveur, tel quel ; 423 sans
  corps lisible : « Opération refusée par le serveur (code 423). »).
- **File des saisies** (`PUT /ws/inventaires/details`, et `POST /inventaire/ligne/quantite` pour le versement de la
  collecte) : la saisie **reste « en attente »** (jamais « refusée », jamais perdue : fichier `saisies_v1.jsonl`
  compris) ; son motif dans « À envoyer » est le message du serveur (« En attente (Opération refusée : l'heure du
  serveur est fausse. …) ») ; un envoi groupé s'arrête au premier refus (inutile d'envoyer les suivantes) ; **pas de
  boucle** : relances automatiques espacées comme pour un serveur éteint (15 s, 30 s, 1 min, puis 2 min au plus) ;
  quand l'heure est remise, envoi **seul**, dans l'ordre de saisie, **sans doublon** (quantité totale) ; un envoi
  demandé (mode Collecte : « Envoyer ») interrompu ainsi reprend seul. La route avec auteur refusée ainsi n'est pas
  prise pour une route absente (pas de repli sur `PUT`).
- **Bandeau non bloquant** (deux interfaces) : « 1 saisie en attente d'envoi. » ou « N saisies en attente d'envoi. »
  suivi du message du serveur, tel quel — à la place de « (serveur injoignable) ».
- Mode Direct (saisie guidée, saisie rapide) : le message du serveur s'affiche tel quel (avant : « Non envoyé
  (réseau) … » ou « refusée »). Corrections Écarts / Restants : « <message du serveur> Gardée sur l'appareil (voir
  « À envoyer »). ».
- **Versement en lot** (`POST /inventaire/{id}/versement`) : `IssueVersementLot.horlogeBloquee` ; rien n'est
  enregistré, le lot est **gardé avec la même clé** et le même contenu (« Reprendre le versement » : jamais compté deux
  fois) ; versement interrompu avec le message du serveur.
- **Création d'inventaire**, **produits retenus** (inventaire limité aux produits scannés), **licence** : message du
  serveur tel quel.
- Saisies classées « refusée » par ce refus en 5.0.3 : remises en attente au chargement (envoyées seules ensuite).
- Journal (versions de développement seulement) : « refusé (423, heure du serveur fausse) », jamais le message, une
  quantité ni un code scanné.

## 3. Écran de connexion : `GET /api/v1/horloge/public`

Le serveur à jour répond **sans session** : `{"etat": "OK" | "BLOQUE" | "REGULARISATION", "serveur": "24/11/2026 20:52"}`.
Une seule lecture à l'affichage de l'écran de connexion (et au changement d'adresse, Local / Distant), jamais de
relance :

- **BLOQUE** : bandeau d'information « L'heure du serveur est fausse (heure du serveur : 24/11/2026 20:52) : le serveur
  refuse les enregistrements tant qu'elle n'est pas remise. Les saisies restent gardées sur l'appareil. » ; la
  connexion reste possible ;
- **OK**, **REGULARISATION** (écritures permises) : rien ;
- ancien serveur (**404**), autre réponse, page HTML, serveur injoignable, délai dépassé : rien.

## 4. Routes du serveur concernées

Écritures de l'application : `PUT ws/inventaires/details`, `POST inventaire/ligne/quantite`,
`POST inventaire/{id}/versement`, `POST inventaire/creation`, `POST inventaire/lignes/retenue`, `POST licence/save/…` ;
connexion / déconnexion (`user/auth`, `user/logout`) jamais refusées. Les routes `vente/update-created-date`,
`reglement/reglementdiffere(-all)`, `vente/rappel/{id}`, `ventestats/remove/{id}` et `ventestats/update/{id}/is_Trash`
ne sont pas utilisées par l'application.

## 5. Tests

`test/reseau/horloge_bloquee_test.dart` (vrai serveur HTTP local, données fictives : 423 sur chaque type d'écriture,
file conservée puis rejouée sans doublon, redémarrage pendant le blocage, pas de boucle, mode Collecte, lot gardé avec
la même clé, saisie « refusée » en 5.0.3 remise en attente, `horloge/public` BLOQUE / OK / REGULARISATION / 404 /
autres) ; `test/e2e/horloge_bloquee_test.dart` (application entière, deux interfaces : bandeau avec le message, envoi
au retour de l'heure, bandeau de connexion) ; non-régression `v3_identite_test`, `version_gradle_test` (5.0.4+26).

Performance : le plafond de requêtes au démarrage (jusqu'à l'écran de connexion) passe de 1 à 2 (`Seuils.demarrageRequetes`) :
la licence et la lecture unique de `horloge/public` ; `test/performance/requetes_test.dart` vérifie qu'il n'y a rien d'autre.
Aucun autre plafond ne change.
