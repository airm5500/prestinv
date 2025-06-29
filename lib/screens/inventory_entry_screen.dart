// lib/screens/inventory_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
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
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
      baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );

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
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucune nouvelle saisie à envoyer.'),
        backgroundColor: Colors.orange,
      ));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez saisir une quantité.'), backgroundColor: Colors.orange));
      return;
    }

    final quantity = int.tryParse(_quantityController.text) ?? 0;

    Future<void> proceedToNext() async {
      await provider.updateQuantity(quantity.toString());
      bool isLastProduct = provider.currentProductIndex >= provider.totalProducts - 1;

      if (isLastProduct && provider.totalProducts > 0) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Fin de l\'emplacement'),
            content: const Text('Vous avez traité le dernier produit. Voulez-vous envoyer les données au serveur ?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Non')),
              TextButton(onPressed: () {
                Navigator.of(ctx).pop();
                _sendDataToServer();
              }, child: const Text('Oui, envoyer')),
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

    if (sendAndLeave == true) {
      await _sendDataToServer();
      return true;
    } else {
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saisie Inventaire'),
          actions: [
            // CORRECTION : Le bouton "premier article" a été retiré d'ici.
            IconButton(
              // CORRECTION : Couleur ré-appliquée manuellement
                icon: const Icon(Icons.send, color: Colors.cyanAccent),
                tooltip: 'Envoyer les données',
                onPressed: _sendDataToServer
            ),
            Consumer<EntryProvider>(
              builder: (context, provider, child) {
                if (provider.selectedRayon == null) return const SizedBox.shrink();
                return Row(
                  children: [
                    IconButton(
                      // CORRECTION : Couleur ré-appliquée manuellement
                        icon: const Icon(Icons.list_alt_outlined, color: Colors.lightGreenAccent),
                        tooltip: 'Récapitulatif',
                        onPressed: () {
                          if (!mounted) return;
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecapScreen(inventoryId: widget.inventoryId, rayonId: provider.selectedRayon!.id, rayonName: provider.selectedRayon!.libelle)));
                        }),
                    IconButton(
                      // CORRECTION : Couleur ré-appliquée manuellement
                        icon: const Icon(Icons.edit_note_outlined, color: Colors.orangeAccent),
                        tooltip: 'Correction écarts',
                        onPressed: () {
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
                _quantityController.clear();
                _quantityFocusNode.requestFocus();
              });
            }

            if (provider.hasPendingSession) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showPendingDataDialog();
              });
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Rayon>(
                      isExpanded: true,
                      hint: const Text('Sélectionner un emplacement'),
                      value: provider.selectedRayon,
                      style: const TextStyle(color: Color(0xFF002D42), fontSize: 16, fontWeight: FontWeight.bold),
                      onChanged: (Rayon? newValue) {
                        if (newValue != null) {
                          provider.fetchProducts(_apiService, widget.inventoryId, newValue.id);
                        }
                      },
                      items: provider.rayons.map<DropdownMenuItem<Rayon>>((Rayon rayon) => DropdownMenuItem<Rayon>(value: rayon, child: Text(rayon.displayName))).toList(),
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                Expanded(
                  child: (provider.isLoading && provider.products.isEmpty)
                      ? const Center(child: CircularProgressIndicator())
                      : (provider.products.isEmpty || provider.currentProduct == null)
                      ? const Center(child: Text('Aucun produit. Sélectionnez un emplacement.'))
                      : buildProductView(provider),
                ),
                NumericKeyboard(onKeyPressed: _onKeyPressed),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget buildProductView(EntryProvider provider) {
    final Product product = provider.currentProduct!;
    const boldBlueStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue);
    final textFieldBorderColor = Colors.deepPurple; // Couleur pour le champ et le bouton

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('${provider.currentProductIndex + 1} / ${provider.totalProducts}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),

          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Text(
              product.produitName,
              style: boldBlueStyle.copyWith(fontSize: 20),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),

          Text('CIP: ${product.produitCip}', style: boldBlueStyle),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Prix Achat: ${product.produitPrixAchat} F', style: const TextStyle(fontSize: 18, color: Colors.orange, fontWeight: FontWeight.w500)),
                Text('Prix Vente: ${product.produitPrixUni} F', style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Consumer<AppConfig>(
            builder: (context, appConfig, child) {
              return Visibility(
                visible: appConfig.showTheoreticalStock,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Stock Théorique: ${product.quantiteInitiale}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: product.quantiteInitiale < 0 ? Colors.red.shade700 : const Color(0xFF1B5E20)),
                  ),
                ),
              );
            },
          ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: OutlinedButton( // Nouveau style de bouton
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(16),
                    side: BorderSide(color: textFieldBorderColor, width: 2),
                  ),
                  onPressed: provider.previousProduct,
                  child: Icon(Icons.chevron_left, size: 32, color: textFieldBorderColor),
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                child: TextField(
                  controller: _quantityController,
                  focusNode: _quantityFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Quantité Comptée',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: textFieldBorderColor, width: 2),
                    ),
                  ),
                  keyboardType: TextInputType.none,
                  readOnly: true,
                  textAlign: TextAlign.center,
                  cursorColor: textFieldBorderColor,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textFieldBorderColor),
                ),
              ),
              const SizedBox(width: 72),
            ],
          ),
          const SizedBox(height: 20),

          // CORRECTION : Bouton déplacé ici depuis l'AppBar
          TextButton.icon(
            onPressed: () => provider.goToFirstProduct(),
            icon: const Icon(Icons.first_page),
            label: const Text('Retour au premier article'),
          ),
        ],
      ),
    );
  }
}