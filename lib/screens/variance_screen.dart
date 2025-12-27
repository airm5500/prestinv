// lib/screens/variance_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _searchFocusNode = FocusNode();

  final _quantityController = TextEditingController();
  final _quantityFocusNode = FocusNode();

  List<Product> _productsWithVariance = [];
  List<Product> _filteredProducts = [];
  int _currentProductIndex = 0;

  bool _isLoading = true;
  bool _showSearchResults = false;
  bool _isNewEntry = true;
  late ApiService _apiService;

  bool _isPrinting = false;

  bool _continuousScanMode = false;
  bool _isSearching = false;

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

    _searchFocusNode.addListener(() {
      setState(() {
        _isSearching = _searchFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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

  void _handleScanOrSearch(String query) {
    if (query.isEmpty) return;

    final matches = _productsWithVariance.where((p) {
      final q = query.toLowerCase();
      return p.produitCip.toLowerCase().contains(q) ||
          p.produitName.toLowerCase().contains(q);
    }).toList();

    if (matches.length == 1) {
      _openQuickEntryDialog(matches.first);
      _searchController.clear();
      setState(() { _showSearchResults = false; });
    } else if (matches.length > 1) {
      setState(() {
        _filteredProducts = matches;
        _showSearchResults = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce produit n\'est pas dans la liste des écarts.'), backgroundColor: Colors.red),
      );
      _searchFocusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && _searchController.text.isNotEmpty) {
          _searchController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchController.text.length,
          );
        }
      });
    }
  }

  void _openQuickEntryDialog(Product product) {
    final quickQtyController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Correction Rapide', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(product.produitName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('CIP: ${product.produitCip}', style: const TextStyle(fontSize: 14)),
              const Divider(),
              Consumer<AppConfig>(
                builder: (context, appConfig, child) {
                  return Visibility(
                    visible: appConfig.showTheoreticalStock,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Théo: ${product.quantiteInitiale}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                            'Écart Actuel: ${product.quantiteSaisie - product.quantiteInitiale}',
                            style: TextStyle(
                                color: (product.quantiteSaisie - product.quantiteInitiale) == 0 ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold
                            )
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: quickQtyController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent),
                  decoration: const InputDecoration(
                    labelText: 'Nouvelle Qté',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                  autofocus: true,
                  showCursor: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 280,
                  child: NumericKeyboard(
                    onKeyPressed: (key) {
                      if (key == 'OK') {
                        final int qty = int.tryParse(quickQtyController.text) ?? 0;
                        _applyQuickCorrection(product, qty);
                        Navigator.of(ctx).pop();

                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (mounted) {
                            if (_continuousScanMode) {
                              _searchFocusNode.requestFocus();
                            } else {
                              _quantityFocusNode.requestFocus();
                            }
                          }
                        });

                      } else if (key == 'DEL') {
                        if (quickQtyController.text.isNotEmpty) {
                          quickQtyController.text = quickQtyController.text.substring(0, quickQtyController.text.length - 1);
                        }
                      } else {
                        quickQtyController.text += key;
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler', style: TextStyle(color: Colors.red))
            ),
          ],
        );
      },
    );
  }

  void _applyQuickCorrection(Product product, int newQuantity) async {
    setState(() {
      product.quantiteSaisie = newQuantity;
      if (_productsWithVariance.isNotEmpty && _productsWithVariance[_currentProductIndex].id == product.id) {
        _quantityController.text = newQuantity.toString();
      }
    });

    try {
      await _apiService.updateProductQuantity(product.id, newQuantity);
      if (mounted) _showNotification('Correction enregistrée !', Colors.green);
    } catch (e) {
      if (mounted) _showNotification('Erreur sauvegarde: $e', Colors.red);
    }
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
    _openQuickEntryDialog(product);
    _searchController.clear();
    setState(() {
      _showSearchResults = false;
    });
    FocusScope.of(context).unfocus();
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

  // --- PARTIE MODIFIÉE : GÉNÉRATION DU PDF ---
  Future<void> _printVariances() async {
    if (_isPrinting) return;

    setState(() { _isPrinting = true; });

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

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document();

      // MODIFICATION ICI : Ordre des colonnes (CIP en premier)
      final tableData = <List<String>>[
        ['CIP', 'Désignation', 'Stock Théo.', 'Stock Corrigé', 'Écart'],
        ..._productsWithVariance.map((p) => [
          p.produitCip, // CIP en premier
          p.produitName,
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
              // MODIFICATION ICI : Taille de police réduite à 9
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              // Alignement ajusté
              cellAlignments: {
                0: pw.Alignment.centerLeft, // CIP
                1: pw.Alignment.centerLeft, // Désignation
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight
              },
              // Largeur relative pour donner de la place au Nom
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(5),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(1),
              },
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
      if (mounted) {
        Navigator.of(context).pop();
        setState(() { _isPrinting = false; });
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
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onSubmitted: (value) => _handleScanOrSearch(value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Rechercher / Scanner un produit avec écart',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _searchFocusNode.requestFocus();
                          }
                      )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                Column(
                  children: [
                    Switch(
                      value: _continuousScanMode,
                      onChanged: (value) {
                        setState(() {
                          _continuousScanMode = value;
                        });
                        if (value) {
                          _searchFocusNode.requestFocus();
                        }
                      },
                    ),
                    const Text('Mode Scan', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ],
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
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: ListTile(
                            title: Text(product.produitName, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('CIP: ${product.produitCip}'),
                                Text(
                                    'Prix Vente: ${product.produitPrixUni.toStringAsFixed(0)} F',
                                    style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w500)
                                ),
                              ],
                            ),
                            onTap: () => _selectProduct(_filteredProducts[index]),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          _buildNotificationArea(),
          if (!_isSearching && !_showSearchResults)
            NumericKeyboard(onKeyPressed: _onKeyPressed),
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
                  showCursor: true,
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