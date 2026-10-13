// lib/collecte/collecte_store.dart
// Collecte libre (hors ligne) gardée sur l'appareil : même clé qu'avant (« collection_data »), rien
// n'est perdu à la mise à jour. Le versement marque les lignes versées (date + inventaire).
import 'dart:convert';

import 'package:prestinv/models/collected_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CollecteStore {
  CollecteStore._();

  static const String cle = 'collection_data';

  /// Lignes de la collecte, la plus récente d'abord. Une ligne illisible est ignorée.
  static Future<List<CollectedItem>> lire() async {
    final prefs = await SharedPreferences.getInstance();
    final brut = prefs.getString(cle);
    if (brut == null) return [];
    final out = <CollectedItem>[];
    try {
      for (final e in json.decode(brut) as List<dynamic>) {
        try {
          out.add(CollectedItem.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
    } catch (_) {}
    out.sort((a, b) => b.dateScan.compareTo(a.dateScan));
    return out;
  }

  static Future<void> ecrire(List<CollectedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cle, json.encode(items.map((e) => e.toJson()).toList()));
  }

  /// Marque versées les lignes NON versées dont le code est dans [codes].
  static Future<void> marquerVersees(Set<String> codes, String inventaire, DateTime quand) async {
    if (codes.isEmpty) return;
    final items = await lire();
    var change = false;
    for (final i in items) {
      if (!i.versee && codes.contains(i.code)) {
        i
          ..verseLe = quand
          ..verseDans = inventaire;
        change = true;
      }
    }
    if (change) await ecrire(items);
  }
}
