// lib/screens/config_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:http/http.dart' as http;

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
  final _appNameController = TextEditingController();
  final _maxResultController = TextEditingController();
  final _largeValueController = TextEditingController();
  final _autoLogoutController = TextEditingController();
  final _exportPathController = TextEditingController();
  final _sendReminderController = TextEditingController();

  // Variables d'état
  late bool _showStockValue;
  late bool _isCumulEnabled; // Doit être initialisée dans initState
  bool _isAppNameEditable = false;
  bool _isTestingConnection = false;

  @override
  void initState() {
    super.initState();
    // On initialise les champs avec les valeurs actuelles de la configuration
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    _localAddressController.text = appConfig.localApiAddress;
    _localPortController.text = appConfig.localApiPort;
    _distantAddressController.text = appConfig.distantApiAddress;
    _distantPortController.text = appConfig.distantApiPort;
    _appNameController.text = appConfig.appName;
    _maxResultController.text = appConfig.maxResult.toString();
    _largeValueController.text = appConfig.largeValueThreshold.toString();
    _autoLogoutController.text = appConfig.autoLogoutMinutes.toString();
    _exportPathController.text = appConfig.networkExportPath;
    _sendReminderController.text = appConfig.sendReminderMinutes.toString();

    _showStockValue = appConfig.showTheoreticalStock;
    // CORRECTION : Initialisation de la variable (sinon crash)
    _isCumulEnabled = appConfig.isCumulEnabled;
  }

  @override
  void dispose() {
    // On n'oublie pas de disposer de tous les contrôleurs
    _localAddressController.dispose();
    _localPortController.dispose();
    _distantAddressController.dispose();
    _distantPortController.dispose();
    _appNameController.dispose();
    _maxResultController.dispose();
    _largeValueController.dispose();
    _autoLogoutController.dispose();
    _exportPathController.dispose();
    _sendReminderController.dispose();
    super.dispose();
  }

  /// Teste la connectivité vers une adresse en effectuant une requête HTTP légère.
  Future<void> _testConnectivity(String address, String port) async {
    if (address.isEmpty || _isTestingConnection) return;

    String host = address.trim();
    if (host.startsWith('http')) {
      host = Uri.parse(host).host;
    }
    String urlString = 'http://$host';
    if (port.isNotEmpty) {
      urlString += ':$port';
    }
    final url = Uri.parse(urlString);

    setState(() => _isTestingConnection = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Test de connexion vers $urlString...')),
    );

    try {
      await http.head(url).timeout(const Duration(seconds: 7));

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Succès : Serveur accessible à l\'adresse $urlString !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Échec : Impossible de joindre le serveur. Vérifiez l\'adresse, le port et la connexion réseau.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
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
      appName: _appNameController.text.trim(),
    );

    final int maxResult = int.tryParse(_maxResultController.text) ?? 3;
    final int largeValue = int.tryParse(_largeValueController.text) ?? 1000;
    final int logoutMinutes = int.tryParse(_autoLogoutController.text) ?? 0;
    final int sendReminder = int.tryParse(_sendReminderController.text) ?? 15;
    final String exportPath = _exportPathController.text.trim();

    appConfig.setAppSettings(
      maxResult: maxResult,
      showStock: _showStockValue,
      largeValue: largeValue,
      logoutMinutes: logoutMinutes,
      exportPath: exportPath,
      sendReminderMinutes: sendReminder,
      // CORRECTION : Sauvegarde du paramètre Cumul
      isCumulEnabled: _isCumulEnabled,
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
    final appConfig = Provider.of<AppConfig>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connexion API', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text('Adresse Locale', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TextFormField(controller: _localAddressController, decoration: const InputDecoration(labelText: 'Adresse IP ou domaine', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextFormField(controller: _localPortController, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                IconButton(icon: Icon(Icons.network_ping, color: _isTestingConnection ? Colors.grey : Theme.of(context).primaryColor), tooltip: 'Tester la connexion', onPressed: _isTestingConnection ? null : () => _testConnectivity(_localAddressController.text, _localPortController.text)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Adresse Distante', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TextFormField(controller: _distantAddressController, decoration: const InputDecoration(labelText: 'Adresse IP ou domaine', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextFormField(controller: _distantPortController, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                IconButton(icon: Icon(Icons.network_ping, color: _isTestingConnection ? Colors.grey : Theme.of(context).primaryColor), tooltip: 'Tester la connexion', onPressed: _isTestingConnection ? null : () => _testConnectivity(_distantAddressController.text, _distantPortController.text)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Nom de l\'Application (contexte URL)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _appNameController,
                    readOnly: !_isAppNameEditable,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      filled: !_isAppNameEditable,
                      fillColor: Colors.grey.shade200,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(_isAppNameEditable ? Icons.save_alt_outlined : Icons.edit_outlined),
                  tooltip: _isAppNameEditable ? 'Enregistrer' : 'Modifier',
                  onPressed: () => setState(() => _isAppNameEditable = !_isAppNameEditable),
                )
              ],
            ),
            const Divider(height: 40),
            Text('Paramètres de l\'application', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(controller: _maxResultController, decoration: const InputDecoration(labelText: 'Nombre d\'inventaires à afficher', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 16),
            TextFormField(controller: _largeValueController, decoration: const InputDecoration(labelText: 'Seuil d\'alerte pour grande quantité', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 16),
            TextFormField(controller: _autoLogoutController, decoration: const InputDecoration(labelText: 'Délai de déconnexion (minutes, 0=désactivé)', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 16),
            TextFormField(controller: _sendReminderController, decoration: const InputDecoration(labelText: 'Rappel d\'envoi (minutes, 0=désactivé)', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 16),
            TextFormField(controller: _exportPathController, decoration: const InputDecoration(labelText: 'Chemin réseau pour nom de fichier (Optionnel)', hintText: 'ex: \\\\SERVEUR\\partage', border: OutlineInputBorder())),
            SwitchListTile(title: const Text('Afficher le stock théorique'), contentPadding: EdgeInsets.zero, value: _showStockValue, onChanged: (bool value) => setState(() => _showStockValue = value)),

            // Switch CUMUL
            SwitchListTile(
              title: const Text('Activer le Cumul de quantité'),
              subtitle: const Text('Proposer d\'additionner si le produit est déjà compté'),
              contentPadding: EdgeInsets.zero,
              value: _isCumulEnabled,
              onChanged: (bool value) => setState(() => _isCumulEnabled = value),
            ),

            SwitchListTile(
              title: const Text('Mode d\'envoi'),
              subtitle: Text(appConfig.sendMode == SendMode.direct ? 'Direct (après chaque saisie)' : 'Collecte (envoi manuel)'),
              value: appConfig.sendMode == SendMode.direct,
              onChanged: (bool value) => Provider.of<AppConfig>(context, listen: false).setSendMode(value ? SendMode.direct : SendMode.collect),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _saveConfiguration, child: const Text('VALIDER LA CONFIGURATION')),
            ),
          ],
        ),
      ),
    );
  }
}