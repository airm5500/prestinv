class Rayon {
  final String id;
  final String code;
  final String libelle;

  Rayon({required this.id, required this.code, required this.libelle});

  String get displayName => '$code - $libelle';

  factory Rayon.fromJson(Map<String, dynamic> json) {
    return Rayon(
      id: '${json['id'] ?? ''}',
      code: '${json['code'] ?? ''}',
      libelle: '${json['libelle'] ?? ''}',
    );
  }
}
/// État de comptage d'un rayon (demande 30 : `GET /ws/inventaires/{id}/rayons/etat`), lignes RETENUES
/// seulement (bool_INVENTAIRE = 1).
class EtatRayon {
  final Rayon rayon;
  final int totalProduits;
  final int comptes;
  final int restants;
  const EtatRayon({required this.rayon, required this.totalProduits, required this.comptes, required this.restants});

  /// 0 : pas commencé ; 1 : commencé ; 2 : terminé (mêmes valeurs que EntryProvider.rayonStatuses).
  int get statut => comptes <= 0 ? 0 : (restants <= 0 ? 2 : 1);

  factory EtatRayon.fromJson(Map<String, dynamic> j) {
    int n(String k) {
      final v = j[k];
      if (v is num) return v.toInt();
      final p = int.tryParse('${v ?? ''}');
      if (p == null) throw FormatException('champ $k illisible');
      return p;
    }

    final id = '${j['rayonId'] ?? ''}'.trim();
    if (id.isEmpty) throw const FormatException('rayon sans identifiant');
    final total = n('totalProduits');
    final comptes = n('comptes');
    return EtatRayon(
      rayon: Rayon(id: id, code: '${j['code'] ?? ''}', libelle: '${j['libelle'] ?? ''}'),
      totalProduits: total,
      comptes: comptes,
      restants: j['restants'] == null ? total - comptes : n('restants'),
    );
  }
}
