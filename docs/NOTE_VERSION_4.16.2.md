# Prestige Inventaire 4.16.2 (code 20) — Auteur des saisies dans l'historique

*Pour le pharmacien et l'équipe qui compte.*

Elle s'installe par-dessus la 4.16.1 sans désinstaller ; rien n'est perdu.

## Historique des cumuls : qui avait compté

**Votre décision** : afficher l'auteur des saisies aussi dans l'historique.

L'**historique des cumuls** (produit déjà compté → « Ajouter ») rappelle désormais qui avait compté la quantité
« avant » : « CIP … · ANTIBIOTIQUES · 10:42 · **déjà compté par Awa Kouassi** ». C'est le nom donné par le serveur
Prestige (à défaut, l'identifiant de connexion), ajouté **sur la ligne d'informations existante** : aucune place en
plus. Nouvelle interface (Saisie guidée ou Scan continu › menu › Historique des cumuls) **et** ancienne interface
(bouton « Historique des cumuls » de la saisie).

Avec un serveur Prestige plus ancien, qui ne donne pas l'auteur, rien ne change. Les rapports PDF des cumuls sont
inchangés. Rappel : depuis la 4.16.1, la correction des écarts (nouvelle interface) affiche aussi « compté par … ».

## Tests

`test/nv_accueil_ecrans_test.dart` (deux interfaces ; nom, identifiant à défaut, rien sans auteur). Toutes les
catégories rejouées comme la CI.
