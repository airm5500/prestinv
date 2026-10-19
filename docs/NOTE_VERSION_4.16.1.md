# Prestige Inventaire 4.16.1 (code 19) — Demandes au serveur 46 à 50 prises en compte

*Pour le pharmacien et l'équipe qui compte.*

Elle s'installe par-dessus la 4.16.0 sans désinstaller ; rien n'est perdu. Avec un serveur Prestige qui n'a pas
encore ces nouveautés, tout fonctionne exactement comme en 4.16.0.

Les demandes de l'application Inventaire (regroupées dans prestige_vente_app/docs/serveur/
TRANSMISSION_SERVEUR_2026-10-15.md, § 4) ont été traitées par le serveur ; vérifiées dans son code :

| N° | Côté serveur | Dans l'application 4.16.1 |
|---|---|---|
| 46 — inventaire limité à une liste de produits, en une fois | fait (`produits` dans la création, réponse `inconnus`, une seule transaction, 500 produits au plus) | **utilisé** : « Créer un inventaire avec ces produits » envoie la liste ; le serveur à jour crée l'inventaire de ces produits **seulement**, en une fois (plus de fenêtre où l'inventaire existe sans ses produits, 2 requêtes au lieu de 3). Serveur plus ancien : méthode en deux temps de la 4.15, inchangée |
| 47 — rayons limités aux lignes à compter | fait (liste des rayons, état des rayons, critères) | rien à changer : l'application masquait déjà les rayons sans produit à compter ; désormais vrai aussi sur les autres terminaux et pour les inventaires « unitaires » créés dans Prestige |
| 48 — droit et session sur l'ajout des produits | fait (401, 403 « Droit manquant », 409 inventaire clôturé) | messages lisibles : « Droit manquant : Créer un inventaire », « Inventaire clôturé : aucune ligne n'a été modifiée » |
| 49 — autres formes du code au versement en lot | fait (EAN-13 tiré d'un GTIN-14, CIP7 tiré d'un EAN-13 34009) | rien à changer : moins de codes repris produit par produit |
| 50 — auteur de chaque saisie | fait (`auteurId`, `auteurLogin`, `auteurNom` dans les lignes) | **affiché** dans la correction des écarts : « … · compté par Awa K. » (sur la ligne d'informations existante, sans place en plus) |

## Tests

`test/integration/creation_collecte_test.dart` (création atomique, inconnus, 409 / 403, auteur, rayons à compter —
au format réel du serveur), `test/nv_ecarts_restants_test.dart` (« compté par »), `test/performance/collecte_4_15_test.dart`
(2 requêtes pour créer depuis la collecte sur un serveur à jour). Toutes les catégories rejouées.
