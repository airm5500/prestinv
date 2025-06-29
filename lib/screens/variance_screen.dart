// lib/screens/variance_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/screens/barcode_scanner_screen.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';
import 'package:prestinv/utils/app_utils.dart';
import 'package:provider/provider.dart';

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

  List<Product> _productsWithVariance = [];
  List<Product> _filteredProducts = [];
  Product? _selectedProduct;
  bool _isLoading = true;
  bool _showSearchResults = false;
  bool _isNewEntry = true;
  late ApiService _apiService;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
      baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );
    _fetchAndSetupProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _fetchAndSetupProducts() async {
    setState(() => _isLoading = true);
    try {
      List<Product> allProductsFromServer = await _apiService.fetchProducts(widget.inventoryId, widget.rayonId);

      // FILTRAGE : On ne garde que les produits qui ont fait l'objet d'une saisie et qui présentent un écart.
      _productsWithVariance = allProductsFromServer
          .where((p) => p.quantiteSaisie != p.quantiteInitiale)
          .toList();

      if (_productsWithVariance.isNotEmpty) {
        _selectProduct(_productsWithVariance.first);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de chargement des produits: $e')),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _filteredProducts = [];
          _showSearchResults = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _filteredProducts = _productsWithVariance.where((product) {
          return product.produitCip.toLowerCase().contains(query) ||
              product.produitName.toLowerCase().contains(query);
        }).toList();
        _showSearchResults = true;
      });
    }
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

  Future<void> _scanBarcode() async {
    if (!mounted) {
      return;
    }
    try {
      final scannedCode = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );
      if (scannedCode == null || !mounted) {
        return;
      }

      final foundProduct = _productsWithVariance.firstWhere(
            (p) => p.produitCip == scannedCode,
        orElse: () => Product(id: -1, produitCip: '', produitName: 'NOT_FOUND', produitPrixAchat: 0, produitPrixUni: 0, quantiteInitiale: 0, quantiteSaisie: 0),
      );

      if (foundProduct.id != -1) {
        _selectProduct(foundProduct);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ce produit ne fait pas partie des écarts.'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur du scanner: $e')));
      }
    }
  }

  Future<void> _sendDataToServer() async {
    if (!mounted) return;

    final unsyncedProducts = _productsWithVariance.where((p) => !p.isSynced).toList();
    if (unsyncedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune modification à envoyer.')));
      return;
    }

    final ValueNotifier<String> progressNotifier = ValueNotifier('Préparation de l\'envoi...');
    showProgressDialog(context, progressNotifier);

    int successCount = 0;
    try {
      for (final product in unsyncedProducts) {
        progressNotifier.value = 'Envoi... (${successCount + 1}/${unsyncedProducts.length})';
        try {
          await _apiService.updateProductQuantity(product.id, product.quantiteSaisie);
          if (mounted) {
            setState(() => product.isSynced = true);
          }
          successCount++;
        } catch (e) {
          // L'échec d'un produit n'arrête pas la boucle
        }
      }
      progressNotifier.value = '$successCount sur ${unsyncedProducts.length} envoyé(s).';
      await Future.delayed(const Duration(seconds: 2));

    } catch (e) {
      progressNotifier.value = 'Une erreur est survenue !';
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Correction Écarts - ${widget.rayonName}'),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scanner un code-barres', onPressed: _scanBarcode),
          IconButton(icon: const Icon(Icons.send), tooltip: 'Envoyer les modifications', onPressed: _sendDataToServer),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_productsWithVariance.isEmpty && !_isLoading)
          ? const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            "Aucun produit avec un écart de stock n'a été trouvé dans cet emplacement.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      )
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Rechercher un produit avec écart',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear())
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
                    color: const Color(0xF2FFFFFF),
                    child: _filteredProducts.isEmpty
                        ? const Center(child: Text("Ce produit ne fait pas partie des écarts."))
                        : ListView.builder(
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
          Consumer<AppConfig>(
            builder: (context, appConfig, child) {
              return Visibility(
                visible: appConfig.showTheoreticalStock,
                child: Text('Stock Théorique: ${product.quantiteInitiale}'),
              );
            },
          ),
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