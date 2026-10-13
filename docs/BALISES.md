# Balises de retour arrière (Prestige Inventaire)

Chaque étape de la refonte part d'une **balise git** posée sur l'état précédent. En cas de problème
sur le terrain, on peut reconstruire l'APK d'avant l'étape sans rien chercher dans l'historique.

| Balise | Posée sur | Contenu |
|---|---|---|
| `prestinv-avant-etape-0` | `d09ef4e` (master d'origine, 26/02/2026) | Application telle que livrée avant toute modification (version affichée 4.8.5). |
| `prestinv-avant-etape-1` | dernier commit de l'étape 0 | Socle : CI, test réparé, mot de passe retiré des tests, version unique 4.9.0+5, interrupteur `InterfaceVersion` (éteint). Aucun écran changé. |
| `prestinv-avant-etape-2` | dernier commit de l'étape 1 | Fiabilité de la saisie (file locale persistante des saisies, envoi rejouable, « À envoyer », mode Direct par défaut pour les nouvelles installations). |
| `prestinv-avant-etape-3` | dernier commit de l'étape 2 | Robustesse et sécurité (erreurs ≠ liste vide, session expirée, serveur injoignable ≠ licence, mot de passe chiffré, code administrateur, contrôles de saisie). |

Les balises sont créées **localement** ; les publier avec :

```bash
git push origin prestinv-avant-etape-0 prestinv-avant-etape-1 prestinv-avant-etape-2 prestinv-avant-etape-3
```

## Revenir à une version précédente

```bash
git checkout prestinv-avant-etape-1      # par exemple
flutter build apk --release
```

**Attention, après l'étape 1** : les saisies non envoyées sont gardées dans la nouvelle file locale
(`saisies_v1.jsonl`), plus dans les anciennes clés `inv_<inventaire>_ray_<rayon>_unsynced`.
Avant de réinstaller une version antérieure à l'étape 1, **envoyer toutes les saisies**
(Accueil → « À envoyer » doit être vide), sinon l'ancienne version ne les verra pas.

## Interrupteur « Nouvelle interface »

`lib/interface_version.dart` (même principe que `prestige_vente_app`). Éteint par défaut ; tant que
la nouvelle interface (étape 4) n'existe pas, les deux positions ouvrent les écrans d'origine et le
réglage n'est pas affiché. À l'étape 4 il sera ajouté à la Configuration (`InterfaceVersionTile`) pour
revenir aux écrans d'origine sans réinstaller.

## Essai réel contre un serveur de test

`test_reel/essai_serveur_reel_test.dart` (hors CI) : connexion, lecture des inventaires, « déjà
compté », file persistante (correction pendant l'envoi, redémarrage), 401, licence. La ligne de test
reçoit des quantités puis sa valeur d'origine ; la date de comptage (`dt_UPDATED`) est à remettre à
la main (SQL) sur le serveur de test.

## Règle de version

Une seule version, dans `pubspec.yaml` (`version: X.Y.Z+N`) ; Android la reprend
(`versionName = X.Y.Z`, `versionCode = N`). Augmenter `N` à chaque APK diffusé.
