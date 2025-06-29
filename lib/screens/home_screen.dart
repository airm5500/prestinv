// lib/screens/home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/analysis_screen.dart';
import 'package:prestinv/utils/app_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    // Le timer est démarré via le context dans le build, une seule fois
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _resetInactivityTimer();
      }
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetInactivityTimer() {
    if (!mounted) return;
    final appConfig = context.read<AppConfig>();
    final authProvider = context.read<AuthProvider>();

    if (!authProvider.isLoggedIn) {
      _inactivityTimer?.cancel();
      return;
    }

    final delay = appConfig.autoLogoutMinutes;
    if (delay <= 0) {
      _inactivityTimer?.cancel();
      return;
    }

    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(Duration(minutes: delay), () {
      if (authProvider.isLoggedIn && mounted) {
        performLogout(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userName = authProvider.user?.firstName ?? 'Utilisateur';
    final userOfficine = authProvider.user?.officine ?? '';

    return GestureDetector(
      onTap: _resetInactivityTimer,
      onPanDown: (_) => _resetInactivityTimer(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Prestinv - Accueil'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(icon: const Icon(Icons.analytics_outlined), tooltip: 'Analyse', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalysisScreen()))),
            IconButton(icon: const Icon(Icons.logout), tooltip: 'Déconnexion', onPressed: () => performLogout(context)),
            IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Configuration', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfigScreen()))),
          ],
        ),
        // CORRECTION : Nouvelle disposition du body avec une Column
        body: Column(
          children: [
            // 1. La zone de connexion est maintenant en haut
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mode de connexion :'),
                      Row(
                        children: [
                          Text(
                            appConfig.apiMode == ApiMode.local ? 'Local' : 'Distant',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                          ),
                          Switch(
                            value: appConfig.apiMode == ApiMode.local,
                            onChanged: (value) {
                              appConfig.setApiMode(value ? ApiMode.local : ApiMode.distant);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 2. Le reste du contenu est centré dans l'espace restant
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
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
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
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
      ),
    );
  }
}