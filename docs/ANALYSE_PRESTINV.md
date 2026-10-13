# Prestige Inventaire (`prestinv`) : analyse, risques et refonte

> Analyse **en lecture seule** du dépôt `prestinv`, branche `master` (= `origin/master`, commit unique `d09ef4e « modif affichage stock ecran variance »` du 26/02/2026). Rien n'a été modifié dans ce dépôt.
> Serveur lu sur la branche `claude/new-session-xm8ptu` de Prestige (aucune modification).
> Maquettes : `prestinv_maquettes.html` · Aperçus : `apercus/1_accueil_inventaires.png` … `apercus/4_ecarts_tablette.png`.
> Vérification outillée faite sur une **copie** du dépôt (Flutter 3.47.5 / Dart 3.13.4) : `outils/flutter_analyze.txt`, `outils/flutter_test.txt`.

---

## 0. L'essentiel en 10 lignes

1. L'application sert à **compter le stock** pendant l'inventaire, sur téléphone ou terminal Sunmi, et à envoyer les quantités au serveur Prestige.
2. **Risque n° 1 — perte de comptage en « Saisie rapide (Scan) »** : en mode d'envoi « Collecte » (réglage par défaut), chaque nouveau scan efface de la mémoire les quantités précédentes non envoyées ; elles ne sont **jamais** envoyées ni sauvegardées (§2.1, P1).
3. **Risque n° 2 — écrasement d'un comptage** : avec le cumul activé, si le réseau ne répond pas à la vérification « déjà compté ? », l'application conclut « jamais compté » et **remplace** la quantité d'un collègue (P2).
4. **Risque n° 3 — une saisie corrigée peut ne jamais partir** en mode « Direct » (P3), et dans Écarts / Restants **OK sur un champ vide enregistre 0** (P5).
5. **Activation de licence impossible depuis l'app** : l'app envoie un `POST`, le serveur n'accepte qu'un `GET`, et la route exige une session alors qu'on n'est pas encore connecté (S5).
6. **Serveur injoignable au premier lancement = écran « Application non activée »** (R1).
7. **Côté serveur**, l'enregistrement d'une quantité (`PUT /ws/inventaires/details`) est **ouvert sans connexion** et ne note ni l'auteur ni l'état de l'inventaire (S2).
8. Sécurité : mot de passe en clair dans le téléphone, HTTP en clair, journaux bavards, réglages serveur sans code, mot de passe réel dans un test (§2.2).
9. Aucun test valide (le seul test échoue), aucune CI, versions incohérentes (1.3.1 / 4.8.5).
10. Proposition : **6 étapes, 17 à 25 jours**, en commençant par la fiabilité de la saisie (file locale persistante + envoi rejouable sans doublon), sans changer l'apparence ; puis refonte bleu nuit / ambre derrière un interrupteur.

---

## 1. Ce que fait l'application aujourd'hui

### 1.1 En bref
`prestinv` (« Prestige Inventaire ») se connecte au serveur Prestige de l'officine, liste les **inventaires ouverts** (créés sur le poste Prestige ; l'app **ne crée ni ne clôture** d'inventaire) et permet de saisir les **quantités comptées**, par rayon ou par scan. Elle montre ensuite les **écarts** (compté ≠ théorique) pour les corriger, les **restants** (produits jamais comptés), un **récapitulatif** imprimable, une **analyse** (camembert) et une **collecte libre hors ligne** (liste code + quantité exportée en CSV/PDF, sans lien avec le serveur).

### 1.2 Fiche technique

| Élément | Constat |
|---|---|
| Flutter / Dart | `pubspec.yaml:8` SDK `>=3.0.0 <4.0.0` ; `pubspec.lock` exige **Dart ≥ 3.8, Flutter ≥ 3.27** ; `.metadata` révision `b25305a8` (stable). |
| Versions affichées | `pubspec.yaml:5` = **1.3.1** ; `android/app/build.gradle.kts` `versionCode = 4`, `versionName = "4.8.5"` codés en dur. Captures `prestInv_img/` d'une version plus ancienne (« Prestinv - Accueil », un seul bouton). |
| Dépendances | `http`, `provider`, `shared_preferences`, `fl_chart`, `intl`, `pdf`, `printing`, `path_provider`, `share_plus`, `permission_handler`, `flutter_native_splash`, `dart_ping` (**inutilisé**). Pas de base locale (sqlite), pas de stockage sécurisé, pas de lecteur caméra. |
| Gestion d'état | `provider` : `AppConfig`, `AuthProvider`, `InventoryProvider`, `EntryProvider`, `LicenseProvider` (`main.dart:34-45`). `ApiService` est recréé à chaque écran (pas de singleton). |
| Client HTTP | `http`, base `http://<ip>:<port>/<appName>/api/v1/...` (`app_config.dart:52-79`). Délais 5 à 60 s selon l'appel, **aucun** pour la connexion (`auth_provider.dart:44`), la déconnexion (`:106`) et `fetchTouchedProductsByRayon` (`api_service.dart:381-401`). |
| Authentification | Session cookie `JSESSIONID` (`POST /user/auth`), gardée **en mémoire seulement** : chaque relance impose de se reconnecter. Session expirée non détectée (voir R4). |
| Démarrage | Splash → vérification licence (`GET /licence/find`, cache local si échec) → connexion → accueil (`main.dart:165-186`). La licence est **revérifiée à chaque retour au premier plan** (`main.dart:120-126`). |
| Thème | Material, bleu `#002D42` + vert-bleu `#00B09B` « charte UbiPharm » (`app_colors.dart`), couleurs codées en dur dans chaque écran (violet, orange, bleu…). Différent de la charte refondue de `prestige_vente_app` (`#003366` + ambre `#F59E0B`). |
| Tests | `test/widget_test.dart` : **échoue** (ne fournit pas `LicenseProvider` → `ProviderNotFoundException`, voir `outils/flutter_test.txt`). `integration_test/app_test.dart` : dépend d'un vrai serveur `192.168.1.7` et d'un **vrai mot de passe** (ligne 31), teste un écran scanner qui n'existe plus (ligne 161). |
| Analyse statique | `flutter analyze` : 0 erreur, **6 avertissements** (code mort : `main.dart:142`, `inventory_entry_screen.dart:55,543`…), 99 remarques (32 API dépréciées dont `WillPopScope`, 30 `print`, 13 `use_build_context_synchronously`). |
| CI | **Aucune** (pas de `.github/`). README d'origine Flutter. |
| Plateformes | Dossiers android, ios, web, windows, linux, macos ; seul **Android** est réellement utilisé (terminal Sunmi, téléphones, tablette). `applicationId = com.dici.prestinv` ; **release signée avec la clé de debug** (`build.gradle.kts`, bloc `release`). |

### 1.3 Écrans et parcours

| Accueil (bouton) | Écran | Ce qu'on y fait |
|---|---|---|
| SAISIE GUIDÉE | Liste inventaires → `InventoryEntryScreen` | Choisir un **emplacement (rayon)** (pastille verte/orange/grise selon l'état), puis produit par produit : stock théorique (masquable), quantité au **clavier numérique maison**, OK → produit suivant. Filtres « N° de … à … » et « alphabétique », « Aller au produit », « Traiter les oublis », récap, correction d'écarts du rayon, export CSV du rayon. |
| SAISIE RAPIDE (Scan) | Même écran en mode rapide | Champ « Rechercher / Scanner » ; un scan ou une recherche ouvre une fenêtre de quantité (clavier). Option **cumul** : « Déjà compté : X. Additionner ? ». Historique des cumuls imprimable. |
| CORRECTION ÉCARTS | `GlobalVarianceScreen` | Écarts de tout l'inventaire, filtre par rayon, scan, correction enchaînée (‹ ›). Sortie « obligation de tous les traiter » avec « Forcer la sortie ». |
| RESTANTS À FAIRE | `UncountedScreen` | Produits jamais comptés (tout l'inventaire ou par rayon), filtres, saisie directe. |
| COLLECTE LIBRE (hors ligne) | `CollectionScreen` | Scanner un code, quantité (additionnée si code déjà présent), liste locale, CSV dans Téléchargements, impression PDF. **Aucun envoi au serveur.** |
| Icônes du haut | Analyse, Configuration, Déconnexion | Analyse : camembert surplus/manquants/justes + PDF. Configuration : IP local/distant, port, contexte, nombre d'inventaires affichés, seuil « grande quantité », déconnexion auto, rappel d'envoi, stock théorique visible, cumul, **mode d'envoi Direct / Collecte**. |

**Deux modes d'envoi** (`app_config.dart:27`, défaut **Collecte**) :
- *Direct* : chaque quantité est envoyée tout de suite (en tâche de fond) ;
- *Collecte* : les quantités restent sur le téléphone jusqu'au bouton « Envoyer » (envoi produit par produit, arrêt à la première erreur).

### 1.4 Routes serveur appelées (préfixe `/<app>/api/v1`)

| Usage dans l'app | Route | Ressource Java (serveur) | Session exigée ? |
|---|---|---|---|
| Connexion / déconnexion | `POST /user/auth`, `POST /user/logout` | `AccountResource.java` (`@Path("v1/user")`) | non (liste d'exceptions) |
| Licence | `GET /licence/find` ; `POST /licence/save/{clé}` | `LicenceRessource.java:32-43` — **`save` est un `@GET`** | `find` non ; `save/{clé}` **oui** (l'exception `v1/licence/save/` ne correspond jamais au chemin réel) |
| Liste des inventaires | `GET /ws/inventaires?maxResult=` | `ErpRessource.java:244-248` → `InventaireServiceImpl.fetch` (statut `enable`) | non |
| Rayons | `GET /ws/inventaires/rayons?idInventaire=` | `ErpRessource.java:250-255` | non |
| Produits d'un rayon / recherche | `GET /ws/inventaires/details?idInventaire&idRayon&query` | `ErpRessource.java:257-265` | non |
| Recherche globale (scan) | `GET /ws/inventaires/detailsAll` | `ErpRessource.java:289-296` | **oui** |
| « Déjà compté ? » | `GET /ws/inventaires/detailsTouchedRayon`, `/detailsAllTouched` | `ErpRessource.java:278-287`, `308-316` | oui |
| Restants | `GET /ws/inventaires/detailsUntouchedRayon`, `/detailsAllUntouched` | `ErpRessource.java:267-276`, `298-306` | oui |
| Écarts | `GET /ws/inventaires/detailsAllEcarts` | `ErpRessource.java:318-326` | oui |
| **Enregistrer une quantité** | `PUT /ws/inventaires/details {id, quantite}` | `ErpRessource.java:328-333` → `InventaireServiceImpl.updateDetailQuantity` (`:718-722`) | **non** |
| (code mort) export CSV serveur | `POST /export/csv?rayonId&path` | **aucune route** correspondante | — |
| (code mort) analyse complète | `GET /inventaires/analyse_complete` | **aucune route** correspondante | — |
| Test de connexion | `HEAD http://ip:port` | — | — |

Exceptions de session : `filter/AuthenticationFilter.java:35-43` (liste exacte, comparée par égalité stricte `:158-160`). Toutes les routes `fetch*` du serveur **attrapent leurs erreurs et renvoient une liste vide** (`InventaireServiceImpl.java:94, 113, 159, 204, 249, 292, 339, 387`). Le serveur accepte déjà la **pagination** (`page`, `maxResult`), non utilisée par l'app.

### 1.5 Données stockées sur le téléphone (SharedPreferences, en clair)

| Clé | Contenu |
|---|---|
| `localApiAddress`, `localApiPort`, `distantApiAddress`, `distantApiPort`, `appName`, `apiMode`, `sendMode`, `maxResult`, `showTheoreticalStock`, `largeValueThreshold`, `autoLogoutMinutes`, `sendReminderMinutes`, `isCumulEnabled`, `networkExportPath` (inutilisé) | Réglages (`app_config.dart:83-104`) |
| `rememberMe`, `savedLogin`, **`savedPassword`** | Identifiants si « Rester connecté » (`auth_provider.dart:57-64`) |
| `cached_license` | Dernière licence lue (`license_provider.dart:86`) |
| `inv_<inventaire>_ray_<rayon>_unsynced` | Quantités **non envoyées**, par rayon (`entry_provider.dart:122-135`) |
| `inv_<…>_ray_<…>_index`, `…_filter` | Position et filtre par rayon |
| `cumul_logs_<rayon>` | Historique des cumuls — **pas lié à l'inventaire** (`entry_provider.dart:170`) |
| `collection_data` | Collecte libre, **une seule liste pour tous les inventaires** (`collection_screen.dart:55,70`) |

### 1.6 Hors ligne
- **Saisie guidée** : un rayon déjà chargé peut être compté sans réseau en mode Collecte ; les quantités sont sauvegardées par rayon et proposées à l'envoi à la réouverture du rayon (« Saisie non terminée »).
- **Saisie rapide (Scan), Écarts, Restants** : **pas de hors ligne** (chaque scan interroge le serveur ; Écarts/Restants envoient immédiatement et abandonnent en cas d'échec).
- **Collecte libre** : hors ligne, mais **aucun chemin de retour vers Prestige** (export CSV « Code;Quantite;Date » ; l'import serveur `POST /inventaire/import-csv` ne lit que des CIP pour **créer** un inventaire, sans quantités).
- La « synchronisation en arrière-plan » à la mise en veille est **vide** (`main.dart:133-156`, commentaires seulement).

---

## 2. Problèmes constatés (avec preuves)

### 2.1 Fiabilité de la saisie (le plus important pour un inventaire)

| # | Problème | Preuve | Conséquence concrète |
|---|---|---|---|
| **P1** | **Saisie rapide + mode Collecte : seule la dernière saisie survit.** En mode rapide aucun rayon n'est choisi ; chaque recherche/scan **remplace** la liste en mémoire par le résultat du scan. La sauvegarde locale est ignorée sans rayon. | `entry_provider.dart:303-308` (`_allProducts = results`), `:123` (`if (_selectedRayon == null) return;`), `inventory_list_screen.dart` (mode rapide → pas de rayon), défaut `SendMode.collect` `app_config.dart:27,103` | On scanne 50 produits, on appuie sur « Envoyer » : **un seul** part. Rien n'est sauvegardé : fermeture, appel, batterie → tout est perdu. L'export CSV « session » ne contient que le dernier. |
| **P2** | **Cumul : réseau lent = écrasement silencieux.** La vérification « déjà compté ? » (délai 5 s) renvoie « non » sur **toute** erreur ; l'app enregistre alors la nouvelle quantité à la place de l'ancienne. | `api_service.dart:96-103` (`return null` sur erreur), utilisée `inventory_entry_screen.dart:340, 705` | Deux préparateurs sur le même produit (réserve + rayon) : le second efface le comptage du premier. |
| **P3** | **Mode Direct : une correction rapide peut ne jamais partir.** L'envoi d'une quantité est lancé sans attendre ; à son retour, le produit est marqué « envoyé » même si l'utilisateur a **re-saisi** entre-temps. Les envois concurrents peuvent aussi arriver dans le désordre. | `inventory_entry_screen.dart:385-395`, `entry_provider.dart:147-155` (`markAsConfirmedFromServer` sans comparer la valeur) | Saisie 5, correction immédiate en 50 : le serveur garde 5, l'app affiche « Serveur à jour ». |
| **P4** | **Écarts / Restants : échec réseau = correction perdue mais affichée.** La valeur est changée à l'écran avant l'envoi ; en cas d'échec, simple message 2 s, pas de nouvelle tentative. Dans Écarts globaux, le produit est même marqué **« validé »** malgré l'échec. | `variance_screen.dart:299-320, 390-411` ; `global_variance_screen.dart:341-346, 390-405` ; `uncounted_screen.dart:423-443` | Le pharmacien croit avoir corrigé ; le serveur garde l'ancienne quantité ; la clôture se fait sur une valeur fausse. |
| **P5** | **OK sur un champ vide enregistre 0** (« produit absent ») dans Écarts et Restants ; un nombre trop long (> 18 chiffres) devient aussi 0. | `variance_screen.dart:247, 394` ; `uncounted_screen.dart:391` (`int.tryParse(...) ?? 0`) ; `global_variance_screen.dart:342` | Une touche OK de trop met un produit à zéro, envoyé immédiatement. |
| **P6** | **Quantités en attente invisibles hors du rayon ouvert.** « Données non envoyées » ne regarde que le rayon affiché ; les attentes des autres rayons ne réapparaissent qu'en rouvrant ce rayon. Aucune vue globale. | `entry_provider.dart:56` (`hasUnsyncedData` sur le rayon courant), `app_utils.dart:47` (déconnexion) | Fin de journée : des saisies restent sur le téléphone sans que personne le sache. |
| **P7** | **Envoi vers un inventaire clôturé.** Les attentes locales ne sont jamais purgées ; le serveur accepte la mise à jour sans vérifier l'état de l'inventaire. | `entry_provider.dart:277-296` ; serveur `InventaireServiceImpl.java:718-722` | Une ancienne saisie peut modifier un inventaire déjà validé. |
| **P8** | **Double appui sur OK** : la validation est asynchrone et non verrouillée ; un double appui peut sauter un produit (avance de deux) ou, avec cumul, proposer d'additionner deux fois. | `inventory_entry_screen.dart:316-431` (aucun drapeau « en cours ») | Produit oublié (rattrapé seulement par « Traiter les oublis ») ou quantité doublée. |
| **P9** | Fenêtre « envoyer » : « Envoyer et Quitter » quitte **même si l'envoi a échoué**. | `inventory_entry_screen.dart:532-537` | Sortie avec données non envoyées (conservées seulement en mode guidé). |
| **P10** | Filtre par rayon dans Écarts globaux : affiche les produits **comptés** du rayon, pas les **écarts** ; réponse lue sans UTF-8 (accents abîmés), recherche non encodée, pas de délai. | `global_variance_screen.dart:172-180` → `api_service.dart:381-401` | Liste trompeuse (produits justes mêlés aux écarts). |
| **P11** | Historique des cumuls et collecte libre **non rattachés à l'inventaire** ; PDF des cumuls sur **une seule page** (échec au-delà d'une quarantaine de lignes). | `entry_provider.dart:169-170` ; `collection_screen.dart:55` ; `cumul_history_screen.dart:96` (`pw.Page`) | Mélange d'inventaires ; impression impossible pour un gros cumul. |

Ce qui est bien et sera conservé : la mise à jour serveur est une **valeur absolue** (`quantite = 8`, pas « +8 ») — rejouer le même envoi ne crée pas de doublon, c'est la bonne base pour une file d'envoi fiable ; l'envoi groupé s'arrête à la première erreur et garde le reste ; la sauvegarde par rayon en mode guidé ; l'alerte « grande quantité » ; « Traiter les oublis ».

### 2.2 Sécurité

| # | Problème | Preuve | Risque |
|---|---|---|---|
| S1 | **Mot de passe en clair** sur le téléphone (« Rester connecté ») et pré-rempli. Le mot de passe est aussi rogné (`trim`). | `auth_provider.dart:57-61`, `login_screen.dart:37, 55` | Terminal partagé ou perdu = mot de passe Prestige divulgué. |
| S2 | **Serveur : enregistrer une quantité ne demande aucune connexion** (`v1/ws/inventaires/details` dans les exceptions, pour GET **et** PUT) ; aucun auteur ni contrôle d'inventaire ouvert ; identifiant inconnu → erreur 500. | `AuthenticationFilter.java:39`, `ErpRessource.java:328-333`, `InventaireServiceImpl.java:718-722` | Toute machine du réseau de l'officine peut modifier les quantités d'inventaire ; aucune traçabilité « qui a compté ». |
| S3 | **HTTP en clair** uniquement (`http://` forcé), y compris en mode Distant ; le fichier `network_security_config.xml` n'autorise qu'un hôte « serveur » et ne protège rien (le client Dart ne l'utilise pas). | `app_config.dart:67`, `android/.../network_security_config.xml` | Identifiants lisibles sur un Wi-Fi ou via Internet. |
| S4 | **Journaux** : URL complètes, résultats, erreurs (30 `print`). | `api_service.dart:68, 89, 97, 101, 158, 251, 282, 311` | Données lisibles par câble USB (logcat). |
| S5 | **Activation de licence cassée** : l'app fait `POST /licence/save/{clé}`, le serveur n'accepte que `GET`, et cette route exige une session alors que l'écran licence s'affiche **avant** la connexion. La clé est mise dans l'URL sans encodage. | `api_service.dart:334-343` vs `LicenceRessource.java:32-37`, `AuthenticationFilter.java:42-43, 158-160` | Le bouton « ACTIVER » ne peut pas réussir (à confirmer sur le terrain, question 2). |
| S6 | **Réglages serveur accessibles sans code** depuis l'écran de connexion et la licence. | `login_screen.dart:184`, `license_register_screen.dart:66` | Redirection vers un faux serveur qui récolte les mots de passe. |
| S7 | **Mot de passe réel** et IP dans le test d'intégration versionné. | `integration_test/app_test.dart:31, 51` | Mot de passe d'un compte exposé à toute personne ayant le code. |
| S8 | Release signée avec la clé debug ; permissions `CAMERA`, `WRITE/READ_EXTERNAL_STORAGE` inutiles ; écriture directe dans `/storage/emulated/0/Download`. | `build.gradle.kts` (bloc `release`), `AndroidManifest.xml`, `inventory_entry_screen.dart:122` | Mise à jour Play Store impossible proprement ; permissions demandées sans raison. |
| S9 | Licence contrôlée avec la **date du téléphone** et un cache local modifiable. | `license_provider.dart:21-28, 84-100` | Contournable en changeant la date (risque commercial plus que sécurité). |

### 2.3 Robustesse : pannes affichées comme « vide » ou comme « licence »

| # | Problème | Preuve |
|---|---|---|
| R1 | **Serveur injoignable au premier lancement (pas de cache) = « Application non activée »** : toute erreur de `/licence/find` → statut `none` → écran licence. Licence revérifiée à chaque retour au premier plan (spinner plein écran). | `license_provider.dart:42-53`, `main.dart:120-126, 177-179` |
| R2 | État des rayons faux en cas d'erreur : « pas commencé » si la requête échoue (`false`), « reste à faire » si l'autre échoue (`true`). | `api_service.dart:366-379, 404-416` |
| R3 | Recherches en erreur **avalées** (aucun message) : Restants et Écarts globaux ; serveur qui renvoie une liste vide sur erreur → « Aucun écart trouvé ! » / « Aucun produit » alors que la requête a échoué. | `uncounted_screen.dart:326-328`, `global_variance_screen.dart:230-232` ; serveur `InventaireServiceImpl.java:94…387` |
| R4 | **Session expirée non gérée** : les écrans affichent « Échec du chargement (Statut: 401) » en rouge, sans proposer de se reconnecter ; l'erreur remplace tout l'écran de saisie sans bouton Réessayer. | `api_service.dart:36-38…`, `inventory_entry_screen.dart:1303-1307`, `inventory_list_screen.dart:70-72` |
| R5 | Déconnexion : appel serveur sans délai ni `try` → réseau coupé = **impossible de se déconnecter** ; la déconnexion automatique utilise un contexte sans navigateur (plantage si des saisies sont en attente). | `auth_provider.dart:102-108`, `main.dart:108-111` + `app_utils.dart:51` |
| R6 | Données JSON lues sans contrôle (`json['id']` obligatoire, `Inventory`, `Rayon`) : un champ nul fait planter l'écran. | `models/inventory.dart:9-10`, `models/rayon.dart:12-14`, `models/product.dart:30` |
| R7 | Code mort qui trompe la lecture : `_attemptBackgroundSync` vide, `requestCsvGeneration` et `fetchAllProductsForInventory` vers des routes inexistantes, `networkExportPath`. | `main.dart:133-156`, `api_service.dart:199-238` |

### 2.4 Contrôles de saisie
- Quantité : **aucune longueur maximale** au clavier maison (`inventory_entry_screen.dart:268`, `collection_screen.dart:209`) ; champ vide = 0 dans Écarts/Restants (P5) ; seuil « grande quantité » appliqué **seulement** en saisie guidée/rapide, pas dans Écarts, Restants ni Collecte. Pas de négatif possible (bonne chose, aucune touche « − »).
- Configuration : IP/domaine sans contrôle de format, port non borné (0-65535), seuils acceptant 0 ou des valeurs absurdes (`config_screen.dart:122-157`) ; enregistrement non attendu (`setApiConfig` sans `await`).
- Filtres : alphabétique limité à 3 lettres (`inventory_entry_screen.dart:1080`) — correct ; numérique borné — correct.
- Clé de licence : seulement « non vide », pas d'encodage.

### 2.5 Performance (gros inventaires : 3 000 à 8 000 lignes)
- Ouverture du sélecteur de rayons : **2 requêtes par rayon, l'une après l'autre**, chacune renvoyant toute la liste des produits du rayon, et ce **à chaque ouverture** (`entry_provider.dart:240-254`, `inventory_entry_screen.dart:891`). 40 rayons = 80 requêtes.
- Écarts globaux et Restants chargent **tout l'inventaire** en une fois, sans pagination (le serveur la propose pourtant), avec tri sur le téléphone.
- Sauvegarde locale : la liste complète des attentes du rayon est réécrite en JSON à **chaque** OK (`entry_provider.dart:122-135`).
- Chaque saisie de caractère (douchette) déclenche une recherche après 500 ms en plus de la validation (`inventory_entry_screen.dart:596-608`).

### 2.6 Ergonomie terminal Sunmi (douchette intégrée) et affichage
- En saisie guidée, après chaque OK le curseur revient au champ **Quantité (lecture seule)** : un scan à ce moment-là est **perdu** ; il faut toucher le champ de recherche, ce qui **cache le clavier numérique** et ouvre le clavier Android (`inventory_entry_screen.dart:1322, 1513`).
- Pas de lecture des touches physiques (chiffres / Entrée) : sur un terminal à clavier, impossible de taper la quantité sans l'écran.
- Pas de retour sonore ni vibration au scan ; messages de 2 s en texte coloré seulement (rouge/vert), invisibles en rayon.
- Bouton « Aller au produit » et « Précédent » ronds en violet/bleu ; aucune indication d'avancement (x / y comptés) hors du compteur de position.
- Tablette : rien d'adapté (seule la hauteur < 700 px réduit les polices) ; pas de tableau pour les écarts.
- Charte différente des deux autres applications ; emojis dans les messages (« ✅ », « ⚠️ ») ; libellés en majuscules sur deux lignes.

---

## 3. Propositions

### 3.1 Fiabilité de la saisie : file locale persistante + envoi rejouable
1. **Journal local unique** (fichier JSON ou sqlite, une ligne par saisie) : `inventaire, ligne (id), CIP, quantité, mode (remplacer/ajouter), horodatage, état (en attente / envoyé / refusé), n° de saisie`. Écrit **avant** tout envoi et **avant** de passer au produit suivant. Valable pour Guidée, Scan, Écarts, Restants.
2. **Envoi rejouable** : la mise à jour serveur étant une valeur absolue, rejouer la **dernière** valeur d'une ligne est sans risque. La file n'envoie que la dernière saisie par ligne, dans l'ordre, et ne marque « envoyé » que si la valeur envoyée est **toujours** la valeur locale (corrige P3). Reprise automatique au retour du réseau, au démarrage et à l'ouverture de l'inventaire ; bouton « Envoyer » global sur l'accueil (P6).
3. **Cumul sûr** : si « déjà compté ? » échoue, on **demande quand même** Remplacer / Ajouter (P2). À terme, demander au serveur une opération « ajouter » atomique (évite qu'un collègue écrase entre la lecture et l'écriture).
4. **Garde-fous** : bouton OK verrouillé pendant le traitement (P8), champ vide refusé partout (P5), 6 chiffres maximum, seuil « grande quantité » partout, « Envoyer et quitter » ne quitte qu'après succès (P9).
5. **Mode Scan** : le journal de session remplace la liste en mémoire (corrige P1) ; affichage des 10 dernières saisies avec leur état (maquette 2B).

### 3.2 Robustesse et sécurité (reprise des règles de `prestige_vente_app`)
- `ApiLoadException` + chargement commun (`_loadList`) : distinguer **serveur injoignable / session expirée / refus / vide** ; `LoadErrorBanner` avec Réessayer ; plus jamais de « liste vide » sur erreur.
- Écran de lancement comme `lib/connexion/lancement_screen.dart` : **serveur injoignable ≠ licence** (R1) ; licence revérifiée au plus une fois par jour, sans remplacer l'écran en cours.
- Session expirée : reconnexion en fenêtre, la saisie en cours et la file sont conservées (R4).
- `IdentifiantsSecurises` : plus de mot de passe stocké (identifiant seul ; empreinte en option) ; `PinSecurise` pour ouvrir la Configuration (S1, S6).
- Journaux limités au mode debug ; délais sur tous les appels ; lecture JSON tolérante (R6) ; suppression du code mort (R7).
- Contrôles de saisie sur le modèle de `VenteInput` : quantité, IP/port, seuils, clé de licence (§2.4).
- Licence : appeler la route telle que le serveur l'expose (S5), après décision serveur (question 2).
- Performance : état des rayons en **une** requête (petite route serveur à ajouter, ou calcul depuis `detailsAllTouched`), pagination des Restants/Écarts, sauvegarde par ligne au lieu de la réécriture complète.

### 3.3 Côté serveur (à décider ; aucune modification faite)
- `PUT /ws/inventaires/details` : exiger la session (le retirer de la liste d'exceptions), refuser si l'inventaire n'est plus ouvert, enregistrer l'auteur (`strUPDATEDID`) et renvoyer la valeur enregistrée (S2, P7). Option : champ `mode: "ajouter"` atomique pour le cumul.
- Route légère « état des rayons » (comptés / total / en attente) pour l'accueil et le sélecteur.
- `licence/save` : accepter l'appel attendu par l'app (ou l'app s'aligne sur `GET`) et la rendre accessible avant connexion **avec** un contrôle (S5).
- Ne plus renvoyer une liste vide quand une requête échoue (renvoyer une erreur 500 explicite).

### 3.4 Ergonomie scan et saisie rapide
- **Douchette toujours prête** (même méthode que l'accueil de vente_app, `accueil_screen.dart:141-175` : lecture des touches matérielles quand aucun champ texte n'a le focus) : un scan ouvre le produit quel que soit l'écran ; les chiffres et Entrée du clavier physique alimentent la quantité.
- Bip + vibration : court = OK, double = inconnu / déjà compté.
- Feuille de quantité avec **Remplacer / Ajouter**, **+1 / −1**, rappel de la valeur déjà comptée.
- Code inconnu gardé dans le journal « à vérifier » au lieu d'un message de 2 s.
- Écarts triés par **valeur** (quantité × prix d'achat), compteur « à vérifier », « Garder » sans modifier.

### 3.5 Refonte visuelle : trois propositions (charte commune bleu nuit / ambre)
Charte identique à vente_app : `Pal` (`#003366`, ambre `#F59E0B` pour l'action principale, fond `#F2F4F8`, texte `#14213D`, gris `#5B6B82`), cartes arrondies, statuts avec libellé (jamais la couleur seule). Barre du bas : Accueil · Scanner · Écarts · Réglages.

| | **A — Guidé** | **B — Scan continu** | **C — Tablette / contrôle** |
|---|---|---|---|
| Idée | Tableau de bord de l'inventaire en cours (avancement, file d'envoi, « Reprendre »), rayons avec état, saisie produit par produit | Scanner → quantité → scanner ; journal des dernières saisies avec état d'envoi | Menu latéral, tableaux denses (écarts, restants), bilan en valeur, correction à droite |
| Accueil | `apercus/1` gauche | même accueil | menu latéral `apercus/4` |
| Saisie | `apercus/2` gauche | `apercus/2` centre et droite | — (saisie sur terminal) |
| Écarts | `apercus/3` | même liste | `apercus/4` |
| Pour qui | Préparateurs, inventaire tournant par rayon | Terminal Sunmi, réserve, gros volumes | Pharmacien titulaire qui contrôle avant clôture |

**Recommandation** : A et B dans la même application (ce sont deux modes déjà présents, rendus fiables), C automatiquement sur tablette ou grand écran. États d'erreur communs : serveur injoignable, session expirée, licence expirée, inventaire clôturé (`apercus/1` à droite).

---

## 4. Plan par étapes, sans régression

### 4.1 Filet de sécurité (avant toute modification)
- **Balises git** avant chaque étape (`prestinv-avant-etape-1`, …) et note de version par étape (comme `docs/BALISES_INTERFACE.md` de vente_app).
- **Interrupteur « Nouvelle interface »** (copie de `InterfaceVersion` de vente_app) : éteint, l'accueil et les écrans d'origine restent **intacts**.
- **Mêmes clés de stockage** : réglages, positions et filtres conservés ; au premier lancement de la nouvelle version, les attentes `inv_*_unsynced` existantes sont **reprises dans le journal** (aucune saisie perdue lors de la mise à jour).
- **Tests** : réparer le test existant ; tests unitaires de la file (envoi, échec, reprise, valeur modifiée pendant l'envoi, double OK, cumul sans réseau) avec un faux serveur ; tests de widgets par écran (chargement / erreur / vide / données ; 360 px et 1024 px) ; retrait du mot de passe du test d'intégration.
- **CI GitHub Actions** : `flutter analyze` + `flutter test` + build APK à chaque envoi.

### 4.2 Étapes et estimation

| Étape | Contenu | Risque | Estimation |
|---|---|---|---|
| 0 | Socle : CI, test réparé, mot de passe retiré des tests, une seule version (`pubspec.yaml` → Android), interrupteur, palette `Pal` partagée, nettoyage code mort | Nul (aucun écran changé) | 1-1,5 j |
| 1 | **Fiabilité de la saisie** sans changer l'apparence : journal local persistant, file d'envoi rejouable, reprise, cumul sûr, OK verrouillé, champ vide refusé, longueur max, seuil partout, attentes visibles sur l'accueil (corrige P1 à P9) | Moyen → couvert par tests unitaires + migration des attentes | 4-5 j |
| 2 | **Robustesse & sécurité** : erreurs distinctes, serveur ≠ licence, session expirée avec reconnexion, plus de mot de passe stocké, PIN réglages, journaux, délais, contrôles de configuration, licence alignée sur le serveur | Faible | 2-3 j |
| 3 | **Ergonomie scan** : douchette toujours prête, touches physiques, bip/vibration, feuille Remplacer/Ajouter, journal de scan | Faible (ajout) | 2-3 j |
| 4 | **Refonte visuelle** A/B (accueil, rayons, saisie, écarts, restants, collecte) derrière l'interrupteur, puis C tablette | Moyen → un écran à la fois | 6-8 j |
| 5 | Serveur (si validé) : `PUT` authentifié + contrôle inventaire ouvert + auteur, route « état des rayons », licence ; app adaptée | Moyen (serveur partagé avec les autres apps) | 1,5-2,5 j |
| 6 | Publication : clé de signature release, permissions nettoyées, HTTPS en distant si le serveur l'offre | Moyen | 0,5-1 j |

Total indicatif : **17 à 25 jours**, livrable étape par étape ; l'étape 1 seule supprime déjà les pertes de comptage. Recommandation : **ne pas lancer d'inventaire annuel avec la saisie rapide en mode Collecte** avant l'étape 1 (utiliser le mode Direct ou la saisie guidée par rayon).

---

## 5. Questions à valider

1. **Mode Scan + Collecte** : l'équipe l'utilise-t-elle aujourd'hui ? Des comptages ont-ils « disparu » lors d'un inventaire passé (cela confirmerait P1) ?
2. **Licence** : l'activation depuis l'application a-t-elle déjà fonctionné ? (Sinon on aligne l'app sur la route serveur `GET /licence/save/{clé}` et on décide si elle doit être accessible avant connexion.)
3. **Plusieurs terminaux sur le même rayon** : est-ce courant ? Préférez-vous « Ajouter » par défaut, « Remplacer » par défaut, ou toujours demander ?
4. **Mode d'envoi par défaut** après refonte : Direct (envoi immédiat, file en secours) — d'accord ? Faut-il garder le choix Direct / Collecte dans les réglages ?
5. **Collecte libre** : doit-elle pouvoir être **versée dans un inventaire** de Prestige (codes + quantités) ? Si oui, une route serveur d'import des quantités est nécessaire (aujourd'hui l'import ne crée qu'un inventaire à partir des CIP).
6. **Serveur** : accepte-t-on que l'enregistrement d'une quantité exige désormais la connexion et soit refusé sur un inventaire clôturé ? (Correction la plus importante côté sécurité.)
7. **Traçabilité** : afficher « compté par Koffi à 08:55 » demande d'enregistrer l'auteur côté serveur — souhaité ?
8. **Stock théorique** : doit-il rester masquable (comptage « à l'aveugle ») et, si oui, ce choix est-il réservé à l'administrateur (PIN) ?
9. **Terminaux** : quels modèles Sunmi exactement (V2, V2 Pro, L2s, avec ou sans clavier physique) ? Pour régler la douchette et la taille des touches.
10. **Seuils** : quantité maximale acceptée (proposé 99 999) et seuil d'alerte « grande quantité » (aujourd'hui 1 000) — valeurs à garder ?
11. **Présentation** : A + B sur téléphone/terminal et C sur tablette — d'accord ? Le choix est-il réservé à l'administrateur comme dans vente_app ?
12. **Mode Distant** : passe-t-il par Internet ? Si oui, peut-on mettre le serveur en **HTTPS** ?
13. **Ordre** : Fiabilité (1) → Robustesse/sécurité (2) → Scan (3) → Refonte (4) → Serveur (5) — d'accord, ou faut-il avancer l'étape serveur (5) avant le prochain inventaire ?
14. Écran « Analyse » (camembert) : utile, ou à remplacer par le bilan en valeur des écarts (aperçu 4) ?
