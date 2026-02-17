// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/analysis_screen.dart';
import 'package:prestinv/utils/app_utils.dart';
import 'package:prestinv/screens/collection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  // CORRECTION ICI : Variable statique pour mémoriser si l'alerte a déjà été montrée dans cette session
  static bool _alertShown = false;

  @override
  void initState() {
    super.initState();
    // Affichage des alertes de licence après le build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // On ne lance la vérification que si l'alerte n'a pas encore été montrée
      if (!_alertShown) {
        _checkLicenseWarnings();
      }
    });
  }

  void _checkLicenseWarnings() {
    final license = Provider.of<LicenseProvider>(context, listen: false);
    final days = license.daysRemaining;

    String? message;
    Color color = Colors.orange;

    // Logique des alertes
    if (days <= 1) {
      message = "ATTENTION : Votre licence expire DEMAIN !";
      color = Colors.red;
    } else if (days <= 7) {
      message = "Rappel : Il vous reste moins d'une semaine de licence ($days jours).";
      color = Colors.redAccent;
    } else if (days == 30 || days == 29) {
      message = "Information : Votre licence expire dans 1 mois.";
    } else if (days == 90 || days == 89) {
      message = "Information : Votre licence expire dans 3 mois.";
    }

    if (message != null) {
      // CORRECTION ICI : On marque l'alerte comme montrée AVANT d'afficher le dialog
      _alertShown = true;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [Icon(Icons.warning_amber, color: color), const SizedBox(width: 10), const Text("Licence")]),
          content: Text(message!),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("OK"))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final licenseProvider = Provider.of<LicenseProvider>(context); // Ecoute pour le compteur

    final userName = authProvider.user?.firstName ?? 'Utilisateur';
    final userOfficine = authProvider.user?.officine ?? '';
    final int daysLeft = licenseProvider.daysRemaining;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventaire - Accueil'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.analytics_outlined), tooltip: 'Analyse', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalysisScreen()))),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Configuration', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfigScreen()))),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Déconnexion', onPressed: () => performLogout(context)),
        ],
      ),
      body: Column(
        children: [
          // BANDEAU SUPERIEUR (Licence + Mode)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Compteur Licence
                Row(
                  children: [
                    Icon(Icons.timer, size: 16, color: daysLeft < 30 ? Colors.red : Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      '$daysLeft j restants',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: daysLeft < 30 ? Colors.red : Colors.green,
                          fontSize: 12
                      ),
                    ),
                  ],
                ),

                // Switch Mode
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
              child: SingleChildScrollView(
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
                    const SizedBox(height: 30),

                    // LES BOUTONS
                    _buildMenuButton(
                      context, 'SAISIE GUIDEE\n(Mode Guidé)', Icons.inventory_2_outlined,
                      AppColors.accent,
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryListScreen(isQuickMode: false))),
                    ),
                    const SizedBox(height: 16),

                    _buildMenuButton(
                      context, 'SAISIE RAPIDE\n(Mode Scan)', Icons.qr_code_scanner,
                      Colors.orange.shade800,
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryListScreen(isQuickMode: true))),
                    ),
                    const SizedBox(height: 16),

                    _buildMenuButton(
                      context, 'CORRECTION ÉCARTS\n(Scan & Liste)', Icons.rule,
                      Colors.red.shade700,
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryListScreen(isVarianceMode: true))),
                    ),
                    const SizedBox(height: 16),

                    _buildMenuButton(
                      context, 'RESTANTS À FAIRE\n(Produits non comptés)', Icons.hourglass_empty,
                      Colors.purple.shade700,
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryListScreen(isUncountedMode: true))),
                    ),
                    const SizedBox(height: 16),

                    _buildMenuButton(
                      context, 'COLLECTE LIBRE\n(Mode Hors-ligne)', Icons.data_saver_on,
                      Colors.teal.shade700,
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CollectionScreen())),
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

  Widget _buildMenuButton(BuildContext context, String label, IconData icon, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 28),
        label: Text(label, textAlign: TextAlign.center),
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
        ),
        onPressed: onPressed,
      ),
    );
  }
}