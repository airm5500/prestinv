// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/analysis_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prestinv - Accueil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: 'Analyse',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnalysisScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuration',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConfigScreen()),
              );
            },
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Mode de connexion actuel: ${appConfig.apiMode == ApiMode.local ? 'Local' : 'Distant'}'),
            Switch(
              value: appConfig.apiMode == ApiMode.local,
              onChanged: (value) {
                // CORRECTION: ApiMode.distant au lieu de Api.distant
                appConfig.setApiMode(value ? ApiMode.local : ApiMode.distant);
              },
              activeTrackColor: Colors.lightGreenAccent,
              activeColor: Colors.green,
              inactiveTrackColor: Colors.orangeAccent,
              inactiveThumbColor: Colors.orange,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              child: const Text('Commencer un inventaire'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InventoryListScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}