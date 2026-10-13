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

  /// Refus définitif (4xx) : la saisie passe en « refusée », visible, jamais renvoyée seule.
  refus,

  /// Erreur du serveur (5xx) : réessayée, puis « refusée » après plusieurs échecs.
  erreurServeur,
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

abstract class SaisieServeur {
  /// Pose la quantité TOTALE [quantite] sur la ligne [ligneId]. Ne lève jamais : le résultat est classé.
  Future<ReponseEnvoi> poserQuantite(int ligneId, int quantite);

  /// Identifiants des inventaires encore ouverts sur le serveur (`null` si la liste n'a pas pu être lue).
  Future<InventairesOuverts?> inventairesOuverts();
}
