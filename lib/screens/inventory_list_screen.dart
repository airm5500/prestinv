import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

  @override
  _InventoryListScreenState createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // On récupère AppConfig
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      final apiService = ApiService(baseUrl: appConfig.currentApiUrl);

      // On utilise la valeur de maxResult depuis la config
      Provider.of<InventoryProvider>(context, listen: false)
          .fetchInventories(apiService, maxResult: appConfig.maxResult);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choisir un inventaire'),
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.error != null) {
            return Center(child: Text('Erreur: ${provider.error}'));
          }
          if (provider.inventories.isEmpty) {
            return const Center(child: Text('Aucun inventaire trouvé.'));
          }
          return ListView.builder(
            itemCount: provider.inventories.length,
            itemBuilder: (ctx, i) => Card(
              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
              child: ListTile(
                title: Text(provider.inventories[i].libelle),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
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
    );
  }
}