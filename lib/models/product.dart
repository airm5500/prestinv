class Product {
  final int id;
  final String produitCip;
  final String produitName;
  final double produitPrixAchat;
  final double produitPrixUni;
  final int quantiteInitiale;
  int quantiteSaisie; // mutable
  bool isSynced; // pour le suivi de la synchronisation

  Product({
    required this.id,
    required this.produitCip,
    required this.produitName,
    required this.produitPrixAchat,
    required this.produitPrixUni,
    required this.quantiteInitiale,
    required this.quantiteSaisie,
    this.isSynced = true, // Par défaut, on considère que c'est synchronisé
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
    );
  }
}