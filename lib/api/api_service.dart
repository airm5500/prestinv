// lib/api/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';

class ApiService {
  final String baseUrl;
  // Le service prend maintenant le cookie de session en paramètre
  final String? sessionCookie;

  ApiService({required this.baseUrl, this.sessionCookie});

  // Méthode centrale qui construit les en-têtes pour chaque requête
  Map<String, String> _getHeaders() {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    // Si un cookie de session existe, on l'ajoute à l'en-tête
    if (sessionCookie != null && sessionCookie!.isNotEmpty) {
      headers['Cookie'] = sessionCookie!;
    }
    return headers;
  }

  // Toutes les méthodes ci-dessous utilisent maintenant _getHeaders()

  Future<List<Inventory>> fetchInventories({int maxResult = 3}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires?maxResult=$maxResult'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((json) => Inventory.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load inventories');
    }
  }

  Future<List<Rayon>> fetchRayons(String idInventaire) async {
    final response = await http.get(
      Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/rayons?idInventaire=$idInventaire'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((json) => Rayon.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load rayons');
    }
  }

  Future<List<Product>> fetchProducts(String idInventaire, String idRayon) async {
    final response = await http.get(
      Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/details?idInventaire=$idInventaire&idRayon=$idRayon'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      List<Product> products = data.map((json) => Product.fromJson(json)).toList();
      products.sort((a, b) => a.produitName.compareTo(b.produitName));
      return products;
    } else {
      throw Exception('Failed to load products');
    }
  }

  Future<bool> updateProductQuantity(int productId, int newQuantity) async {
    final response = await http.put(
      Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/details'),
      headers: _getHeaders(),
      body: jsonEncode(<String, dynamic>{
        'id': productId,
        'quantite': newQuantity,
      }),
    );
    return response.statusCode == 200 || response.statusCode == 204;
  }
}