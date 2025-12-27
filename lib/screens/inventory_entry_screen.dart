// lib/screens/inventory_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:prestinv/models/product_filter.dart';

class InventoryEntryScreen extends StatefulWidget {
  final String inventoryId;
  final bool isQuickMode;
  const InventoryEntryScreen({super.key, required this.inventoryId, this.isQuickMode = false});
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

  // Timer pour la recherche instantanée (Debounce)
  Timer? _debounceTimer;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;
  List<Product> _filteredProducts = [];
  bool _showSearchResults = false;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl, sessionCookie: authProvider.sessionCookie);

    // Détection du focus pour masquer le clavier numérique si le clavier virtuel est ouvert
    _searchFocusNode.addListener(() { setState(() { _isSearching = _searchFocusNode.hasFocus; }); });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = Provider.of<EntryProvider>(context, listen: false);
        provider.reset();

        // En mode Saisie Guidée (pas rapide), on charge la liste des rayons
        if (!widget.isQuickMode) {
          provider.fetchRayons(_apiService, widget.inventoryId);
        }
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
    _searchFocusNode.dispose();
    _debounceTimer?.cancel(); // Annulation du timer de recherche
    super.dispose();
  }

  void _navigateToRecap() async {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Chargement du récap..."),])));
    try {
      final provider = Provider.of<EntryProvider>(context, listen: false);
      String targetRayonId = provider.selectedRayon?.id ?? "";
      String targetRayonName = provider.selectedRayon?.libelle ?? "Global";
      List<Product> products;
      if (targetRayonId.isNotEmpty) {
        products = await _apiService.fetchProducts(widget.inventoryId, targetRayonId);
      } else {
        products = provider.allProducts;
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecapScreen(inventoryId: widget.inventoryId, rayonId: targetRayonId, rayonName: targetRayonName, preloadedProducts: products)));
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showNotification(String message, Color color) {
    _notificationTimer?.cancel();
    setState(() { _notificationMessage = message; _notificationColor = color; });
    _notificationTimer = Timer(const Duration(seconds: 2), () { if (mounted) { setState(() { _notificationMessage = null; }); } });
  }

  void _resetSendReminderTimer() {
    _sendReminderTimer?.cancel();
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (appConfig.sendMode == SendMode.collect && appConfig.sendReminderMinutes > 0) {
      _sendReminderTimer = Timer(Duration(minutes: appConfig.sendReminderMinutes), () { if (provider.hasUnsyncedData && mounted) { _showSendReminderNotification(); } });
    }
  }

  void _showSendReminderNotification() { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rappel : Vous avez des données non envoyées !'), backgroundColor: Colors.blue, duration: Duration(seconds: 5))); }

  void _onKeyPressed(String value) {
    if (value == 'DEL') { if (_quantityController.text.isNotEmpty) { _quantityController.text = _quantityController.text.substring(0, _quantityController.text.length - 1); } } else if (value == 'OK') { _validateAndProceed(); } else { _quantityController.text += value; }
  }

  Future<void> _sendDataToServer() async {
    if (!mounted) return;
    final provider = Provider.of<EntryProvider>(context, listen: false);

    if (!provider.hasUnsyncedData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune donnée en attente d\'envoi.'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)),
      );
      return;
    }

    final ValueNotifier<String> progressNotifier = ValueNotifier('Préparation...');
    if (mounted) showProgressDialog(context, progressNotifier); else return;

    int unsyncedCount = provider.allProducts.where((p) => !p.isSynced).length;
    await provider.sendDataToServer(_apiService, (int current, int total) {
      progressNotifier.value = 'Envoi... ($current/$total)';
    });
    progressNotifier.value = '$unsyncedCount article(s) traité(s).';
    _sendReminderTimer?.cancel();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop();
  }

  void _validateAndProceed() async {
    if (!mounted) return;
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    if (_quantityController.text.isEmpty) { _showNotification('Veuillez saisir une quantité.', Colors.orange); return; }
    final quantity = int.tryParse(_quantityController.text) ?? 0;

    Future<void> proceedToNext() async {
      await provider.updateQuantity(quantity.toString());
      _resetSendReminderTimer();

      if (appConfig.sendMode == SendMode.direct) {
        try {
          await _apiService.updateProductQuantity(provider.currentProduct!.id, quantity);
          if (mounted) { _showNotification('Saisie envoyée !', Colors.green); }
        } catch (e) {
          if (mounted) { _showNotification('Erreur réseau. Saisie non envoyée.', Colors.red); }
        }
      }

      bool isLastProduct = provider.currentProductIndex >= provider.totalProducts - 1;
      if (isLastProduct && provider.totalProducts > 0) {
        _sendReminderTimer?.cancel(); if (!mounted) return;
        showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(provider.activeFilter.isActive ? 'Fin du filtre' : 'Fin de l\'emplacement'), content: Text(provider.activeFilter.isActive ? 'Vous avez traité le dernier produit du filtre.' : 'Vous avez traité le dernier produit. Voulez-vous envoyer les données au serveur ?'), actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')), if (!provider.activeFilter.isActive) TextButton(onPressed: () { Navigator.of(ctx).pop(); _sendDataToServer(); }, child: const Text('Oui, envoyer')), ],),);
      } else {
        provider.nextProduct();
      }
    }

    if (quantity > appConfig.largeValueThreshold) {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Alerte Grande Quantité'), content: Text('La quantité saisie ($quantity) est très élevée. Voulez-vous confirmer ?'), actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Non')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Oui, Confirmer')), ],),);
      if (confirmed == true) { await proceedToNext(); }
    } else { await proceedToNext(); }
  }

  Future<bool> _onWillPop() async {
    _sendReminderTimer?.cancel();
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (!provider.hasUnsyncedData) { return true; }
    if (!mounted) return false;
    final bool? sendAndLeave = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(title: const Text('Quitter l\'inventaire ?'), content: const Text('Des données n\'ont pas été envoyées. Voulez-vous les envoyer avant de quitter ?'), actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Envoyer et Quitter')), ],),);
    if (!mounted) return false;
    if (sendAndLeave == true) { await _sendDataToServer(); return true; } else { _resetSendReminderTimer(); return false; }
  }

  void _showPendingDataDialog() {
    final provider = Provider.of<EntryProvider>(context, listen: false); provider.acknowledgedPendingSession();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Saisie non terminée'), content: const Text('Des saisies non envoyées de la dernière session ont été trouvées. Voulez-vous les envoyer maintenant ?'), actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Non')), TextButton(onPressed: () { Navigator.of(ctx).pop(); _sendDataToServer(); }, child: const Text('Oui, envoyer')), ],),);
  }

  void _onLocationChanged(Rayon? newValue) async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (newValue?.id != provider.selectedRayon?.id) {
      if (provider.hasUnsyncedData) {
        final bool? confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Changer d\'emplacement ?'), content: const Text('Les données actuelles seront envoyées au serveur avant de changer.'), actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuer')), ],),);
        if (confirmed != true) return;
        await _sendDataToServer();
      }
      if (mounted) {
        _sendReminderTimer?.cancel(); _searchController.clear(); _showSearchResults = false;
        if (newValue == null) {
          provider.reset();
          _resetSendReminderTimer();
          if (mounted) _searchFocusNode.requestFocus();
        } else {
          provider.fetchProducts(_apiService, widget.inventoryId, newValue.id).then((_) {
            _resetSendReminderTimer();
            if (mounted) _searchFocusNode.requestFocus();
          });
        }
      }
    }
  }

  // --- LOGIQUE DE RECHERCHE AMÉLIORÉE ---

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    if (query.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _filteredProducts = [];
      });
      return;
    }

    // Déclenche la recherche après 500ms d'inactivité
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      // IMPORTANT: fromTyping = true indique qu'on est en train de taper
      // et qu'on ne veut PAS fermer le clavier ni ouvrir de popup automatiquement
      _handleScanOrSearch(query, fromTyping: true);
    });
  }

  Future<void> _handleScanOrSearch(String query, {bool fromTyping = false}) async {
    if (query.isEmpty) return;

    _debounceTimer?.cancel();
    final provider = Provider.of<EntryProvider>(context, listen: false);

    // Pas de snackbar pendant la frappe pour éviter de polluer l'écran
    if (!fromTyping) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recherche...'), duration: Duration(milliseconds: 500)),
      );
    }

    try {
      final onlineMatches = await provider.searchProductOnline(_apiService, widget.inventoryId, query);

      if (!mounted) return;

      if (onlineMatches.isNotEmpty) {
        // Résultats trouvés
        setState(() {
          _filteredProducts = onlineMatches;
          _showSearchResults = true;
        });

        if (fromTyping) {
          // Pendant la frappe : On affiche la liste MAIS on garde le clavier ouvert.
          // On n'ouvre JAMAIS le popup automatiquement ici, même s'il n'y a qu'un seul résultat.
          // L'utilisateur doit choisir le produit dans la liste.
        } else {
          // Validation manuelle (Touche Entrée) :
          if (onlineMatches.length == 1) {
            // Un seul résultat -> Popup direct et on ferme le clavier
            _openQuickEntryDialog(onlineMatches.first);
            _searchController.clear();
            setState(() { _showSearchResults = false; });
            FocusScope.of(context).unfocus();
          } else {
            // Plusieurs résultats -> On garde le clavier fermé pour voir la liste
            FocusScope.of(context).unfocus();
          }
        }
      } else {
        // Aucun résultat
        if (!fromTyping) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Produit introuvable.'), backgroundColor: Colors.red),
          );
        }
        // En frappe, on ne fait rien de spécial, la liste vide ou ancienne disparaît
      }
    } catch (e) {
      if (mounted && !fromTyping) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
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
              const Text('Saisie Rapide', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(product.produitName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text('CIP: ${product.produitCip}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              if (product.locationLabel != null)
                Text('(${product.locationLabel})', style: const TextStyle(fontSize: 14, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('PA: ${product.produitPrixAchat.toStringAsFixed(0)} F', style: const TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.bold)),
                  Text('PV: ${product.produitPrixUni.toStringAsFixed(0)} F', style: const TextStyle(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Consumer<AppConfig>(
                builder: (context, appConfig, child) {
                  return Visibility(
                    visible: appConfig.showTheoreticalStock,
                    child: Text(
                      'Stock Théo: ${product.quantiteInitiale}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: product.quantiteInitiale < 0 ? Colors.red : Colors.green),
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
                  decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder()),
                  keyboardType: TextInputType.none,
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
                        if (quickQtyController.text.isEmpty) return;

                        final int qty = int.tryParse(quickQtyController.text) ?? 0;
                        _saveScannedQuantity(product, qty);
                        Navigator.of(ctx).pop();

                        // --- GESTION DU RETOUR ET FOCUS ---
                        _searchController.clear();
                        setState(() {
                          _showSearchResults = false;
                          _filteredProducts = [];
                        });

                        if (widget.isQuickMode) {
                          // En mode Rapide, on remet le focus sur la recherche pour le scan suivant
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) _searchFocusNode.requestFocus();
                          });
                        } else {
                          // En mode Guidé (Rayon), on remet le focus sur la saisie de quantité principale
                          // Cela permet de revenir "à l'écran de saisie qui était déjà en cours"
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) {
                              FocusScope.of(context).unfocus(); // Ferme le clavier recherche si ouvert
                              _quantityFocusNode.requestFocus();
                            }
                          });
                        }
                      } else if (key == 'DEL') {
                        if (quickQtyController.text.isNotEmpty) { quickQtyController.text = quickQtyController.text.substring(0, quickQtyController.text.length - 1); }
                      } else { quickQtyController.text += key; }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler', style: TextStyle(color: Colors.red))), ],
        );
      },
    );
  }

  void _saveScannedQuantity(Product product, int quantity) async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    product.quantiteSaisie = quantity;
    await provider.updateSpecificProduct(product);

    if (mounted) { _showNotification('Saisie enregistrée : ${product.produitName}', Colors.green); }
    if (appConfig.sendMode == SendMode.direct) { try { await _apiService.updateProductQuantity(product.id, quantity); } catch (e) { /* ... */ } }
  }

  void _selectProduct(Product product) {
    _openQuickEntryDialog(product);
  }

  void _showLocationSelector(BuildContext context, EntryProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) {
        List<Rayon> filteredRayons = provider.rayons;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Choisir un emplacement'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(labelText: 'Rechercher un rayon', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                      onChanged: (value) { setState(() { filteredRayons = provider.rayons.where((r) => r.displayName.toLowerCase().contains(value.toLowerCase())).toList(); }); },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filteredRayons.isEmpty
                          ? const Center(child: Text("Aucun emplacement trouvé"))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredRayons.length,
                        itemBuilder: (ctx, index) {
                          final rayon = filteredRayons[index];
                          final isSelected = rayon.id == provider.selectedRayon?.id;
                          return ListTile(
                            leading: CircleAvatar(backgroundColor: isSelected ? AppColors.accent.withOpacity(0.1) : AppColors.primary.withOpacity(0.1), child: Icon(Icons.location_on, color: isSelected ? AppColors.accent : AppColors.primary, size: 20)),
                            title: Text(rayon.libelle, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? AppColors.accent : Colors.black)),
                            subtitle: Text(rayon.code, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            onTap: () { Navigator.of(ctx).pop(); _onLocationChanged(rayon); },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')) ],
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
        // resizeToAvoidBottomInset est true par défaut, ce qui permet à la vue de remonter
        // quand le clavier est ouvert, rendant la liste scrollable au-dessus.
        resizeToAvoidBottomInset: true,

        appBar: AppBar(
          title: Text(widget.isQuickMode ? 'Saisie Rapide (Scan)' : 'Saisie Inventaire'),
          actions: [
            IconButton(icon: const Icon(Icons.send), tooltip: 'Envoyer les données', onPressed: _sendDataToServer),
            Consumer<EntryProvider>(
              builder: (context, provider, child) {
                if (provider.selectedRayon == null) return const SizedBox.shrink();
                return Row(
                  children: [
                    IconButton(icon: const Icon(Icons.list_alt_outlined), tooltip: 'Récapitulatif', onPressed: () { if (!mounted) return; _navigateToRecap(); }),
                    IconButton(icon: const Icon(Icons.edit_note_outlined), tooltip: 'Correction écarts', onPressed: () { if (!mounted) return; Navigator.of(context).push(MaterialPageRoute(builder: (_) => VarianceScreen(inventoryId: widget.inventoryId, rayonId: provider.selectedRayon!.id, rayonName: provider.selectedRayon!.libelle))); }),
                  ],
                );
              },
            ),
          ],
        ),
        body: Consumer<EntryProvider>(
          builder: (context, provider, child) {

            bool showLocationSelector = !widget.isQuickMode;
            bool showSearchAndBody = widget.isQuickMode || provider.selectedRayon != null;

            if (provider.error != null) {
              return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Une erreur est survenue :\n${provider.error}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 16))));
            }
            if (provider.isLoading && provider.rayons.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final currentProduct = provider.currentProduct;
            if (!widget.isQuickMode && currentProduct != null && currentProduct.id != _lastDisplayedProductId) {
              _lastDisplayedProductId = currentProduct.id;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) { _quantityController.clear(); _quantityFocusNode.requestFocus(); }
              });
            }
            if (provider.hasPendingSession) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showPendingDataDialog(); }); }

            return Column(
              children: [
                if (showLocationSelector)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8.0),
                        onTap: () => _showLocationSelector(context, provider),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
                          child: Row(
                            children: [
                              const Icon(Icons.touch_app_outlined, color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  provider.selectedRayon?.libelle ?? 'Sélectionner un emplacement',
                                  style: TextStyle(
                                    color: provider.selectedRayon == null
                                        ? Colors.grey.shade700
                                        : AppColors.primary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                if (showSearchAndBody)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onSubmitted: (value) => _handleScanOrSearch(value, fromTyping: false),
                            onChanged: _onSearchChanged,
                            textInputAction: TextInputAction.search,
                            autofocus: widget.isQuickMode,
                            decoration: InputDecoration(
                              labelText: 'Rechercher / Scanner', hintText: 'CIP, Nom ou Scan...', prefixIcon: const Icon(Icons.qr_code_scanner, size: 20),
                              isDense: true, border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))), contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                              suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _showSearchResults = false;
                                  _filteredProducts = [];
                                });
                                _searchFocusNode.requestFocus();
                              }) : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const Divider(height: 1, thickness: 1),

                if (showSearchAndBody)
                  Expanded(
                    child: Stack(
                      children: [
                        (provider.isLoading && provider.products.isEmpty) ? const Center(child: CircularProgressIndicator()) : (provider.products.isEmpty || provider.currentProduct == null) ? Center(child: Text(provider.activeFilter.isActive ? 'Aucun produit dans cet intervalle.' : 'Aucun produit. Commencez par scanner.'))
                            : widget.isQuickMode
                            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey.shade300), const SizedBox(height: 16), const Text('Mode Saisie Rapide Activé', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 8), const Text('Scannez un produit pour saisir sa quantité', style: TextStyle(color: Colors.grey))]))
                            : buildProductView(provider),
                        if (_showSearchResults)
                          Container(
                            color: AppColors.background.withOpacity(0.98),
                            child: _filteredProducts.isEmpty
                                ? Center(child: Text("Aucun produit trouvé"))
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
                                        Text('CIP: ${product.produitCip} / Stock Théo: ${product.quantiteInitiale}'),
                                        Text('Prix Vente: ${product.produitPrixUni.toStringAsFixed(0)} F', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                    onTap: () => _selectProduct(product),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  const Expanded(child: Center(child: Text("Veuillez sélectionner un emplacement pour commencer.", style: TextStyle(color: Colors.grey, fontSize: 16)))),

                if (showSearchAndBody && !widget.isQuickMode && !_isSearching) NumericKeyboard(onKeyPressed: _onKeyPressed),
              ],
            );
          },
        ),
      ),
    );
  }

  // ... (Widgets _buildNotificationArea et buildProductView inchangés) ...
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
                        decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade300)),
                        child: Text(
                          'Filtre: $filterDetails',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: badgeFontSize, color: Colors.blue.shade900),
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