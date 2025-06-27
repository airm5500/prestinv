// lib/screens/config_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/home_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _localController = TextEditingController();
  final _distantController = TextEditingController();
  final _maxResultController = TextEditingController();
  late bool _showStockValue;

  @override
  void initState() {
    super.initState();
    // On initialise les champs avec les valeurs actuelles de la configuration
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    _localController.text = appConfig.localApiUrl;
    _distantController.text = appConfig.distantApiUrl;
    _maxResultController.text = appConfig.maxResult.toString();
    _showStockValue = appConfig.showTheoreticalStock;
  }

  @override
  void dispose() {
    _localController.dispose();
    _distantController.dispose();
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
            Text('Connexion Prestige Inventaire', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            TextField(
              controller: _localController,
              decoration: const InputDecoration(
                labelText: 'Adresse IP Locale (ex: http://192.168.1.10:8080)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _distantController,
              decoration: const InputDecoration(
                labelText: 'Adresse IP Publique (32.22)',
                border: OutlineInputBorder(),
              ),
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
                  // On récupère et nettoie les valeurs
                  String localUrl = _localController.text.trim();
                  if (localUrl.isNotEmpty && !localUrl.startsWith('http')) {
                    localUrl = 'http://$localUrl';
                  }
                  String distantUrl = _distantController.text.trim();
                  if (distantUrl.isNotEmpty && !distantUrl.startsWith('http')) {
                    distantUrl = 'http://$distantUrl';
                  }

                  final int maxResult = int.tryParse(_maxResultController.text) ?? 3;

                  // On sauvegarde toutes les configurations
                  appConfig.setApiUrls(localUrl, distantUrl);
                  appConfig.setAppSettings(
                    maxResult: maxResult,
                    showStock: _showStockValue,
                  );

                  // On gère la navigation : si on peut revenir en arrière, on le fait.
                  // Sinon (premier lancement), on va à l'écran d'accueil.
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