// lib/screens/config_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:http/http.dart' as http;
import 'package:prestinv/widgets/pin_admin.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:prestinv/scan/retour_scan.dart';
import 'package:prestinv/version_app.dart';

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
  final _quantiteScanController = TextEditingController();

  // Variables d'état
  late bool _showStockValue;
  late bool _isCumulEnabled; // Doit être initialisée dans initState
  late bool _sonScan;
  late bool _vibrationScan;
  bool _isAppNameEditable = false;
  bool _isTestingConnection = false;

  /// Connexion au serveur (adresses, ports, contexte) modifiable seulement après le code
  /// administrateur : un réglage modifié par n'importe qui pouvait renvoyer les mots de passe vers
  /// un faux serveur.
  bool _serveurDeverrouille = false;

  final _formKey = GlobalKey<FormState>();

  /// Contrôles des champs du serveur : seulement quand ils sont modifiables (une ancienne valeur
  /// non conforme ne bloque pas l'enregistrement des autres réglages).
  String? Function(String?) _siDeverrouille(String? Function(String?) controle) =>
      (v) => _serveurDeverrouille ? controle(v) : null;

  /// 4.14 : scan par l'appareil photo — réglage protégé (code administrateur), enregistré tout de suite.
  Future<void> _changerScanCamera(bool v) async {
    final ok = await demanderPinAdmin(context, motif: 'Ce réglage ne peut être modifié que par l\'administrateur.');
    if (!ok || !mounted) return;
    await Provider.of<AppConfig>(context, listen: false).setReglagesProteges(scanCamera: v);
  }

  Future<void> _deverrouillerServeur() async {
    final ok = await demanderPinAdmin(context);
    if (!mounted) return;
    if (ok) {
      setState(() => _serveurDeverrouille = true);
    }
  }

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
    _sonScan = appConfig.sonScan;
    _vibrationScan = appConfig.vibrationScan;
    _quantiteScanController.text = appConfig.quantiteScanDefaut?.toString() ?? '';
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
    _quantiteScanController.dispose();
    super.dispose();
  }

  /// Teste la connectivité vers une adresse en effectuant une requête HTTP légère.
  Future<void> _testConnectivity(String address, String port) async {
    if (address.isEmpty || _isTestingConnection) return;

    String host = address.trim();
    // HTTPS accepté (non imposé) : le test garde le schéma saisi.
    final https = host.toLowerCase().startsWith('https://');
    if (host.toLowerCase().startsWith('http')) {
      host = Uri.parse(host).host;
    }
    String urlString = '${https ? 'https' : 'http'}://$host';
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

  Future<void> _saveConfiguration() async {
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    // Valeurs contrôlées : rien d'absurde n'est enregistré (port, adresse, seuils…).
    if (!(_formKey.currentState?.validate() ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuration non enregistrée : corrigez les champs en rouge.'), backgroundColor: Colors.red));
      return;
    }

    await appConfig.setApiConfig(
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

    await appConfig.setAppSettings(
      maxResult: maxResult,
      showStock: _showStockValue,
      largeValue: largeValue,
      logoutMinutes: logoutMinutes,
      exportPath: exportPath,
      sendReminderMinutes: sendReminder,
      // CORRECTION : Sauvegarde du paramètre Cumul
      isCumulEnabled: _isCumulEnabled,
    );

    final qScan = int.tryParse(_quantiteScanController.text.trim());
    await appConfig.setScanSettings(
      son: _sonScan,
      vibration: _vibrationScan,
      quantiteDefaut: qScan,
      aucuneQuantite: qScan == null,
    );

    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => InterfaceVersion.home()),
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
        child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connexion API', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (!_serveurDeverrouille)
              OutlinedButton.icon(
                onPressed: _deverrouillerServeur,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Modifier la connexion (code administrateur)'),
              )
            else
              Row(children: [
                const Icon(Icons.lock_open, color: Colors.green),
                const SizedBox(width: 6),
                const Expanded(child: Text('Connexion modifiable')),
                TextButton(onPressed: () => changerPinAdmin(context), child: const Text('Changer le code')),
              ]),
            const SizedBox(height: 16),
            const Text('Adresse Locale', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TextFormField(controller: _localAddressController, enabled: _serveurDeverrouille, validator: _siDeverrouille(SaisieInput.erreurAdresse), decoration: const InputDecoration(labelText: 'Adresse IP ou domaine', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextFormField(controller: _localPortController, enabled: _serveurDeverrouille, validator: _siDeverrouille(SaisieInput.erreurPort), decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                IconButton(icon: Icon(Icons.network_ping, color: _isTestingConnection ? Colors.grey : Theme.of(context).primaryColor), tooltip: 'Tester la connexion', onPressed: _isTestingConnection ? null : () => _testConnectivity(_localAddressController.text, _localPortController.text)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Adresse Distante', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TextFormField(controller: _distantAddressController, enabled: _serveurDeverrouille, validator: _siDeverrouille((v) => SaisieInput.erreurAdresse(v, obligatoire: false)), decoration: const InputDecoration(labelText: 'Adresse IP ou domaine', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextFormField(controller: _distantPortController, enabled: _serveurDeverrouille, validator: _siDeverrouille(SaisieInput.erreurPort), decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
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
                    validator: _siDeverrouille(SaisieInput.erreurContexte),
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
                  onPressed: _serveurDeverrouille ? () => setState(() => _isAppNameEditable = !_isAppNameEditable) : null,
                )
              ],
            ),
            const Divider(height: 40),
            Text('Paramètres de l\'application', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(controller: _maxResultController, validator: (v) => SaisieInput.erreurEntier(v, 1, 100, 'Nombre d\'inventaires'), decoration: const InputDecoration(labelText: 'Nombre d\'inventaires à afficher', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 16),
            TextFormField(controller: _largeValueController, validator: (v) => SaisieInput.erreurEntier(v, 1, SaisieInput.maxQuantite, 'Seuil'), decoration: const InputDecoration(labelText: 'Seuil d\'alerte pour grande quantité', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 16),
            TextFormField(controller: _autoLogoutController, validator: (v) => SaisieInput.erreurEntier(v, 0, 600, 'Délai'), decoration: const InputDecoration(labelText: 'Délai de déconnexion (minutes, 0=désactivé)', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 16),
            TextFormField(controller: _sendReminderController, validator: (v) => SaisieInput.erreurEntier(v, 0, 600, 'Rappel'), decoration: const InputDecoration(labelText: 'Rappel d\'envoi (minutes, 0=désactivé)', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 16),
            TextFormField(controller: _exportPathController, maxLength: 200, decoration: const InputDecoration(labelText: 'Chemin réseau pour nom de fichier (Optionnel)', hintText: 'ex: \\\\SERVEUR\\partage', border: OutlineInputBorder())),
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
            const Divider(height: 32),
            Text('Scan (douchette)', style: Theme.of(context).textTheme.titleLarge),
            SwitchListTile(
              key: const ValueKey('reglage-son-scan'),
              title: const Text('Son après un scan'),
              subtitle: const Text('Bip court : trouvé · double : déjà compté · long : erreur'),
              contentPadding: EdgeInsets.zero,
              value: _sonScan,
              onChanged: (v) => setState(() => _sonScan = v),
            ),
            SwitchListTile(
              key: const ValueKey('reglage-vibration-scan'),
              title: const Text('Vibration après un scan'),
              contentPadding: EdgeInsets.zero,
              value: _vibrationScan,
              onChanged: (v) => setState(() => _vibrationScan = v),
            ),
            SwitchListTile(
              key: const ValueKey('reglage-scan-camera'),
              title: const Text('Scan par l\'appareil photo'),
              subtitle: const Text('Téléphones sans douchette (code administrateur). Désactivé par défaut.'),
              contentPadding: EdgeInsets.zero,
              value: appConfig.scanCamera,
              onChanged: _changerScanCamera,
            ),
            Wrap(spacing: 4, children: [
              TextButton(onPressed: () => RetourScan.jouer(TypeRetour.succes, son: _sonScan, vibration: _vibrationScan), child: const Text('Essai : trouvé')),
              TextButton(onPressed: () => RetourScan.jouer(TypeRetour.dejaCompte, son: _sonScan, vibration: _vibrationScan), child: const Text('déjà compté')),
              TextButton(onPressed: () => RetourScan.jouer(TypeRetour.erreur, son: _sonScan, vibration: _vibrationScan), child: const Text('erreur')),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('reglage-quantite-scan'),
              controller: _quantiteScanController,
              validator: (v) => (v ?? '').trim().isEmpty ? null : SaisieInput.erreurEntier(v, 1, SaisieInput.maxQuantite, 'Quantité proposée'),
              decoration: const InputDecoration(
                  labelText: 'Quantité proposée après un scan (vide = aucune)',
                  helperText: 'Saisie rapide : remplacée dès qu\'on tape un chiffre',
                  border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              inputFormatters: SaisieInput.quantiteFormatters,
            ),
            const Divider(height: 32),
            // Interrupteur « Nouvelle interface » (proposé, désactivé par défaut ; code administrateur).
            const InterfaceVersionTile(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _saveConfiguration, child: const Text('VALIDER LA CONFIGURATION')),
            ),
            // Version installée (pubspec.yaml → Gradle), lue à l'exécution.
            const SizedBox(height: 16),
            const Center(child: VersionAffichee(key: ValueKey('reglages-version'))),
          ],
        ),
        ),
      ),
    );
  }
}