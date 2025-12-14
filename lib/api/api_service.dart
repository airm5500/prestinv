// lib/api/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';

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
}