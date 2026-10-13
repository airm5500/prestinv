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
      id: '${json['id'] ?? ''}',
      // Gestion robuste des dates (parfois "yyyy-MM-dd", parfois ISO complet, parfois un horodatage)
      dateStart: lireDate(json['dateStart']),
      dateEnd: lireDate(json['dateEnd']),
      typeLicence: '${json['typeLicence'] ?? 'UNKNOWN'}',
    );
  }

  /// Date lue de façon contrôlée : « aaaa-mm-jj… » ou horodatage en millisecondes ; sinon
  /// FormatException (licence illisible = pas de licence, jamais une date inventée).
  static DateTime lireDate(Object? v) {
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    final t = '${v ?? ''}'.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
    if (m == null) throw FormatException('date de licence illisible : $t');
    final an = int.parse(m.group(1)!), mois = int.parse(m.group(2)!), jour = int.parse(m.group(3)!);
    if (an < 2000 || an > 2200 || mois < 1 || mois > 12 || jour < 1 || jour > 31) {
      throw FormatException('date de licence hors bornes : $t');
    }
    final d = DateTime(an, mois, jour);
    if (d.month != mois || d.day != jour) throw FormatException('date de licence invalide : $t');
    return d;
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