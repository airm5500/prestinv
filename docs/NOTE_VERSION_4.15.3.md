# Prestige Inventaire 4.15.3 (code 17) — Note de version

*Pour le pharmacien et l'équipe qui compte.*

Elle s'installe par-dessus la 4.15.2 sans désinstaller ; rien n'est perdu (réglages, saisies en attente,
collecte, rapports de versement, versement interrompu à reprendre).

## 1. Deux messages distincts quand le serveur ne répond pas

**Votre retour** : distinguer « je suis sur le Wi-Fi et le serveur est injoignable » de « le serveur répond
mais Prestige n'est pas déployé ».

Désormais, dans les **deux interfaces**, à la **connexion**, au **lancement** et au **chargement des listes** :

| Situation | Message |
|---|---|
| Aucune réponse : délai dépassé, Wi-Fi ou réseau absent, PC serveur éteint, Payara arrêté (connexion refusée) | **« Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé. »** |
| Le serveur répond, mais Prestige n'est pas déployé : page « 404 » de Payara, 502, 503, 504 | **« Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant. »** |

Au lancement, l'écran porte le titre correspondant (« Serveur injoignable » ou « Serveur indisponible ») ;
votre licence n'est jamais mise en cause. Ne changent pas : « Identifiant ou mot de passe incorrect. »,
« Erreur serveur (500) » et les refus de Prestige lui-même (par exemple « Cette ligne n'existe plus dans
l'inventaire »).

## 2. Pendant un redéploiement, l'application ne se croit plus sur un « ancien serveur »

Avant : pendant un redéploiement, une route nouvelle (état des rayons, versement en lot, ajout des produits
d'un inventaire de collecte) répondait « 404 » et l'application concluait à un serveur ancien : elle passait
à l'ancienne méthode jusqu'au prochain lancement (ou, pour la création depuis la collecte, refusait avec le
message « serveur ancien »).

Désormais, **seulement après un tel 404** (aucune requête de plus en fonctionnement normal), l'application
vérifie que Prestige répond (lecture légère de la licence, déjà faite au lancement) :

- Prestige ne répond pas → **« Serveur indisponible… »** : rien n'est conclu ; le versement est interrompu,
  ce qui est préparé est gardé sur le terminal et repris ensuite **sans jamais compter deux fois** ; la
  création depuis la collecte peut être retentée ;
- Prestige répond → c'est bien un serveur qui n'a pas la route : ancien chemin (ou refus de la création
  depuis la collecte), comme en 4.15.1.

## 3. Inchangé (en attente de votre réponse)

Le message « Position N : nom » de la saisie guidée et l'aide « Additionnée si le code est déjà dans la
liste » de la collecte sont gardés.

## Tests

`test/integration/serveur_indisponible_test.dart` (deux cas, délai dépassé, redéploiement pendant l'état des
rayons, le versement en lot et la création depuis la collecte ; aucune vérification en fonctionnement
normal) et `test/e2e/serveur_indisponible_test.dart` (deux interfaces : connexion et lancement dans les deux
cas). Toutes les catégories rejouées (unitaires, intégration, bout en bout, ergonomie, performance, réseau).
