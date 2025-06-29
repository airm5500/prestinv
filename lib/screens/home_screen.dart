// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/analysis_screen.dart';
import 'package:prestinv/utils/app_utils.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userName = authProvider.user?.firstName ?? 'Utilisateur';
    final userOfficine = authProvider.user?.officine ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prestinv - Accueil'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.analytics_outlined), tooltip: 'Analyse', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalysisScreen()))),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Déconnexion', onPressed: () => performLogout(context)),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Configuration', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfigScreen()))),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Mode de connexion :'),
                Row(
                  children: [
                    Text(
                      appConfig.apiMode == ApiMode.local ? 'Local' : 'Distant',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                    Switch(
                      activeColor: AppColors.accent,
                      value: appConfig.apiMode == ApiMode.local,
                      onChanged: (value) {
                        Provider.of<AppConfig>(context, listen: false)
                            .setApiMode(value ? ApiMode.local : ApiMode.distant);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'Bienvenue, $userName',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.primary),
                      textAlign: TextAlign.center,
                    ),
                    if (userOfficine.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          userOfficine,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 40),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('COMMENCER L\'INVENTAIRE'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const InventoryListScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
