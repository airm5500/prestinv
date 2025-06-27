import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/models/product.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  Future<List<Inventory>> fetchInventories({int maxResult = 3}) async {
    final response = await http.get(Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires?maxResult=$maxResult'));

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((json) => Inventory.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load inventories');
    }
  }

  Future<List<Rayon>> fetchRayons(String idInventaire) async {
    final response = await http.get(Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/rayons?idInventaire=$idInventaire'));

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((json) => Rayon.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load rayons');
    }
  }

  Future<List<Product>> fetchProducts(String idInventaire, String idRayon) async {
    final response = await http.get(Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/details?idInventaire=$idInventaire&idRayon=$idRayon'));

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      List<Product> products = data.map((json) => Product.fromJson(json)).toList();
      // Tri par ordre alphabétique
      products.sort((a, b) => a.produitName.compareTo(b.produitName));
      return products;
    } else {
      throw Exception('Failed to load products');
    }
  }

  Future<bool> updateProductQuantity(int productId, int newQuantity) async {
    final response = await http.put(
      Uri.parse('$baseUrl/laborex/api/v1/ws/inventaires/details'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, dynamic>{
        'id': productId,
        'quantite': newQuantity,
      }),
    );
    return response.statusCode == 200 || response.statusCode == 204;
  }
}