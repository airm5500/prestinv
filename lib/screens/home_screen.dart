// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/screens/analysis_screen.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
// Import du nouveau fichier utilitaire pour les fonctions communes
import 'package:prestinv/utils/app_utils.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    // On récupère les informations de l'utilisateur pour le message de bienvenue
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userName = authProvider.user?.firstName ?? 'Utilisateur';
    final userOfficine = authProvider.user?.officine ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prestinv - Accueil'),
        // Empêche la flèche de retour d'apparaître sur l'écran d'accueil
        automaticallyImplyLeading: false,
        actions: [
          // Bouton pour l'écran d'analyse
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Analyse',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnalysisScreen()),
              );
            },
          ),
          // Bouton pour la déconnexion
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            // La logique complexe de déconnexion est maintenant un simple appel de fonction
            onPressed: () => performLogout(context),
          ),
          // Bouton pour l'écran de configuration
          IconButton(
            icon: const Icon(Icons.settings_outlined),
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Message de bienvenue personnalisé
              Text(
                'Bienvenue, $userName',
                style: Theme.of(context).textTheme.headlineSmall,
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

              // Sélecteur de mode de connexion
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Mode de connexion : ${appConfig.apiMode == ApiMode.local ? 'Local' : 'Distant'}'),
                      Switch(
                        value: appConfig.apiMode == ApiMode.local,
                        onChanged: (value) {
                          appConfig.setApiMode(value ? ApiMode.local : ApiMode.distant);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Bouton principal
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('COMMENCER L\'INVENTAIRE'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => InventoryListScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}