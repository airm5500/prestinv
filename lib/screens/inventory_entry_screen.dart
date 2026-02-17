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
import 'package:prestinv/screens/cumul_history_screen.dart';

import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class InventoryEntryScreen extends StatefulWidget {
  final String inventoryId;
  final bool isQuickMode;
  const InventoryEntryScreen(
      {super.key, required this.inventoryId, this.isQuickMode = false});
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

  Timer? _debounceTimer;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;
  List<Product> _filteredProducts = [];
  bool _showSearchResults = false;

  bool _isManualAccess = false;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
        baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
        sessionCookie: authProvider.sessionCookie);

    _searchFocusNode.addListener(() {
      setState(() {
        _isSearching = _searchFocusNode.hasFocus;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = Provider.of<EntryProvider>(context, listen: false);
        provider.reset();
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
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _exportProductsToCsv(
      List<Product> products, String suffixName) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune donnée à exporter.')));
      return;
    }

    final StringBuffer csvContent = StringBuffer();
    csvContent.writeln('code_cip;quantite');

    for (final p in products) {
      csvContent.writeln('${p.produitCip};${p.quantiteSaisie}');
    }

    final timestamp = DateFormat('ddMMyyyy_HHmm').format(DateTime.now());
    final cleanSuffix = suffixName.replaceAll(RegExp(r'[^\w\s]+'), '');
    final fileName = 'Export_${cleanSuffix}_$timestamp.csv';

    try {
      if (Platform.isAndroid) {
        final Directory downloadDir = Directory('/storage/emulated/0/Download');
        if (!await downloadDir.exists()) {
          try {
            await downloadDir.create(recursive: true);
          } catch (e) {
            print("Err create dir: $e");
          }
        }

        final String filePath = '${downloadDir.path}/$fileName';
        final File file = File(filePath);

        bool saveSuccess = false;

        try {
          await file.writeAsString(csvContent.toString());
          saveSuccess = true;
        } catch (e) {
          var status = await Permission.storage.status;
          if (!status.isGranted) status = await Permission.storage.request();

          if (status.isGranted) {
            try {
              await file.writeAsString(csvContent.toString());
              saveSuccess = true;
            } catch (e2) {
              print("Echec permissions: $e2");
            }
          }
        }

        if (saveSuccess) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ Export réussi dans Téléchargements :\n$fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
                label: 'Partager',
                textColor: Colors.white,
                onPressed: () {
                  Share.shareXFiles([XFile(filePath)], text: 'Export CSV');
                }),
          ));
          return;
        }
      }

      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvContent.toString());

      if (!mounted) return;
      Share.shareXFiles([XFile(filePath)], text: 'Export CSV $suffixName');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur export: $e'), backgroundColor: Colors.red));
    }
  }

  void _navigateToRecap() async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Text("Chargement du récap..."),
        ])));
    try {
      final provider = Provider.of<EntryProvider>(context, listen: false);
      String targetRayonId = provider.selectedRayon?.id ?? "";
      String targetRayonName = provider.selectedRayon?.libelle ?? "Global";
      List<Product> products;
      if (targetRayonId.isNotEmpty) {
        products = await _apiService.fetchProducts(
            widget.inventoryId, targetRayonId);
      } else {
        products = provider.allProducts;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecapScreen(
              inventoryId: widget.inventoryId,
              rayonId: targetRayonId,
              rayonName: targetRayonName,
              preloadedProducts: products)));
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
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
    if (appConfig.sendMode == SendMode.collect &&
        appConfig.sendReminderMinutes > 0) {
      _sendReminderTimer =
          Timer(Duration(minutes: appConfig.sendReminderMinutes), () {
            if (provider.hasUnsyncedData && mounted) {
              _showSendReminderNotification();
            }
          });
    }
  }

  void _showSendReminderNotification() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Rappel : Vous avez des données non envoyées !'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 5)));
  }

  void _onKeyPressed(String value) {
    if (value == 'DEL') {
      if (_quantityController.text.isNotEmpty) {
        _quantityController.text = _quantityController.text
            .substring(0, _quantityController.text.length - 1);
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
          content: Text('Aucune donnée en attente d\'envoi.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2)));
      return;
    }
    final ValueNotifier<String> progressNotifier =
    ValueNotifier('Préparation...');
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

    if (_quantityController.text.isEmpty) {
      _showNotification('Veuillez saisir une quantité.', Colors.orange);
      return;
    }

    final inputQuantity = int.tryParse(_quantityController.text) ?? 0;
    int finalQuantity = inputQuantity;

    if (appConfig.isCumulEnabled &&
        provider.currentProduct != null &&
        _isManualAccess) {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => const Center(child: CircularProgressIndicator()));
      try {
        int? existingQty = await provider.checkExistingQuantityForProduct(
            _apiService,
            provider.currentProduct!.produitCip,
            widget.inventoryId,
            appConfig.sendMode);
        Navigator.pop(context);

        if (existingQty != null) {
          bool? shouldCumulate = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text("⚠️ Déjà compté"),
                backgroundColor: const Color(0xFFFFF3CD),
                content: _buildCumulContent(provider.currentProduct!.produitName,
                    existingQty, inputQuantity),
                actions: [
                  TextButton(
                      child: const Text("NON (Écraser)",
                          style: TextStyle(color: Colors.red)),
                      onPressed: () => Navigator.of(context).pop(false)),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white),
                      child: const Text("OUI (Additionner)"),
                      onPressed: () => Navigator.of(context).pop(true)),
                ],
              );
            },
          );

          if (shouldCumulate == true) {
            finalQuantity = existingQty + inputQuantity;
            provider.addCumulLog(
                provider.currentProduct!, existingQty, inputQuantity);
          }
        }
      } catch (e) {
        Navigator.pop(context);
      }
    }

    Future<void> proceedToNext(int quantityToSave) async {
      await provider.updateQuantity(quantityToSave.toString());
      _resetSendReminderTimer();
      if (appConfig.sendMode == SendMode.direct) {
        try {
          await _apiService.updateProductQuantity(
              provider.currentProduct!.id, quantityToSave);
          // CORRECTION : On marque le produit comme synchronisé immédiatement
          await provider.markAsSynced(provider.currentProduct!.id);

          if (mounted) _showNotification('Saisie envoyée !', Colors.green);
        } catch (e) {
          if (mounted) _showNotification('Erreur réseau.', Colors.red);
        }
      }

      bool isLastProduct =
          provider.currentProductIndex >= provider.totalProducts - 1;
      if (isLastProduct && provider.totalProducts > 0) {
        _sendReminderTimer?.cancel();
        if (!mounted) return;
        bool isFilterActive = provider.activeFilter.isActive;
        showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                title: Text(isFilterActive
                    ? 'Fin du filtre'
                    : 'Fin de l\'emplacement'),
                content: const Text('Envoyer les données ?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Non')),
                  TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _sendDataToServer();
                      },
                      child: const Text('Oui'))
                ]));
      } else {
        provider.nextProduct();
        setState(() {
          _isManualAccess = false;
        });
      }
    }

    if (finalQuantity > appConfig.largeValueThreshold) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
              title: const Text('Alerte Grande Quantité'),
              content: Text('Total : $finalQuantity. Confirmer ?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Non')),
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Oui'))
              ]));
      if (confirmed == true) await proceedToNext(finalQuantity);
    } else {
      await proceedToNext(finalQuantity);
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
        content: const Text(
            'Des données n\'ont pas été envoyées. Voulez-vous les envoyer avant de quitter ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Envoyer et Quitter')),
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
        content: const Text(
            'Des saisies non envoyées de la dernière session ont été trouvées. Voulez-vous les envoyer maintenant ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Non')),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _sendDataToServer();
              },
              child: const Text('Oui, envoyer')),
        ],
      ),
    );
  }

  void _onLocationChanged(Rayon? newValue) async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (newValue?.id != provider.selectedRayon?.id) {
      if (provider.hasUnsyncedData) {
        final bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Changer d\'emplacement ?'),
            content: const Text(
                'Les données actuelles seront envoyées au serveur avant de changer.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Annuler')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Continuer')),
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
        if (newValue == null) {
          provider.reset();
          _resetSendReminderTimer();
          if (mounted) _searchFocusNode.requestFocus();
        } else {
          provider
              .fetchProducts(_apiService, widget.inventoryId, newValue.id)
              .then((_) {
            provider.loadCumulLogs(newValue.id);
            _resetSendReminderTimer();
            if (mounted) _searchFocusNode.requestFocus();
          });
        }
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (query.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _filteredProducts = [];
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _handleScanOrSearch(query, fromTyping: true);
    });
  }

  Future<void> _handleScanOrSearch(String query,
      {bool fromTyping = false}) async {
    if (query.isEmpty) return;
    _debounceTimer?.cancel();
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (!fromTyping) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recherche...'), duration: Duration(milliseconds: 500)));
    }

    try {
      final onlineMatches = await provider.searchProductOnline(
          _apiService, widget.inventoryId, query);
      if (!mounted) return;

      if (onlineMatches.isNotEmpty) {
        setState(() {
          _filteredProducts = onlineMatches;
          _showSearchResults = true;
        });
        if (!fromTyping) {
          if (onlineMatches.length == 1) {
            _openQuickEntryDialog(onlineMatches.first);
            _searchController.clear();
            setState(() {
              _showSearchResults = false;
            });
            FocusScope.of(context).unfocus();
          } else {
            FocusScope.of(context).unfocus();
          }
        }
      } else {
        if (!fromTyping) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Produit introuvable.'),
              backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted && !fromTyping) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _openQuickEntryDialog(Product product) {
    final quickQtyController = TextEditingController();
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final provider = Provider.of<EntryProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: _buildQuickDialogTitle(product, appConfig),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: quickQtyController,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent),
                    decoration: const InputDecoration(
                        labelText: 'Quantité', border: OutlineInputBorder()),
                    keyboardType: TextInputType.none,
                    readOnly: true,
                    autofocus: true,
                    showCursor: true),
                const SizedBox(height: 16),
                SizedBox(
                  height: 280,
                  child: NumericKeyboard(
                    onKeyPressed: (key) async {
                      if (key == 'OK') {
                        if (quickQtyController.text.isEmpty) return;
                        int inputQty =
                            int.tryParse(quickQtyController.text) ?? 0;
                        int finalQty = inputQty;

                        if (appConfig.isCumulEnabled) {
                          showDialog(
                              context: ctx,
                              barrierDismissible: false,
                              builder: (c) => const Center(
                                  child: CircularProgressIndicator()));
                          try {
                            int? existingQty = await provider
                                .checkExistingQuantityForProduct(
                                _apiService,
                                product.produitCip,
                                widget.inventoryId,
                                appConfig.sendMode);
                            Navigator.pop(ctx);

                            if (existingQty != null) {
                              bool? shouldCumulate = await showDialog<bool>(
                                context: ctx,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text("⚠️ Déjà compté"),
                                    backgroundColor: const Color(0xFFFFF3CD),
                                    content: _buildCumulContent(
                                        product.produitName,
                                        existingQty,
                                        inputQty),
                                    actions: [
                                      TextButton(
                                          child: const Text("NON (Écraser)",
                                              style:
                                              TextStyle(color: Colors.red)),
                                          onPressed: () =>
                                              Navigator.of(context).pop(false)),
                                      ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue,
                                              foregroundColor: Colors.white),
                                          child:
                                          const Text("OUI (Additionner)"),
                                          onPressed: () =>
                                              Navigator.of(context).pop(true)),
                                    ],
                                  );
                                },
                              );
                              if (shouldCumulate == true) {
                                finalQty = existingQty + inputQty;
                                provider.addCumulLog(
                                    product, existingQty, inputQty);
                              }
                            }
                          } catch (e) {
                            Navigator.pop(ctx);
                          }
                        }

                        _saveScannedQuantity(product, finalQty);
                        Navigator.of(ctx).pop();
                        _searchController.clear();
                        setState(() {
                          _showSearchResults = false;
                          _filteredProducts = [];
                        });
                        if (widget.isQuickMode) {
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) _searchFocusNode.requestFocus();
                          });
                        } else {
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) {
                              FocusScope.of(context).unfocus();
                              _quantityFocusNode.requestFocus();
                            }
                          });
                        }
                      } else if (key == 'DEL') {
                        if (quickQtyController.text.isNotEmpty) {
                          quickQtyController.text = quickQtyController.text
                              .substring(
                              0, quickQtyController.text.length - 1);
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
                child:
                const Text('Annuler', style: TextStyle(color: Colors.red))),
          ],
        );
      },
    );
  }

  Widget _buildCumulContent(String productName, int oldQty, int newQty) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Produit : $productName"),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Déjà en base :"),
          Text("$oldQty",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Votre saisie :"),
          Text("$newQty",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
        ]),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("TOTAL :",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text("${oldQty + newQty}",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue))
        ]),
        const SizedBox(height: 15),
        const Text("Voulez-vous ADDITIONNER ?",
            style: TextStyle(fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _buildQuickDialogTitle(Product product, AppConfig appConfig) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Saisie Rapide',
            style: TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(product.produitName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text('CIP: ${product.produitCip}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        if (product.locationLabel != null)
          Text('(${product.locationLabel})',
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.blueGrey,
                  fontStyle: FontStyle.italic)),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('PA: ${product.produitPrixAchat.toStringAsFixed(0)} F',
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold)),
          Text('PV: ${product.produitPrixUni.toStringAsFixed(0)} F',
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold))
        ]),
        const SizedBox(height: 4),
        Visibility(
            visible: appConfig.showTheoreticalStock,
            child: Text('Stock Théo: ${product.quantiteInitiale}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: product.quantiteInitiale < 0
                        ? Colors.red
                        : Colors.green))),
      ],
    );
  }

  void _saveScannedQuantity(Product product, int quantity) async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    product.quantiteSaisie = quantity;
    await provider.updateSpecificProduct(product);
    if (mounted) {
      _showNotification(
          'Saisie enregistrée : ${product.produitName}', Colors.green);
    }
    if (appConfig.sendMode == SendMode.direct) {
      try {
        await _apiService.updateProductQuantity(product.id, quantity);
        await provider.markAsSynced(product.id);
      } catch (e) {
        /* ... */
      }
    }
  }

  void _selectProduct(Product product) {
    _openQuickEntryDialog(product);
  }

  void _showLocationSelector(BuildContext context, EntryProvider provider) {
    provider.loadRayonStatuses(_apiService, widget.inventoryId);

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
                      decoration: const InputDecoration(
                          labelText: 'Rechercher un rayon',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder()),
                      onChanged: (value) {
                        setState(() {
                          filteredRayons = provider.rayons
                              .where((r) => r.displayName
                              .toLowerCase()
                              .contains(value.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Consumer<EntryProvider>(
                          builder: (context, entryProvider, child) {
                            return filteredRayons.isEmpty
                                ? const Center(child: Text("Aucun emplacement trouvé"))
                                : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredRayons.length,
                              itemBuilder: (ctx, index) {
                                final rayon = filteredRayons[index];
                                final isSelected = rayon.id ==
                                    entryProvider.selectedRayon?.id;

                                final int status =
                                    entryProvider.rayonStatuses[rayon.id] ?? 0;

                                Color bgColor;
                                IconData icon;
                                Color iconColor;

                                if (status == 2) {
                                  bgColor = Colors.green.shade100;
                                  icon = Icons.check_circle;
                                  iconColor = Colors.green;
                                } else if (status == 1) {
                                  bgColor = Colors.orange.shade100;
                                  icon = Icons.hourglass_bottom;
                                  iconColor = Colors.orange.shade800;
                                } else {
                                  bgColor = isSelected
                                      ? AppColors.primary.withOpacity(0.1)
                                      : Colors.transparent;
                                  icon = Icons.location_on;
                                  iconColor = isSelected
                                      ? AppColors.primary
                                      : Colors.grey;
                                }

                                return Container(
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    border: Border(
                                        bottom: BorderSide(
                                            color: Colors.grey.shade200)),
                                  ),
                                  child: ListTile(
                                    leading: Icon(icon, color: iconColor),
                                    title: Text(rayon.libelle,
                                        style: TextStyle(
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: Colors.black)),
                                    subtitle: Text(rayon.code,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600])),
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      _onLocationChanged(rayon);
                                    },
                                  ),
                                );
                              },
                            );
                          }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Annuler'))
              ],
            );
          },
        );
      },
    );
  }

  void _showFilterDialog(BuildContext context, EntryProvider provider) {
    final currentFilter = provider.activeFilter;
    final totalProducts = provider.totalProductsInRayon;
    final _fromNumController = TextEditingController(
        text: currentFilter.type == FilterType.numeric
            ? currentFilter.from
            : '');
    final _toNumController = TextEditingController(
        text:
        currentFilter.type == FilterType.numeric ? currentFilter.to : '');
    final _fromAlphaController = TextEditingController(
        text: currentFilter.type == FilterType.alphabetic
            ? currentFilter.from
            : '');
    final _toAlphaController = TextEditingController(
        text: currentFilter.type == FilterType.alphabetic
            ? currentFilter.to
            : '');
    FilterType selectedType = currentFilter.type;

    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setPopupState) {
            return AlertDialog(
                title: const Text('Appliquer un filtre'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      RadioListTile<FilterType>(
                          title: const Text('Intervalle numérique'),
                          value: FilterType.numeric,
                          groupValue: selectedType,
                          onChanged: (val) =>
                              setPopupState(() => selectedType = val!)),
                      Row(children: [
                        Expanded(
                            child: TextFormField(
                                controller: _fromNumController,
                                decoration: const InputDecoration(
                                    labelText: 'De (N°)',
                                    border: OutlineInputBorder()),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                enabled: selectedType == FilterType.numeric)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextFormField(
                                controller: _toNumController,
                                decoration: const InputDecoration(
                                    labelText: 'À (N°)',
                                    border: OutlineInputBorder()),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                enabled: selectedType == FilterType.numeric))
                      ]),
                      const SizedBox(height: 16),
                      RadioListTile<FilterType>(
                          title: const Text('Intervalle alphabétique'),
                          value: FilterType.alphabetic,
                          groupValue: selectedType,
                          onChanged: (val) =>
                              setPopupState(() => selectedType = val!)),
                      Row(children: [
                        Expanded(
                            child: TextFormField(
                                controller: _fromAlphaController,
                                decoration: const InputDecoration(
                                    labelText: 'De (Texte)',
                                    border: OutlineInputBorder()),
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(3)
                                ],
                                enabled: selectedType == FilterType.alphabetic)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextFormField(
                                controller: _toAlphaController,
                                decoration: const InputDecoration(
                                    labelText: 'À (Texte)',
                                    border: OutlineInputBorder()),
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(3)
                                ],
                                enabled: selectedType == FilterType.alphabetic))
                      ])
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Annuler')),
                  ElevatedButton(
                      child: const Text('Appliquer'),
                      onPressed: () {
                        ProductFilter newFilter = ProductFilter();
                        if (selectedType == FilterType.numeric) {
                          int from =
                              int.tryParse(_fromNumController.text) ?? 0;
                          int to = int.tryParse(_toNumController.text) ?? 0;
                          if (from <= 0) from = 1;
                          if (to > totalProducts) to = totalProducts;
                          if (to == 0) to = totalProducts;
                          if (from > to) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Erreur : "De" doit être inférieur à "À"'),
                                    backgroundColor: Colors.red));
                            return;
                          }
                          newFilter = ProductFilter(
                              type: FilterType.numeric,
                              from: from.toString(),
                              to: to.toString());
                        } else if (selectedType == FilterType.alphabetic) {
                          String from =
                          _fromAlphaController.text.toUpperCase();
                          String to = _toAlphaController.text.toUpperCase();
                          if (from.isEmpty || to.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Erreur : Les champs ne peuvent pas être vides'),
                                    backgroundColor: Colors.red));
                            return;
                          }
                          if (from.compareTo(to) > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Erreur : "De" doit être alphabétiquement avant "À"'),
                                    backgroundColor: Colors.red));
                            return;
                          }
                          newFilter = ProductFilter(
                              type: FilterType.alphabetic,
                              from: from,
                              to: to);
                        }
                        provider.applyFilter(newFilter);
                        Navigator.of(ctx).pop();
                      })
                ]);
          });
        });
  }

  void _showJumpDialog(EntryProvider provider) {
    final TextEditingController jumpController = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
              title: const Text('Aller au produit'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    "Entrez une position (ex: 45), un nom ou un code :"),
                const SizedBox(height: 10),
                TextField(
                    controller: jumpController,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Position, Nom ou Code',
                        prefixIcon: Icon(Icons.directions)),
                    onSubmitted: (_) =>
                        _performJump(ctx, provider, jumpController.text))
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Annuler')),
                ElevatedButton(
                    onPressed: () =>
                        _performJump(ctx, provider, jumpController.text),
                    child: const Text('Aller'))
              ]);
        });
  }

  void _performJump(BuildContext dialogContext, EntryProvider provider,
      String input) {
    if (input.isEmpty) return;
    Navigator.of(dialogContext).pop();
    final products = provider.products;
    int targetIndex = -1;
    if (RegExp(r'^\d+$').hasMatch(input)) {
      int pos = int.parse(input);
      if (pos > 0 && pos <= products.length) {
        targetIndex = pos - 1;
      }
    }
    if (targetIndex == -1) {
      targetIndex = products.indexWhere((p) =>
      p.produitCip.contains(input) ||
          p.produitName.toLowerCase().contains(input.toLowerCase()));
    }
    if (targetIndex != -1) {
      setState(() {
        _isManualAccess = true;
      });
      final targetProduct = products[targetIndex];
      provider.jumpToProduct(targetProduct);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Position ${targetIndex + 1} : ${targetProduct.produitName}'),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun produit trouvé.'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
            title: Text(widget.isQuickMode
                ? 'Saisie Rapide (Scan)'
                : 'Saisie Inventaire'),
            actions: [
              IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Envoyer les données',
                  onPressed: _sendDataToServer),
              IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'Historique des cumuls',
                  onPressed: () {
                    if (!mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CumulHistoryScreen()));
                  }),
              if (widget.isQuickMode)
                Consumer<EntryProvider>(
                  builder: (context, provider, child) => IconButton(
                    icon: const Icon(Icons.file_download),
                    tooltip: 'Exporter la session (CSV)',
                    onPressed: () => _exportProductsToCsv(
                        provider.allProducts, "Saisie_Rapide"),
                  ),
                ),
              Consumer<EntryProvider>(builder: (context, provider, child) {
                if (provider.selectedRayon == null) return const SizedBox.shrink();
                return Row(children: [
                  IconButton(
                      icon: const Icon(Icons.list_alt_outlined),
                      tooltip: 'Récapitulatif',
                      onPressed: () {
                        if (!mounted) return;
                        _navigateToRecap();
                      }),
                  IconButton(
                      icon: const Icon(Icons.edit_note_outlined),
                      tooltip: 'Correction écarts',
                      onPressed: () {
                        if (!mounted) return;
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => VarianceScreen(
                                inventoryId: widget.inventoryId,
                                rayonId: provider.selectedRayon!.id,
                                rayonName: provider.selectedRayon!.libelle)));
                      })
                ]);
              })
            ]),
        body: Consumer<EntryProvider>(
          builder: (context, provider, child) {
            bool showLocationSelector = !widget.isQuickMode;
            bool showSearchAndBody =
                widget.isQuickMode || provider.selectedRayon != null;
            if (provider.error != null) {
              return Center(
                  child: Text(provider.error!,
                      style: const TextStyle(color: Colors.red)));
            }
            if (provider.isLoading &&
                provider.rayons.isEmpty &&
                !widget.isQuickMode) {
              return const Center(child: CircularProgressIndicator());
            }

            final currentProduct = provider.currentProduct;
            if (!widget.isQuickMode &&
                currentProduct != null &&
                currentProduct.id != _lastDisplayedProductId) {
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
                if (showLocationSelector)
                  Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: Colors.grey.shade300)),
                      child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                              borderRadius: BorderRadius.circular(8.0),
                              onTap: () =>
                                  _showLocationSelector(context, provider),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12.0, vertical: 16.0),
                                  child: Row(children: [
                                    const Icon(Icons.touch_app_outlined,
                                        color: AppColors.primary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(
                                            provider.selectedRayon?.libelle ??
                                                'Sélectionner un emplacement',
                                            style: TextStyle(
                                                color: provider.selectedRayon ==
                                                    null
                                                    ? Colors.grey.shade700
                                                    : AppColors.primary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis)),
                                    if (provider.selectedRayon != null)
                                      IconButton(
                                        icon: const Icon(Icons.file_download,
                                            color: Colors.blue),
                                        tooltip: "Exporter le rayon (CSV)",
                                        onPressed: () => _exportProductsToCsv(
                                            provider.allProducts,
                                            "Rayon_${provider.selectedRayon!.libelle}"),
                                      ),
                                    if (provider.selectedRayon == null)
                                      const Icon(Icons.arrow_drop_down,
                                          color: AppColors.primary)
                                  ]))))),
                if (showSearchAndBody)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                      child: Row(children: [
                        Expanded(
                            child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onSubmitted: (value) => _handleScanOrSearch(
                                    value,
                                    fromTyping: false),
                                onChanged: _onSearchChanged,
                                textInputAction: TextInputAction.search,
                                autofocus: widget.isQuickMode,
                                decoration: InputDecoration(
                                    labelText: 'Rechercher / Scanner',
                                    hintText: 'CIP, Nom ou Scan...',
                                    prefixIcon: const Icon(
                                        Icons.qr_code_scanner,
                                        size: 20),
                                    isDense: true,
                                    border: const OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(8))),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12.0, vertical: 10.0),
                                    suffixIcon:
                                    _searchController.text.isNotEmpty
                                        ? IconButton(
                                        icon: const Icon(Icons.clear,
                                            size: 20),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _showSearchResults = false;
                                            _filteredProducts = [];
                                          });
                                          _searchFocusNode
                                              .requestFocus();
                                        })
                                        : null))),
                        if (!widget.isQuickMode) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(12),
                                  minimumSize: Size.zero),
                              onPressed: provider.selectedRayon == null
                                  ? null
                                  : () => _showFilterDialog(context, provider),
                              child: const Icon(Icons.filter_alt_outlined)),
                          const SizedBox(width: 8),
                          OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(12),
                                  minimumSize: Size.zero),
                              onPressed: (provider.selectedRayon == null ||
                                  !provider.activeFilter.isActive)
                                  ? null
                                  : () => provider.applyFilter(
                                  ProductFilter(type: FilterType.none)),
                              child: const Icon(Icons.delete_outline))
                        ]
                      ])),
                const Divider(height: 1, thickness: 1),
                if (showSearchAndBody)
                  Expanded(
                      child: Stack(children: [
                        (provider.isLoading && provider.products.isEmpty)
                            ? const Center(child: CircularProgressIndicator())
                            : (provider.products.isEmpty ||
                            provider.currentProduct == null)
                            ? Center(
                            child: Text(provider.activeFilter.isActive
                                ? 'Aucun produit.'
                                : 'Aucun produit.'))
                            : widget.isQuickMode
                            ? Center(
                            child: Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.qr_code_scanner,
                                      size: 80,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  const Text(
                                      'Mode Saisie Rapide Activé',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey))
                                ]))
                            : buildProductView(provider),
                        if (_showSearchResults)
                          Container(
                              color: AppColors.background.withOpacity(0.98),
                              child: _filteredProducts.isEmpty
                                  ? const Center(child: Text("Aucun produit trouvé"))
                                  : ListView.builder(
                                  itemCount: _filteredProducts.length,
                                  itemBuilder: (context, index) {
                                    final product = _filteredProducts[index];
                                    final appConfig =
                                    Provider.of<AppConfig>(context,
                                        listen: false);
                                    return Card(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        child: ListTile(
                                            title: Text(product.produitName,
                                                maxLines: 1,
                                                overflow:
                                                TextOverflow.ellipsis),
                                            subtitle: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  Text(appConfig
                                                      .showTheoreticalStock
                                                      ? 'CIP: ${product.produitCip} / Stock Théo: ${product.quantiteInitiale}'
                                                      : 'CIP: ${product.produitCip}'),
                                                  Text(
                                                      'Prix Vente: ${product.produitPrixUni.toStringAsFixed(0)} F',
                                                      style: TextStyle(
                                                          color: Colors.grey
                                                              .shade800,
                                                          fontWeight:
                                                          FontWeight.w500))
                                                ]),
                                            onTap: () =>
                                                _selectProduct(product)));
                                  }))
                      ])),
                if (showSearchAndBody && !widget.isQuickMode && !_isSearching)
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
                child: Text(_notificationMessage!,
                    style: TextStyle(
                        color: _notificationColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)))));
  }

  Widget buildProductView(EntryProvider provider) {
    final Product product = provider.currentProduct!;
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isSmallScreen = screenHeight < 700;

    double stockFontSize = isSmallScreen ? 14 : 16;
    double titleFontSize = isSmallScreen ? 14 : 16;
    double priceFontSize = isSmallScreen ? 13 : 16;
    double quantityFontSize = isSmallScreen ? 22 : 26;
    double buttonSize = isSmallScreen ? 56 : 64;
    double buttonIconSize = isSmallScreen ? 28 : 30;

    const double lineHeightMultiplier = 1.3;
    final double fixedTitleHeight = titleFontSize * lineHeightMultiplier * 2;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      children: [
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Builder(builder: (context) {
            int currentGlobalIndex =
            provider.allProducts.indexWhere((p) => p.id == product.id);
            int displayIndex = (currentGlobalIndex != -1)
                ? currentGlobalIndex
                : provider.currentProductIndex;
            return Text(
                '${displayIndex + 1} / ${provider.totalProductsInRayon}',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: stockFontSize));
          }),
          if (provider.activeFilter.isActive)
            Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12)),
                child: const Text('Filtré', style: TextStyle(fontSize: 12)))
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: fixedTitleHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${product.produitCip} - ${product.produitName}',
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  height: lineHeightMultiplier,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('PA: ${product.produitPrixAchat} F',
              style: TextStyle(fontSize: priceFontSize, color: Colors.orange)),
          Text('PV: ${product.produitPrixUni} F',
              style: TextStyle(fontSize: priceFontSize, color: AppColors.accent))
        ]),
        const SizedBox(height: 8),
        Consumer<AppConfig>(builder: (context, appConfig, child) {
          return Visibility(
              visible: appConfig.showTheoreticalStock,
              child: Text('Stock Théorique: ${product.quantiteInitiale}',
                  style: TextStyle(
                      fontSize: stockFontSize,
                      fontWeight: FontWeight.bold,
                      color: product.quantiteInitiale < 0
                          ? Colors.red.shade700
                          : const Color(0xFF1B5E20))));
        }),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    side: const BorderSide(color: Colors.deepPurple, width: 2),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: provider.previousProduct,
                  child: Icon(Icons.chevron_left,
                      size: buttonIconSize, color: Colors.deepPurple))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: _quantityController,
                  focusNode: _quantityFocusNode,
                  textAlign: TextAlign.center,
                  readOnly: true,
                  style: TextStyle(
                      fontSize: quantityFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple),
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), labelText: 'Quantité'))),
          const SizedBox(width: 8),
          SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    side: const BorderSide(color: Colors.blue, width: 2),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _showJumpDialog(provider),
                  child: Icon(Icons.find_in_page,
                      size: buttonIconSize * 0.9, color: Colors.blue)))
        ]),
        _buildNotificationArea(),
      ],
    );
  }
}