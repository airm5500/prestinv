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

  /// Méthode centrale qui construit les en-têtes pour chaque requête.
  Map<String, String> _getHeaders() {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    if (sessionCookie != null && sessionCookie!.isNotEmpty) {
      headers['Cookie'] = sessionCookie!;
    }
    return headers;
  }

  /// Récupère la liste des inventaires depuis le serveur.
  Future<List<Inventory>> fetchInventories({int maxResult = 3}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires?maxResult=$maxResult'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 20));

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

  /// Récupère les emplacements (rayons) pour un inventaire donné.
  Future<List<Rayon>> fetchRayons(String idInventaire) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/rayons?idInventaire=$idInventaire'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 20));

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

  /// Récupère les produits pour un emplacement donné.
  Future<List<Product>> fetchProducts(String idInventaire, String idRayon) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/details?idInventaire=$idInventaire&idRayon=$idRayon'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        List<Product> products = data.map((json) => Product.fromJson(json)).toList();
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

  /// Met à jour la quantité d'un produit. Lève une exception en cas d'échec.
  Future<void> updateProductQuantity(int productId, int newQuantity) async {
    final url = Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/details');
    final requestBody = jsonEncode(<String, dynamic>{
      'id': productId,
      'quantite': newQuantity,
    });

    try {
      final response = await http.put(
        url,
        headers: _getHeaders(),
        body: requestBody,
      ).timeout(const Duration(seconds: 15));

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

  /// Demande au serveur de générer un fichier CSV pour un emplacement donné.
  Future<bool> requestCsvGeneration(String rayonId) async {
    // L'URL de votre API Java EE pour l'export CSV
    final url = Uri.parse('$baseUrl/laborex/api/v1/export/csv?rayonId=$rayonId');
    try {
      // On utilise POST car c'est une action qui crée une ressource (un fichier) sur le serveur
      final response = await http.post(url, headers: _getHeaders()).timeout(const Duration(seconds: 30));
      // On considère un succès si le statut est 200 (OK) ou 201 (Created)
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      // En cas d'erreur réseau, on retourne false
      return false;
    }
  }
}
