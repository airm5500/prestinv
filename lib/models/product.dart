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

  Product({
    required this.id,
    required this.produitCip,
    required this.produitName,
    required this.produitPrixAchat,
    required this.produitPrixUni,
    required this.quantiteInitiale,
    required this.quantiteSaisie,
    this.isSynced = true,
  });

  // Constructeur pour créer un Product depuis un Map (JSON)
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      produitCip: json['produitCip'],
      produitName: json['produitName'],
      produitPrixAchat: (json['produitPrixAchat'] as num).toDouble(),
      produitPrixUni: (json['produitPrixUni'] as num).toDouble(),
      quantiteInitiale: json['quantiteInitiale'],
      quantiteSaisie: json['quantiteSaisie'],
      // On ajoute 'isSynced' pour la persistance locale
      isSynced: json['isSynced'] ?? true,
    );
  }

  // NOUVELLE MÉTHODE: Convertit un Product en Map (JSON) pour le stockage
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
    };
  }
}