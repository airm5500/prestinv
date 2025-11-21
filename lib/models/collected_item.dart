// lib/models/collected_item.dart

class CollectedItem {
  final String code;
  int quantity;
  final DateTime dateScan;

  CollectedItem({
    required this.code,
    required this.quantity,
    required this.dateScan,
  });

  // Conversion en JSON pour la sauvegarde
  Map<String, dynamic> toJson() => {
    'code': code,
    'quantity': quantity,
    'dateScan': dateScan.toIso8601String(),
  };

  // Création depuis JSON pour le chargement
  factory CollectedItem.fromJson(Map<String, dynamic> json) => CollectedItem(
    code: json['code'],
    quantity: json['quantity'],
    dateScan: DateTime.parse(json['dateScan']),
  );
}