// lib/screens/variance_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/screens/barcode_scanner_screen.dart';

class VarianceScreen extends StatefulWidget {
  final String inventoryId;
  final String rayonId;
  final String rayonName;

  const VarianceScreen({
    super.key,
    required this.inventoryId,
    required this.rayonId,
    required this.rayonName,
  });

  @override
  State<VarianceScreen> createState() => _VarianceScreenState();
}

class _VarianceScreenState extends State<VarianceScreen> {
  final _searchController = TextEditingController();
  final _quantityController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  Product? _selectedProduct;
  bool _isLoading = true;
  bool _showSearchResults = false;
  bool _isNewEntry = true;
  late ApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(
        baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl);
    _fetchAndSetupProducts();
    _searchController.addListener(_filterProducts);
  }

  Future<void> _scanBarcode() async {
    try {
      final scannedCode = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );

      if (scannedCode == null) return;

      // On recherche le produit correspondant au code scanné
      final foundProduct = _allProducts.firstWhere(
            (p) => p.produitCip == scannedCode,
        // MODIFICATION: Ajout des paramètres manquants pour le produit factice
        orElse: () => Product(
          id: -1,
          produitCip: '',
          produitName: 'NOT_FOUND',
          produitPrixAchat: 0,
          produitPrixUni: 0,
          quantiteInitiale: 0,
          quantiteSaisie: 0,
        ),
      );

      if (foundProduct.id != -1) {
        _selectProduct(foundProduct);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produit non trouvé dans cet emplacement.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur du scanner: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Correction Écarts - ${widget.rayonName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scanner un code-barres',
            onPressed: _scanBarcode,
          ),
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: 'Envoyer les modifications',
            onPressed: _sendDataToServer,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Rechercher par CIP ou Désignation',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_selectedProduct != null && !_showSearchResults)
                  buildProductView(_selectedProduct!),
                if (_showSearchResults)
                  Container(
                    color: Colors.white,
                    child: ListView.builder(
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return ListTile(
                          title: Text(product.produitName),
                          subtitle: Text('CIP: ${product.produitCip}'),
                          onTap: () => _selectProduct(product),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (!_showSearchResults) NumericKeyboard(onKeyPressed: _onKeyPressed),
        ],
      ),
    );
  }

  // Le reste du fichier est identique à la version précédente.
  // J'inclus les méthodes pour que le fichier soit complet.

  Future<void> _fetchAndSetupProducts() async {
    setState(() => _isLoading = true);
    try {
      _allProducts =
      await _apiService.fetchProducts(widget.inventoryId, widget.rayonId);
      if (_allProducts.isNotEmpty) {
        _selectProduct(_allProducts.first);
      }
    } catch (e) {
      // Gérer l'erreur
    }
    setState(() => _isLoading = false);
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredProducts = [];
        _showSearchResults = false;
      });
      return;
    }
    setState(() {
      _filteredProducts = _allProducts.where((product) {
        return product.produitCip.toLowerCase().contains(query) ||
            product.produitName.toLowerCase().contains(query);
      }).toList();
      _showSearchResults = true;
    });
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _quantityController.text = product.quantiteSaisie.toString();
      _searchController.clear();
      _showSearchResults = false;
      _isNewEntry = true;
      FocusScope.of(context).unfocus();
    });
  }

  void _onKeyPressed(String value) {
    if (value == 'DEL') {
      if (_quantityController.text.isNotEmpty) {
        _quantityController.text =
            _quantityController.text.substring(0, _quantityController.text.length - 1);
      }
      _isNewEntry = false;
    } else if (value == 'OK') {
      _updateQuantity();
    } else {
      if (_isNewEntry) {
        _quantityController.text = value;
        _isNewEntry = false;
      } else {
        _quantityController.text += value;
      }
    }
  }

  void _updateQuantity() {
    if (_selectedProduct != null) {
      final newQuantity = int.tryParse(_quantityController.text) ?? 0;
      setState(() {
        _selectedProduct!.quantiteSaisie = newQuantity;
        _selectedProduct!.isSynced = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Quantité mise à jour. Pensez à envoyer les modifications.'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _sendDataToServer() async {
    final unsyncedProducts = _allProducts.where((p) => !p.isSynced).toList();

    if (unsyncedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucune modification à envoyer.'),
      ));
      return;
    }

    final ValueNotifier<String> progressNotifier = ValueNotifier('Préparation de l\'envoi...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: progressNotifier,
            builder: (context, value, child) {
              return Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 20),
                  Text(value),
                ],
              );
            },
          ),
        );
      },
    );

    int successCount = 0;
    for (final product in unsyncedProducts) {
      progressNotifier.value = 'Envoi... (${successCount + 1}/${unsyncedProducts.length})';
      final success = await _apiService.updateProductQuantity(
          product.id, product.quantiteSaisie);
      if (success) {
        setState(() {
          product.isSynced = true;
        });
        successCount++;
      }
    }

    progressNotifier.value = '$successCount sur ${unsyncedProducts.length} envoyé(s).';

    await Future.delayed(const Duration(seconds: 2));

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Widget buildProductView(Product product) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.produitName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent),
          ),
          const SizedBox(height: 10),
          Text('CIP: ${product.produitCip}'),
          const SizedBox(height: 10),
          Text('Stock Théorique: ${product.quantiteInitiale}'),
          const SizedBox(height: 20),
          TextField(
            controller: _quantityController,
            decoration: const InputDecoration(
              labelText: 'Quantité Corrigée',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.none,
            readOnly: true,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}