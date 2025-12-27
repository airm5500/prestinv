// lib/screens/global_variance_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';

class GlobalVarianceScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;

  const GlobalVarianceScreen({
    super.key,
    required this.inventoryId,
    required this.inventoryName,
  });

  @override
  State<GlobalVarianceScreen> createState() => _GlobalVarianceScreenState();
}

class _GlobalVarianceScreenState extends State<GlobalVarianceScreen> {
  // Contrôleurs pour la recherche
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  // Gestion de la recherche instantanée (Debounce)
  Timer? _debounceTimer;
  bool _isSearching = false;

  late ApiService _apiService;

  // Données
  List<Product> _allVariances = [];
  List<Product> _displayedVariances = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
      baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );

    // Écouteur pour savoir si le clavier virtuel est ouvert
    _searchFocusNode.addListener(() {
      setState(() {
        _isSearching = _searchFocusNode.hasFocus;
      });
    });

    // Chargement initial
    _loadAllVariances();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Chargement de la liste complète au démarrage
  Future<void> _loadAllVariances() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final products = await _apiService.fetchGlobalVariances(widget.inventoryId);
      if (mounted) {
        setState(() {
          _allVariances = products;
          _displayedVariances = products;
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

  // --- LOGIQUE DE RECHERCHE / SCAN ---

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    // 1. Filtrage local immédiat pour la réactivité
    _filterLocally(query);

    // 2. Si c'est un scan (recherche précise), on interroge le serveur après délai
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        _performApiSearch(query);
      }
    });
  }

  void _filterLocally(String query) {
    if (query.isEmpty) {
      setState(() => _displayedVariances = _allVariances);
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _displayedVariances = _allVariances.where((p) =>
      p.produitCip.contains(lowerQuery) ||
          p.produitName.toLowerCase().contains(lowerQuery)
      ).toList();
    });
  }

  Future<void> _performApiSearch(String query) async {
    try {
      // On interroge l'API dédiée aux écarts avec le query
      final results = await _apiService.fetchGlobalVariances(widget.inventoryId, query: query);

      if (!mounted) return;

      // Si on trouve un résultat unique (cas typique du scan douchette)
      if (results.length == 1) {
        _openCorrectionDialog(results.first);
        // On nettoie la recherche pour le prochain scan
        _searchController.clear();
        _filterLocally('');
        FocusScope.of(context).unfocus();
      } else if (results.isNotEmpty) {
        // Si plusieurs résultats, on met à jour l'affichage
        setState(() {
          _displayedVariances = results;
        });
      }
    } catch (e) {
      print("Erreur recherche API: $e");
    }
  }

  // --- CORRECTION ET ENVOI ---

  void _openCorrectionDialog(Product product) {
    final qtyController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Correction Écart', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(product.produitName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('CIP: ${product.produitCip}', style: const TextStyle(fontSize: 14)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Théo: ${product.quantiteInitiale}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                      'Saisi: ${product.quantiteSaisie}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (product.quantiteSaisie == product.quantiteInitiale) ? Colors.green : Colors.red
                      )
                  ),
                ],
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
                  decoration: const InputDecoration(labelText: 'Nouvelle Quantité', border: OutlineInputBorder()),
                  readOnly: true, // Clavier virtuel masqué
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
                        _applyCorrection(product, qty);
                        Navigator.of(ctx).pop();

                        // Retour focus sur recherche pour scan suivant
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

  void _applyCorrection(Product product, int newQuantity) async {
    // 1. Mise à jour Optimiste Locale
    setState(() {
      product.quantiteSaisie = newQuantity;
    });

    // 2. Envoi Serveur
    try {
      await _apiService.updateProductQuantity(product.id, newQuantity);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${product.produitName} : Stock corrigé à $newQuantity'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur d'envoi : $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Correction Écarts (Global)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllVariances,
            tooltip: 'Actualiser la liste',
          )
        ],
      ),
      body: Column(
        children: [
          // --- BARRE DE RECHERCHE ---
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
                labelText: 'Scanner ou Rechercher un produit',
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

          // --- LISTE DES ÉCARTS ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(child: Text("Erreur : $_errorMessage", style: const TextStyle(color: Colors.red)))
                : _displayedVariances.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade300),
                  const SizedBox(height: 16),
                  const Text("Aucun écart trouvé !", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text("Tout semble correct.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
                : ListView.separated(
              itemCount: _displayedVariances.length,
              separatorBuilder: (ctx, i) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final p = _displayedVariances[i];
                final ecart = p.quantiteSaisie - p.quantiteInitiale;

                // --- CORRECTION COULEURS ---
                Color badgeColor;
                Color badgeTextColor;
                Color badgeBorderColor;

                if (ecart > 0) {
                  // Écart Positif (Vert)
                  badgeColor = Colors.green.shade100;
                  badgeTextColor = Colors.green.shade800;
                  badgeBorderColor = Colors.green;
                } else if (ecart < 0) {
                  // Écart Négatif (Rouge)
                  badgeColor = Colors.red.shade100;
                  badgeTextColor = Colors.red.shade800;
                  badgeBorderColor = Colors.red;
                } else {
                  // Pas d'écart (Neutre/Gris) - Rare ici
                  badgeColor = Colors.grey.shade100;
                  badgeTextColor = Colors.grey.shade800;
                  badgeBorderColor = Colors.grey;
                }

                return ListTile(
                  title: Text(p.produitName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('CIP: ${p.produitCip}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Théo: ${p.quantiteInitiale}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('Saisi: ${p.quantiteSaisie}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: badgeBorderColor)
                        ),
                        child: Text(
                          (ecart > 0) ? "+$ecart" : "$ecart",
                          style: TextStyle(
                              color: badgeTextColor,
                              fontWeight: FontWeight.bold
                          ),
                        ),
                      )
                    ],
                  ),
                  onTap: () => _openCorrectionDialog(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}