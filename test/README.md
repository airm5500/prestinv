# Tests de Prestige Inventaire

Règle de l'officine : **toute évolution passe par ces tests, et aucun test existant n'est affaibli**.
Tout tourne avec `flutter test`, sur un PC Linux ou sur la CI GitHub, **sans émulateur ni vrai serveur** :
l'application entière est montée contre un faux serveur Prestige.

```bash
flutter test                      # tout
flutter test test/e2e             # une catégorie
flutter test test/ergonomie --plain-name "Saisie guidée"   # un écran
PRESTINV_RELEVE=1 flutter test test/ergonomie/affichage_ecrans_test.dart   # relevé sans échec (diagnostic)
```

## Catégories

| Dossier | Catégorie | Ce qui est vérifié |
|---|---|---|
| `test/*_test.dart` | **Non-régression** (historique), unitaires et widgets | Tous les correctifs passés : file des saisies, scan Sunmi, cumul, versement, licence, session expirée, nouvelle interface écran par écran… Ces tests ne doivent jamais être affaiblis. |
| `test/unitaires/` | **Unitaires** | Outils de test eux-mêmes (faux serveur : deux transports identiques, scénarios, cookie) ; règles de la 4.13 sans écran (`regles_4_13_test.dart` : filtre du rayon, boutons Commencer / Poursuivre / Revérifier, rappel bloquant et envoi automatique avec horloge simulée, droit de création, masquages PDF / CSV, taille de l'écran). |
| `test/non_regression/` | **Non-régression** (garde-fous) | Aucun secret réel dans le dépôt (empreinte du mot de passe retiré), aucun identifiant par défaut. |
| `test/integration/` | **Intégration** | Services réels (`ApiService`, `AuthProvider`, `LicenseProvider`, `SaisieQueue`, `MoteurVersement`) contre le faux serveur servi en **vrai HTTP** sur 127.0.0.1 : codes 200 / `success:false` / 401 / 403 / 404 / 5xx, délai, connexion coupée ou refusée, cookie `JSESSIONID`. |
| `test/e2e/` | **Bout en bout** | Application entière (`racineApplication`, comme `main()`), nouvelle interface (par défaut) **et** ancienne (choisie dans les paramètres), parcours complets, pannes, saisie hors ligne puis reprise. Joue aussi les parcours de `integration_test/` pour les garder à jour. |
| `test/ergonomie/` | **Ergonomie / cohérence d'affichage** | Chaque écran principal sur Sunmi V2s (720×1440 px, ×2), Sunmi V3 / V3H / V3mix (1080×1920 px, ×3), téléphone 360×640 dp, tablette 1920×1200 px (×1,5), texte ×1,0 et ×1,3, et (4.13) aux trois **tailles d'écran** Automatique / Compact / Très compact ; saisie guidée qui **ne bouge pas** (nom court / long, filtre posé / retiré : `stabilite_saisie_test.dart`) ; (4.13.1) Automatique → Compact sur petit écran, carte produit entière sur V2s (`petits_ecrans_test.dart`) : aucun débordement ni exception de rendu, cibles tactiles ≥ 48 dp (`androidTapTargetGuideline`), contraste (`textContrastGuideline`), champ de quantité visible au-dessus du pavé et du clavier système (`viewInsets` simulés). Pas d'images de référence (« goldens ») : uniquement des règles mesurables. |
| `integration_test/` | Sur appareil | Mêmes parcours que `test/e2e/integration_test_coherence_test.dart`, mais sur un terminal et contre un **vrai** serveur. Identifiants fournis au lancement (`--dart-define=PRESTINV_TEST_LOGIN=… PRESTINV_TEST_PASSWORD=… PRESTINV_TEST_HOST=…`), jamais dans le code. |

La CI (`.github/workflows/ci.yml`) lance chaque catégorie dans une étape séparée, après `flutter analyze`,
et refuse tout fichier `*_test.dart` rangé hors de ces dossiers.

## Parcours clés couverts

| Parcours | Nouvelle interface | Ancienne interface |
|---|---|---|
| Lancement / licence : valide, aucune licence, expirée, en cache | `e2e/pannes_test`, `integration/services_serveur_test`, `licence_lancement_test` | idem |
| **Règle : serveur injoignable, 5xx, 401, 403 ≠ « aucune licence »** | `e2e/pannes_test` (500, 503, 401, 403, coupure), `integration/…` (500, 502, 503, 401, 403, refus, coupure) | idem |
| Connexion (refus, succès, cookie sur chaque requête), déconnexion | `e2e/parcours_nouvelle_interface_test` | `e2e/parcours_ancienne_interface_test` |
| Accueil, choix de l'inventaire (mémorisé), création d'inventaire | `e2e/parcours_nouvelle_interface_test`, `nv_accueil_ecrans_test` | `creation_inventaire_test` |
| Saisie guidée (rayon, quantité, envoi) | `e2e/parcours_nouvelle_interface_test`, `nv_saisie_test` | `e2e/parcours_ancienne_interface_test`, `saisie_*`, `deja_compte_test` |
| Saisie par scan (douchette Sunmi simulée, touche latérale) | `e2e/…`, `nv_saisie_test` | `e2e/…`, `scan_*_test` |
| Collecte hors ligne → versement / rapport | `e2e/…`, `nv_accueil_ecrans_test` | `e2e/…`, `versement_collecte_test` |
| Écarts | `e2e/…`, `nv_ecarts_restants_test` | `e2e/…`, `ecarts_restants_test` |
| « Actualiser l'avancement » | `e2e/…`, `nv_avancement_test` | — |
| Changer d'interface dans les paramètres (code administrateur) | `e2e/…`, `nv_interrupteur_test` | `e2e/…`, `nv_interrupteur_test` |
| 4.13 : accueil → « Voir les inventaires » déroulé → inventaire choisi → saisie guidée → filtre (paire obligatoire, Annuler, Retirer) → menu ⋮ → Quitter | `e2e/parcours_4_13_test` | — |
| 4.13 : onglet Scanner → « Scanner pour… » → Collecte / scan continu (présélection) | `e2e/parcours_4_13_test` | — |
| 4.13 : envoi manuel → message BLOQUANT après le délai, « Envoyer maintenant » ; délai 0 → envoi automatique toutes les 15 min | `e2e/parcours_4_13_test`, `unitaires/regles_4_13_test` | 4.13.1 : `e2e/parcours_ancienne_interface_test` (style d'origine, ancien bandeau de 5 s remplacé, retour 2 min après un échec, délai 0) |
| 4.13 : création réservée (profil « xtypeuser », réglage protégé, code administrateur si profil inconnu), créé → sélectionné, visible ; création depuis la collecte | `e2e/parcours_4_13_test`, `integration/regles_4_13_test`, `nv_accueil_ecrans_test` | — |
| 4.13 : analyse « Tous les emplacements » (progression, annulation, ligne → aperçu sans requête) | `nv_4_13_test`, `integration/regles_4_13_test` | — |
| 4.13 : récapitulatif Tous / Déjà comptés / Pas comptés ; masquer la quantité déjà comptée ; stock théorique masqué (écran, PDF / CSV) | `nv_4_13_test`, `unitaires/regles_4_13_test` | — |
| 4.13 : taille de l'écran (réglage protégé, « Relancer maintenant ») | `e2e/parcours_4_13_test`, `nv_4_13_test`, `ergonomie/*` | `ergonomie/affichage_ecrans_test` |
| 4.13.1 : Automatique → Compact sur petit écran (seuil), mention « Automatique (Compact appliqué sur cet écran) », carte produit entière sur V2s | `unitaires/regles_4_13_test`, `nv_4_13_test`, `e2e/parcours_4_13_test`, `ergonomie/petits_ecrans_test` | — |
| Mini-clavier du champ de scan : le clavier du téléphone s'ouvre | `nv_4_13_test` | `nv_4_13_test` (saisie guidée et rapide d'origine) |
| Session expirée → reconnexion sans quitter l'écran | `e2e/pannes_test` | `e2e/pannes_test`, `session_expiree_test` |
| Session expirée avant le premier envoi → « Session expirée — reconnectez-vous », envoi repris après reconnexion | `e2e/pannes_test`, `integration/services_serveur_test` | `integration/…` |
| Serveur coupé en cours de travail → message réseau, Réessayer | `e2e/pannes_test` | `e2e/pannes_test` |
| Saisie hors ligne puis envoi automatique au retour du serveur | `e2e/pannes_test`, `integration/…` | `e2e/pannes_test` |

## Outils (`test/support/`, `test/helpers/`)

- **`support/faux_serveur_prestige.dart`** — faux serveur Prestige réutilisable :
  - `FauxServeurPrestige()` : comptes, licence et catalogue fictifs ; `exigerSession` (401 sans cookie valide) ;
  - transports : `client` (en mémoire, pour `testWidgets`) ou `await demarrer()` (vrai `HttpServer` sur 127.0.0.1, pour `test`) ;
  - scénarios : `scripter('rayons', ReponseScriptee.code(500))`, `.echec('message')` (`success:false`), `.json(…)`, `.lente(durée)`, `.coupee()`, option `fois: n` ;
  - `expirerSessions()`, `couper()` / `retablir()`, `arreter()` ; journal `requetes` / `recues('route')` (méthode, paramètres, cookie, corps) ;
  - `catalogue` : inventaires, rayons, produits et quantités modifiables (`FauxPrestige` des tests d'écrans).
- **`support/donnees_fictives.dart`** — `CompteFictif`, `licenceFictive()` (fin relative à aujourd'hui), catalogue d'officine. **Jamais de vrais identifiants** : le garde-fou `non_regression/secrets_test.dart` échoue si le mot de passe réel retiré réapparaît (comparaison d'empreinte SHA-256 ; ajoutez l'empreinte de tout autre secret retiré à `empreintesInterdites`).
- **`support/application_essai.dart`** — `lancerApplication(tester, nouvelleInterface: null|false, mode:, serveur:)`, `seConnecter`, `revenirAccueil`, `fermerApplication`.
- **`support/ergonomie.dart`** — parc `appareils`, `echellesTexte`, `configurer`, `releverErreursRendu`, `manquementsAccessibilite`, `ouvrirClavier`, `horsDeVueSousClavier`.
- `helpers/` (historique) : `banc_essai.dart` (providers + file en mémoire), `nouvelle_interface.dart` (polices réelles, tailles, pavé), `douchette_essai.dart` (douchette et touches Sunmi), `faux_serveur.dart` (file des saisies), `coffre_memoire.dart` (Keystore).

Les tests de widgets tournent en **temps simulé** : n'y utilisez pas de vrai fichier ni de vrai socket (utilisez
`DisqueMemoire` et le transport en mémoire) ; les délais du faux serveur avancent avec `tester.pump(durée)`.

## Ajouter un nouvel écran : la marche à suivre

1. **Ergonomie (obligatoire)** : ajoutez une entrée `EcranControle('Nom', nouvelle: true, construire: () => const MonEcran())`
   dans `test/ergonomie/catalogue_ecrans.dart`. L'écran est alors contrôlé automatiquement sur les 4 appareils × 2 échelles
   × 3 tailles d'écran (débordements, cibles tactiles, contraste). Aux tailles Compact / Très compact (réduction voulue
   par l'administrateur), la cible tactile exigée est de 48 dp de l'interface (48 × facteur dp réels) et la règle de
   contraste n'est pas appliquée : elle mesure une capture à 1 px par dp où le texte réduit est flouté par le lissage
   (couleurs identiques à toutes les tailles, contrôlées en Automatique). S'il contient une saisie de quantité, ajoutez une `SituationSaisie`
   dans `test/ergonomie/clavier_quantite_test.dart`. Indicateur animé sans fin : `anime: true`.
2. **Bout en bout** : si l'écran ouvre un nouveau parcours, ajoutez un `testWidgets` dans
   `test/e2e/parcours_nouvelle_interface_test.dart` (et dans `parcours_ancienne_interface_test.dart` si l'écran
   d'origine existe) : `lancerApplication` → `seConnecter` → navigation réelle → vérification **côté serveur**
   (`app.serveur.catalogue…`, `app.serveur.recues(…)`).
3. **Pannes** : si l'écran charge des données, vérifiez dans `test/e2e/pannes_test.dart` (ou un test d'écran) :
   session expirée → « Se reconnecter », serveur coupé → message réseau + « Réessayer », jamais de liste vide trompeuse.
4. **Nouvelle route serveur** : décrivez-la dans le faux serveur (`FauxPrestige` / `FauxServeurPrestige`) avec la même
   forme de réponse que Prestige, puis testez le service dans `test/integration/` (200, `success:false`, 401, 500, coupure).
5. Nommez les tests en français, décrivant le comportement attendu ; un test qui révèle une anomalie non corrigée est
   gardé **sauté** (`skip: 'Anomalie connue Ax : …'`) et l'anomalie est ajoutée ci-dessous — jamais supprimé ni assoupli.

## Anomalies connues (relevées par ces tests, non corrigées)

Les tests correspondants sont présents mais **sautés** uniquement pour les configurations concernées ; partout ailleurs la
règle est exigée. Corriger l'anomalie = retirer le saut.

| Réf. | Anomalie | Où | Test |
|---|---|---|---|
| A2 | Écrans d'origine (gelés) : textes gris et boutons colorés (OK vert, boutons de l'accueil) sous le seuil de contraste (Licence, Accueil « j restants », bouton OK de la saisie guidée, « Scannez le produit suivant », Restants, Collecte, Configuration). Règle non exigée pour les écrans d'origine seulement : la correction toucherait les couleurs des boutons de plusieurs écrans gelés, laissée à la décision de l'officine. | `lib/screens/…` | `ergonomie/affichage_ecrans_test.dart` |
| A4 (origine) | Saisie guidée **d'origine**, recherche par nom (clavier système ouvert) : le champ de quantité sort de la zone visible ; il revient à la fermeture du clavier. | `lib/screens/inventory_entry_screen.dart` | `ergonomie/clavier_quantite_test.dart` (C bis, « Saisie guidée (origine) ») |
| A5 (origine) | Saisie guidée **d'origine** sur écran de 640 dp de haut (Sunmi V3 / V3H / V3mix 1080×1920, téléphone 360×640) et, en texte ×1,3, sur V2s : le champ de quantité est poussé sous le bas de la liste défilante, partiellement (×1,0) ou totalement (×1,3) caché derrière le pavé. Correction = refonte de la mise en page de l'écran gelé (même principe que la nouvelle interface). | `lib/screens/inventory_entry_screen.dart` | `ergonomie/clavier_quantite_test.dart` (A, « Saisie guidée (origine) ») |

## Anomalies corrigées

| Réf. | Anomalie | Correctif | Tests réactivés / ajoutés |
|---|---|---|---|
| A1 | Session expirée **avant** le premier envoi : 401/403 sur la liste des inventaires ouverts annoncé « Serveur injoignable », sans proposition de reconnexion. | `ApiService.inventairesOuverts` lève `SessionServeurExpiree` (401, 403, « Veuillez vous connecter ») ; la file le distingue d'une panne réseau : message « Session expirée — reconnectez-vous », saisies gardées, **envoi interrompu repris automatiquement après la reconnexion** (`signalerReconnexion`). Nouvelle interface : message avec l'action « Se reconnecter » après « Envoyer les données » (et en mode Direct). | `integration/services_serveur_test.dart` (401 et 403), `e2e/pannes_test.dart` (« Session expirée AVANT le premier envoi ») |
| A3 | Fenêtre « Ajout Collecte » d'origine qui débordait quand le clavier système était ouvert. | Fenêtre défilante (`scrollable: true`). | `ergonomie/clavier_quantite_test.dart` (B, Collecte origine) |
| A4 (nouvelle) | Saisie guidée de la nouvelle interface : pendant la recherche par nom, la quantité sortait de l'écran. | Quantité épinglée hors de la liste (voir A5) : elle reste juste au-dessus du clavier système. | `ergonomie/clavier_quantite_test.dart` (C bis, nouvelle) |
| A5 (nouvelle) | Saisie guidée de la nouvelle interface : quantité cachée derrière le pavé sur 640 dp de haut / texte ×1,3. | Affichage de la quantité tapée **et** rappel compact du produit (`nv-zone-quantite`, `nv-produit-compact`) épinglés juste au-dessus du pavé, hors de la liste qui défile : toujours visibles sans défilement. Même enchaînement, mêmes touches, même douchette. Le scan continu n'était pas concerné (feuille de quantité). | `ergonomie/clavier_quantite_test.dart` (A et C, nouvelle) |
| A6 | Fenêtres de quantité d'origine (« Saisie Rapide », « Ajout Collecte ») qui débordaient en texte ×1,3 (pavé de hauteur fixe 280 dp). | Pavé d'**au moins** 280 dp (aspect identique en ×1,0, plus haut si le texte est agrandi), fenêtre défilante. | `ergonomie/clavier_quantite_test.dart` (A et B, origine) |
| 4.13 | Icône mini-clavier du champ de scan : le clavier du téléphone ne s'ouvrait pas (le champ avait déjà le focus et passer du clavier « aucun » au clavier texte ne l'affiche pas). | `ChampDouchette.basculerClavier` demande l'affichage (`TextInput.show`) après la reconstruction. | `nv_4_13_test.dart` (guidée, scan continu, collecte, écarts, restants) |
| 4.13 | Inventaire créé depuis le terminal absent de la saisie guidée / du scan continu. | Après création : liste relue par `InventoryProvider` (seule source), inventaire retrouvé par son libellé si le serveur ne donne pas l'identifiant, sélectionné ; liste relue à chaque retour sur l'accueil. | `nv_accueil_ecrans_test`, `e2e/parcours_nouvelle_interface_test`, `integration/regles_4_13_test` |
| 4.13 | Feuille de quantité de la collecte cachée par le clavier du téléphone s'il était ouvert (vu aux tailles réduites). | La feuille remonte au-dessus du clavier (`viewInsets`). | `ergonomie/clavier_quantite_test.dart` (B, collecte) |
| 4.13.1 | Sunmi V2s en taille Automatique : bas de la carte produit de la saisie guidée coupé (Stock théorique, Déjà compté, Prix achat), à faire défiler. | Automatique applique Compact sur un petit écran (côté long < 740 dp ou côté court < 340 dp ; `TailleEcranReglage.effective`). | `ergonomie/petits_ecrans_test.dart`, `unitaires/regles_4_13_test.dart` |

Corrigés lors de la mise en place du socle : pastilles de filtre de la nouvelle interface à 44 dp → 48 dp (règle des
cibles tactiles) ; date de fin de licence du faux serveur figée au 31/12/2027 (les tests seraient devenus rouges à cette
date) → relative à aujourd'hui ; `integration_test/app_test.dart` obsolète (sans file des saisies : plantage au
lancement ; bouton « COMMENCER L'INVENTAIRE » disparu ; identifiant par défaut) → réécrit et vérifié à chaque `flutter test`.

## Tests adaptés en 4.13 (éléments volontairement déplacés)

La revue du pharmacien retire de l'accueil la carte « Inventaire en cours », la liste « Inventaires ouverts » et
les tuiles ; la sélection d'un inventaire redevient obligatoire avant toute saisie. Les tests qui les visaient
gardent **les mêmes vérifications**, à la nouvelle place : `nv_avancement_test` (carte et « Actualiser » sur
l'écran de l'inventaire choisi ; pourcentage compté en produits, 67 % sur le jeu d'essai comme avant),
`nv_accueil_ecrans_test` (Accueil), `e2e/parcours_nouvelle_interface_test`, `e2e/pannes_test` (passage par
`choisirInventaire` ; menu ⋮ « Envoyer les saisies maintenant »), `nv_rendu_test` (liste à dérouler).
