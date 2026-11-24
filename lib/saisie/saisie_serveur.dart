// lib/saisie/saisie_serveur.dart
// Ce dont la file des saisies a besoin du serveur (remplaçable par un faux serveur dans les tests).

/// Nature du résultat d'un envoi.
enum ResultatEnvoi {
  /// Le serveur a enregistré la quantité.
  ok,

  /// Serveur injoignable / délai dépassé : on garde la saisie et on réessaiera.
  reseau,

  /// Session expirée ou accès refusé (401 / 403) : on garde la saisie, reconnexion nécessaire.
  session,

  /// Refus MÉTIER définitif (4xx explicite : 400, 404 JSON, 409, 422…) : la saisie passe en « refusée »,
  /// visible, jamais renvoyée seule.
  refus,

  /// Erreur du serveur (5xx, réponse illisible) : la saisie RESTE en attente et est renvoyée automatiquement
  /// (5.0.2 : jamais « refusée », quel que soit le nombre d'essais : serveur qui s'arrête, redémarre…).
  erreurServeur,

  /// 5.0.4 — Le serveur refuse toute écriture tant que SON heure est fausse (HTTP 423, `horlogeBloquee:true`).
  /// Ce n'est ni une panne réseau ni un refus de la saisie : elle RESTE en attente (même quantité totale, aucun
  /// doublon) et repart seule, à intervalles espacés, quand l'heure du serveur est remise. Le message est celui
  /// du serveur, affiché tel quel.
  horlogeBloquee,
}

class ReponseEnvoi {
  final ResultatEnvoi type;
  final String message;
  const ReponseEnvoi(this.type, [this.message = '']);

  static const ok = ReponseEnvoi(ResultatEnvoi.ok);
  bool get estOk => type == ResultatEnvoi.ok;
}

/// Liste des inventaires ouverts lue sans erreur (peut être vide).
class InventairesOuverts {
  final Set<String> ids;
  const InventairesOuverts(this.ids);
}

/// Le serveur refuse la lecture faute de session valide (401 / 403, ou réponse « Veuillez vous
/// connecter ») : il faut se reconnecter, ce n'est PAS une panne réseau.
class SessionServeurExpiree implements Exception {
  final String message;
  const SessionServeurExpiree([this.message = 'Session expirée.']);

  @override
  String toString() => message;
}

abstract class SaisieServeur {
  /// Pose la quantité TOTALE [quantite] sur la ligne [ligneId]. Ne lève jamais : le résultat est classé.
  Future<ReponseEnvoi> poserQuantite(int ligneId, int quantite);

  /// Comme [poserQuantite], par la route qui exige la session et enregistre l'AUTEUR de la saisie
  /// (`POST /inventaire/ligne/quantite`) ; serveur sans cette route : route habituelle.
  /// Utilisée pour le versement de la collecte.
  Future<ReponseEnvoi> poserQuantiteSession(int ligneId, int quantite);

  /// Identifiants des inventaires encore ouverts sur le serveur (`null` si la liste n'a pas pu être lue).
  /// Session expirée ou accès refusé : lève [SessionServeurExpiree].
  Future<InventairesOuverts?> inventairesOuverts();
}
