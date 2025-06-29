// lib/screens/config_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/home_screen.dart';
// Import du package de ping
import 'package:dart_ping/dart_ping.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  // Contrôleurs pour tous les champs de texte
  final _localAddressController = TextEditingController();
  final _localPortController = TextEditingController();
  final _distantAddressController = TextEditingController();
  final _distantPortController = TextEditingController();
  final _maxResultController = TextEditingController();
  final _largeValueController = TextEditingController();
  final _autoLogoutController = TextEditingController();

  // Variable d'état pour le Switch
  late bool _showStockValue;
  // Variable pour suivre l'état du ping
  bool _isPinging = false;

  @override
  void initState() {
    super.initState();
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    _localAddressController.text = appConfig.localApiAddress;
    _localPortController.text = appConfig.localApiPort;
    _distantAddressController.text = appConfig.distantApiAddress;
    _distantPortController.text = appConfig.distantApiPort;

    _maxResultController.text = appConfig.maxResult.toString();
    _largeValueController.text = appConfig.largeValueThreshold.toString();
    _autoLogoutController.text = appConfig.autoLogoutMinutes.toString();
    _showStockValue = appConfig.showTheoreticalStock;
  }

  @override
  void dispose() {
    _localAddressController.dispose();
    _localPortController.dispose();
    _distantAddressController.dispose();
    _distantPortController.dispose();
    _maxResultController.dispose();
    _largeValueController.dispose();
    _autoLogoutController.dispose();
    super.dispose();
  }

  /// NOUVELLE MÉTHODE : Lance un ping sur l'adresse fournie.
  Future<void> _performPing(String address) async {
    if (address.isEmpty || _isPinging) return;

    // On nettoie l'adresse pour ne garder que l'hôte (ex: '192.168.1.7')
    final host = Uri.tryParse(address)?.host ?? address.split(':').first;

    setState(() => _isPinging = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ping en cours sur $host...')),
    );

    try {
      final ping = Ping(host, count: 3, timeout: 2);
      bool success = false;

      await for (final event in ping.stream) {
        if (event is PingResponse) {
          success = true;
          break; // Un seul succès suffit
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Succès : Hôte "$host" accessible !' : 'Échec : Hôte "$host" inaccessible.'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du ping: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPinging = false);
      }
    }
  }

  void _saveConfiguration() {
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    appConfig.setApiConfig(
      localAddress: _localAddressController.text.trim(),
      localPort: _localPortController.text.trim(),
      distantAddress: _distantAddressController.text.trim(),
      distantPort: _distantPortController.text.trim(),
    );

    final int maxResult = int.tryParse(_maxResultController.text) ?? 3;
    final int largeValue = int.tryParse(_largeValueController.text) ?? 1000;
    final int logoutMinutes = int.tryParse(_autoLogoutController.text) ?? 0;

    appConfig.setAppSettings(
      maxResult: maxResult,
      showStock: _showStockValue,
      largeValue: largeValue,
      logoutMinutes: logoutMinutes,
    );

    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Params Acces aux données', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // --- Section Locale ---
            const Text('Adresse Locale', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _localAddressController,
                    decoration: const InputDecoration(labelText: 'Adresse IP ou domaine', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _localPortController,
                    decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                // NOUVEAU : Bouton de Ping
                IconButton(
                  icon: Icon(Icons.network_ping, color: _isPinging ? Colors.grey : Theme.of(context).primaryColor),
                  tooltip: 'Tester la connexion (Ping)',
                  onPressed: _isPinging ? null : () => _performPing(_localAddressController.text),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // --- Section Distante ---
            const Text('Adresse Distante', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _distantAddressController,
                    decoration: const InputDecoration(labelText: 'Adresse IP ou domaine', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _distantPortController,
                    decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                // NOUVEAU : Bouton de Ping
                IconButton(
                  icon: Icon(Icons.network_ping, color: _isPinging ? Colors.grey : Theme.of(context).primaryColor),
                  tooltip: 'Tester la connexion (Ping)',
                  onPressed: _isPinging ? null : () => _performPing(_distantAddressController.text),
                ),
              ],
            ),

            const Divider(height: 40),
            Text('Paramètres de l\'application', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            TextFormField(
              controller: _maxResultController,
              decoration: const InputDecoration(labelText: 'Nombre d\'inventaires à afficher', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _largeValueController,
              decoration: const InputDecoration(labelText: 'Seuil d\'alerte pour grande quantité', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _autoLogoutController,
              decoration: const InputDecoration(labelText: 'Délai de déconnexion (minutes, 0=désactivé)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),

            SwitchListTile(
              title: const Text('Afficher le stock théorique'),
              contentPadding: EdgeInsets.zero,
              value: _showStockValue,
              onChanged: (bool value) {
                setState(() {
                  _showStockValue = value;
                });
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveConfiguration,
                child: const Text('VALIDER LA CONFIGURATION'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}