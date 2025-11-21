// lib/screens/inventory_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import pour les InputFormatters
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';
import 'package:prestinv/screens/recap_screen.dart';
import 'package:prestinv/screens/variance_screen.dart';
import 'package:prestinv/utils/app_utils.dart';
import 'package:prestinv/models/product.dart';
import 'dart:async';

// Import pour le modèle de filtre
import 'package:prestinv/models/product_filter.dart';

class InventoryEntryScreen extends StatefulWidget {
  final String inventoryId;

  const InventoryEntryScreen({super.key, required this.inventoryId});

  @override
  State<InventoryEntryScreen> createState() => _InventoryEntryScreenState();
}

class _InventoryEntryScreenState extends State<InventoryEntryScreen> {
  final _quantityController = TextEditingController();
  final _quantityFocusNode = FocusNode();
  int? _lastDisplayedProductId;

  late ApiService _apiService;

  String? _notificationMessage;
  Color? _notificationColor;
  Timer? _notificationTimer;

  Timer? _sendReminderTimer;

  // Variables pour la recherche
  final _searchController = TextEditingController();
  List<Product> _filteredProducts = [];
  bool _showSearchResults = false;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
      baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );

    _searchController.addListener(_filterProducts);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = Provider.of<EntryProvider>(context, listen: false);
        provider.reset();
        provider.fetchRayons(_apiService, widget.inventoryId);
      }
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _quantityFocusNode.dispose();
    _notificationTimer?.cancel();
    _sendReminderTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // --- NOUVEAU : Fonction de navigation avec chargement ---
  void _navigateToRecap() async {
    // 1. Afficher le loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text("Chargement du récap..."),
          ],
        ),
      ),
    );

    try {
      final provider = Provider.of<EntryProvider>(context, listen: false);

      // 2. Récupérer les données (simule le chargement du serveur)
      // On utilise l'API service pour avoir des données fraîches comme le faisait le RecapScreen
      final products = await _apiService.fetchProducts(widget.inventoryId, provider.selectedRayon!.id);

      if (!mounted) return;

      // 3. Fermer le loader
      Navigator.of(context).pop();

      // 4. Naviguer vers l'écran Récap avec les données
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecapScreen(
        inventoryId: widget.inventoryId,
        rayonId: provider.selectedRayon!.id,
        rayonName: provider.selectedRayon!.libelle,
        preloadedProducts: products, // On passe les produits chargés
      )));

    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // En cas d'erreur, on ferme le loader
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }
  // --- FIN ---

  void _showNotification(String message, Color color) {
    _notificationTimer?.cancel();
    setState(() {
      _notificationMessage = message;
      _notificationColor = color;
    });
    _notificationTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _notificationMessage = null;
        });
      }
    });
  }

  void _resetSendReminderTimer() {
    _sendReminderTimer?.cancel();
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final provider = Provider.of<EntryProvider>(context, listen: false);

    if (appConfig.sendMode == SendMode.collect && appConfig.sendReminderMinutes > 0) {
      _sendReminderTimer = Timer(Duration(minutes: appConfig.sendReminderMinutes), () {
        if (provider.hasUnsyncedData && mounted) {
          _showSendReminderNotification();
        }
      });
    }
  }

  void _showSendReminderNotification() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rappel : Vous avez des données non envoyées !'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _onKeyPressed(String value) {
    if (value == 'DEL') {
      if (_quantityController.text.isNotEmpty) {
        _quantityController.text = _quantityController.text.substring(0, _quantityController.text.length - 1);
      }
    } else if (value == 'OK') {
      _validateAndProceed();
    } else {
      _quantityController.text += value;
    }
  }

  Future<void> _sendDataToServer() async {
    if (!mounted) return;
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (!provider.hasUnsyncedData) {
      _showNotification('Aucune nouvelle saisie à envoyer.', Colors.orange);
      return;
    }
    final ValueNotifier<String> progressNotifier = ValueNotifier('Préparation...');
    if (mounted) {
      showProgressDialog(context, progressNotifier);
    } else {
      return;
    }

    int unsyncedCount = provider.products.where((p) => !p.isSynced).length;

    await provider.sendDataToServer(_apiService, (int current, int total) {
      progressNotifier.value = 'Envoi... ($current/$total)';
    });

    progressNotifier.value = '$unsyncedCount article(s) traité(s).';
    _sendReminderTimer?.cancel();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _validateAndProceed() async {
    if (!mounted) return;
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    if (_quantityController.text.isEmpty) {
      _showNotification('Veuillez saisir une quantité.', Colors.orange);
      return;
    }
    final quantity = int.tryParse(_quantityController.text) ?? 0;

    Future<void> proceedToNext() async {
      await provider.updateQuantity(quantity.toString());
      _resetSendReminderTimer();
      if (appConfig.sendMode == SendMode.direct) {
        try {
          await _apiService.updateProductQuantity(provider.currentProduct!.id, quantity);
          if (mounted) {
            _showNotification('Saisie envoyée !', Colors.green);
          }
        } catch (e) {
          if (mounted) {
            _showNotification('Erreur réseau. Saisie non envoyée.', Colors.red);
          }
        }
      }

      bool isLastProduct = provider.currentProductIndex >= provider.totalProducts - 1;

      if (isLastProduct && provider.totalProducts > 0) {
        _sendReminderTimer?.cancel();
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(provider.activeFilter.isActive ? 'Fin du filtre' : 'Fin de l\'emplacement'),
            content: Text(provider.activeFilter.isActive
                ? 'Vous avez traité le dernier produit du filtre.'
                : 'Vous avez traité le dernier produit. Voulez-vous envoyer les données au serveur ?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
              if (!provider.activeFilter.isActive)
                TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _sendDataToServer();
                    },
                    child: const Text('Oui, envoyer')),
            ],
          ),
        );
      } else {
        provider.nextProduct();
      }
    }

    if (quantity > appConfig.largeValueThreshold) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Alerte Grande Quantité'),
          content: Text('La quantité saisie ($quantity) est très élevée. Voulez-vous confirmer ?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Non')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Oui, Confirmer')),
          ],
        ),
      );
      if (confirmed == true) {
        await proceedToNext();
      }
    } else {
      await proceedToNext();
    }
  }

  Future<bool> _onWillPop() async {
    _sendReminderTimer?.cancel();
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (!provider.hasUnsyncedData) {
      return true;
    }
    if (!mounted) return false;
    final bool? sendAndLeave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter l\'inventaire ?'),
        content: const Text('Des données n\'ont pas été envoyées. Voulez-vous les envoyer avant de quitter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Envoyer et Quitter')),
        ],
      ),
    );
    if (!mounted) return false;
    if (sendAndLeave == true) {
      await _sendDataToServer();
      return true;
    } else {
      _resetSendReminderTimer();
      return false;
    }
  }

  void _showPendingDataDialog() {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    provider.acknowledgedPendingSession();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saisie non terminée'),
        content: const Text('Des saisies non envoyées de la dernière session ont été trouvées. Voulez-vous les envoyer maintenant ?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Non')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _sendDataToServer();
            },
            child: const Text('Oui, envoyer'),
          ),
        ],
      ),
    );
  }

  void _onLocationChanged(Rayon? newValue) async {
    if (newValue == null) return;
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (newValue.id == provider.selectedRayon?.id) return;
    if (provider.hasUnsyncedData) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Changer d\'emplacement ?'),
          content: const Text('Les données de l\'emplacement actuel seront envoyées au serveur avant de changer.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuer')),
          ],
        ),
      );
      if (confirmed != true) return;
      await _sendDataToServer();
    }
    if (mounted) {
      _sendReminderTimer?.cancel();
      _searchController.clear();
      _showSearchResults = false;
      provider.fetchProducts(_apiService, widget.inventoryId, newValue.id).then((_) {
        _resetSendReminderTimer();
      });
    }
  }

  // --- Logique de recherche et Scan ---

  void _filterProducts() {
    final provider = Provider.of<EntryProvider>(context, listen: false);
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
        _filteredProducts = provider.products.where((product) {
          return product.produitCip.toLowerCase().contains(query) ||
              product.produitName.toLowerCase().contains(query);
        }).toList();
        _showSearchResults = true;
      });
    }
  }

  void _handleScanOrSearch(String query) {
    if (query.isEmpty) return;

    final provider = Provider.of<EntryProvider>(context, listen: false);

    final matches = provider.allProducts.where((p) {
      final q = query.toLowerCase();
      return p.produitCip.toLowerCase().contains(q) ||
          p.produitName.toLowerCase().contains(q);
    }).toList();

    if (matches.length == 1) {
      _openQuickEntryDialog(matches.first);

      _searchController.clear();
      setState(() {
        _showSearchResults = false;
      });
      FocusScope.of(context).unfocus();

    } else if (matches.length > 1) {
      setState(() {
        _filteredProducts = matches;
        _showSearchResults = true;
      });
      FocusScope.of(context).unfocus();

    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produit non trouvé dans cet emplacement.'), backgroundColor: Colors.red),
      );
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
              const Text('Saisie Rapide (Scan)', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(product.produitName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('CIP: ${product.produitCip}', style: const TextStyle(fontSize: 14)),
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
                    labelText: 'Quantité',
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
                        _saveScannedQuantity(product, qty);
                        Navigator.of(ctx).pop();
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

  void _saveScannedQuantity(Product product, int quantity) async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    product.quantiteSaisie = quantity;
    product.isSynced = false;

    await provider.updateQuantity(provider.currentProduct?.quantiteSaisie.toString() ?? "0");

    if (mounted) {
      _showNotification('Saisie enregistrée : ${product.produitName}', Colors.green);
    }

    if (appConfig.sendMode == SendMode.direct) {
      try {
        await _apiService.updateProductQuantity(product.id, quantity);
      } catch (e) {
        // Erreur silencieuse
      }
    }
  }

  void _selectProduct(Product product) {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    provider.jumpToProduct(product);

    if (mounted) {
      setState(() {
        _searchController.clear();
        _showSearchResults = false;
        FocusScope.of(context).unfocus();
      });
    }
  }

  void _showFilterDialog(BuildContext context, EntryProvider provider) {
    final currentFilter = provider.activeFilter;
    final totalProducts = provider.totalProductsInRayon;

    final _fromNumController = TextEditingController(text: currentFilter.type == FilterType.numeric ? currentFilter.from : '');
    final _toNumController = TextEditingController(text: currentFilter.type == FilterType.numeric ? currentFilter.to : '');
    final _fromAlphaController = TextEditingController(text: currentFilter.type == FilterType.alphabetic ? currentFilter.from : '');
    final _toAlphaController = TextEditingController(text: currentFilter.type == FilterType.alphabetic ? currentFilter.to : '');

    FilterType selectedType = currentFilter.type;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return AlertDialog(
              title: const Text('Appliquer un filtre'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<FilterType>(
                      title: const Text('Intervalle numérique'),
                      value: FilterType.numeric,
                      groupValue: selectedType,
                      onChanged: (val) => setPopupState(() => selectedType = val!),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fromNumController,
                            decoration: const InputDecoration(labelText: 'De (N°)', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            enabled: selectedType == FilterType.numeric,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _toNumController,
                            decoration: const InputDecoration(labelText: 'À (N°)', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            enabled: selectedType == FilterType.numeric,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    RadioListTile<FilterType>(
                      title: const Text('Intervalle alphabétique'),
                      value: FilterType.alphabetic,
                      groupValue: selectedType,
                      onChanged: (val) => setPopupState(() => selectedType = val!),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fromAlphaController,
                            decoration: const InputDecoration(labelText: 'De (Texte)', border: OutlineInputBorder()),
                            inputFormatters: [LengthLimitingTextInputFormatter(3)],
                            enabled: selectedType == FilterType.alphabetic,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _toAlphaController,
                            decoration: const InputDecoration(labelText: 'À (Texte)', border: OutlineInputBorder()),
                            inputFormatters: [LengthLimitingTextInputFormatter(3)],
                            enabled: selectedType == FilterType.alphabetic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
                ElevatedButton(
                  child: const Text('Appliquer'),
                  onPressed: () {
                    ProductFilter newFilter = ProductFilter();

                    if (selectedType == FilterType.numeric) {
                      int from = int.tryParse(_fromNumController.text) ?? 0;
                      int to = int.tryParse(_toNumController.text) ?? 0;
                      if (from <= 0) from = 1;
                      if (to > totalProducts) to = totalProducts;
                      if (to == 0) to = totalProducts;
                      if (from > to) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur : "De" doit être inférieur à "À"'), backgroundColor: Colors.red));
                        return;
                      }
                      newFilter = ProductFilter(type: FilterType.numeric, from: from.toString(), to: to.toString());

                    } else if (selectedType == FilterType.alphabetic) {
                      String from = _fromAlphaController.text.toUpperCase();
                      String to = _toAlphaController.text.toUpperCase();
                      if (from.isEmpty || to.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur : Les champs ne peuvent pas être vides'), backgroundColor: Colors.red));
                        return;
                      }
                      if (from.compareTo(to) > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur : "De" doit être alphabétiquement avant "À"'), backgroundColor: Colors.red));
                        return;
                      }
                      newFilter = ProductFilter(type: FilterType.alphabetic, from: from, to: to);
                    }

                    provider.applyFilter(newFilter);
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saisie Inventaire'),
          actions: [
            IconButton(icon: const Icon(Icons.send), tooltip: 'Envoyer les données', onPressed: _sendDataToServer),
            Consumer<EntryProvider>(
              builder: (context, provider, child) {
                if (provider.selectedRayon == null) return const SizedBox.shrink();
                return Row(
                  children: [
                    // MODIFIÉ : Appel à la nouvelle fonction _navigateToRecap
                    IconButton(icon: const Icon(Icons.list_alt_outlined), tooltip: 'Récapitulatif', onPressed: () {
                      if (!mounted) return;
                      _navigateToRecap();
                    }),
                    IconButton(icon: const Icon(Icons.edit_note_outlined), tooltip: 'Correction écarts', onPressed: () {
                      if (!mounted) return;
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => VarianceScreen(inventoryId: widget.inventoryId, rayonId: provider.selectedRayon!.id, rayonName: provider.selectedRayon!.libelle)));
                    }),
                  ],
                );
              },
            ),
          ],
        ),
        body: Consumer<EntryProvider>(
          builder: (context, provider, child) {
            if (provider.error != null) {
              return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Une erreur est survenue :\n${provider.error}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 16))));
            }
            if (provider.isLoading && provider.rayons.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final currentProduct = provider.currentProduct;
            if (currentProduct != null && currentProduct.id != _lastDisplayedProductId) {
              _lastDisplayedProductId = currentProduct.id;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _quantityController.clear();
                  _quantityFocusNode.requestFocus();
                }
              });
            }
            if (provider.hasPendingSession) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showPendingDataDialog();
              });
            }

            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Rayon>(
                      isExpanded: true,
                      hint: const Text('Sélectionner un emplacement'),
                      value: provider.selectedRayon,
                      icon: const Icon(Icons.touch_app_outlined, color: AppColors.primary),
                      style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold),
                      onChanged: _onLocationChanged,
                      items: provider.rayons.map<DropdownMenuItem<Rayon>>((Rayon rayon) => DropdownMenuItem<Rayon>(value: rayon, child: Text(rayon.displayName))).toList(),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onSubmitted: (value) => _handleScanOrSearch(value),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            labelText: 'Rechercher / Scanner',
                            hintText: 'CIP, Nom ou Scan...',
                            prefixIcon: const Icon(Icons.qr_code_scanner, size: 20),
                            isDense: true,
                            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                FocusScope.of(context).unfocus();
                              },
                            )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(12), minimumSize: Size.zero),
                        onPressed: provider.selectedRayon == null ? null : () => _showFilterDialog(context, provider),
                        child: const Icon(Icons.filter_alt_outlined),
                      ),
                      const SizedBox(width: 8),

                      OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(12), minimumSize: Size.zero),
                        onPressed: (provider.selectedRayon == null || !provider.activeFilter.isActive)
                            ? null
                            : () => provider.applyFilter(ProductFilter(type: FilterType.none)),
                        child: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 1),

                Expanded(
                  child: Stack(
                    children: [
                      (provider.isLoading && provider.products.isEmpty)
                          ? const Center(child: CircularProgressIndicator())
                          : (provider.products.isEmpty || provider.currentProduct == null)
                          ? Center(
                          child: Text(
                              provider.activeFilter.isActive
                                  ? 'Aucun produit dans cet intervalle.'
                                  : 'Aucun produit. Sélectionnez un emplacement.'
                          )
                      )
                          : buildProductView(provider),

                      if (_showSearchResults)
                        Container(
                          color: AppColors.background.withOpacity(0.98),
                          child: _filteredProducts.isEmpty
                              ? Center(
                              child: Text(
                                  "Aucun produit ne correspond à votre recherche ${provider.activeFilter.isActive ? 'dans ce filtre.' : ''}"
                              )
                          )
                              : ListView.builder(
                            itemCount: _filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = _filteredProducts[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                child: ListTile(
                                  title: Text(product.produitName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text('CIP: ${product.produitCip} / Stock Théo: ${product.quantiteInitiale}'),
                                  onTap: () => _selectProduct(product),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                NumericKeyboard(onKeyPressed: _onKeyPressed),
              ],
            );
          },
        ),
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
          ? const SizedBox(height: 48, key: ValueKey('empty'))
          : Container(
        key: const ValueKey('notification'),
        height: 48,
        child: Center(
          child: Text(
            _notificationMessage!,
            style: TextStyle(color: _notificationColor, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget buildProductView(EntryProvider provider) {
    final Product product = provider.currentProduct!;
    const textFieldBorderColor = Colors.deepPurple;

    final screenHeight = MediaQuery.of(context).size.height;
    final bool isSmallScreen = screenHeight < 700;

    double titleFontSize = 16;
    double priceFontSize = 16;
    double stockFontSize = 16;
    double badgeFontSize = 14;
    double quantityFontSize = 26;
    double buttonSize = 64;
    double buttonIconSize = 30;

    if (isSmallScreen) {
      titleFontSize = 14;
      priceFontSize = 13;
      stockFontSize = 14;
      badgeFontSize = 12;
      quantityFontSize = 22;
      buttonSize = 56;
      buttonIconSize = 28;
    }

    final double twoLineTitleHeight = (titleFontSize * 1.4) * 2;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      children: [
        const SizedBox(height: 8),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '${provider.currentProductIndex + 1} / ${provider.totalProductsInRayon}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: stockFontSize),
            ),

            if (provider.activeFilter.isActive)
              Flexible(
                child: Builder(
                    builder: (context) {
                      String filterDetails = '';
                      final filter = provider.activeFilter;

                      if (filter.type == FilterType.numeric) {
                        filterDetails = 'N° ${filter.from} à ${filter.to}';
                      } else if (filter.type == FilterType.alphabetic) {
                        filterDetails = 'De ${filter.from} à ${filter.to}';
                      }

                      return Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade300)
                        ),
                        child: Text(
                          'Filtre: $filterDetails  |  Pos: ${provider.currentProductIndex + 1}/${provider.totalProducts}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: badgeFontSize,
                            color: Colors.blue.shade900,
                          ),
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      );
                    }
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),

        Container(
          height: twoLineTitleHeight,
          alignment: Alignment.centerLeft,
          child: Text(
            '${product.produitCip} - ${product.produitName}',
            style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold, color: AppColors.primary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Prix Achat: ${product.produitPrixAchat} F', style: TextStyle(fontSize: priceFontSize, color: Colors.orange, fontWeight: FontWeight.w500)),
              Text('Prix Vente: ${product.produitPrixUni} F', style: TextStyle(fontSize: priceFontSize, color: AppColors.accent, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        Consumer<AppConfig>(
          builder: (context, appConfig, child) {
            return Visibility(
              visible: appConfig.showTheoreticalStock,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'Stock Théorique: ${product.quantiteInitiale}',
                  style: TextStyle(fontSize: stockFontSize, fontWeight: FontWeight.bold, color: product.quantiteInitiale < 0 ? Colors.red.shade700 : const Color(0xFF1B5E20)),
                ),
              ),
            );
          },
        ),

        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                  side: const BorderSide(color: textFieldBorderColor, width: 2),
                ),
                onPressed: provider.previousProduct,
                child: Icon(Icons.chevron_left, size: buttonIconSize, color: textFieldBorderColor),
              ),
            ),
            const SizedBox(width: 8),

            Expanded(
              child: TextField(
                controller: _quantityController,
                focusNode: _quantityFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Quantité Comptée',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: textFieldBorderColor, width: 2),
                  ),
                ),
                keyboardType: TextInputType.none,
                readOnly: true,
                showCursor: true,
                textAlign: TextAlign.center,
                cursorColor: textFieldBorderColor,
                style: TextStyle(fontSize: quantityFontSize, fontWeight: FontWeight.bold, color: textFieldBorderColor),
              ),
            ),

            SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                  side: const BorderSide(color: Colors.red, width: 2),
                ),
                onPressed: () => provider.goToFirstProduct(),
                child: Icon(Icons.first_page, size: buttonIconSize, color: Colors.red),
              ),
            ),
          ],
        ),
        _buildNotificationArea(),
      ],
    );
  }
}