// lib/models/collected_item.dart

class CollectedItem {
  final String code;
  int quantity;
  final DateTime dateScan;

  /// Versé dans un inventaire (date) : la ligne n'est plus reversée ; un nouveau scan du même code crée
  /// une nouvelle ligne. null : pas encore versé.
  DateTime? verseLe;

  /// Libellé de l'inventaire où la ligne a été versée.
  String? verseDans;

  CollectedItem({
    required this.code,
    required this.quantity,
    required this.dateScan,
    this.verseLe,
    this.verseDans,
  });

  bool get versee => verseLe != null;

  // Conversion en JSON pour la sauvegarde (les versions précédentes ignorent les champs ajoutés).
  Map<String, dynamic> toJson() => {
        'code': code,
        'quantity': quantity,
        'dateScan': dateScan.toIso8601String(),
        if (verseLe != null) 'verseLe': verseLe!.toIso8601String(),
        if (verseDans != null) 'verseDans': verseDans,
      };

  // Création depuis JSON pour le chargement
  factory CollectedItem.fromJson(Map<String, dynamic> json) => CollectedItem(
        code: '${json['code']}',
        quantity: (json['quantity'] as num).toInt(),
        dateScan: DateTime.parse('${json['dateScan']}'),
        verseLe: json['verseLe'] == null ? null : DateTime.tryParse('${json['verseLe']}'),
        verseDans: json['verseDans'] as String?,
      );
}
