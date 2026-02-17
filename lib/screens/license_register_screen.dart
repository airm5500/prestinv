// lib/screens/license_register_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/screens/config_screen.dart'; // Utile pour régler l'IP si ça ne marche pas

class LicenseRegisterScreen extends StatefulWidget {
  const LicenseRegisterScreen({super.key});

  @override
  State<LicenseRegisterScreen> createState() => _LicenseRegisterScreenState();
}

class _LicenseRegisterScreenState extends State<LicenseRegisterScreen> {
  final _keyController = TextEditingController();
  bool _isSubmitting = false;

  void _submitKey() async {
    if (_keyController.text.trim().isEmpty) return;

    setState(() => _isSubmitting = true);

    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final licenseProvider = Provider.of<LicenseProvider>(context, listen: false);

    final api = ApiService(
      baseUrl: appConfig.currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );

    final success = await licenseProvider.registerLicense(api, _keyController.text.trim());

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(licenseProvider.error ?? "Clé invalide"), backgroundColor: Colors.red),
        );
      }
      // Si succès, le Provider changera de statut et le Wrapper dans main.dart nous redirigera automatiquement.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Activation Licence"),
        actions: [
          // Accès config au cas où l'URL API est mauvaise
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfigScreen())),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified_user_outlined, size: 80, color: Colors.blueGrey),
            const SizedBox(height: 24),
            const Text(
              "Application non activée",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              "Veuillez saisir votre clé de licence pour continuer",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: "Clé de licence",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitKey,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("ACTIVER"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}