// lib/api/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/models/license.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';

/// Nature d'un échec de chargement (jamais confondu avec « liste vide »).
enum TypeErreurChargement { reseau, session, refus, donnees }

/// Échec de chargement : message lisible + nature (réseau, session expirée, refus, données illisibles).
class ApiLoadException implements Exception {
  final String message;
  final TypeErreurChargement type;
  const ApiLoadException(this.message, [this.type = TypeErreurChargement.refus]);

  bool get sessionExpiree => type == TypeErreurChargement.session;
  bool get reseau => type == TypeErreurChargement.reseau;

  @override
  String toString() => message;
}

class ApiService implements SaisieServeur {
  final String baseUrl;
  final String? sessionCookie;

  /// Cookie de session lu au moment de chaque appel (après une reconnexion, le nouveau est utilisé).
  final String? Function()? cookie;

  /// Client HTTP (remplaçable dans les tests).
  final http.Client? client;

  ApiService({required this.baseUrl, this.sessionCookie, this.cookie, this.client});

  /// Tests : client HTTP utilisé par toutes les instances qui n'en reçoivent pas (faux serveur).
  static http.Client? clientParDefaut;

  http.Client? get _client => client ?? clientParDefaut;

  String? get _cookieCourant => cookie != null ? cookie!() : sessionCookie;

  Map<String, String> _getHeaders() {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    final c = _cookieCourant;
    if (c != null && c.isNotEmpty) {
      headers['Cookie'] = c;
    }
    return headers;
  }

  Future<http.Response> _httpGet(Uri url) => _client != null ? _client!.get(url, headers: _getHeaders()) : http.get(url, headers: _getHeaders());

  Future<http.Response> _httpPut(Uri url, String body) =>
      _client != null ? _client!.put(url, headers: _getHeaders(), body: body) : http.put(url, headers: _getHeaders(), body: body);

  static bool _estErreurReseau(Object e) => e is SocketException || e is TimeoutException || e is http.ClientException || e is HandshakeException;

  // --- FILE DES SAISIES (SaisieServeur) ---

  /// Pose la quantité TOTALE sur une ligne (PUT /ws/inventaires/details). Ne lève jamais.
  @override
  Future<ReponseEnvoi> poserQuantite(int ligneId, int quantite) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/details');
    try {
      final response = await _httpPut(url, jsonEncode({'id': ligneId, 'quantite': quantite})).timeout(const Duration(seconds: 15));
      final code = response.statusCode;
      if (code >= 200 && code < 300) return ReponseEnvoi.ok;
      if (code == 401 || code == 403) return ReponseEnvoi(ResultatEnvoi.session, 'Session expirée ou accès refusé (code $code).');
      if (code >= 400 && code < 500) return ReponseEnvoi(ResultatEnvoi.refus, 'Le serveur a refusé la quantité (code $code).');
      return ReponseEnvoi(ResultatEnvoi.erreurServeur, 'Erreur du serveur (code $code).');
    } on TimeoutException {
      return const ReponseEnvoi(ResultatEnvoi.reseau, 'Le serveur met trop de temps à répondre.');
    } catch (e) {
      if (_estErreurReseau(e)) return const ReponseEnvoi(ResultatEnvoi.reseau, 'Serveur injoignable.');
      return ReponseEnvoi(ResultatEnvoi.reseau, 'Envoi impossible : $e');
    }
  }

  /// Tous les inventaires ouverts (GET /ws/inventaires sans limite). `null` si la liste n'a pas pu être lue.
  @override
  Future<InventairesOuverts?> inventairesOuverts() async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is! List) return null;
      return InventairesOuverts({for (final i in data) if (i is Map && i['id'] != null) '${i['id']}'});
    } catch (_) {
      return null;
    }
  }

  // --- INVENTAIRES ---

  Future<List<Inventory>> fetchInventories({int maxResult = 3}) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires?maxResult=$maxResult');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((json) => Inventory.fromJson(json)).toList();
      } else {
        throw Exception('Échec du chargement des inventaires (Statut: ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre le serveur.');
    } on TimeoutException {
      throw Exception('Erreur réseau: Le délai de connexion a été dépassé.');
    } catch (e) {
      rethrow;
    }
  }

  // --- CUMUL / VERIFICATION ---

  /// Quantité déjà comptée sur le serveur pour ce produit (`null` = jamais compté).
  ///
  /// IMPORTANT : un échec (réseau lent, serveur injoignable, session expirée, réponse illisible) LÈVE
  /// [ApiLoadException] — il ne signifie JAMAIS « jamais compté » (sinon on écraserait le comptage d'un
  /// collègue). Si [ligneId] est fourni, c'est cette ligne précise qui compte (un même produit peut
  /// figurer dans deux emplacements) ; sinon la première ligne de ce CIP déjà comptée.
  Future<int?> verifierDejaCompte(String inventoryId, String cip, {int? ligneId}) async {
    if (cip.isEmpty) return null;
    final uri = Uri.parse('$baseUrl/api/v1/ws/inventaires/detailsAllTouched').replace(queryParameters: {
      'idInventaire': inventoryId,
      'query': cip,
    });
    final http.Response response;
    try {
      response = await _httpGet(uri).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const ApiLoadException('Le serveur met trop de temps à répondre : impossible de savoir si ce produit est déjà compté.', TypeErreurChargement.reseau);
    } catch (e) {
      throw const ApiLoadException('Serveur injoignable : impossible de savoir si ce produit est déjà compté.', TypeErreurChargement.reseau);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ApiLoadException('Session expirée : reconnectez-vous pour vérifier si ce produit est déjà compté.', TypeErreurChargement.session);
    }
    if (response.statusCode != 200) {
      throw ApiLoadException('Le serveur a refusé la vérification « déjà compté » (code ${response.statusCode}).');
    }
    final List<dynamic> data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    } catch (_) {
      throw const ApiLoadException('Réponse illisible du serveur pour la vérification « déjà compté ».', TypeErreurChargement.donnees);
    }
    int? qteDe(dynamic item) {
      if (item is! Map || item['dtUpdated'] == null || item['quantiteSaisie'] is! num) return null;
      return (item['quantiteSaisie'] as num).toInt();
    }

    if (ligneId != null) {
      final memeLigne = data.where((i) => i is Map && i['id'] is num && (i['id'] as num).toInt() == ligneId).toList();
      if (memeLigne.isNotEmpty) return qteDe(memeLigne.first);
      // La réponse ne contient pas cette ligne : jamais comptée (les lignes comptées sont toutes renvoyées).
      if (data.any((i) => i is Map && i['id'] is num)) return null;
    }
    for (final item in data) {
      if (item is Map && item['produitCip']?.toString() == cip) {
        final q = qteDe(item);
        if (q != null) return q;
      }
    }
    return null;
  }

  // --- RAYONS & PRODUITS ---

  Future<List<Rayon>> fetchRayons(String idInventaire) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/rayons?idInventaire=$idInventaire');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((json) => Rayon.fromJson(json)).toList();
      } else {
        throw Exception('Échec du chargement des emplacements (Statut: ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre le serveur.');
    } on TimeoutException {
      throw Exception('Erreur réseau: Le délai de connexion a été dépassé.');
    } catch (e) {
      rethrow;
    }
  }

  /// Récupère les produits.
  /// LOGIQUE DE BASCULE :
  /// - Si [idRayon] est NULL ou VIDE => Utilise 'detailsAll' (Mode Global / Saisie Rapide)
  /// - Si [idRayon] est RENSEIGNÉ => Utilise 'details' (Mode par Emplacement)
  Future<List<Product>> fetchProducts(String idInventaire, String? idRayon, {String? query}) async {

    // 1. Choix de l'endpoint
    String endpoint;
    if (idRayon != null && idRayon.isNotEmpty) {
      endpoint = 'details';
    } else {
      endpoint = 'detailsAll';
    }

    // 2. Construction de l'URL de base
    String urlStr = '$baseUrl/api/v1/ws/inventaires/$endpoint?idInventaire=$idInventaire';

    // 3. Ajout du rayon (seulement si endpoint 'details')
    if (idRayon != null && idRayon.isNotEmpty) {
      urlStr += '&idRayon=$idRayon';
    }

    // 4. Ajout du query (Recherche CIP, EAN, Nom...)
    if (query != null && query.isNotEmpty) {
      urlStr += '&query=${Uri.encodeQueryComponent(query)}';
    }

    final url = Uri.parse(urlStr);

    try {
      // Debug: afficher l'URL appelée dans la console
      print("Calling API: $urlStr");

      final response = await _httpGet(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        List<Product> products = data.map((json) => Product.fromJson(json)).toList();

        // Tri alphabétique optionnel
        products.sort((a, b) => a.produitName.compareTo(b.produitName));

        return products;
      } else {
        throw Exception('Échec du chargement des produits (Statut: ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre le serveur.');
    } on TimeoutException {
      throw Exception('Erreur réseau: Le délai de connexion a été dépassé.');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateProductQuantity(int productId, int newQuantity) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/details');
    // On envoie un objet JSON avec id et quantite
    final requestBody = jsonEncode({'id': productId, 'quantite': newQuantity});
    try {
      final response = await _httpPut(url, requestBody).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Le serveur a répondu avec le statut ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre le serveur.');
    } on TimeoutException {
      throw Exception('Erreur réseau: Le délai de connexion a été dépassé.');
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> requestCsvGeneration(String rayonId, {String? destinationPath}) async {
    String queryString = 'rayonId=$rayonId';
    if (destinationPath != null && destinationPath.isNotEmpty) {
      queryString += '&path=${Uri.encodeQueryComponent(destinationPath)}';
    }

    final url = Uri.parse('$baseUrl/api/v1/export/csv?$queryString');

    try {
      final response = await http.post(url, headers: _getHeaders()).timeout(const Duration(seconds: 30));
      // Debug simple
      if (response.statusCode != 200 && response.statusCode != 201) {
        print('ERREUR EXPORT: Code ${response.statusCode}');
      }
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('EXCEPTION EXPORT: $e');
      return false;
    }
  }

  // --- ANALYSE & ÉCARTS ---

  Future<List<Product>> fetchAllProductsForInventory(String inventoryId) async {
    final url = Uri.parse('$baseUrl/api/v1/inventaires/analyse_complete?idInventaire=$inventoryId');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((json) => Product.fromJson(json)).toList();
      } else {
        throw Exception('Échec du chargement des produits pour l\'analyse (Statut: ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre le serveur.');
    } on TimeoutException {
      throw Exception('Erreur réseau: Le délai de connexion a été dépassé.');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Product>> fetchGlobalVariances(String idInventaire, {String? query}) async {
    String urlStr = '$baseUrl/api/v1/ws/inventaires/detailsAllEcarts?idInventaire=$idInventaire';

    if (query != null && query.isNotEmpty) {
      urlStr += '&query=${Uri.encodeQueryComponent(query)}';
    }

    final url = Uri.parse(urlStr);

    try {
      print("Calling API Variances: $urlStr");
      final response = await _httpGet(url).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        List<Product> products = data.map((json) => Product.fromJson(json)).toList();

        // On peut trier par nom pour faciliter la lecture
        products.sort((a, b) => a.produitName.compareTo(b.produitName));
        return products;
      } else {
        throw Exception('Échec du chargement des écarts (Statut: ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre le serveur.');
    } on TimeoutException {
      throw Exception('Erreur réseau: Le délai de connexion a été dépassé.');
    } catch (e) {
      rethrow;
    }
  }

  // --- NON INVENTORIÉS ---

  Future<List<Product>> fetchUntouchedProducts(String idInventaire, {String? query}) async {
    String urlStr = '$baseUrl/api/v1/ws/inventaires/detailsAllUntouched?idInventaire=$idInventaire';
    if (query != null && query.isNotEmpty) {
      urlStr += '&query=${Uri.encodeQueryComponent(query)}';
    }
    final url = Uri.parse(urlStr);
    try {
      print("Calling API Untouched: $urlStr");
      final response = await _httpGet(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        List<Product> products = data.map((json) => Product.fromJson(json)).toList();
        products.sort((a, b) => a.produitName.compareTo(b.produitName));
        return products;
      } else {
        throw Exception('Échec du chargement des restants (Statut: ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre le serveur.');
    } on TimeoutException {
      throw Exception('Erreur réseau: Le délai de connexion a été dépassé.');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Product>> fetchUntouchedProductsByRayon(String idInventaire, String idRayon, {String? query}) async {
    String urlStr = '$baseUrl/api/v1/ws/inventaires/detailsUntouchedRayon?idInventaire=$idInventaire&idRayon=$idRayon';

    if (query != null && query.isNotEmpty) {
      urlStr += '&query=${Uri.encodeQueryComponent(query)}';
    }

    final url = Uri.parse(urlStr);

    try {
      print("Calling API Untouched Rayon: $urlStr");
      final response = await _httpGet(url).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        List<Product> products = data.map((json) => Product.fromJson(json)).toList();
        products.sort((a, b) => a.produitName.compareTo(b.produitName));
        return products;
      } else {
        throw Exception('Échec du chargement des restants par rayon (Statut: ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre le serveur.');
    } on TimeoutException {
      throw Exception('Erreur réseau: Le délai de connexion a été dépassé.');
    } catch (e) {
      rethrow;
    }
  }

  // --- GESTION LICENCE ---

  /// Enregistre une nouvelle licence
  Future<bool> saveLicense(String key) async {
    final url = Uri.parse('$baseUrl/api/v1/licence/save/$key');
    try {
      final response = await http.post(url, headers: _getHeaders()).timeout(const Duration(seconds: 15));
      // On considère que 200 = succès
      return response.statusCode == 200;
    } catch (e) {
      throw Exception("Erreur lors de l'enregistrement de la licence : $e");
    }
  }

  /// Récupère la licence active
  Future<License> findLicense() async {
    final url = Uri.parse('$baseUrl/api/v1/licence/find');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Le serveur retourne un JSON unique, pas une liste
        final dynamic data = json.decode(utf8.decode(response.bodyBytes));
        return License.fromJson(data);
      } else {
        throw Exception('Aucune licence valide trouvée (Code ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('Impossible de joindre le serveur de licence (Hors-ligne ?)');
    } catch (e) {
      rethrow;
    }
  }

  /// Vérifie si un rayon a été entamé (Liste des produits touchés non vide)
  Future<bool> hasTouchedProductsInRayon(String inventoryId, String rayonId) async {
    // On laisse query vide pour avoir tout le rayon
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/detailsTouchedRayon?idInventaire=$inventoryId&idRayon=$rayonId&query=');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.isNotEmpty;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<List<Product>> fetchTouchedProductsByRayon(String inventoryId, String rayonId, {String? query}) async {
    // On construit l'URL avec les paramètres obligatoires
    String url = '$baseUrl/api/v1/ws/inventaires/detailsTouchedRayon?idInventaire=$inventoryId&idRayon=$rayonId';

    // Si on fait une recherche/scan, on ajoute le query à l'URL
    if (query != null && query.isNotEmpty) {
      url += '&query=$query';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {'Cookie': sessionCookie ?? ''},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Product.fromJson(json)).toList();
    } else {
      throw Exception('Erreur lors du chargement des écarts de cet emplacement');
    }
  }

  /// Vérifie s'il reste des produits à faire (Liste des produits intouchés non vide)
  Future<bool> hasUntouchedProductsInRayon(String inventoryId, String rayonId) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/detailsUntouchedRayon?idInventaire=$inventoryId&idRayon=$rayonId&query=');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.isNotEmpty; // Si vide = tout est fini
      }
      return true; // En cas d'erreur, on suppose qu'il en reste (sécurité)
    } catch (e) {
      return true;
    }
  }
}