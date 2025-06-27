import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:provider/provider.dart';

class RecapScreen extends StatefulWidget {
  final String inventoryId;
  final String rayonId;
  final String rayonName;

  const RecapScreen({
    super.key,
    required this.inventoryId,
    required this.rayonId,
    required this.rayonName,
  });

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  late Future<List<Product>> _productsFuture;

  @override
  void initState() {
    super.initState();
    final apiService = ApiService(
      baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
    );
    _productsFuture = apiService.fetchProducts(widget.inventoryId, widget.rayonId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Récap: ${widget.rayonName}'),
      ),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Aucun produit à afficher.'));
          }

          final products = snapshot.data!;

          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Désignation')),
                  DataColumn(label: Text('Stock Théo.'), numeric: true),
                  DataColumn(label: Text('Stock Compté'), numeric: true),
                  DataColumn(label: Text('Écart'), numeric: true),
                ],
                rows: products.map((product) {
                  // Calcul de l'écart entre la valeur stock et la valeur comptée
                  final ecart = product.quantiteSaisie - product.quantiteInitiale;
                  Color ecartColor = Colors.grey;
                  if (ecart > 0) {
                    ecartColor = Colors.green;
                  } else if (ecart < 0) {
                    ecartColor = Colors.red;
                  }

                  return DataRow(cells: [
                    DataCell(Text(product.produitName)),
                    DataCell(Text(product.quantiteInitiale.toString())),
                    DataCell(Text(product.quantiteSaisie.toString())),
                    DataCell(
                      Text(
                        ecart.toString(),
                        style: TextStyle(
                          color: ecartColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ]);
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}