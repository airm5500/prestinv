# Images pour le magasin d'applications Sunmi — Prestige Inventaire

Captures d'écran **pures** de la nouvelle interface (version 4.12.0) : pas de cadre d'appareil, pas de
texte ajouté, pas de bandeau de débogage. Vrai thème de l'application (bleu nuit et ambre, clair),
polices **Roboto** et icônes Material fournies avec le SDK Flutter.

Données de démonstration **neutres** : officine fictive « Pharmacie Démo », poste « Comptoir 1 »
(identifiant `comptoir1`), produits courants désignés par leur DCI, codes CIP fictifs, aucun nom de
personne, aucune donnée de client. L'heure des saisies est celle de la génération.

## Contenu

| Fichier | Écran |
|---|---|
| `1_connexion.png` | Connexion |
| `2_accueil.png` | Accueil : inventaire en cours, avancement (60 %, « Avancement à 10:42 »), Reprendre, modes de saisie |
| `3_saisie_guidee.png` | Saisie guidée : rayon ANTIBIOTIQUES, produit 4 / 7, quantité en cours de frappe, produit précédent envoyé |
| `4_scan_continu.png` | Scan continu : cadre « Scannez le produit suivant », journal des dernières saisies envoyées |
| `5_ecarts.png` | Écarts : chiffres clés en F CFA, liste triée par valeur (tablette : tableau + correction) |

| Dossier | Format | Taille (pixels) | Rendu |
|---|---|---|---|
| `terminal/` | portrait | **1080 × 1920** | 411 × 731 dp, densité 2,625 (420 dpi) |
| `terminal/720x1440/` | portrait | **720 × 1440** | 360 × 720 dp, densité 2 — écran natif du Sunmi V2s |
| `tablette/` | paysage | **1920 × 1200** | 1280 × 800 dp, densité 1,5 |

Toutes les images sont en **PNG 8 bits RGB, sans canal alpha (aucune transparence)**.

## Régénérer

Depuis la racine du dépôt, avec le SDK Flutter du projet :

```bash
flutter test test_apercus/store_sunmi_test.dart
```

Le test (hors CI) monte chaque écran avec un faux serveur de démonstration, capture l'écran à la taille
exacte en pixels et écrit lui-même le PNG en RGB (les fichiers existants sont remplacés). Il échoue si
les polices Roboto du SDK sont introuvables (variable `FLUTTER_ROOT`), si une image n'a pas la taille
attendue ou si un écran déborde.

Après régénération, **ouvrir chaque image** pour vérifier : texte net, rien de coupé, aucun carré à la
place des lettres.

## Avant de publier

Les exigences du magasin Sunmi (nombre de captures, tailles et rapports d'aspect acceptés, poids
maximal, format, icône et visuel de présentation) peuvent évoluer : **vérifier les exigences exactes
sur le portail développeur Sunmi** au moment du dépôt, et adapter la liste `formats` de
`test_apercus/store_sunmi_test.dart` si une autre taille est demandée.
