class Rayon {
  final String id;
  final String code;
  final String libelle;

  Rayon({required this.id, required this.code, required this.libelle});

  String get displayName => '$code - $libelle';

  factory Rayon.fromJson(Map<String, dynamic> json) {
    return Rayon(
      id: json['id'],
      code: json['code'],
      libelle: json['libelle'],
    );
  }
}