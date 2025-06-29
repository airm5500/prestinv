// lib/screens/inventory_list_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

// CORRECTION : Ajout de l'import manquant pour EntryProvider
import 'package:prestinv/providers/entry_provider.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

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
    // On s'assure que le widget est toujours dans l'arbre avant d'utiliser son context
    if (!mounted) return;

    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final apiService = ApiService(
      baseUrl: appConfig.currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );
    // Le provider est appelé avec listen: false car on est dans initState
    await Provider.of<InventoryProvider>(context, listen: false)
        .fetchInventories(apiService, maxResult: appConfig.maxResult);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choisir un inventaire'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshInventories,
        child: Consumer<InventoryProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Erreur de chargement des inventaires.\nAssurez-vous que le serveur est accessible et que la configuration est correcte.\n\nDétail: ${provider.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
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
                    // Cet appel fonctionne car l'import est maintenant présent
                    Provider.of<EntryProvider>(context, listen: false).reset();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InventoryEntryScreen(
                          inventoryId: provider.inventories[i].id,
                        ),
                      ),
                    );
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