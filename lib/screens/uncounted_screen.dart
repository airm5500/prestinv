// lib/screens/uncounted_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';

// Enum pour les types de filtres de stock
enum StockFilterType { none, less, more, lessEq, moreEq, diff, equal }

class UncountedScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;

  const UncountedScreen({
    super.key,
    required this.inventoryId,
    required this.inventoryName,
  });

  @override
  State<UncountedScreen> createState() => _UncountedScreenState();
}

class _UncountedScreenState extends State<UncountedScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  Timer? _debounceTimer;
  bool _isSearching = false;

  late ApiService _apiService;

  // Listes
  List<Product> _allUntouched = [];
  List<Product> _displayedProducts = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Notification
  String? _notificationMessage;
  Color? _notificationColor;
  Timer? _notificationTimer;

  // État du filtre Stock Théo
  StockFilterType _currentFilterType = StockFilterType.none;
  int _currentFilterValue = 0;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
      baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );

    _searchFocusNode.addListener(() {
      setState(() {
        _isSearching = _searchFocusNode.hasFocus;
      });
    });

    _loadUntouchedProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUntouchedProducts() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final products = await _apiService.fetchUntouchedProducts(widget.inventoryId);
      if (mounted) {
        setState(() {
          _allUntouched = products;
          // On applique le filtre initial
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // --- LOGIQUE DE FILTRAGE ---

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _applyFilters(); // Filtrage local immédiat
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        _performApiSearch(query);
      }
    });
  }

  /// Applique à la fois la recherche texte ET le filtre stock
  void _applyFilters() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      _displayedProducts = _allUntouched.where((p) {
        // 1. Filtre Texte
        bool matchesQuery = true;
        if (query.isNotEmpty) {
          matchesQuery = p.produitCip.contains(query) ||
              p.produitName.toLowerCase().contains(query);
        }

        // 2. Filtre Stock Théo
        bool matchesStock = true;
        if (_currentFilterType != StockFilterType.none) {
          final stock = p.quantiteInitiale;
          final val = _currentFilterValue;
          switch (_currentFilterType) {
            case StockFilterType.less: matchesStock = stock < val; break;
            case StockFilterType.more: matchesStock = stock > val; break;
            case StockFilterType.lessEq: matchesStock = stock <= val; break;
            case StockFilterType.moreEq: matchesStock = stock >= val; break;
            case StockFilterType.diff: matchesStock = stock != val; break;
            case StockFilterType.equal: matchesStock = stock == val; break;
            default: break;
          }
        }

        return matchesQuery && matchesStock;
      }).toList();
    });
  }

  // --- DIALOGUE DE FILTRE (CORRIGÉ) ---
  void _showStockFilterDialog() {
    // Variables temporaires pour le dialog
    StockFilterType tempType = _currentFilterType;
    final TextEditingController valController = TextEditingController(text: _currentFilterValue.toString());

    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text("Filtrer par Stock Théo"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nous définissons les RadioListTiles directement ici pour que setDialogState fonctionne sur tempType
                      RadioListTile<StockFilterType>(
                        title: const Text("Aucun filtre", style: TextStyle(fontSize: 14)),
                        value: StockFilterType.none,
                        groupValue: tempType,
                        dense: true,
                        onChanged: (val) => setDialogState(() => tempType = val!),
                      ),
                      const Divider(),
                      RadioListTile<StockFilterType>(
                        title: const Text("Supérieur à (>)", style: TextStyle(fontSize: 14)),
                        value: StockFilterType.more,
                        groupValue: tempType,
                        dense: true,
                        onChanged: (val) => setDialogState(() => tempType = val!),
                      ),
                      RadioListTile<StockFilterType>(
                        title: const Text("Inférieur à (<)", style: TextStyle(fontSize: 14)),
                        value: StockFilterType.less,
                        groupValue: tempType,
                        dense: true,
                        onChanged: (val) => setDialogState(() => tempType = val!),
                      ),
                      RadioListTile<StockFilterType>(
                        title: const Text("Supérieur ou égal (>=)", style: TextStyle(fontSize: 14)),
                        value: StockFilterType.moreEq,
                        groupValue: tempType,
                        dense: true,
                        onChanged: (val) => setDialogState(() => tempType = val!),
                      ),
                      RadioListTile<StockFilterType>(
                        title: const Text("Inférieur ou égal (<=)", style: TextStyle(fontSize: 14)),
                        value: StockFilterType.lessEq,
                        groupValue: tempType,
                        dense: true,
                        onChanged: (val) => setDialogState(() => tempType = val!),
                      ),
                      RadioListTile<StockFilterType>(
                        title: const Text("Égal à (=)", style: TextStyle(fontSize: 14)),
                        value: StockFilterType.equal,
                        groupValue: tempType,
                        dense: true,
                        onChanged: (val) => setDialogState(() => tempType = val!),
                      ),
                      RadioListTile<StockFilterType>(
                        title: const Text("Différent de (!=)", style: TextStyle(fontSize: 14)),
                        value: StockFilterType.diff,
                        groupValue: tempType,
                        dense: true,
                        onChanged: (val) => setDialogState(() => tempType = val!),
                      ),

                      const SizedBox(height: 15),

                      // Le champ texte s'affiche uniquement si un filtre est sélectionné
                      if (tempType != StockFilterType.none)
                        TextField(
                          controller: valController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: "Valeur de référence",
                            hintText: "Ex: 0",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.numbers),
                          ),
                          autofocus: true,
                        )
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Annuler")
                  ),
                  ElevatedButton(
                      onPressed: () {
                        // Application des changements
                        setState(() {
                          _currentFilterType = tempType;
                          _currentFilterValue = int.tryParse(valController.text) ?? 0;
                        });
                        _applyFilters();
                        Navigator.pop(ctx);
                      },
                      child: const Text("Appliquer")
                  ),
                ],
              );
            },
          );
        }
    );
  }

  Future<void> _performApiSearch(String query) async {
    try {
      final results = await _apiService.fetchUntouchedProducts(widget.inventoryId, query: query);
      if (!mounted) return;

      if (results.length == 1) {
        _openSaisieDialog(results.first);
        _searchController.clear();
        _applyFilters();
        FocusScope.of(context).unfocus();
      } else if (results.isNotEmpty) {
        setState(() {
          _allUntouched = results;
          _applyFilters();
        });
      }
    } catch (e) {
      print("Erreur recherche API: $e");
    }
  }

  // --- SAISIE ET VALIDATION ---

  void _openSaisieDialog(Product product) {
    final qtyController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Saisie Restant', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(product.produitName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('CIP: ${product.produitCip}', style: const TextStyle(fontSize: 14)),
              const Divider(),
              // Mise en valeur si filtre actif
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Stock Théo: ${product.quantiteInitiale}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _currentFilterType != StockFilterType.none ? Colors.blue : Colors.blueGrey,
                          fontSize: 16
                      )
                  ),
                ],
              )
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent),
                  decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder()),
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
                        final int qty = int.tryParse(qtyController.text) ?? 0;
                        _applySaisie(product, qty);
                        Navigator.of(ctx).pop();

                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (mounted) _searchFocusNode.requestFocus();
                        });
                      } else if (key == 'DEL') {
                        if (qtyController.text.isNotEmpty) {
                          qtyController.text = qtyController.text.substring(0, qtyController.text.length - 1);
                        }
                      } else {
                        qtyController.text += key;
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

  void _applySaisie(Product product, int quantity) async {
    try {
      await _apiService.updateProductQuantity(product.id, quantity);

      if (mounted) {
        _showNotification('${product.produitName} : $quantity saisi', Colors.green);
        setState(() {
          // On retire de la liste globale
          _allUntouched.removeWhere((p) => p.id == product.id);
          // On réapplique les filtres pour mettre à jour l'affichage
          _applyFilters();
        });
      }
    } catch (e) {
      if (mounted) {
        _showNotification("Erreur d'envoi : $e", Colors.red);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restants à faire'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUntouchedProducts,
            tooltip: 'Actualiser la liste',
          )
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche AVEC bouton filtre
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    onSubmitted: (val) => _performApiSearch(val),
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Scanner ou Rechercher',
                      hintText: 'CIP, Nom...',
                      prefixIcon: const Icon(Icons.qr_code_scanner, size: 28, color: AppColors.primary),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _applyFilters(); _searchFocusNode.requestFocus(); })
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // BOUTON FILTRE
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    FloatingActionButton(
                      mini: true,
                      backgroundColor: _currentFilterType != StockFilterType.none ? Colors.orange : Colors.grey.shade200,
                      foregroundColor: _currentFilterType != StockFilterType.none ? Colors.white : Colors.black,
                      onPressed: _showStockFilterDialog,
                      child: const Icon(Icons.filter_list),
                    ),
                    if (_currentFilterType != StockFilterType.none)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                      )
                  ],
                )
              ],
            ),
          ),

          // Indicateur de filtre actif
          if (_currentFilterType != StockFilterType.none)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Filtre actif : Stock ${_getFilterSymbol(_currentFilterType)} $_currentFilterValue",
                      style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold)
                  ),
                  InkWell(
                    onTap: () {
                      setState(() => _currentFilterType = StockFilterType.none);
                      _applyFilters();
                    },
                    child: const Icon(Icons.close, size: 18, color: Colors.orange),
                  )
                ],
              ),
            ),

          // Liste des restants
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(child: Text("Erreur : $_errorMessage", style: const TextStyle(color: Colors.red)))
                : _displayedProducts.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      _currentFilterType != StockFilterType.none ? Icons.filter_alt_off : Icons.check_circle,
                      size: 64, color: Colors.grey.shade300
                  ),
                  const SizedBox(height: 16),
                  Text(
                      _currentFilterType != StockFilterType.none ? "Aucun produit ne correspond au filtre." : "Tout est inventorié !",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
            )
                : ListView.separated(
              itemCount: _displayedProducts.length,
              separatorBuilder: (ctx, i) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final p = _displayedProducts[i];
                return ListTile(
                  title: Text(p.produitName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('CIP: ${p.produitCip}'),
                  trailing: Consumer<AppConfig>(
                      builder: (context, appConfig, child) {
                        if (appConfig.showTheoreticalStock) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade300)
                            ),
                            child: Text('Théo: ${p.quantiteInitiale}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                  ),
                  onTap: () => _openSaisieDialog(p),
                );
              },
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _notificationMessage == null
                ? const SizedBox(height: 0, key: ValueKey('empty'))
                : Container(
              key: const ValueKey('notification'),
              width: double.infinity,
              color: _notificationColor,
              padding: const EdgeInsets.all(12),
              child: Text(
                _notificationMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (!_isSearching && _displayedProducts.isNotEmpty)
            const SizedBox(height: 0),
        ],
      ),
    );
  }

  String _getFilterSymbol(StockFilterType type) {
    switch (type) {
      case StockFilterType.less: return "<";
      case StockFilterType.more: return ">";
      case StockFilterType.lessEq: return "<=";
      case StockFilterType.moreEq: return ">=";
      case StockFilterType.equal: return "=";
      case StockFilterType.diff: return "!=";
      default: return "";
    }
  }
}