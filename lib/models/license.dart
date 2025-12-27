// lib/models/license.dart

class License {
  final String id;
  final DateTime dateStart;
  final DateTime dateEnd;
  final String typeLicence;

  License({
    required this.id,
    required this.dateStart,
    required this.dateEnd,
    required this.typeLicence,
  });

  factory License.fromJson(Map<String, dynamic> json) {
    return License(
      id: json['id'] ?? '',
      // Gestion robuste des dates (parfois "yyyy-MM-dd", parfois ISO complet)
      dateStart: DateTime.parse(json['dateStart'].toString().substring(0, 10)),
      dateEnd: DateTime.parse(json['dateEnd'].toString().substring(0, 10)),
      typeLicence: json['typeLicence'] ?? 'UNKNOWN',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dateStart': dateStart.toIso8601String(),
      'dateEnd': dateEnd.toIso8601String(),
      'typeLicence': typeLicence,
    };
  }
}