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

  // NOUVEAU : Pour stocker le nom de l'emplacement (utile en mode Global)
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
    this.locationLabel,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      produitCip: json['produitCip'],
      produitName: json['produitName'],
      produitPrixAchat: (json['produitPrixAchat'] as num).toDouble(),
      produitPrixUni: (json['produitPrixUni'] as num).toDouble(),
      quantiteInitiale: json['quantiteInitiale'],
      quantiteSaisie: json['quantiteSaisie'],
      isSynced: json['isSynced'] ?? true,
      locationLabel: json['locationLabel'], // Récupération si sauvegardé
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
      'locationLabel': locationLabel, // Sauvegarde
    };
  }
}