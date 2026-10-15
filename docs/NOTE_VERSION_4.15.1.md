# Prestige Inventaire 4.15.1 (code 15) — Note de version

*Pour le pharmacien et l'équipe qui compte.*

Elle s'installe par-dessus la 4.15.0 sans désinstaller ; rien n'est perdu (réglages, saisies en attente,
collecte, rapports de versement, versement interrompu à reprendre).

## 1. Serveur trop ancien : la création depuis la collecte est refusée (deux interfaces)

**Votre décision** : sur un serveur Prestige qui ne sait pas limiter un inventaire aux produits scannés
(sans la route qui « retient » les produits), plus jamais d'inventaire contenant tous les produits des
emplacements.

**Désormais** (Scanner › Collecte › « Créer un inventaire avec ces produits » ; ancienne interface :
« Verser la collecte » › « Nouvel inventaire… ») : sur un tel serveur, le récapitulatif affiche

> Ce serveur Prestige ne permet pas encore de créer un inventaire limité aux produits scannés. Mettez le
> serveur à jour ou versez la collecte dans un inventaire existant.

et le bouton « Créer l'inventaire » reste inactif : **rien n'est envoyé au serveur**. Le versement dans un
inventaire existant (« Verser dans un inventaire ») reste possible comme avant. Sur un serveur à jour,
rien ne change par rapport à la 4.15.0 : l'inventaire ne contient que les produits collectés, sur leurs
emplacements.

## 2. Droit « Créer un inventaire » : confirmé

Comme en 4.15.0 et selon votre réponse : quand le serveur donne le droit `creerInventaire` à la connexion,
c'est lui qui décide (le réglage du terminal ne sert plus que pour un serveur ancien).

## 3. Un seul document pour le serveur

Les demandes au serveur de l'application Inventaire sont regroupées dans
prestige_vente_app/docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md (§ 4) — le fichier
`docs/DEMANDE_SERVEUR_2026-10-15.md` de la 4.15.0 est retiré.

## Tests

Mis à jour : `test/creation_collecte_4_15_test.dart` (refus, nouvelle et ancienne interface, petit écran
Sunmi V2s), `test/integration/creation_collecte_test.dart` (aucune requête de création envoyée ; un
inventaire existant choisi n'est pas modifié). Toutes les catégories rejouées (unitaires, intégration, bout
en bout, ergonomie, performance, réseau).
