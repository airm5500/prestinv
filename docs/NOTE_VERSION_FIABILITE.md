# Prestige Inventaire 4.9.0 — Note de version « Fiabilité de la saisie »

*Pour le pharmacien et l'équipe qui compte. Rien ne change dans l'apparence des écrans de saisie :
les boutons, les claviers et les parcours sont les mêmes. Ce qui change, c'est qu'**aucune quantité
saisie ne peut plus se perdre**.*

Version : **4.9.0** (code 5). Elle s'installe par-dessus l'ancienne 4.8.5 sans la désinstaller.

---

## 1. Ce qui change pour vous

### Chaque quantité est gardée sur le terminal avant d'être envoyée
- Dès que vous appuyez sur **OK**, la quantité est écrite dans la mémoire du terminal, **avant**
  l'envoi au serveur et **avant** de passer au produit suivant.
- Elle y reste tant que le serveur ne l'a pas confirmée : fermeture de l'application, appel,
  batterie vide, redémarrage du terminal… **rien n'est perdu**.
- Le serveur reçoit toujours la **quantité totale** (« 12 », jamais « + 3 ») : renvoyer deux fois la
  même saisie ne crée aucun doublon.

### Saisie rapide (Scan) : plus de perte
- **Avant** : en mode Collecte, seul le **dernier** produit scanné était gardé ; les autres étaient
  perdus. **Maintenant** : 50 scans = 50 quantités gardées, puis envoyées.
- L'export CSV de la saisie rapide contient toutes les quantités de l'inventaire.

### « Déjà compté ? » (cumul) sur réseau lent
- **Avant** : si le réseau était lent, l'application concluait « jamais compté » et **remplaçait**
  le comptage d'un collègue.
- **Maintenant** : si la vérification échoue, une fenêtre **« Vérification impossible »** s'ouvre
  avec **Réessayer** / **Annuler**. Tant que la vérification n'a pas abouti, **rien n'est enregistré**.
- Le réglage « Cumul » reste le même (désactivé = **Remplacer**, comme avant) ; la question
  « Additionner ? » est inchangée.

### Mode Direct
- Une correction faite pendant l'envoi de la valeur précédente est bien envoyée ensuite.
- Le nuage vert **« Serveur à jour »** ne s'affiche que quand **tout** est réellement enregistré sur
  le serveur ; sinon le nuage orange reste affiché.
- **Nouvelles installations : mode Direct par défaut.** Si vous utilisiez déjà l'application, votre
  réglage est **conservé** (y compris Collecte si vous n'aviez jamais changé le réglage).

### Écarts et Restants
- **OK sur un champ vide est refusé** (« Veuillez saisir une quantité. »). Avant, cela enregistrait
  0 (« produit absent »). Pour un produit absent, tapez **0**.
- Le produit n'est marqué **vérifié** (Écarts) ou **retiré de la liste** (Restants) qu'**après**
  confirmation du serveur. En cas d'échec : message en rouge, la saisie reste gardée et repart
  toute seule.
- Le bouton **OK** est verrouillé pendant l'envoi (sablier) : un double appui n'envoie qu'une fois.
- En saisie guidée aussi, un double appui sur OK ne saute plus de produit.

### Nouveau : « À envoyer »
- Sur l'accueil, un bandeau orange **« N saisie(s) à envoyer »** apparaît quand des quantités ne sont
  pas encore sur le serveur — **tous rayons et tous inventaires confondus**. Il disparaît quand tout
  est envoyé.
- En le touchant : la liste des saisies en attente (produit, rayon, heure, quantité, état),
  le bouton **« Envoyer maintenant »**, et pour une saisie **refusée** : « Remettre en attente » ou
  « Supprimer ».
- **Inventaire clôturé** : une saisie d'un inventaire clôturé n'est **jamais** envoyée ; elle
  apparaît « Refusée : Inventaire clôturé ou supprimé sur le serveur ».
- La déconnexion ne fait plus perdre les saisies : elles repartent à la connexion suivante.

### Erreurs plus claires
- **Serveur injoignable ≠ liste vide** : au lieu de « Aucun inventaire » / « Aucun écart » /
  « Tout est inventorié ! » / « Produit introuvable », l'écran affiche **« Chargement
  impossible »** avec **Réessayer**.
- **Session expirée** : bouton **« Se reconnecter »** (fenêtre de connexion, sans quitter l'écran ;
  les saisies sont gardées).
- **Premier lancement serveur éteint** : écran **« Serveur injoignable »** (et non plus
  « Application non activée »), avec nouvel essai automatique toutes les 10 secondes.
- La licence est revérifiée au retour dans l'application sans sablier plein écran.

### Sécurité
- Le **mot de passe** mémorisé (« Rester connecté ») est désormais chiffré par le terminal (il était
  en clair). Le passage se fait tout seul au premier lancement ; vous restez connecté.
- **Configuration du serveur protégée par un code administrateur** : adresse, port et contexte ne
  sont modifiables qu'après le code. **Code initial : 1234** ; il faut alors choisir un nouveau code
  (4 à 8 chiffres, pas de suite ni de répétition). Après 5 erreurs : attente de 30 s, puis plus.
  Les autres réglages (seuils, cumul, mode d'envoi, stock théorique) et le choix Local / Distant
  restent libres.
- Les journaux techniques ne contiennent plus ni mot de passe, ni cookie, ni clé de licence.
- Adresse **https://** acceptée (si le serveur la propose) ; http:// reste le défaut.
- Contrôles de saisie : quantités de 0 à 99 999 (5 chiffres au plus), port 1 à 65 535, adresse IP
  ou nom valides, seuils bornés ; recherches et codes scannés limités à 60 caractères.

---

## 2. Comment tester sur un terminal Sunmi (V2s, V3H, V3, V3 Mix) ou un téléphone

Prévoir **un inventaire de test** ouvert sur le poste Prestige (ne pas tester sur l'inventaire
annuel), et noter 3 produits avec leur quantité avant l'essai pour la remettre ensuite.

1. **Installation par-dessus** l'ancienne version : vérifier que la connexion fonctionne et que le
   réglage « Mode d'envoi » n'a pas changé (Configuration).
2. **Saisies en attente de l'ancienne version** : si des saisies n'avaient pas été envoyées avant la
   mise à jour, le bandeau « À envoyer » les montre dès l'accueil.
3. **Saisie rapide (Scan) en mode Collecte** : scanner 10 produits différents, **forcer l'arrêt**
   de l'application (Paramètres Android → Applications → Prestige Inventaire → Forcer l'arrêt),
   relancer : le bandeau « 10 saisie(s) à envoyer » apparaît ; « Envoyer maintenant » → les 10
   quantités sont sur le poste Prestige (avant, seule la dernière l'était).
4. **Saisie guidée hors réseau** : ouvrir un rayon, couper le Wi-Fi, saisir 5 produits, rallumer le
   Wi-Fi : en mode Direct, elles partent seules en moins de 15 secondes (nuage vert).
5. **Correction rapide en Direct** : saisir 5, revenir (‹) et corriger en 50 aussitôt : le poste
   Prestige doit afficher 50.
6. **Cumul activé, réseau coupé** : en saisie rapide, scanner un produit déjà compté, Wi-Fi coupé :
   la fenêtre « Vérification impossible » doit apparaître ; Annuler ⇒ rien n'est enregistré.
7. **Écarts / Restants** : OK sur un champ vide ⇒ message, rien d'envoyé ; Wi-Fi coupé ⇒ message
   rouge, produit **non** coché ; Wi-Fi rallumé ⇒ la saisie part seule.
8. **Inventaire clôturé** : saisir en Collecte, clôturer l'inventaire sur le poste, puis « Envoyer
   maintenant » ⇒ saisies « Refusées : inventaire clôturé », rien de modifié sur le poste.
9. **Serveur éteint au premier lancement** (terminal neuf ou données effacées) : écran « Serveur
   injoignable » avec compte à rebours ; rallumer le serveur ⇒ l'écran de connexion arrive seul.
10. **Configuration** : « Modifier la connexion (code administrateur) » ⇒ 1234 ⇒ choisir un code ;
    le noter dans un endroit sûr.
11. **Rester connecté** : cocher, se connecter, fermer/rouvrir l'application ⇒ identifiant et mot de
    passe toujours pré-remplis.

Remettre ensuite les quantités notées des 3 produits sur le poste Prestige.

---

## 3. Ce qui ne change pas (encore)

- **Activation de la licence depuis l'application** : elle n'a jamais fonctionné et ne fonctionne
  toujours pas — l'application envoie une demande que le serveur refuse (le serveur attend une autre
  forme d'appel et exige d'être connecté, alors que l'écran d'activation s'affiche avant la
  connexion). Correction prévue avec l'**étape serveur**. En attendant : activer la licence depuis
  le poste Prestige.
- **Le serveur accepte encore une quantité sans connexion** et ne note pas qui a compté ; il ne
  refuse pas lui-même un inventaire clôturé (c'est l'application qui le vérifie avant d'envoyer).
  Corrections prévues à l'**étape serveur**.
- Collecte libre (hors ligne) : toujours sans versement dans Prestige (export CSV / PDF comme avant).
- Apparence : inchangée (la refonte visuelle est une étape ultérieure, derrière un interrupteur).

## 4. Revenir à l'ancienne version

Voir `docs/BALISES.md`. **Avant** de réinstaller une version antérieure : **envoyer toutes les
saisies** (bandeau « À envoyer » absent de l'accueil), car l'ancienne version ne lit pas la nouvelle
mémoire des saisies.
