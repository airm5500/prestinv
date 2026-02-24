// lib/screens/global_variance_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
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
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  bool _isSearching = false;

  late ApiService _apiService;

  List<Product> _allVariances = [];
  List<Product> _displayedVariances = [];
  List<Rayon> _rayons = [];
  Rayon? _selectedRayonFilter;

  bool _isLoading = true;
  String? _errorMessage;

  // --- NOUVEAU : Mémoire des écarts réellement validés ---
  final Set<int> _correctedProductIds = {};

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

    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final futures = await Future.wait([
        _apiService.fetchGlobalVariances(widget.inventoryId),
        _apiService.fetchRayons(widget.inventoryId)
      ]);

      if (mounted) {
        setState(() {
          _allVariances = futures[0] as List<Product>;
          _rayons = futures[1] as List<Rayon>;

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

  Future<void> _loadAllVariances() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final products = await _apiService.fetchGlobalVariances(widget.inventoryId);
      if (mounted) {
        setState(() {
          _allVariances = products;
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

  // --- LOGIQUE DE SÉCURITÉ DE SORTIE ---
  Future<bool> _handleExitSecurity() async {
    if (_displayedVariances.isEmpty) return true;

    // On compte combien de produits affichés n'ont pas encore été validés
    int remaining = _displayedVariances.where((p) => !_correctedProductIds.contains(p.id)).length;

    if (remaining == 0) return true; // Tout a été corrigé

    // S'il reste des produits à corriger, on bloque et on avertit
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter la correction ?'),
        content: Text('Attention, il reste encore $remaining écart(s) à vérifier dans cette liste.\n\nVous avez l\'obligation de tous les traiter.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), // Annule la sortie
              child: const Text('Rester et Corriger')
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), // Force la sortie (Optionnel, vous pouvez le retirer pour bloquer totalement)
              child: const Text('Forcer la sortie', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    ) ?? false;
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _applyFilters(query: query);
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) _performApiSearch(query);
    });
  }

  // Dans lib/screens/global_variance_screen.dart

  void _onRayonFilterChanged(Rayon? rayon) async {
    setState(() {
      _selectedRayonFilter = rayon;
      _isLoading = true; // On affiche le sablier pendant qu'on interroge le serveur
    });

    try {
      List<Product> newVariances;

      if (rayon == null) {
        // Cas 1 : "Tous les emplacements" -> On garde l'ancienne méthode globale
        newVariances = await _apiService.fetchGlobalVariances(widget.inventoryId);
      } else {
        // Cas 2 : Un rayon spécifique -> ON UTILISE VOTRE API AVEC L'ID !
        newVariances = await _apiService.fetchTouchedProductsByRayon(
            widget.inventoryId,
            rayon.id
        );
      }

      if (mounted) {
        setState(() {
          _allVariances = newVariances;
          // On réapplique le filtre de la barre de recherche au cas où vous auriez scanné un truc
          _applyFilters(query: _searchController.text);
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

  void _applyFilters({String query = ''}) {
    List<Product> temp = List.from(_allVariances);

    // Filtre par Texte/Scan (Géré localement pour être très rapide)
    if (query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      temp = temp.where((p) =>
      p.produitCip.contains(lowerQuery) ||
          p.produitName.toLowerCase().contains(lowerQuery)
      ).toList();
    }

    setState(() {
      _displayedVariances = temp;
    });
  }

  Future<void> _performApiSearch(String query) async {
    try {
      final results = await _apiService.fetchGlobalVariances(widget.inventoryId, query: query);
      if (!mounted) return;

      if (results.length == 1) {
        setState(() { _displayedVariances = results; });
        _openCorrectionDialog(0);
        _searchController.clear();
        _applyFilters();
        FocusScope.of(context).unfocus();
      } else if (results.isNotEmpty) {
        setState(() { _displayedVariances = results; });
      }
    } catch (e) {
      print("Erreur recherche API: $e");
    }
  }

  // --- CORRECTION AVEC NAVIGATION (< >) ---
  void _openCorrectionDialog(int startIndex) {
    int currentIndex = startIndex;
    final qtyController = TextEditingController();
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              final product = _displayedVariances[currentIndex];
              final bool isValidated = _correctedProductIds.contains(product.id);

              return AlertDialog(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isValidated ? '✅ Écart Vérifié' : 'Correction Écart',
                            style: TextStyle(fontSize: 14, color: isValidated ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
                        Text('${currentIndex + 1} / ${_displayedVariances.length}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(product.produitName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis
                    ),
                    Text('CIP: ${product.produitCip}', style: const TextStyle(fontSize: 14)),
                    if (product.locationLabel != null)
                      Text('Emplacement: ${product.locationLabel}', style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (appConfig.showTheoreticalStock)
                          Text('Théo: ${product.quantiteInitiale}', style: const TextStyle(fontWeight: FontWeight.bold))
                        else
                          const Text('Théo: ***', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),

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
                      // --- NAVIGATION ET SAISIE ---
                      Row(
                        children: [
                          // Flèche Précédent
                          IconButton(
                            icon: Icon(Icons.chevron_left, size: 36, color: currentIndex > 0 ? Colors.deepPurple : Colors.grey),
                            onPressed: currentIndex > 0 ? () {
                              setDialogState(() {
                                currentIndex--;
                                qtyController.clear();
                              });
                            } : null,
                          ),
                          // Champ Quantité
                          Expanded(
                            child: TextField(
                              controller: qtyController,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent),
                              decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder()),
                              readOnly: true,
                              autofocus: true,
                              showCursor: true,
                            ),
                          ),
                          // Flèche Suivant
                          IconButton(
                            icon: Icon(Icons.chevron_right, size: 36, color: currentIndex < _displayedVariances.length - 1 ? Colors.deepPurple : Colors.grey),
                            onPressed: currentIndex < _displayedVariances.length - 1 ? () {
                              setDialogState(() {
                                currentIndex++;
                                qtyController.clear();
                              });
                            } : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Clavier
                      SizedBox(
                        height: 280,
                        child: NumericKeyboard(
                          onKeyPressed: (key) {
                            if (key == 'OK') {
                              if (qtyController.text.isEmpty) return;
                              final int qty = int.tryParse(qtyController.text) ?? 0;

                              // 1. Appliquer la correction et mémoriser la validation
                              _applyCorrection(product, qty);
                              setState(() { _correctedProductIds.add(product.id); }); // Mémorise la validation

                              // 2. Passage automatique
                              if (currentIndex < _displayedVariances.length - 1) {
                                setDialogState(() {
                                  currentIndex++;
                                  qtyController.clear();
                                });
                              } else {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Fin de la liste atteinte.'), backgroundColor: Colors.blue)
                                );
                                Future.delayed(const Duration(milliseconds: 100), () {
                                  if (mounted) _searchFocusNode.requestFocus();
                                });
                              }

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
                      child: const Text('Fermer', style: TextStyle(color: Colors.red))
                  ),
                ],
              );
            }
        );
      },
    );
  }

  void _applyCorrection(Product product, int newQuantity) async {
    setState(() {
      product.quantiteSaisie = newQuantity;
    });

    try {
      await _apiService.updateProductQuantity(product.id, newQuantity);
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
    final appConfig = Provider.of<AppConfig>(context);

    // Ajout du WillPopScope pour intercepter la touche "Retour" du téléphone
    return WillPopScope(
      onWillPop: _handleExitSecurity,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _handleExitSecurity()) {
                if (mounted) Navigator.of(context).pop();
              }
            },
          ),
          title: const Text('Correction Écarts'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 4.0),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilters();
                      _searchFocusNode.requestFocus();
                    },
                  )
                      : null,
                ),
              ),
            ),

            if (_rayons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Rayon?>(
                      isExpanded: true,
                      value: _selectedRayonFilter,
                      icon: const Icon(Icons.filter_list, color: AppColors.primary),
                      hint: const Text("Filtrer par emplacement", style: TextStyle(fontWeight: FontWeight.bold)),
                      items: [
                        const DropdownMenuItem<Rayon?>(
                          value: null,
                          child: Text("Tous les emplacements", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        ..._rayons.map((Rayon r) {
                          return DropdownMenuItem<Rayon?>(
                            value: r,
                            child: Text(r.libelle, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                      ],
                      onChanged: _onRayonFilterChanged,
                    ),
                  ),
                ),
              ),

            const Divider(height: 1, thickness: 1),

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
                    const Text("Tout semble correct pour ce filtre.", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
                  : ListView.separated(
                itemCount: _displayedVariances.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final p = _displayedVariances[i];
                  final ecart = p.quantiteSaisie - p.quantiteInitiale;
                  final isValidated = _correctedProductIds.contains(p.id); // Vérifie si on a cliqué sur OK pour ce produit

                  Color badgeColor;
                  Color badgeTextColor;
                  Color badgeBorderColor;

                  if (ecart > 0) {
                    badgeColor = Colors.green.shade100;
                    badgeTextColor = Colors.green.shade800;
                    badgeBorderColor = Colors.green;
                  } else if (ecart < 0) {
                    badgeColor = Colors.red.shade100;
                    badgeTextColor = Colors.red.shade800;
                    badgeBorderColor = Colors.red;
                  } else {
                    badgeColor = Colors.grey.shade100;
                    badgeTextColor = Colors.grey.shade800;
                    badgeBorderColor = Colors.grey;
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                    // Ajout d'une coche verte visuelle si le produit a été vérifié
                    leading: isValidated
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                    title: Text(
                      p.produitName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isValidated ? Colors.grey.shade700 : Colors.black, // Grise légèrement le nom si validé
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                        'CIP: ${p.produitCip}${p.locationLabel != null ? ' • ${p.locationLabel}' : ''}',
                        style: const TextStyle(fontSize: 12)
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (appConfig.showTheoreticalStock)
                              Text('Théo: ${p.quantiteInitiale}', style: const TextStyle(fontSize: 11, color: Colors.grey))
                            else
                              const Text('Théo: ***', style: TextStyle(fontSize: 11, color: Colors.grey)),

                            Text('Saisi: ${p.quantiteSaisie}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 45,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: badgeBorderColor)
                          ),
                          child: Text(
                            (ecart > 0) ? "+$ecart" : "$ecart",
                            style: TextStyle(
                                color: badgeTextColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12
                            ),
                          ),
                        )
                      ],
                    ),
                    onTap: () => _openCorrectionDialog(i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}