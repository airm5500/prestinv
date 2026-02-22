// lib/models/product.dart

class Product {
  final int id;
  final String produitCip;
  final String produitName;
  final double produitPrixAchat;
  final double produitPrixUni;
  final int quantiteInitiale;
  int quantiteSaisie;
  bool isSynced;
  final String? dtUpdated; // Nouveau champ pour la date de mise à jour
  String? locationLabel;

  Product({
    required this.id,
    required this.produitCip,
    required this.produitName,
    required this.produitPrixAchat,
    required this.produitPrixUni,
    required this.quantiteInitiale,
    required this.quantiteSaisie,
    this.isSynced = true,
    this.dtUpdated,
    this.locationLabel,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      produitCip: json['produitCip'] ?? '',
      produitName: json['produitName'] ?? '',
      produitPrixAchat: (json['produitPrixAchat'] as num?)?.toDouble() ?? 0.0,
      produitPrixUni: (json['produitPrixUni'] as num?)?.toDouble() ?? 0.0,
      quantiteInitiale: json['quantiteInitiale'] ?? 0,
      quantiteSaisie: json['quantiteSaisie'] ?? 0,
      isSynced: json['isSynced'] ?? true,
      dtUpdated: json['dtUpdated'], // Récupération de la date
      locationLabel: json['locationLabel'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'produitCip': produitCip,
      'produitName': produitName,
      'produitPrixAchat': produitPrixAchat,
      'produitPrixUni': produitPrixUni,
      'quantiteInitiale': quantiteInitiale,
      'quantiteSaisie': quantiteSaisie,
      'isSynced': isSynced,
      'dtUpdated': dtUpdated,
      'locationLabel': locationLabel,
    };
  }
}