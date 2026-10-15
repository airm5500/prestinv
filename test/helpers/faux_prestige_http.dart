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

  /// EAN-13 (reconnu par la recherche du serveur, absent de la réponse comme sur le vrai serveur).
  final String? ean;

  /// Auteur de la dernière quantité posée par la route « avec auteur ».
  String? auteur;
  FauxProduit(this.id, this.cip, this.nom, this.rayon, this.theorique, {int? saisi, this.ean}) : saisi = saisi ?? theorique;

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

  /// Délai par fin de chemin (ex. {'detailsAllTouched': 12 s}).
  final Map<String, Duration> delais = {};

  /// Si posé, les PUT attendent ce Completer (pour contrôler l'ordre exact).
  Completer<void>? verrouPut;

  final List<(int, int)> puts = [];
  final List<String> appels = [];

  /// Quantités reçues par POST /inventaire/ligne/quantite (route qui enregistre l'auteur).
  final List<(int, int)> postsQuantite = [];

  /// Demandes de création reçues (libellé, type).
  final List<(String, String)> creations = [];

  /// 4.14.1 : `valeurs` de chaque demande de création (null : absentes = tous les produits).
  final List<List<String>?> creationsValeurs = [];

  /// Emplacements de l'officine (GET /referentiel-article/zones-geographiques) en plus des rayons.
  final Map<String, String> autresEmplacements = {'R3': 'RESERVE'};

  /// Route POST /inventaire/ligne/quantite absente (ancien serveur : 404).
  bool sansRouteLigneQuantite = false;

  /// Création : réponse forcée (corps JSON) ; null = succès.
  Map<String, dynamic>? reponseCreation;

  /// Création : la réponse se perd (réseau coupé APRÈS que le serveur a créé l'inventaire).
  bool creationReponsePerdue = false;

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
    final d = delais[fin];
    if (d != null) await Future<void>.delayed(d);
    if (injoignable || routesInjoignables.contains(fin)) throw const SocketException('Connection refused');
    final code = codes[fin];
    if (code != null) return http.Response('', code);
    final q = req.url.queryParameters;
    final query = (q['query'] ?? '').toLowerCase();
    bool correspond(FauxProduit p) =>
        query.isEmpty || p.cip.contains(query) || p.nom.toLowerCase().contains(query) || (p.ean != null && p.ean!.startsWith(query));
    List<FauxProduit> touches() => produits.where((p) => p.dtUpdated != null).toList();
    http.Response liste(Iterable<FauxProduit> ps) =>
        http.Response.bytes(utf8.encode(json.encode(ps.map((p) => p.toJson()).toList())), 200, headers: {'content-type': 'application/json; charset=utf-8'});

    if (req.method == 'POST' && fin == 'quantite') {
      if (sansRouteLigneQuantite) return http.Response('', 404);
      if (verrouPut != null) await verrouPut!.future;
      final b = json.decode(req.body) as Map<String, dynamic>;
      final id = int.tryParse('${b['lg_INVENTAIRE_FAMILLE_ID']}');
      final quantite = (b['int_NUMBER'] as num?)?.toInt();
      if (quantite == null || quantite < 0) return http.Response(json.encode({'success': 0, 'errors': 'Quantite invalide.'}), 200);
      final p = produits.where((p) => p.id == id).firstOrNull;
      if (p == null) return http.Response(json.encode({'success': 0, 'errors': "Cette ligne d'inventaire n'existe plus."}), 200);
      postsQuantite.add((p.id, quantite));
      p
        ..saisi = quantite
        ..dtUpdated = '2026-10-13T10:00:00'
        ..auteur = 'admin';
      return http.Response(json.encode({'success': 1, 'int_NUMBER': quantite}), 200);
    }
    if (req.method == 'POST' && fin == 'creation') {
      final b = json.decode(req.body) as Map<String, dynamic>;
      final nom = '${b['str_NAME'] ?? ''}'.trim();
      final type = '${b['str_TYPE_TRANSACTION'] ?? ''}'.trim();
      creations.add((nom, type));
      final brut = b['valeurs'];
      final valeurs = brut is List ? [for (final v in brut) '$v'] : null;
      creationsValeurs.add(valeurs);
      if (reponseCreation != null) return http.Response.bytes(utf8.encode(json.encode(reponseCreation)), 200);
      if (nom.isEmpty) return http.Response(json.encode({'success': 0, 'message': 'Indiquez un libelle pour cet inventaire.'}), 200);
      if (type.isEmpty) return http.Response(json.encode({'success': 0, 'message': "Choisissez un type d'inventaire."}), 200);
      // Le plus récent en tête (ORDER BY dtCREATED DESC).
      inventaires = {'NEW${creations.length}': nom, ...inventaires};
      if (creationReponsePerdue) throw const SocketException('Connection reset');
      // Comme createInventaireMultiCriteres : sans valeur → tous les produits ; sinon ceux des emplacements.
      final filtre = valeurs?.where((v) => v.isNotEmpty && v != '0' && v != '%%').toSet() ?? const <String>{};
      final lignes = filtre.isEmpty ? produits.length : produits.where((p) => filtre.contains(p.rayon)).length;
      return http.Response(json.encode({'success': 1, 'lignes': lignes, 'nombre': '$lignes article(s) inventorie(s)'}), 200);
    }
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
      case 'zones-geographiques':
        final tous = {...rayons, ...autresEmplacements};
        return http.Response.bytes(
            utf8.encode(json.encode({
              'total': tous.length,
              'results': [for (final e in tous.entries) {'lg_ZONE_GEO_ID': e.key, 'str_CODE': e.key, 'str_LIBELLEE': e.value}],
            })),
            200);
      case 'fiche':
        // Recherche de la fiche article (produit-search/fiche) : CIP, EAN-13 ; emplacement en libellé et en identifiant.
        final cherche = q['search_value'] ?? '';
        final ps = produits.where((p) => cherche.isNotEmpty && (p.cip.startsWith(cherche) || (p.ean != null && p.ean!.startsWith(cherche))));
        return http.Response.bytes(
            utf8.encode(json.encode({
              'total': ps.length,
              'results': [
                for (final p in ps.take(int.tryParse(q['limit'] ?? '') ?? 20))
                  {'lg_FAMILLE_ID': 'F${p.id}', 'int_CIP': p.cip, 'str_NAME': p.nom, 'lg_ZONE_GEO_ID': rayons[p.rayon] ?? '', 'lg_ZONE_GEO_ID_REEL': p.rayon},
              ],
            })),
            200);
      case 'find':
        // Fin de licence relative à aujourd'hui (une date fixe rendait les tests rouges à son échéance).
        final fin = DateTime.now().add(const Duration(days: 400)).toIso8601String().substring(0, 10);
        return http.Response(json.encode({'id': 'L1', 'dateStart': '2026-01-01', 'dateEnd': fin, 'typeLicence': 'ANNUELLE'}), 200);
      case 'auth':
        return http.Response(json.encode({'success': true, 'str_LOGIN': 'admin', 'str_FIRST_NAME': 'Test'}), 200, headers: {'set-cookie': 'JSESSIONID=abc; Path=/'});
    }
    return http.Response('', 404);
  }
}

/// Client HTTP qui délègue à [interne] mais coupe (erreur réseau) les requêtes désignées par [coupe].
abstract class BaseClientDelegue extends http.BaseClient {
  final http.Client interne;
  BaseClientDelegue(this.interne);

  bool coupe(Uri url, String methode);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (coupe(request.url, request.method)) throw const SocketException('Connexion coupée (essai)');
    return interne.send(request);
  }
}
