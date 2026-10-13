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
      id: (json['id'] as num).toInt(),
      produitCip: '${json['produitCip'] ?? ''}',
      produitName: '${json['produitName'] ?? ''}',
      produitPrixAchat: (json['produitPrixAchat'] as num?)?.toDouble() ?? 0.0,
      produitPrixUni: (json['produitPrixUni'] as num?)?.toDouble() ?? 0.0,
      quantiteInitiale: (json['quantiteInitiale'] as num?)?.toInt() ?? 0,
      quantiteSaisie: (json['quantiteSaisie'] as num?)?.toInt() ?? 0,
      isSynced: json['isSynced'] is bool ? json['isSynced'] as bool : true,
      dtUpdated: json['dtUpdated']?.toString(), // Récupération de la date
      locationLabel: json['locationLabel']?.toString(),
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