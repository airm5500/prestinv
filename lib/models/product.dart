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

  /// 4.16.1 (demande serveur 50) — auteur de la dernière saisie (`auteurLogin`, `auteurNom` des routes
  /// ws/inventaires/details*) ; null : serveur plus ancien, ou ligne jamais saisie.
  final String? auteurLogin;
  final String? auteurNom;

  /// Nom à afficher (« compté par … ») : nom complet, sinon identifiant ; null si inconnu.
  String? get auteur {
    final n = (auteurNom ?? '').trim();
    if (n.isNotEmpty) return n;
    final l = (auteurLogin ?? '').trim();
    return l.isEmpty ? null : l;
  }

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
    this.auteurLogin,
    this.auteurNom,
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
      auteurLogin: json['auteurLogin'] is String ? json['auteurLogin'] as String : null,
      auteurNom: json['auteurNom'] is String ? json['auteurNom'] as String : null,
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
      if (auteurLogin != null) 'auteurLogin': auteurLogin,
      if (auteurNom != null) 'auteurNom': auteurNom,
    };
  }
}