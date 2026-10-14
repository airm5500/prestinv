# Taille de l'écran — module réutilisable (`lib/ui/taille_ecran.dart`)

*Prestige Inventaire 4.13. Écrit pour être repris tel quel dans les deux autres applications Prestige
(prestige_vente_app et la troisième application) : un seul fichier Dart, sans dépendance autre que
`flutter` et `shared_preferences`.*

## 1. Le besoin

Sur les petits terminaux (Sunmi V2s, écran 5,45″ : 720 × 1440 px, densité 2 → **360 × 720 dp**), les
écrans conçus pour un téléphone de 390 × 844 dp n'ont pas assez de hauteur : en 4.13.0, la saisie
guidée y coupait le bas de la carte produit (il fallait la faire défiler). Plutôt que de retoucher
chaque écran, un **réglage unique** réduit toute l'interface :

| Taille | Facteur | Surface vue par l'application sur un V2s | Effet |
|---|---|---|---|
| **Automatique** (défaut) | 1,0, ou 0,9 sur un petit écran | 400 × 800 dp (Compact appliqué) | taille définie par Android ; **Compact sur un petit écran** (4.13.1) |
| **Compact** | 0,9 | 400 × 800 dp | tout est 10 % plus petit |
| **Très compact** | 0,8 | 450 × 900 dp | tout est 20 % plus petit |

### Automatique sur les petits écrans (4.13.1)

`TailleEcranReglage.petitEcran(taille)` : écran **petit** si son **côté long < 740 dp** ou son **côté
court < 340 dp**, mesuré sur l'écran réel (taille de la vue, avant réduction), quelle que soit
l'orientation. `TailleEcranReglage.effective(choix, taille)` : Automatique → Compact sur un petit écran ;
**Compact et Très compact (choix manuels) restent prioritaires**. Calibrage :

| Appareil | Taille logique | Résultat |
|---|---|---|
| Sunmi V2s 720 × 1440, ×2 | 360 × 720 dp (≈ 672 sans barre de navigation) | Compact |
| Sunmi V3 / V3H / V3mix 1080 × 1920, ×3 ; téléphone 720 × 1280, ×2 | 360 × 640 dp | Compact |
| Téléphone 1080 × 2400, ×2,625 / ×2,75 | 411 × 914 / 393 × 873 dp | normale |
| Téléphone 1080 × 2400, ×3 (Samsung) | 360 × 800 dp (752 sans barre de navigation) | normale |
| Tablettes | 1280 × 800 dp… | normale |

Un seuil sur la seule largeur (< 380 dp) a été écarté : il aurait réduit les Samsung 1080 × 2400
(360 dp de large), qui ont assez de hauteur. Ce qui manque aux petits terminaux, c'est la hauteur.
Les réglages affichent alors « **Automatique (Compact appliqué sur cet écran)** »
(`TailleEcranReglage.compactAutomatique(context)`).

Le réglage est **protégé par le code administrateur** et **appliqué au prochain lancement** ; la fenêtre
qui suit le choix propose « **Relancer maintenant** » (l'interface est reconstruite et revient à
l'accueil ; la session, les saisies et la file d'envoi sont gardées). Il vaut pour **les deux
interfaces** (nouvelle et d'origine).

## 2. Le principe

```
runApp ─ providers ─ … ─ RacineTailleEcran            ← lit TailleEcranReglage.active
                          └ EchelleInterface(facteur)
                             ├ MediaQuery( taille / f, marges / f, clavier / f, densité × f )
                             └ FittedBox(fill) ─ SizedBox(taille / f)
                                └ MaterialApp (navigateur, fenêtres, feuilles, messages, calques)
```

- `EchelleInterface` se place **au-dessus de `MaterialApp`** : tout ce qui est dessiné par l'application
  — écrans, fenêtres (`showDialog`), feuilles du bas, messages (`SnackBar`), menus, info-bulles,
  poignées de sélection de texte — est dans le navigateur, donc réduit.
- Il publie une `MediaQuery` « vue de l'intérieur » : **taille**, **marges système** (barre d'état,
  encoche, barre de gestes), **clavier** (`viewInsets`) et **densité** (`devicePixelRatio × facteur`)
  sont ramenés à l'échelle. Un écran qui se cale au-dessus du clavier y reste exactement (le clavier de
  300 dp réels vaut 375 dp de l'interface en Très compact, réduits ensuite de 0,8 : 300 dp réels).
- Le rendu est réduit par une **transformation** (`FittedBox`), pas par une image : le texte reste net.
  Les **touchers** suivent la même transformation (aucun décalage). La position du curseur envoyée au
  clavier Android passe par la transformation globale du champ : elle reste juste.
- La **douchette** (événements clavier matériel, Sunmi « remplissage direct ») n'est pas concernée.
- `WidgetsApp` ne crée jamais sa propre `MediaQuery` (c'est le widget `View` qui le fait) : la nôtre est
  bien celle que voient tous les écrans.

Pourquoi pas le `devicePixelRatio` du moteur (classe `RendererBinding`) ? Les touchers sont convertis
avec la densité **réelle** de la vue (`GestureBinding`, privé) : changer la densité seulement au rendu
décalerait chaque toucher. La transformation au niveau des widgets n'a pas ce défaut.

## 3. Mode d'emploi (dans une autre application)

1. Copier `lib/ui/taille_ecran.dart`.
2. Dans `main()`, avant `runApp` :
   ```dart
   await TailleEcranReglage.charger();
   ```
3. Envelopper la `MaterialApp` (et rien d'autre) :
   ```dart
   return RacineTailleEcran(child: MaterialApp(...));
   ```
4. Dans les réglages (après le code administrateur) :
   ```dart
   await TailleEcranReglage.enregistrer(TailleEcran.compact); // prochain lancement
   // facultatif : Navigator.popUntil(premier écran) puis
   TailleEcranReglage.appliquerMaintenant();                  // « Relancer maintenant »
   ```
   `TailleEcranReglage.enAttente` indique qu'un choix attend le prochain lancement.

Clé enregistrée : `taille_ecran_v1` (`automatique`, `compact`, `tresCompact` ; toute autre valeur =
Automatique). Si la `MaterialApp` a une `navigatorKey` globale, le navigateur est conservé lors de la
relance (d'où le retour à l'accueil avant `appliquerMaintenant`).

## 4. Tests (dans Prestige Inventaire)

- `test/unitaires/regles_4_13_test.dart` : facteurs, données d'écran ramenées à l'échelle (taille,
  marges, clavier, densité), réglage mémorisé, valeur abîmée ; seuil des petits écrans (parc réel,
  limites exactes, choix manuels prioritaires).
- `test/ergonomie/petits_ecrans_test.dart` : V2s en Automatique → Compact, carte produit de la saisie
  guidée entière (coupée à 1,0) ; téléphone 1080 × 2400 en taille normale.
- `test/nv_4_13_test.dart` : touchers justes, bouton posé au-dessus du clavier sur l'écran réel,
  `RacineTailleEcran` qui suit le réglage (Automatique → Compact sur petit écran), mention dans les
  Réglages.
- `test/e2e/parcours_4_13_test.dart` : Réglages → Très compact (code administrateur) → « Relancer
  maintenant » → surface de 450 dp sur un V2s, la liste se déroule normalement.
- `test/ergonomie/` : **chaque écran** (nouvelle et ancienne interface) × appareils × texte 1,0 / 1,3 ×
  **Automatique / Compact / Très compact** ; champ de quantité au-dessus du pavé et du clavier système ;
  saisie guidée qui ne bouge pas. Aux tailles réduites, la cible tactile exigée est de 48 dp **de
  l'interface** (soit 43,2 / 38,4 dp réels : réduction voulue par l'administrateur) ; la règle de contraste
  de Flutter n'y est pas appliquée (elle mesure une capture à 1 px par dp où le texte réduit est flouté
  par le lissage ; les couleurs, identiques à toutes les tailles, sont contrôlées en Automatique).

## 5. Limites connues

- Les vues natives Android (aucune dans Prestige Inventaire) ne seraient pas réduites.
- Les captures d'écran système restent à la résolution réelle (normal).
- En Très compact, les textes de 12 dp deviennent 9,6 dp réels : à réserver aux petits terminaux.
