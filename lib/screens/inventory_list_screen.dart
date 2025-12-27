// lib/screens/inventory_list_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/screens/global_variance_screen.dart';
import 'package:prestinv/screens/uncounted_screen.dart'; // NOUVEAU IMPORT

class InventoryListScreen extends StatefulWidget {
  final bool isQuickMode;
  final bool isVarianceMode;
  // AJOUT : Nouveau mode Restants
  final bool isUncountedMode;

  const InventoryListScreen({
    super.key,
    this.isQuickMode = false,
    this.isVarianceMode = false,
    this.isUncountedMode = false,
  });

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshInventories();
    });
  }

  Future<void> _refreshInventories() async {
    if (!mounted) return;

    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final apiService = ApiService(
      baseUrl: appConfig.currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );
    await Provider.of<InventoryProvider>(context, listen: false)
        .fetchInventories(apiService, maxResult: appConfig.maxResult);
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Choisir un inventaire';
    if (widget.isQuickMode) title += ' (Scan Rapide)';
    else if (widget.isVarianceMode) title += ' (Correction Écarts)';
    else if (widget.isUncountedMode) title += ' (Restants)'; // Titre adapté

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshInventories,
        child: Consumer<InventoryProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null) {
              return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Erreur: ${provider.error}', style: const TextStyle(color: Colors.red))));
            }
            if (provider.inventories.isEmpty) {
              return const Center(child: Text('Aucun inventaire trouvé.'));
            }

            return ListView.builder(
              itemCount: provider.inventories.length,
              itemBuilder: (ctx, i) => Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: ListTile(
                  title: Text(provider.inventories[i].libelle),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // --- ROUTAGE SELON LE MODE ---
                    if (widget.isVarianceMode) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => GlobalVarianceScreen(
                          inventoryId: provider.inventories[i].id,
                          inventoryName: provider.inventories[i].libelle,
                        ),
                      ));
                    }
                    else if (widget.isUncountedMode) {
                      // ROUTAGE VERS ECRAN RESTANTS
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => UncountedScreen(
                          inventoryId: provider.inventories[i].id,
                          inventoryName: provider.inventories[i].libelle,
                        ),
                      ));
                    }
                    else {
                      // Modes Saisie Classique
                      Provider.of<EntryProvider>(context, listen: false).reset();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => InventoryEntryScreen(
                          inventoryId: provider.inventories[i].id,
                          isQuickMode: widget.isQuickMode,
                        ),
                      ));
                    }
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}