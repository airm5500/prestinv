// lib/api/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/models/license.dart';
// Note: J'ai retiré collected_item.dart car il n'était pas utilisé ici

class ApiService {
  final String baseUrl;
  final String? sessionCookie;

  ApiService({required this.baseUrl, this.sessionCookie});

  Map<String, String> _getHeaders() {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    if (sessionCookie != null && sessionCookie!.isNotEmpty) {
      headers['Cookie'] = sessionCookie!;
    }
    return headers;
  }

  // --- INVENTAIRES ---

  Future<List<Inventory>> fetchInventories({int maxResult = 3}) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires?maxResult=$maxResult');
    try {
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 20));
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

  /// Vérifie si un produit a déjà été touché sur le serveur.
  /// LOGIQUE CORRIGÉE : Utilise dtUpdated comme preuve absolue de comptage.
  /// Renvoie NULL si non trouvé ou dtUpdated absent.
  /// Renvoie la quantité si trouvé avec une date de mise à jour (popup cumul).
  Future<int?> checkExistingProductQuantity(String inventoryId, String query, {String? rayonId}) async {
    try {
      if (query.isEmpty) return null;

      String endpoint = rayonId != null && rayonId.isNotEmpty
          ? '/api/v1/ws/inventaires/detailsTouchedRayon'
          : '/api/v1/ws/inventaires/detailsAllTouched';

      final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: {
        'idInventaire': inventoryId,
        'query': query, // On envoie le CIP scanné ici (ex: 8055207)
        if (rayonId != null && rayonId.isNotEmpty) 'idRayon': rayonId,
      });

      print("API CUMUL CHECK URL: $uri");

      // Timeout court (5s) pour garantir la fluidité en mode scan
      final response = await http.get(uri, headers: _getHeaders()).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));

        // 1. Si vide = Pas touché -> return null (Pas de popup)
        if (data.isEmpty) {
          return null;
        }

        // 2. Si contient des données, on cherche la correspondance exacte avec le CIP
        for (var item in data) {
          String itemCip = item['produitCip']?.toString() ?? '';

          // Sécurité : on s'assure que c'est bien le produit demandé ET qu'il a été modifié (dtUpdated)
          if (itemCip == query && item['dtUpdated'] != null) {
            if (item['quantiteSaisie'] != null) {
              int qte = (item['quantiteSaisie'] as num).toInt();
              print("Produit déjà compté trouvé (dtUpdated présent). Quantité: $qte");
              return qte;
            }
          }
        }

        return null; // Pas de correspondance avec dtUpdated trouvée
      } else {
        print('Erreur API Check: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception API Check: $e');
      return null;
    }
  }

  // --- RAYONS & PRODUITS ---

  Future<List<Rayon>> fetchRayons(String idInventaire) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/rayons?idInventaire=$idInventaire');
    try {
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 20));
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

      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 20));
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
      final response = await http.put(url, headers: _getHeaders(), body: requestBody).timeout(const Duration(seconds: 15));
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
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 60));
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
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 20));

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
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 20));
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
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 20));

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
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 10));

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
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.isNotEmpty;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Vérifie s'il reste des produits à faire (Liste des produits intouchés non vide)
  Future<bool> hasUntouchedProductsInRayon(String inventoryId, String rayonId) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/detailsUntouchedRayon?idInventaire=$inventoryId&idRayon=$rayonId&query=');
    try {
      final response = await http.get(url, headers: _getHeaders()).timeout(const Duration(seconds: 5));
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