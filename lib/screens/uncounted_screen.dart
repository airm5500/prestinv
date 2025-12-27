// lib/screens/uncounted_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';

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

    // Chargement initial des produits non inventoriés
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
          _displayedProducts = products;
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

  // --- RECHERCHE ---

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _filterLocally(query);

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        _performApiSearch(query);
      }
    });
  }

  void _filterLocally(String query) {
    if (query.isEmpty) {
      setState(() => _displayedProducts = _allUntouched);
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _displayedProducts = _allUntouched.where((p) =>
      p.produitCip.contains(lowerQuery) ||
          p.produitName.toLowerCase().contains(lowerQuery)
      ).toList();
    });
  }

  Future<void> _performApiSearch(String query) async {
    try {
      final results = await _apiService.fetchUntouchedProducts(widget.inventoryId, query: query);

      if (!mounted) return;

      if (results.length == 1) {
        _openSaisieDialog(results.first);
        _searchController.clear();
        _filterLocally('');
        FocusScope.of(context).unfocus();
      } else if (results.isNotEmpty) {
        setState(() {
          _displayedProducts = results;
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
              Consumer<AppConfig>(
                builder: (context, appConfig, child) {
                  return Visibility(
                    visible: appConfig.showTheoreticalStock,
                    child: Text('Stock Théo: ${product.quantiteInitiale}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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
    // 1. Envoi Serveur
    try {
      await _apiService.updateProductQuantity(product.id, quantity);

      if (mounted) {
        _showNotification('${product.produitName} : $quantity saisi', Colors.green);

        // 2. Retrait immédiat de la liste locale (car le produit est maintenant "inventorié")
        setState(() {
          _allUntouched.removeWhere((p) => p.id == product.id);
          _displayedProducts.removeWhere((p) => p.id == product.id);
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
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (val) => _performApiSearch(val),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Scanner ou Rechercher un produit restant',
                hintText: 'CIP, Nom...',
                prefixIcon: const Icon(Icons.qr_code_scanner, size: 28, color: AppColors.primary),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterLocally('');
                    _searchFocusNode.requestFocus();
                  },
                )
                    : null,
              ),
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
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text("Tout est inventorié !", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text("Aucun produit restant.", style: TextStyle(color: Colors.grey)),
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
                  // On affiche le stock théorique à titre indicatif si option activée
                  trailing: Consumer<AppConfig>(
                      builder: (context, appConfig, child) {
                        if (appConfig.showTheoreticalStock) {
                          return Text('Théo: ${p.quantiteInitiale}', style: const TextStyle(color: Colors.grey));
                        }
                        return const SizedBox.shrink();
                      }
                  ),
                  onTap: () => _openSaisieDialog(p),
                );
              },
            ),
          ),

          // Notification snackbar custom
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

          // Clavier numérique si pas de recherche
          if (!_isSearching && _displayedProducts.isNotEmpty)
          // Petit espace vide si on veut que le clavier n'apparaisse pas tout le temps,
          // ou on peut le retirer. Ici je ne mets pas le clavier en bas
          // car la saisie se fait dans le popup.
            const SizedBox(height: 0),
        ],
      ),
    );
  }
}