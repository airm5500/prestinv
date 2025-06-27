// lib/screens/inventory_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';
import 'package:prestinv/screens/recap_screen.dart';
import 'package:prestinv/screens/variance_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl);

    Future.microtask(() {
      final provider = Provider.of<EntryProvider>(context, listen: false);
      provider.reset();
      provider.fetchRayons(_apiService, widget.inventoryId);
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _onKeyPressed(String value) {
    if (value == 'DEL') {
      if (_quantityController.text.isNotEmpty) {
        _quantityController.text = _quantityController.text.substring(0, _quantityController.text.length - 1);
      }
    } else if (value == 'OK') {
      _validateAndNext();
    } else {
      _quantityController.text += value;
    }
  }

  // MODIFICATION: Centralisation de la logique d'envoi
  Future<void> _sendDataToServer() async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final unsyncedProducts = provider.products.where((p) => !p.isSynced).toList();

    if (unsyncedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucune nouvelle saisie à envoyer.'),
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
        // Le provider n'est pas utilisé pour la mise à jour de l'état ici
        // car la vue ne dépend pas directement de 'isSynced'
        product.isSynced = true;
        successCount++;
      }
    }

    progressNotifier.value = '$successCount sur ${unsyncedProducts.length} envoyé(s).';
    await Future.delayed(const Duration(seconds: 2));
    Navigator.of(context).pop();
  }


  void _validateAndNext() {
    final provider = Provider.of<EntryProvider>(context, listen: false);

    if (_quantityController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez renseigner une valeur numérique supérieure ou égale à 0.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    provider.updateQuantity(_quantityController.text);

    bool isLastProduct = provider.currentProductIndex >= provider.totalProducts - 1;

    if (isLastProduct) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fin de l\'emplacement'),
          content: const Text('Vous avez traité le dernier produit. Voulez-vous envoyer les données au serveur ?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Non'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            TextButton(
              child: const Text('Oui'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _sendDataToServer(); // Appel de la nouvelle méthode centralisée
              },
            ),
          ],
        ),
      );
    } else {
      if (provider.currentProduct!.quantiteInitiale < 0) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Stock Négatif'),
            content: const Text('La valeur du stock initial est négative. Voulez-vous continuer?'),
            actions: <Widget>[
              TextButton(child: const Text('Non'), onPressed: () => Navigator.of(ctx).pop()),
              TextButton(child: const Text('Oui'), onPressed: () {
                Navigator.of(ctx).pop();
                provider.nextProduct();
              }),
            ],
          ),
        );
      } else {
        provider.nextProduct();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Le build ne change que l'appel onPressed du bouton d'envoi
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saisie Inventaire'),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: 'Envoyer les données',
            onPressed: _sendDataToServer, // Appel de la nouvelle méthode
          ),
          Consumer<EntryProvider>(
            builder: (context, provider, child) {
              if (provider.selectedRayon == null) return const SizedBox.shrink();
              return Row(
                // ... le reste de l'appbar ne change pas
                children: [
                  IconButton(
                    icon: const Icon(Icons.list_alt),
                    tooltip: 'Récapitulatif',
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RecapScreen(
                          inventoryId: widget.inventoryId,
                          rayonId: provider.selectedRayon!.id,
                          rayonName: provider.selectedRayon!.libelle,
                        ),
                      ));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_note),
                    tooltip: 'Correction écarts',
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => VarianceScreen(
                          inventoryId: widget.inventoryId,
                          rayonId: provider.selectedRayon!.id,
                          rayonName: provider.selectedRayon!.libelle,
                        ),
                      ));
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<EntryProvider>(
        builder: (context, provider, child) {
          // ... Le reste du body ne change pas ...
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
              _quantityController.clear();
              _quantityFocusNode.requestFocus();
            });
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButton<Rayon>(
                  isExpanded: true,
                  hint: const Text('Sélectionner un emplacement'),
                  value: provider.selectedRayon,
                  onChanged: (Rayon? newValue) {
                    if (newValue != null) {
                      provider.fetchProducts(_apiService, widget.inventoryId, newValue.id);
                    }
                  },
                  items: provider.rayons.map<DropdownMenuItem<Rayon>>((Rayon rayon) {
                    return DropdownMenuItem<Rayon>(value: rayon, child: Text(rayon.displayName));
                  }).toList(),
                ),
              ),
              const Divider(),
              Expanded(
                child: provider.isLoading && provider.products.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : provider.products.isEmpty
                    ? const Center(child: Text('Aucun produit. Sélectionnez un emplacement.'))
                    : buildProductView(provider),
              ),
              NumericKeyboard(onKeyPressed: _onKeyPressed),
            ],
          );
        },
      ),
    );
  }

  Widget buildProductView(EntryProvider provider) {
    // ... cette méthode ne change pas
    final product = provider.currentProduct!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${provider.currentProductIndex + 1} / ${provider.totalProducts}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Text(
            product.produitName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Text('CIP: ${product.produitCip}'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Prix Achat: ${product.produitPrixAchat} F'),
              Text('Prix Vente: ${product.produitPrixUni} F'),
            ],
          ),
          const SizedBox(height: 10),
          Consumer<AppConfig>(
            builder: (context, appConfig, child) {
              if (appConfig.showTheoreticalStock) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Text(
                    'Stock Théorique: ${product.quantiteInitiale}',
                    style: TextStyle(color: product.quantiteInitiale < 0 ? Colors.red : Colors.black),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          TextField(
            controller: _quantityController,
            focusNode: _quantityFocusNode,
            decoration: const InputDecoration(
              labelText: 'Quantité Comptée (Stock Rayon)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.none,
            readOnly: true,
            textAlign: TextAlign.center,
            cursorColor: Colors.blue,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(onPressed: provider.previousProduct, child: const Icon(Icons.chevron_left)),
              ElevatedButton(onPressed: provider.nextProduct, child: const Icon(Icons.chevron_right)),
            ],
          )
        ],
      ),
    );
  }
}