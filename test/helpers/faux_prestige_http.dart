// Faux serveur HTTP Prestige (routes /api/v1/ws/inventaires/*) pour les tests d'écrans :
// mêmes formes de réponse que ErpRessource / InventaireServiceImpl, état des quantités en mémoire.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FauxProduit {
  final int id;
  final String cip;
  final String nom;
  final String rayon;
  final int theorique;
  int saisi;
  String? dtUpdated;
  FauxProduit(this.id, this.cip, this.nom, this.rayon, this.theorique, {int? saisi}) : saisi = saisi ?? theorique;

  Map<String, dynamic> toJson() => {
        'id': id,
        'produitCip': cip,
        'produitName': nom,
        'produitPrixAchat': 100,
        'produitPrixUni': 150,
        'quantiteInitiale': theorique,
        'quantiteSaisie': saisi,
        'dtUpdated': dtUpdated,
      };
}

class FauxPrestige {
  final List<FauxProduit> produits = [];
  final Map<String, String> rayons = {'R1': 'RAYON UN', 'R2': 'RAYON DEUX'};

  /// Inventaires ouverts renvoyés par GET /ws/inventaires.
  Map<String, String> inventaires = {'INV1': 'Inventaire test'};

  /// Panne réseau totale (toutes les requêtes échouent comme un serveur injoignable).
  bool injoignable = false;

  /// Routes qui échouent en réseau (fin de chemin, ex. 'detailsAllTouched').
  final Set<String> routesInjoignables = {};

  /// Codes HTTP forcés par fin de chemin (ex. {'detailsAll': 401}).
  final Map<String, int> codes = {};

  /// Délai de réponse de chaque requête (réseau lent).
  Duration delai = Duration.zero;

  /// Si posé, les PUT attendent ce Completer (pour contrôler l'ordre exact).
  Completer<void>? verrouPut;

  final List<(int, int)> puts = [];
  final List<String> appels = [];

  FauxPrestige({int nombre = 60}) {
    for (var i = 1; i <= nombre; i++) {
      produits.add(FauxProduit(1000 + i, '3400${i.toString().padLeft(9, '0')}', 'PRODUIT ${i.toString().padLeft(3, '0')}', i.isEven ? 'R2' : 'R1', i % 7));
    }
  }

  FauxProduit produit(int id) => produits.firstWhere((p) => p.id == id);

  MockClient get client => MockClient(_traiter);

  Future<http.Response> _traiter(http.Request req) async {
    final chemin = req.url.path;
    final fin = chemin.split('/').last;
    appels.add('${req.method} $fin');
    if (delai > Duration.zero) await Future<void>.delayed(delai);
    if (injoignable || routesInjoignables.contains(fin)) throw const SocketException('Connection refused');
    final code = codes[fin];
    if (code != null) return http.Response('', code);
    final q = req.url.queryParameters;
    final query = (q['query'] ?? '').toLowerCase();
    bool correspond(FauxProduit p) => query.isEmpty || p.cip.contains(query) || p.nom.toLowerCase().contains(query);
    List<FauxProduit> touches() => produits.where((p) => p.dtUpdated != null).toList();
    http.Response liste(Iterable<FauxProduit> ps) =>
        http.Response.bytes(utf8.encode(json.encode(ps.map((p) => p.toJson()).toList())), 200, headers: {'content-type': 'application/json; charset=utf-8'});

    if (req.method == 'PUT' && fin == 'details') {
      if (verrouPut != null) await verrouPut!.future;
      final b = json.decode(req.body) as Map<String, dynamic>;
      final id = (b['id'] as num).toInt();
      final quantite = (b['quantite'] as num).toInt();
      puts.add((id, quantite));
      final p = produits.where((p) => p.id == id).firstOrNull;
      if (p == null) return http.Response('', 500); // comme le serveur : NPE → 500
      p.saisi = quantite;
      p.dtUpdated = '2026-10-13T10:00:00';
      return http.Response('', 200);
    }
    switch (fin) {
      case 'inventaires':
        return http.Response.bytes(utf8.encode(json.encode([for (final e in inventaires.entries) {'id': e.key, 'libelle': e.value}])), 200);
      case 'rayons':
        return http.Response.bytes(utf8.encode(json.encode([for (final e in rayons.entries) {'id': e.key, 'code': e.key, 'libelle': e.value}])), 200);
      case 'details':
        return liste(produits.where((p) => p.rayon == q['idRayon'] && correspond(p)));
      case 'detailsAll':
        return liste(produits.where(correspond));
      case 'detailsAllTouched':
        return liste(touches().where(correspond));
      case 'detailsTouchedRayon':
        return liste(touches().where((p) => p.rayon == q['idRayon'] && correspond(p)));
      case 'detailsAllUntouched':
        return liste(produits.where((p) => p.dtUpdated == null && correspond(p)));
      case 'detailsUntouchedRayon':
        return liste(produits.where((p) => p.dtUpdated == null && p.rayon == q['idRayon'] && correspond(p)));
      case 'detailsAllEcarts':
        return liste(touches().where((p) => p.saisi != p.theorique && correspond(p)));
      case 'find':
        return http.Response(json.encode({'id': 'L1', 'dateStart': '2026-01-01', 'dateEnd': '2027-12-31', 'typeLicence': 'ANNUELLE'}), 200);
      case 'auth':
        return http.Response(json.encode({'success': true, 'str_LOGIN': 'admin', 'str_FIRST_NAME': 'Test'}), 200, headers: {'set-cookie': 'JSESSIONID=abc; Path=/'});
    }
    return http.Response('', 404);
  }
}
