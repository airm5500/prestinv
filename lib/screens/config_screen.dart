// lib/screens/config_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/home_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  // MODIFICATION: 4 contrôleurs au lieu de 2
  final _localAddressController = TextEditingController();
  final _localPortController = TextEditingController();
  final _distantAddressController = TextEditingController();
  final _distantPortController = TextEditingController();

  final _maxResultController = TextEditingController();
  late bool _showStockValue;

  @override
  void initState() {
    super.initState();
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    _localAddressController.text = appConfig.localApiAddress;
    _localPortController.text = appConfig.localApiPort;
    _distantAddressController.text = appConfig.distantApiAddress;
    _distantPortController.text = appConfig.distantApiPort;

    _maxResultController.text = appConfig.maxResult.toString();
    _showStockValue = appConfig.showTheoreticalStock;
  }

  @override
  void dispose() {
    _localAddressController.dispose();
    _localPortController.dispose();
    _distantAddressController.dispose();
    _distantPortController.dispose();
    _maxResultController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prestige INV Connexion', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // --- Section Locale ---
            const Text('Adresse Locale', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _localAddressController,
                    decoration: const InputDecoration(
                      labelText: 'Adresse IP ou domaine',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _localPortController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
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
                  child: TextField(
                    controller: _distantAddressController,
                    decoration: const InputDecoration(
                      labelText: 'Adresse IP ou domaine',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _distantPortController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),

            const Divider(height: 40),
            Text('Paramètres de l\'application', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _maxResultController,
              decoration: const InputDecoration(
                labelText: 'Nombre d\'inventaires à afficher',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
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
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  appConfig.setApiConfig(
                    localAddress: _localAddressController.text.trim(),
                    localPort: _localPortController.text.trim(),
                    distantAddress: _distantAddressController.text.trim(),
                    distantPort: _distantPortController.text.trim(),
                  );

                  final int maxResult = int.tryParse(_maxResultController.text) ?? 3;
                  appConfig.setAppSettings(
                    maxResult: maxResult,
                    showStock: _showStockValue,
                  );

                  if (Navigator.canPop(context)) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  }
                },
                child: const Text('Valider la Configuration'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}