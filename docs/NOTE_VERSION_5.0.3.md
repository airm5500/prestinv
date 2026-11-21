# Prestige Inventaire V3 5.0.3+25 : une réponse qui n'est pas celle de Prestige n'est plus un envoi réussi

Correction d'un défaut constaté lors de la 5.0.2+24. Même application (`com.dici.prestigeinventaire.v3`), même nom
sur le lanceur (« Prestige Inventaire V3 »), même icône, mêmes écrans.

## 1. Le défaut

Les quantités saisies sont écrites sur le terminal avant tout envoi (`saisies_v1.jsonl`), puis envoyées au serveur
par la file des saisies (`PUT /api/v1/ws/inventaires/details`, quantité totale). Jusqu'à la 5.0.2, **toute réponse
2xx** comptait comme un envoi réussi, même quand ce n'était pas le serveur Prestige qui répondait : page HTML d'un
**portail captif** (Wi-Fi d'invités), d'un relais, d'une box, d'un autre service installé à la même adresse. La
saisie passait alors en « envoyée » et sortait de la file alors qu'elle n'était jamais arrivée : **perte silencieuse**.

## 2. La correction (`lib/api/api_service.dart`)

Un envoi n'est « réussi » que si la réponse est **celle du serveur Prestige** pour cette route (vérifié dans le code
du serveur, lecture seule) :

- `PUT /ws/inventaires/details` : Prestige répond **200 sans corps** (`ErpRessource.updateDetailQuantity`,
  `Response.ok().build()`). Sont reconnus : 200 ou **204** sans corps (sauf s'il est annoncé comme une page HTML), et
  un JSON `{success:1}` (avec `id` / `quantite` égaux à ceux envoyés s'ils sont présents, pour un serveur qui
  confirmerait un jour en JSON).
- `POST /inventaire/ligne/quantite` (versement de la collecte, auteur enregistré) : Prestige répond
  `{"success":1,"int_NUMBER":q}` ; `int_NUMBER` doit être la quantité envoyée.
- `POST /inventaire/{id}/versement` (versement en lot) : `success:1` et une entrée `{index, statut}` par ligne ;
  ses refus (400, 409, 410, 413) sont en JSON avec un `code`.

Tout le reste est une **réponse non reconnue**, classée comme un **serveur injoignable** (même classement que le
serveur éteint, un délai dépassé ou une erreur 5xx en 5.0.2) : page **HTML** (type annoncé ou corps qui commence par
« < »), texte, JSON d'un autre service (objet sans `success`, liste, autre ligne, autre quantité), 2xx inattendu
(201 vide…), **redirection 302 / 303** vers une page de connexion, refus 4xx sous forme de page HTML. La saisie
**reste « en attente »** (jamais « envoyée », jamais « refusée »), relance automatique avec l'espacement existant
(15 s, 30 s, 1 min, 2 min au plus), envoi seul au retour du vrai serveur, dans l'ordre de saisie, **sans doublon**,
bandeau non bloquant **« N saisies en attente d'envoi (serveur injoignable) »**. Mode Collecte (envoi manuel)
inchangé : rien ne part sans « Envoyer » ; un envoi demandé interrompu ainsi reprend seul.

Inchangés : un JSON `success:false` / `success:0` avec un message métier → « refusée » (route avec auteur, comme
avant ; même règle sur la route habituelle) ; « Veuillez vous connecter » → reconnexion ; refus 4xx en JSON (400,
404 « ligne inconnue », 409, 422) → « refusée » ; 401 / 403 → reconnexion ; 5xx, 502 / 503 / 504, 407 / 408 / 425 /
429 → gardée (5.0.2).

Versement en lot : une réponse non reconnue garde le lot **avec sa clé** (reprise à l'identique : le serveur ne le
compte jamais deux fois) ; avant, une page HTML en 400 renvoyait vers l'ancien chemin et une page en 409 / 410 était
prise pour « clé déjà utilisée » / « inventaire introuvable ».

Lectures (listes, recherches, contrôle « déjà compté », licence, état des rayons, liste des inventaires ouverts) :
une page HTML n'est **jamais** une liste vide ni des données ; c'est une erreur (« réponse non reconnue », classée
comme avant « données illisibles » pour les listes) : aucun cache local effacé, aucun inventaire pris pour
« clôturé » (liste des inventaires ouverts : « inconnue », saisie gardée, bandeau « serveur injoignable ») ; pour la
licence, « serveur injoignable » : elle n'est pas mise en cause (avant : « aucune licence enregistrée »).

## 3. Doublons

Le renvoi après une réponse douteuse reste sans effet double : le serveur reçoit la **quantité totale** (`quantite =
X`, jamais « + X ») sur les deux routes de saisie (`TInventaireFamille.setIntNUMBER`), une seule requête en vol par
ligne, dernière valeur gagnante ; le versement en lot garde sa clé anti-doublon (`dejaTraite`). Seul cas que
l'application ne peut pas distinguer : un intermédiaire qui répondrait **200 sans corps et sans type HTML**, exactement
comme Prestige. Une demande au serveur est faite pour que la route confirme en JSON (voir la transmission du
21/11/2026).

## 4. Journal

Le journal de mise au point (versions de développement seulement) n'écrit que **« réponse non reconnue (code, type,
taille) »**, par exemple `PUT ws/inventaires/details : réponse non reconnue (200, text/html, 1532 octets)` : jamais
le contenu de la page reçue, ni l'adresse de la redirection, ni un scan GS1 brut. Le message gardé avec la saisie est
du même type (code, type, taille).

## 5. Contrôles

- `test/reseau/reponse_non_reconnue_test.dart` (nouveau, vrai serveur HTTP local) : 200 HTML (avec et sans type
  annoncé, vide annoncé HTML), 200 texte, 200 JSON inattendu (objet, liste, autre ligne, autre quantité), 302 vers
  une page de connexion, 400 HTML, 201 vide → gardée, puis retour du vrai serveur : file vidée dans l'ordre, sans
  doublon (aussi après redémarrage, et avec le vrai fichier `saisies_v1.jsonl`) ; 200 vide, 204, JSON correct →
  envoyée ; `success:false` → refusée / reconnexion ; route avec auteur ; versement en lot (même clé, `dejaTraite`) ;
  lectures ; mode Collecte ; journal sans contenu.
- `test/e2e/portail_captif_test.dart` (nouveau, application entière, deux interfaces) : page HTML puis 302 pendant
  la saisie guidée ; bandeau, saisie qui continue, envoi automatique au retour.
- `test/non_regression/v3_identite_test.dart`, `version_gradle_test.dart` : version 5.0.3+25, cette note.

Version **5.0.3+25** (`pubspec.yaml`) ; voir `docs/VERSIONS_SUNMI.md`.
