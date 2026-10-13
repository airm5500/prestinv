// lib/saisie/saisie.dart
// Une quantité comptée pour UNE ligne d'inventaire (identifiant de détail serveur), gardée sur
// l'appareil tant qu'elle n'est pas confirmée par le serveur.
//
// La quantité est TOUJOURS la quantité totale à poser sur la ligne (le serveur fait « quantite = X »,
// jamais « + X ») : renvoyer la même saisie deux fois ne crée donc aucun doublon (envoi idempotent).

enum EtatSaisie {
  /// Enregistrée sur l'appareil, pas encore confirmée par le serveur.
  enAttente,

  /// Confirmée par le serveur (valeur [SaisieLigne.quantiteEnvoyee]).
  envoyee,

  /// Refusée par le serveur ou inventaire clôturé : gardée, visible dans « À envoyer », jamais
  /// renvoyée sans action de l'utilisateur.
  refusee,
}

/// Origine d'une saisie. [versement] : quantité versée depuis la collecte hors ligne (envoyée par la
/// route qui enregistre l'auteur, voir SaisieServeur.poserQuantiteSession).
enum OrigineSaisie { guidee, rapide, ecarts, restants, migration, versement }

class SaisieLigne {
  final String inventaireId;
  final int ligneId;
  String inventaireLibelle;
  String cip;
  String nom;
  String? rayonId;
  String? rayonLibelle;

  /// Quantité TOTALE à poser sur la ligne.
  int quantite;

  /// Augmente à chaque nouvelle saisie locale de la ligne : une réponse du serveur ne marque la
  /// ligne « envoyée » que si elle concerne encore la dernière version (correction pendant l'envoi).
  int version;

  EtatSaisie etat;

  /// Dernière quantité confirmée par le serveur (null : jamais confirmée).
  int? quantiteEnvoyee;

  /// Motif du refus (état [EtatSaisie.refusee]) ou de la dernière erreur.
  String? motif;

  /// Erreurs serveur (5xx) successives sur cette ligne.
  int tentatives;

  OrigineSaisie origine;

  /// Envoyée automatiquement même en mode Collecte (corrections Écarts / Restants, qui partent
  /// toujours tout de suite).
  bool envoiAuto;

  String auteur;
  final DateTime creeLe;
  DateTime modifieLe;
  DateTime? envoyeeLe;

  SaisieLigne({
    required this.inventaireId,
    required this.ligneId,
    this.inventaireLibelle = '',
    this.cip = '',
    this.nom = '',
    this.rayonId,
    this.rayonLibelle,
    required this.quantite,
    this.version = 1,
    this.etat = EtatSaisie.enAttente,
    this.quantiteEnvoyee,
    this.motif,
    this.tentatives = 0,
    this.origine = OrigineSaisie.guidee,
    this.envoiAuto = false,
    this.auteur = '',
    required this.creeLe,
    required this.modifieLe,
    this.envoyeeLe,
  });

  static String cleDe(String inventaireId, int ligneId) => '$inventaireId#$ligneId';

  String get cle => cleDe(inventaireId, ligneId);

  bool get enAttente => etat == EtatSaisie.enAttente;
  bool get refusee => etat == EtatSaisie.refusee;
  bool get envoyee => etat == EtatSaisie.envoyee;

  Map<String, dynamic> toJson() => {
        'inv': inventaireId,
        'id': ligneId,
        'invLib': inventaireLibelle,
        'cip': cip,
        'nom': nom,
        'rayon': rayonId,
        'rayonLib': rayonLibelle,
        'q': quantite,
        'v': version,
        'etat': etat.name,
        'qEnv': quantiteEnvoyee,
        'motif': motif,
        'tent': tentatives,
        'orig': origine.name,
        'auto': envoiAuto,
        'auteur': auteur,
        'cree': creeLe.toIso8601String(),
        'modif': modifieLe.toIso8601String(),
        'env': envoyeeLe?.toIso8601String(),
      };

  /// Lecture tolérante : une ligne illisible lève une exception (ignorée par le magasin).
  factory SaisieLigne.fromJson(Map<String, dynamic> j) {
    T enumDe<T extends Enum>(List<T> valeurs, Object? nom, T defaut) =>
        valeurs.where((v) => v.name == nom).firstOrNull ?? defaut;
    final inv = j['inv'];
    final id = j['id'];
    final q = j['q'];
    if (inv is! String || inv.isEmpty || id is! num || q is! num) {
      throw const FormatException('saisie incomplète');
    }
    final cree = DateTime.tryParse('${j['cree']}') ?? DateTime.now();
    return SaisieLigne(
      inventaireId: inv,
      ligneId: id.toInt(),
      inventaireLibelle: '${j['invLib'] ?? ''}',
      cip: '${j['cip'] ?? ''}',
      nom: '${j['nom'] ?? ''}',
      rayonId: j['rayon'] as String?,
      rayonLibelle: j['rayonLib'] as String?,
      quantite: q.toInt(),
      version: (j['v'] as num?)?.toInt() ?? 1,
      etat: enumDe(EtatSaisie.values, j['etat'], EtatSaisie.enAttente),
      quantiteEnvoyee: (j['qEnv'] as num?)?.toInt(),
      motif: j['motif'] as String?,
      tentatives: (j['tent'] as num?)?.toInt() ?? 0,
      origine: enumDe(OrigineSaisie.values, j['orig'], OrigineSaisie.guidee),
      envoiAuto: j['auto'] == true,
      auteur: '${j['auteur'] ?? ''}',
      creeLe: cree,
      modifieLe: DateTime.tryParse('${j['modif']}') ?? cree,
      envoyeeLe: j['env'] == null ? null : DateTime.tryParse('${j['env']}'),
    );
  }
}
