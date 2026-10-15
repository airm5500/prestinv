// lib/screens/serveur_injoignable_screen.dart
// Premier lancement sans joindre le serveur (aucune licence en cache) : ce n'est PAS un problème de
// licence. Message clair, « Réessayer », réessai automatique toutes les 10 s, accès à la Configuration
// (adresse du serveur). Même principe que lancement_screen.dart de prestige_vente_app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:provider/provider.dart';

class ServeurInjoignableScreen extends StatefulWidget {
  /// Relance la vérification (licence = premier contact avec le serveur).
  final Future<void> Function() reessayer;
  final Duration intervalle;
  const ServeurInjoignableScreen({super.key, required this.reessayer, this.intervalle = const Duration(seconds: 10)});

  @override
  State<ServeurInjoignableScreen> createState() => _ServeurInjoignableScreenState();
}

class _ServeurInjoignableScreenState extends State<ServeurInjoignableScreen> {
  Timer? _minuterie;
  late int _reste = widget.intervalle.inSeconds;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _minuterie = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _enCours) return;
      setState(() => _reste--);
      if (_reste <= 0) _essayer();
    });
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _essayer() async {
    if (_enCours) return;
    setState(() => _enCours = true);
    await widget.reessayer();
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _reste = widget.intervalle.inSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<AppConfig>(context);
    final licence = Provider.of<LicenseProvider>(context);
    final adresse = config.currentApiUrl.isEmpty ? 'non configurée' : config.currentApiUrl;
    final indisponible = (licence.error ?? '').startsWith('Serveur indisponible');
    return Scaffold(
      appBar: AppBar(title: const Text('Prestige Inventaire')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 72, color: Colors.orange.shade800),
            const SizedBox(height: 16),
            // 4.15.3 (retour du pharmacien) : « Serveur indisponible » (Prestige en démarrage / redéploiement) ≠
            // « Serveur injoignable » (aucune réponse). Le cas « certificat » garde le titre d'origine (A7).
            Text(indisponible ? 'Serveur indisponible' : 'Serveur injoignable', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              indisponible
                  ? '${ApiService.messageIndisponible}\nServeur : $adresse. Ce n\'est pas un problème de licence.'
                  : 'L\'application n\'arrive pas à joindre le serveur Prestige ($adresse).\n'
                      'Ce n\'est pas un problème de licence : vérifiez le Wi-Fi, que le PC serveur est allumé et l\'adresse dans la Configuration.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (licence.error != null && !indisponible) ...[
              const SizedBox(height: 8),
              Text(licence.error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Text(_enCours ? 'Connexion en cours…' : 'Nouvel essai automatique dans $_reste s',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _enCours ? null : _essayer,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfigScreen()));
                if (mounted) _essayer();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Configuration'),
            ),
          ]),
        ),
      ),
    );
  }
}
