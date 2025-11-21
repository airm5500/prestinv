// lib/screens/variance_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
  final _quantityFocusNode = FocusNode();

  List<Product> _productsWithVariance = [];
  List<Product> _filteredProducts = [];
  int _currentProductIndex = 0;

  bool _isLoading = true;
  bool _showSearchResults = false;
  bool _isNewEntry = true;
  late ApiService _apiService;

  // AJOUT : Variable pour empêcher le double-clic sur l'impression
  bool _isPrinting = false;

  String? _notificationMessage;
  Color? _notificationColor;
  Timer? _notificationTimer;

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
    _quantityFocusNode.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAndSetupProducts() async {
    setState(() => _isLoading = true);
    try {
      List<Product> allProductsFromServer = await _apiService.fetchProducts(widget.inventoryId, widget.rayonId);

      if (mounted) {
        setState(() {
          _productsWithVariance = allProductsFromServer
              .where((p) => p.quantiteSaisie != p.quantiteInitiale)
              .toList();

          if (_productsWithVariance.isNotEmpty) {
            _updateCurrentProduct(0);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de chargement des produits: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _updateCurrentProduct(int index) {
    setState(() {
      _currentProductIndex = index;
      _quantityController.text = _productsWithVariance[index].quantiteSaisie.toString();
      _isNewEntry = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quantityFocusNode.requestFocus();
    });
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      if (mounted) { setState(() { _filteredProducts = []; _showSearchResults = false; }); }
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
    final index = _productsWithVariance.indexWhere((p) => p.id == product.id);
    if(index != -1) {
      _updateCurrentProduct(index);
      setState(() {
        _searchController.clear();
        _showSearchResults = false;
        FocusScope.of(context).unfocus();
      });
    }
  }

  void _previousProduct() {
    if(_currentProductIndex > 0) {
      _updateCurrentProduct(_currentProductIndex - 1);
    }
  }

  void _nextProduct() {
    if(_currentProductIndex < _productsWithVariance.length - 1) {
      _updateCurrentProduct(_currentProductIndex + 1);
    }
  }

  void _onKeyPressed(String value) {
    if (value == 'DEL') {
      if (_quantityController.text.isNotEmpty) {
        _quantityController.text = _quantityController.text.substring(0, _quantityController.text.length - 1);
      }
      _isNewEntry = false;
    } else if (value == 'OK') {
      _updateQuantityAndSend();
    } else {
      if (_isNewEntry) {
        _quantityController.text = value;
        _isNewEntry = false;
      } else {
        _quantityController.text += value;
      }
    }
  }

  void _updateQuantityAndSend() async {
    if (_productsWithVariance.isEmpty || !mounted) return;

    final product = _productsWithVariance[_currentProductIndex];
    final newQuantity = int.tryParse(_quantityController.text) ?? 0;

    setState(() {
      product.quantiteSaisie = newQuantity;
    });

    try {
      await _apiService.updateProductQuantity(product.id, newQuantity);
      if (mounted) {
        _showNotification('Correction envoyée !', Colors.green);
        _nextProduct();
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Erreur d\'envoi: $e', Colors.red);
      }
    }
  }

  void _showNotification(String message, Color color) {
    _notificationTimer?.cancel();
    setState(() {
      _notificationMessage = message;
      _notificationColor = color;
    });
    _notificationTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) { setState(() => _notificationMessage = null); }
    });
  }

  // MODIFIÉ : Fonction d'impression sécurisée (Anti-ANR)
  Future<void> _printVariances() async {
    // 1. Sécurité : Empêcher les clics multiples
    if (_isPrinting) return;

    setState(() {
      _isPrinting = true;
    });

    // 2. Afficher le loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Génération du PDF..."),
            ],
          ),
        );
      },
    );

    // Petit délai pour laisser l'UI s'afficher
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document();

      final tableData = <List<String>>[
        ['Désignation', 'CIP', 'Stock Théo.', 'Stock Corrigé', 'Écart'],
        ..._productsWithVariance.map((p) => [
          p.produitName,
          p.produitCip,
          p.quantiteInitiale.toString(),
          p.quantiteSaisie.toString(),
          (p.quantiteSaisie - p.quantiteInitiale).toString(),
        ])
      ];

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (context) => pw.Header(level: 0, text: 'Rapport des Écarts - ${widget.rayonName}'),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              context: context,
              data: tableData,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignments: {1: pw.Alignment.center, 2: pw.Alignment.center, 3: pw.Alignment.center},
            )
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (format) => doc.save());

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'impression : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      // 3. Nettoyage : Fermer le loader et déverrouiller
      if (mounted) {
        Navigator.of(context).pop(); // Ferme le dialog
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Correction Écarts - ${widget.rayonName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer les écarts',
            // MODIFIÉ : Désactive le bouton si impression en cours
            onPressed: (_productsWithVariance.isEmpty || _isPrinting)
                ? null
                : _printVariances,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_productsWithVariance.isEmpty && !_isLoading)
          ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Aucun produit avec un écart de stock n'a été trouvé.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16))))
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
                suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) : null,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_productsWithVariance.isNotEmpty && !_showSearchResults)
                  buildProductView(_productsWithVariance[_currentProductIndex]),
                if (_showSearchResults)
                  Container(
                    color: const Color(0xF2FFFFFF),
                    child: _filteredProducts.isEmpty
                        ? const Center(child: Text("Ce produit ne fait pas partie des écarts."))
                        : ListView.builder(
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(_filteredProducts[index].produitName),
                        subtitle: Text('CIP: ${_filteredProducts[index].produitCip}'),
                        onTap: () => _selectProduct(_filteredProducts[index]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildNotificationArea(),
          if (!_showSearchResults) NumericKeyboard(onKeyPressed: _onKeyPressed),
        ],
      ),
    );
  }

  Widget _buildNotificationArea() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _notificationMessage == null
          ? const SizedBox(height: 50, key: ValueKey('empty'))
          : Container(
        key: const ValueKey('notification'),
        height: 50,
        child: Center(
          child: Text(
            _notificationMessage!,
            style: TextStyle(color: _notificationColor, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget buildProductView(Product product) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Produit ${_currentProductIndex + 1} sur ${_productsWithVariance.length}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${product.produitCip} - ${product.produitName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),

          Consumer<AppConfig>(
            builder: (context, appConfig, child) => Visibility(
              visible: appConfig.showTheoreticalStock,
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Stock Théorique: ${product.quantiteInitiale}')
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                    side: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2),
                  ),
                  onPressed: _currentProductIndex > 0 ? _previousProduct : null,
                  child: Icon(Icons.chevron_left, size: 30, color: Theme.of(context).colorScheme.secondary),
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                child: TextField(
                  controller: _quantityController,
                  focusNode: _quantityFocusNode,
                  decoration: const InputDecoration(labelText: 'Quantité Corrigée', border: OutlineInputBorder()),
                  keyboardType: TextInputType.none,
                  readOnly: true,
                  showCursor: true, // On garde aussi l'amélioration du curseur
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),

              SizedBox(
                width: 64,
                height: 64,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                    side: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 2),
                  ),
                  onPressed: _currentProductIndex < _productsWithVariance.length - 1 ? _nextProduct : null,
                  child: Icon(Icons.chevron_right, size: 30, color: Theme.of(context).colorScheme.secondary),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}