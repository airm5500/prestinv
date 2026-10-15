// lib/inventaire/autorisation_creation.dart
// Qui peut CRÉER un inventaire depuis le terminal (nouvelle interface, 4.13) ?
//
// Le profil vient de la réponse de connexion (POST /user/auth → « xtypeuser », voir AppUser.typeAccueil) :
// le serveur Prestige y répond « dashboard » pour l'utilisateur système, le pharmacien, l'administrateur
// et le super administrateur, « mainmenumanager » pour les autres profils.
//  - administrateur / pharmacien : toujours autorisés ;
//  - autres profils : seulement si le réglage « Autoriser la création d'inventaire aux autres comptes »
//    (protégé par le code administrateur, désactivé par défaut) est activé ; sinon le bouton est masqué ;
//  - profil inconnu (serveur qui n'envoie pas « xtypeuser ») : la création demande le code
//    administrateur du terminal (décision du pharmacien), sauf si le réglage l'autorise à tous.
// Voir docs/DEMANDE_SERVEUR_COMPTAGE.md (demande d'un rôle explicite).

enum AccesCreation {
  /// Création directe.
  autorise,

  /// Création après le code administrateur du terminal.
  codeAdmin,

  /// Pas de création pour ce compte (bouton masqué).
  refuse,
}

/// [adminOuPharmacien] : null si le serveur n'a pas donné le profil.
///
/// 4.15 — [droitServeur] : droit « Créer un inventaire » donné par le serveur à la connexion
/// (`droits.creerInventaire`, privilège P_CREER_INVENTAIRE, demande 10). Quand il est connu, c'est LUI
/// qui décide (le serveur refuserait de toute façon la création, 403) : vrai → création directe ;
/// faux → refusée, quel que soit le réglage du terminal. Inconnu (serveur ancien) : règles de la 4.13.
AccesCreation accesCreation({required bool? adminOuPharmacien, required bool autresComptesAutorises, bool? droitServeur}) {
  if (droitServeur != null) return droitServeur ? AccesCreation.autorise : AccesCreation.refuse;
  if (adminOuPharmacien == true || autresComptesAutorises) return AccesCreation.autorise;
  if (adminOuPharmacien == null) return AccesCreation.codeAdmin;
  return AccesCreation.refuse;
}
