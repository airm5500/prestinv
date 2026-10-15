# Tests de Prestige Inventaire

Règle de l'officine : **toute évolution passe par ces tests, et aucun test existant n'est affaibli**.
Tout tourne avec `flutter test`, sur un PC Linux ou sur la CI GitHub, **sans émulateur ni vrai serveur** :
l'application entière est montée contre un faux serveur Prestige.

```bash
flutter test                      # tout
flutter test test/e2e             # une catégorie
flutter test test/ergonomie --plain-name "Saisie guidée"   # un écran
PRESTINV_RELEVE=1 flutter test test/ergonomie/affichage_ecrans_test.dart   # relevé sans échec (diagnostic)
flutter test -j 1 test/performance       # performance (un fichier à la fois : temps non faussés)
flutter test test/reseau                 # réseau
# Rapport de livraison (comme la CI) :
flutter test --file-reporter json:build/rapport_tests/5-performance.json -j 1 test/performance
dart run tool/rapport_tests.dart build/rapport_tests
```

## Catégories

| Dossier | Catégorie | Ce qui est vérifié |
|---|---|---|
| `test/*_test.dart` | **Non-régression** (historique), unitaires et widgets | Tous les correctifs passés : file des saisies, scan Sunmi, cumul, versement, licence, session expirée, nouvelle interface écran par écran, version X.Y.Z+N affichée (connexion, Réglages, deux interfaces : `version_affichee_test.dart`)… Ces tests ne doivent jamais être affaiblis. |
| `test/unitaires/` | **Unitaires** | Outils de test eux-mêmes (faux serveur : deux transports identiques, scénarios, cookie) ; règles de la 4.13 sans écran (`regles_4_13_test.dart` : filtre du rayon, boutons Commencer / Poursuivre / Revérifier, rappel bloquant et envoi automatique avec horloge simulée, droit de création, masquages PDF / CSV, taille de l'écran) ; 4.14 (`scan_camera_test.dart`) : réglage « Scan par l'appareil photo » désactivé par défaut, lecture de l'appareil photo simulé **identique** à celle de la douchette, anti-doublon, contenu des codes. |
| `test/non_regression/` | **Non-régression** (garde-fous) | Aucun secret réel dans le dépôt (empreinte du mot de passe retiré), aucun identifiant par défaut ; versions alignées sur le magasin Sunmi (`version_sunmi_test.dart`, lit `docs/VERSIONS_SUNMI.md` : `pubspec.yaml` ≥ version publiée, +N > versionCode publié, format `X.Y.Z+N`, aucun `versionCode` / `versionName` en dur dans Gradle). |
| `test/integration/` | **Intégration** | Services réels (`ApiService`, `AuthProvider`, `LicenseProvider`, `SaisieQueue`, `MoteurVersement`) contre le faux serveur servi en **vrai HTTP** sur 127.0.0.1 : codes 200 / `success:false` / 401 / 403 / 404 / 5xx, délai, connexion coupée ou refusée, cookie `JSESSIONID`. |
| `test/e2e/` | **Bout en bout** | Application entière (`racineApplication`, comme `main()`), nouvelle interface (par défaut) **et** ancienne (choisie dans les paramètres), parcours complets, pannes, saisie hors ligne puis reprise. Joue aussi les parcours de `integration_test/` pour les garder à jour. |
| `test/ergonomie/` | **Ergonomie / cohérence d'affichage** | Chaque écran principal sur Sunmi V2s (720×1440 px, ×2), Sunmi V3 / V3H / V3mix (1080×1920 px, ×3), téléphone 360×640 dp, tablette 1920×1200 px (×1,5), texte ×1,0 et ×1,3, et (4.13) aux trois **tailles d'écran** Automatique / Compact / Très compact ; saisie guidée qui **ne bouge pas** (nom court / long, filtre posé / retiré : `stabilite_saisie_test.dart`) ; (4.13.1) Automatique → Compact sur petit écran, carte produit entière sur V2s (`petits_ecrans_test.dart`) : aucun débordement ni exception de rendu, cibles tactiles ≥ 48 dp (`androidTapTargetGuideline`), contraste (`textContrastGuideline`), champ de quantité visible au-dessus du pavé et du clavier système (`viewInsets` simulés). Pas d'images de référence (« goldens ») : uniquement des règles mesurables. |
| `test/performance/` | **Performance** (4.14.2) | Seuils qui **font échouer la CI** (table ci-dessous) : démarrage jusqu'à l'écran de connexion (temps réel, images, requêtes ; deux interfaces) — `demarrage_test` ; rendu et défilement des longues listes, temps de **chaque image** (accueil 200 inventaires, saisie guidée sur un rayon de 2 000 produits avec « Suivant » ×100 et 2 000 résultats de recherche, écarts 2 000 produits, collecte 1 000 lignes, analyse « Tous les emplacements » 50 emplacements) — `listes_longues_test` ; **nombre de requêtes** des parcours clés (démarrage, connexion + accueil, déroulé de la liste, ouverture d'un inventaire, choix de l'emplacement, saisie de 50 quantités, recherche tapée vite → 1 requête après l'anti-rebond, envoi des saisies) — `requetes_test` ; traitement local (file de 5 000 saisies sur vrai fichier, normalisation de 10 000 codes scannés) — `traitement_local_test`. |
| `test/reseau/` | **Réseau** (4.14.2) | Serveur **lent qui répond** (2, 5, 8 s) sur connexion (deux interfaces), accueil, choix de l'emplacement, saisie guidée, envoi : indicateur visible, aucun message d'erreur avant le délai de l'application, retour possible, aucun double envoi — `serveur_lent_test` ; réponse **tronquée** (longueur annoncée non atteinte) et **JSON partiel** (services en vrai HTTP, écrans : message + Réessayer, jamais une liste vide ni « aucune licence ») — `reponses_tronquees_test` ; **coupure → retour** répétés (dont coupure en pleine requête), reprise de la file, dernière valeur, sans doublon — `coupures_reprise_test` ; **local ↔ distant** et adresse changée (deux vrais serveurs HTTP ; « Passer en Distant » depuis l'écran injoignable) — `adresse_serveur_test` ; **HTTPS** (vrai `HttpServer.bindSecure`, certificat auto-signé généré par openssl, approuvé seulement dans le test) et **certificat refusé** → message dédié ≠ « serveur injoignable » — `https_test`. |
| `integration_test/` | Sur appareil | Mêmes parcours que `test/e2e/integration_test_coherence_test.dart`, mais sur un terminal et contre un **vrai** serveur. Identifiants fournis au lancement (`--dart-define=PRESTINV_TEST_LOGIN=… PRESTINV_TEST_PASSWORD=… PRESTINV_TEST_HOST=…`), jamais dans le code. |

La CI (`.github/workflows/ci.yml`) lance chaque catégorie dans une étape séparée, après `flutter analyze`,
et refuse tout fichier `*_test.dart` rangé hors de ces dossiers. Toutes les catégories sont jouées même si
l'une échoue (le job échoue alors et l'APK n'est pas construit).

**Rapport de tests de livraison** : chaque catégorie écrit ses résultats (`--file-reporter
json:build/rapport_tests/<n>-<catégorie>.json`) ; `tool/rapport_tests.dart` en fait un résumé (par catégorie :
tests, réussis, sautés, échecs, durée ; tests en échec ; tests sautés et leur motif ; **mesures de
performance avec leur seuil** — lignes `PRESTINV_MESURE {json}` imprimées par `mesurer()`), publié dans le
résumé du job GitHub (`$GITHUB_STEP_SUMMARY`) et en artefact **`rapport-tests`** (`rapport.md`,
`resume.json`, JSON bruts), à côté de l'artefact `prestinv-apk`.

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
| 4.14 : scan par l'appareil photo — réglage off → aucun bouton ; on → bouton, lecture simulée = même résultat que la douchette (guidée : aperçu fermé après lecture ; scan continu / collecte : aperçu ouvert, anti-doublon 1,5 s) ; autorisation (explication, refus, refus définitif) ; sans appareil photo → pas de bouton | `scan_camera_test`, `e2e/parcours_camera_test`, `unitaires/scan_camera_test`, `ergonomie/*` (`ecransAppareilPhoto`, situations « aperçu photo ») | `scan_camera_test` (guidée, rapide, collecte d'origine), `e2e/parcours_camera_test` |
| 4.14.1 : saisie guidée, icône d'envoi seule (sans fond ni contour, 48 dp, pastille) | `nv_retours_4_14_1_test`, `e2e/parcours_4_13_test` | — |
| ~~4.14.1 : création depuis la collecte limitée à UN emplacement~~ — remplacée en 4.15 (ligne suivante) | — | — |
| 4.15 : création depuis la collecte = inventaire des SEULS produits collectés, sur leurs emplacements (récapitulatif « N produits, M emplacements », codes non retrouvés ; `valeurs` = emplacements, `bool_INVENTAIRE = 0`, retenue des produits ; serveur sans retenue → création REFUSÉE avec message clair (4.15.1) ; panne → Réessayer ; produits non ajoutés → « Ajouter les produits » sans recréer) | `creation_collecte_4_15_test`, `integration/creation_collecte_test`, `e2e/parcours_4_13_test`, `ergonomie/*`, `performance/collecte_4_15_test`, `reseau/collecte_4_15_reseau_test` | `creation_collecte_4_15_test` (écran de création, « Verser la collecte » › « Nouvel inventaire… »), `ergonomie/*` |
| 4.15.2 : saisie guidée, nom du produit UNE seule fois (carte en haut, entier, sans défilement) et quantité visible au-dessus du pavé — tous appareils, texte ×1,0 / ×1,3, trois tailles | `ergonomie/nom_produit_visible_test` | — |
| 4.15.2 : Prestige en redéploiement (404 sans réponse de Prestige, 502 / 503 / 504, connexion refusée) → « Serveur indisponible, veuillez réessayer » à la connexion, au lancement et aux lectures ; mot de passe faux, 500 et 404 métier inchangés ; saisie gardée (jamais refusée) | `integration/serveur_indisponible_test`, `e2e/serveur_indisponible_test` | `e2e/serveur_indisponible_test` |
| Demandes au serveur : regroupées dans prestige_vente_app/docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md (§ 4) | — | — |
| 4.15 : serveur à jour (réponse aux demandes mobiles) — droit `droits.creerInventaire`, 403 « interdit » ≠ session, `lgInventaireId`, état des rayons en une requête (rayons sans produit à compter masqués), versement en lot avec clé anti-doublon (réponse perdue / tronquée → même clé), PUT details 401 → saisie gardée, 409 / 404 lisibles, lecture en échec 500 ≠ liste vide ; serveur ancien : aucune requête nouvelle | `unitaires/regles_4_15_test`, `integration/routes_recentes_test`, `integration/creation_collecte_test`, `performance/collecte_4_15_test`, `reseau/collecte_4_15_reseau_test` | idem (services communs) |
| 4.14.1 : appareil photo, formats Code 39 / 93, ITF, Codabar, UPC-E ; normalisation (UPC-E → EAN-13, délimiteurs, caractères de contrôle) ; conseil « Approchez le code, bien éclairé » | `unitaires/scan_camera_test`, `scan_camera_test` | — |
| 4.14.1 (remis en 4.14.2) : **toucher** l'icône d'envoi de la saisie guidée envoie les saisies en attente | `nv_retours_4_14_1_test` (voir « Test remis » ci-dessous), `e2e/parcours_4_13_test` | — |
| 4.14.2 : connexion → accueil construit une seule fois, liste lue une fois | `performance/requetes_test` | `performance/requetes_test` |
| 4.14.2 : HTTPS, certificat refusé → « Certificat du serveur refusé » (connexion, lancement, listes, envoi, création) | `reseau/https_test` | `reseau/https_test` (connexion ; lancement : A7) |
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
  - `catalogue` : inventaires, rayons, produits et quantités modifiables (`FauxPrestige` des tests d'écrans) ;
  - 4.15 : `serveurRecent = true` → serveur à jour (`role` / `droits` à la connexion, `droitCreation`, `rayons/etat`,
    versement en lot, `lgInventaireId`) ; par défaut, serveur actuel (sans ces routes). Un inventaire créé pendant
    le test a ses **propres lignes** (`catalogue.crees['NEW1']` : copies des produits, retenues ou non comme
    `bool_INVENTAIRE`) ; `catalogue.sansRouteRetenue` (ancien serveur, 404), `versementsReponsePerdue` (réponse
    perdue après l'enregistrement), journaux `creationsRetenue`, `retenues`, `versementsLot`.
- **`support/donnees_fictives.dart`** — `CompteFictif`, `licenceFictive()` (fin relative à aujourd'hui), catalogue d'officine. **Jamais de vrais identifiants** : le garde-fou `non_regression/secrets_test.dart` échoue si le mot de passe réel retiré réapparaît (comparaison d'empreinte SHA-256 ; ajoutez l'empreinte de tout autre secret retiré à `empreintesInterdites`).
- **`support/application_essai.dart`** — `lancerApplication(tester, nouvelleInterface: null|false, mode:, serveur:)`, `seConnecter`, `revenirAccueil`, `fermerApplication`.
- **`support/ergonomie.dart`** — parc `appareils`, `echellesTexte`, `configurer`, `releverErreursRendu`, `manquementsAccessibilite`, `ouvrirClavier`, `horsDeVueSousClavier`.
- `helpers/` (historique) : `banc_essai.dart` (providers + file en mémoire), `nouvelle_interface.dart` (polices réelles, tailles, pavé), `douchette_essai.dart` (douchette et touches Sunmi), `faux_serveur.dart` (file des saisies), `coffre_memoire.dart` (Keystore), `camera_essai.dart` (4.14 : appareil photo **simulé** — `installerCameraSimulee`, `ouvrirCamera`, `lireCamera`, autorisation Caméra et présence simulées, horloge de l'anti-doublon ; `prefsCamera` active le réglage).

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

## Seuils de performance (4.14.2)

Tous les seuils sont dans `test/support/performance.dart` (classe `Seuils`) ou écrits dans le test (plafonds de
requêtes). Une mesure au-dessus de son seuil **fait échouer le test** (en local comme sur la CI) ; chaque mesure
figure dans le rapport de livraison avec la part du seuil utilisée. Les temps sont mesurés en **mode test**
(JIT, assertions actives : bien plus lent qu'un APK « release » sur le terminal) : ce sont des seuils de
**non-régression**, pas des temps d'appareil. Mesure d'une image : chaque `tester.pump()` est chronométré en
temps réel (`Stopwatch`, non simulé) — c'est tout le travail d'une image (construction, mise en page,
peinture) ; défilement par pas de 120 dp (doigt rapide, ≈ 7 000 dp/s à 60 images/s), un 1er passage à froid
(code compilé à la volée) puis un 2e passage mesuré contre le budget. CI : `flutter test -j 1` (un fichier à la
fois).

| Mesure | Seuil | Mesuré sur la CI GitHub (ubuntu-latest, `-j 1`) | Marge |
|---|---:|---:|---:|
| Démarrage → connexion, à froid (nouvelle interface ; ancienne) | 2 500 ms | 813 ms ; 95 ms | ×3,1 |
| Démarrage → connexion — images rendues / requêtes | 10 / 1 | 3 / 1 | ×3,3 / — |
| Accueil : 200 inventaires, ouverture + déroulé (avancement de chacun) | 6 000 ms | 2 075 ms | ×2,9 |
| Ouverture d'un écran sur longue liste, à froid (saisie guidée 2 000, écarts 2 000, collecte 1 000, analyse 50) | 1 500 ms | 91–421 ms | ×3,6 |
| Pire image d'un 1er défilement (à froid) | 200 ms | 6–59 ms | ×3,4 |
| Pire image d'un défilement (2e passage) — aucune image au-dessus | 64 ms | 5–24 ms | ×2,7 |
| Image courante (p90) d'un défilement | 16 ms | 1,9–4,7 ms | ×3,4 |
| « Suivant » de la saisie guidée (écran entier) : pire image / p90 | 50 / 40 ms | 16,9 / 13,5 ms | ×3 |
| File de 5 000 saisies (vrai fichier) : enregistrement / envoi, par saisie | 5 / 5 ms | 1,3 / 1,3 ms | ×3,8 |
| File de 5 000 saisies : relecture au redémarrage | 500 ms | 113 ms | ×4,4 |
| Normalisation de 10 000 codes scannés | 500 ms | 107 ms | ×4,7 |
| Requêtes : démarrage / connexion + accueil (nouvelle ; ancienne) | 1 / 2 ; 1 | 1 / 2 ; 1 | aucune |
| Requêtes : déroulé de la liste | inventaires × (1 + 2 × emplacements) = 14 | 14 | aucune |
| Requêtes : ouverture d'un inventaire (avancement connu) / choix de l'emplacement / saisie guidée | 0 / 1 + 2 × emplacements = 7 / 1 | 0 / 7 / 1 | aucune |
| Requêtes : saisie de 50 quantités (Collecte) / envoi des 50 | 0 / 50 + 1 | 0 / 51 | aucune |
| Requêtes : recherche par nom tapée vite (7 lettres, 120 ms entre deux) | 1 | 1 | aucune |

Un seuil ne se relève **jamais** pour faire passer un test : seulement après une analyse écrite ici (nouvelle
fonction plus lourde voulue, machine de CI changée), en gardant une marge d'environ ×2 sur la plus lente des
mesures observées.

## Ajouter un test de performance / réseau pour un nouvel écran

1. **Longue liste** : dans `test/performance/listes_longues_test.dart`, construire un gros catalogue
   (`grandCatalogue(rayons:, parRayon:, ecarts:, inventaires:)` de `support/performance.dart`), ouvrir l'écran
   avec `ouvrir(tester, banc, MonEcran())` (temps d'ouverture → `mesurer(…, seuil: Seuils.ouvertureListeMs)`),
   puis `deuxPassages(tester, 'Mon écran')` : défilement complet de la plus grande liste, pire image à froid,
   pire image et image courante (p90) au 2e passage.
2. **Requêtes** : dans `test/performance/requetes_test.dart`, entourer le parcours de
   `compter(serveur, () async { … })` et appeler `mesurer('Requêtes — …', n, seuil: <plafond>, unite:
   'requêtes', detail: detail(liste))`. Le plafond est le nombre **voulu** (formule écrite dans le test si
   cela dépend du catalogue), sans marge.
3. **Temps d'un traitement** : `Stopwatch` + `mesurer(…, seuil: Seuils.xxx, unite: 'ms')`, seuil ajouté à `Seuils`
   avec son commentaire et sa ligne dans le tableau ci-dessus.
4. **Réseau** : si l'écran charge des données, ajouter un `testWidgets` par délai dans
   `test/reseau/serveur_lent_test.dart` (`app.serveur.scripter('<route>', ReponseScriptee.lente(d))`, puis
   `attendreServeurLent(tester, d, 'Mon écran', pendant: …)` : indicateur visible, aucune erreur avant le délai,
   action répétée sans double envoi) et un cas « JSON partiel » / « tronquée »
   (`ReponseScriptee.json('[{"id":1,"no')`, `ReponseScriptee.tronquee(…)`) dans `reponses_tronquees_test.dart`
   (message + Réessayer, jamais une liste vide). Délai d'essai ≤ délai de l'application pour cette route.
5. Les mesures apparaissent seules dans le rapport (aucune autre déclaration nécessaire).

## Test remis : toucher l'icône d'envoi (saisie guidée)

Le test « toucher l'icône d'envoi » retiré en 4.14.1 est remis dans `nv_retours_4_14_1_test.dart`. Il
n'aboutissait pas parce que la saisie posée dans la file **avant** l'ouverture de l'écran déclenche, à
l'ouverture, la fenêtre bloquante « Saisie non terminée — Voulez-vous les envoyer maintenant ? » : son voile
(`ModalBarrier`) recouvre l'en-tête et recevait le toucher (avertissement « would not hit test »), sans envoi.
Ni la cible (48 dp), ni `ensureVisible`, ni une animation n'étaient en cause. Le test répond d'abord « Non »,
rend le toucher manqué **fatal** (`WidgetController.hitTestWarningShouldBeFatal`), puis vérifie la progression,
la file vide, la quantité reçue par le serveur et un seul envoi.

## Anomalies connues (relevées par ces tests, non corrigées)

Les tests correspondants sont présents mais **sautés** uniquement pour les configurations concernées ; partout ailleurs la
règle est exigée. Corriger l'anomalie = retirer le saut.

| Réf. | Anomalie | Où | Test |
|---|---|---|---|
| A2 | Écrans d'origine (gelés) : textes gris et boutons colorés (OK vert, boutons de l'accueil) sous le seuil de contraste (Licence, Accueil « j restants », bouton OK de la saisie guidée, « Scannez le produit suivant », Restants, Collecte, Configuration). Règle non exigée pour les écrans d'origine seulement : la correction toucherait les couleurs des boutons de plusieurs écrans gelés, laissée à la décision de l'officine. | `lib/screens/…` | `ergonomie/affichage_ecrans_test.dart` |
| A4 (origine) | Saisie guidée **d'origine**, recherche par nom (clavier système ouvert) : le champ de quantité sort de la zone visible ; il revient à la fermeture du clavier. | `lib/screens/inventory_entry_screen.dart` | `ergonomie/clavier_quantite_test.dart` (C bis, « Saisie guidée (origine) ») |
| A7 | Lancement de l'**ancienne** interface avec un certificat HTTPS refusé : l'écran d'origine (gelé) garde le titre « Serveur injoignable » ; le motif « Certificat du serveur refusé… » est affiché dessous (vérifié). | `lib/screens/serveur_injoignable_screen.dart` | `reseau/https_test.dart` (« écran au titre… », ancienne interface) |
| A5 (origine) | Saisie guidée **d'origine** sur écran de 640 dp de haut (Sunmi V3 / V3H / V3mix 1080×1920, téléphone 360×640) et, en texte ×1,3, sur V2s : le champ de quantité est poussé sous le bas de la liste défilante, partiellement (×1,0) ou totalement (×1,3) caché derrière le pavé. Correction = refonte de la mise en page de l'écran gelé (même principe que la nouvelle interface). | `lib/screens/inventory_entry_screen.dart` | `ergonomie/clavier_quantite_test.dart` (A, « Saisie guidée (origine) ») |

## Anomalies corrigées

| Réf. | Anomalie | Correctif | Tests réactivés / ajoutés |
|---|---|---|---|
| A1 | Session expirée **avant** le premier envoi : 401/403 sur la liste des inventaires ouverts annoncé « Serveur injoignable », sans proposition de reconnexion. | `ApiService.inventairesOuverts` lève `SessionServeurExpiree` (401, 403, « Veuillez vous connecter ») ; la file le distingue d'une panne réseau : message « Session expirée — reconnectez-vous », saisies gardées, **envoi interrompu repris automatiquement après la reconnexion** (`signalerReconnexion`). Nouvelle interface : message avec l'action « Se reconnecter » après « Envoyer les données » (et en mode Direct). | `integration/services_serveur_test.dart` (401 et 403), `e2e/pannes_test.dart` (« Session expirée AVANT le premier envoi ») |
| A3 | Fenêtre « Ajout Collecte » d'origine qui débordait quand le clavier système était ouvert. | Fenêtre défilante (`scrollable: true`). | `ergonomie/clavier_quantite_test.dart` (B, Collecte origine) |
| A4 (nouvelle) | Saisie guidée de la nouvelle interface : pendant la recherche par nom, la quantité sortait de l'écran. | Quantité épinglée hors de la liste (voir A5) : elle reste juste au-dessus du clavier système. | `ergonomie/clavier_quantite_test.dart` (C bis, nouvelle) |
| A5 (nouvelle) | Saisie guidée de la nouvelle interface : quantité cachée derrière le pavé sur 640 dp de haut / texte ×1,3. | Affichage de la quantité tapée (`nv-zone-quantite`) épinglé juste au-dessus du pavé, hors de la liste qui défile : toujours visible sans défilement. (Le rappel compact du nom ajouté alors, `nv-produit-compact`, est **retiré en 4.15.2** à la demande du pharmacien : le nom n'est qu'en haut, dans la carte produit — `ergonomie/nom_produit_visible_test.dart`.) Même enchaînement, mêmes touches, même douchette. Le scan continu n'était pas concerné (feuille de quantité). | `ergonomie/clavier_quantite_test.dart` (A et C, nouvelle) |
| A6 | Fenêtres de quantité d'origine (« Saisie Rapide », « Ajout Collecte ») qui débordaient en texte ×1,3 (pavé de hauteur fixe 280 dp). | Pavé d'**au moins** 280 dp (aspect identique en ×1,0, plus haut si le texte est agrandi), fenêtre défilante. | `ergonomie/clavier_quantite_test.dart` (A et B, origine) |
| 4.13 | Icône mini-clavier du champ de scan : le clavier du téléphone ne s'ouvrait pas (le champ avait déjà le focus et passer du clavier « aucun » au clavier texte ne l'affiche pas). | `ChampDouchette.basculerClavier` demande l'affichage (`TextInput.show`) après la reconstruction. | `nv_4_13_test.dart` (guidée, scan continu, collecte, écarts, restants) |
| 4.13 | Inventaire créé depuis le terminal absent de la saisie guidée / du scan continu. | Après création : liste relue par `InventoryProvider` (seule source), inventaire retrouvé par son libellé si le serveur ne donne pas l'identifiant, sélectionné ; liste relue à chaque retour sur l'accueil. | `nv_accueil_ecrans_test`, `e2e/parcours_nouvelle_interface_test`, `integration/regles_4_13_test` |
| 4.13 | Feuille de quantité de la collecte cachée par le clavier du téléphone s'il était ouvert (vu aux tailles réduites). | La feuille remonte au-dessus du clavier (`viewInsets`). | `ergonomie/clavier_quantite_test.dart` (B, collecte) |
| 4.13.1 | Sunmi V2s en taille Automatique : bas de la carte produit de la saisie guidée coupé (Stock théorique, Déjà compté, Prix achat), à faire défiler. | Automatique applique Compact sur un petit écran (côté long < 740 dp ou côté court < 340 dp ; `TailleEcranReglage.effective`). | `ergonomie/petits_ecrans_test.dart`, `unitaires/regles_4_13_test.dart` |
| 4.14.2 | Première connexion après le lancement : accueil construit **deux fois** (racine de l'application + écran de connexion qui poussait un second accueil), liste des inventaires lue deux fois. | `InterfaceVersion.allerAccueilApresConnexion` : pas de second accueil quand la connexion est la route racine (après une déconnexion, remplacement comme avant). Deux interfaces. | `performance/requetes_test.dart` (connexion + accueil ≤ 2 requêtes) |
| 4.14.2 | Adresse `https://` dont le certificat est refusé : « Serveur injoignable » / « Erreur de connexion… réseau » au lieu d'un motif dédié. | `ApiService.estCertificatRefuse` / `messageCertificat` (listes, licence, déjà compté, envoi, création), `AuthProvider.login`, écran de lancement de la nouvelle interface titré « Certificat du serveur refusé ». | `reseau/https_test.dart` |

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
