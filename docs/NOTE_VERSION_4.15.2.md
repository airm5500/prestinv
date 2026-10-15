# Prestige Inventaire 4.15.2 (code 16) — Note de version

*Pour le pharmacien et l'équipe qui compte.*

Elle s'installe par-dessus la 4.15.1 sans désinstaller ; rien n'est perdu (réglages, saisies en attente,
collecte, rapports de versement).

## 1. Saisie guidée : le nom du produit n'est plus répété dans le champ de quantité

**Votre retour** : « Pourquoi dans le champ de saisie je vois une répétition du nom du produit ? On ne peut
pas avoir le nom en haut et encore un nom dans le champ de saisie. »

**Origine** : ce rappel n'avait pas été demandé. Il a été ajouté le 13/10 (version 4.13, correction de
l'anomalie A5 : sur les écrans de 640 dp de haut et en texte agrandi, la quantité tapée était cachée
derrière le pavé). En épinglant la quantité au-dessus du pavé, un « rappel compact » du nom y avait été
ajouté par précaution, au cas où la carte produit sortirait de l'écran. Ce cas ne se produit pas : depuis
la 4.13.1 (taille Compact appliquée d'office aux petits écrans), la carte produit est entière.

**Désormais** : le champ « Quantité comptée » n'affiche que son libellé, l'état du produit précédent et la
**quantité tapée**, en grand. Le nom n'est qu'en haut, dans la carte produit. Vérifié sur Sunmi V2s, V3 /
V3H / V3mix, téléphone 360×640 et tablette, texte normal et agrandi (×1,3), aux trois tailles d'écran, avec
un nom court et un nom long : le nom est entier et visible sans faire défiler, et la quantité reste
au-dessus du pavé.

## 2. Prestige en cours de redéploiement : « Serveur indisponible, veuillez réessayer »

**Votre retour** : pendant le redéploiement de Prestige, la connexion affichait « erreur 404 ».

**Désormais**, dans les deux interfaces, à la connexion, au lancement et au chargement des listes :
« **Serveur indisponible, veuillez réessayer.** » quand Prestige ne répond pas (redéploiement : 404 sans
réponse de Prestige ; 502, 503, 504 ; serveur arrêté, connexion refusée). Au lancement, l'écran s'intitule
« Serveur indisponible » (votre licence n'est pas en cause, jamais « aucune licence »).

Ne changent pas : « Identifiant ou mot de passe incorrect. » (mauvais mot de passe), « Erreur serveur
(500) », et les refus de Prestige lui-même (par exemple « Cette ligne n'existe plus dans l'inventaire »).

**Correction liée** : une quantité envoyée pendant le redéploiement était classée « refusée » (code 404) ;
elle reste désormais **en attente** sur le terminal et part automatiquement quand Prestige est revenu.

## Tests

Nouveaux : `test/ergonomie/nom_produit_visible_test.dart` (48 configurations),
`test/integration/serveur_indisponible_test.dart`, `test/e2e/serveur_indisponible_test.dart` (deux
interfaces). Toutes les catégories rejouées (unitaires, intégration, bout en bout, ergonomie, performance,
réseau).
