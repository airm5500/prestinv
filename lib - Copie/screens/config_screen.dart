// lib/screens/config_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/home_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  _ConfigScreenState createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _localController = TextEditingController();
  final _distantController = TextEditingController();
  final _maxResultController = TextEditingController();
  late bool _showStockValue;

  @override
  void initState() {
    super.initState();
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
            const Text('Connexion API', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                labelText: 'Adresse IP Publique (ex: http://votre-domaine.com)',
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 30),
            const Text('Paramètres de l\'application', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            // Champ pour maxResult
            TextField(
              controller: _maxResultController,
              decoration: const InputDecoration(
                labelText: 'Nombre d\'inventaires à afficher',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            // Checkbox pour le stock théorique
            SwitchListTile(
              title: const Text('Afficher le stock théorique'),
              value: _showStockValue,
              onChanged: (bool value) {
                setState(() {
                  _showStockValue = value;
                });
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                String localUrl = _localController.text.trim();
                if (localUrl.isNotEmpty && !localUrl.startsWith('http')) {
                  localUrl = 'http://$localUrl';
                }
                String distantUrl = _distantController.text.trim();
                if (distantUrl.isNotEmpty && !distantUrl.startsWith('http')) {
                  distantUrl = 'http://$distantUrl';
                }

                final int maxResult = int.tryParse(_maxResultController.text) ?? 3;

                appConfig.setApiUrls(localUrl, distantUrl);
                appConfig.setAppSettings(
                  maxResult: maxResult,
                  showStock: _showStockValue,
                );

                // Si on vient de la page d'accueil, on la ferme
                if (Navigator.canPop(context)) {
                  Navigator.of(context).pop();
                } else { // Sinon (premier lancement), on la remplace
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                  );
                }
              },
              child: const Text('Valider la Configuration'),
            ),
          ],
        ),
      ),
    );
  }
}