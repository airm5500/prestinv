class Inventory {
  final String id;
  final String libelle;

  Inventory({required this.id, required this.libelle});

  factory Inventory.fromJson(Map<String, dynamic> json) {
    return Inventory(
      id: json['id'],
      libelle: json['libelle'],
    );
  }
}