// lib/ui/ecrans/licence_screen.dart
// Nouvelle interface — activation de la licence. Même logique que LicenseRegisterScreen (clé
// nettoyée, LicenseProvider.registerLicense ; au retour de la Configuration, nouvelle vérification).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/lancement_screen.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:provider/provider.dart';

class NvLicenceScreen extends StatefulWidget {
  const NvLicenceScreen({super.key});

  @override
  State<NvLicenceScreen> createState() => _NvLicenceScreenState();
}

class _NvLicenceScreenState extends State<NvLicenceScreen> {
  final _cle = TextEditingController();
  bool _enCours = false;

  @override
  void dispose() {
    _cle.dispose();
    super.dispose();
  }

  ApiService _api() {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    return ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
  }

  Future<void> _activer() async {
    final cle = SaisieInput.nettoyerCleLicence(_cle.text);
    if (cle.isEmpty || _enCours) return;
    setState(() => _enCours = true);
    final licence = context.read<LicenseProvider>();
    final ok = await licence.registerLicense(_api(), cle);
    if (!mounted) return;
    setState(() => _enCours = false);
    // Succès : le statut de la licence change et main.dart affiche la connexion.
    if (!ok) nvMessage(context, licence.error ?? 'Clé invalide', ton: context.nv.erreur);
  }

  Future<void> _configuration() async {
    await Navigator.of(context).push(nvRoute(const NvConfigScreen()));
    if (!mounted) return;
    nvMessage(context, 'Reconnexion au serveur…', duree: const Duration(seconds: 1));
    context.read<LicenseProvider>().checkLicense(_api());
  }

  @override
  Widget build(BuildContext context) {
    final licence = context.watch<LicenseProvider>();
    final nv = context.nv;
    return CadreEntree(
      titre: 'Activation',
      sousTitre: 'Prestige Inventaire',
      actions: [ActionEntete(icon: Icons.settings_outlined, tooltip: 'Configuration du serveur', onPressed: _configuration)],
      enfants: [
        SoftCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.verified_user_outlined, color: nv.action, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text('Application non activée', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: nv.encre))),
            ]),
            const SizedBox(height: 8),
            Text('Saisissez la clé de licence de l\'officine pour continuer. Sans réseau, vérifiez l\'adresse du serveur dans la Configuration.',
                style: TextStyle(color: nv.gris, fontSize: 14.5)),
            if (licence.error != null) ...[
              const SizedBox(height: 12),
              Bandeau(ton: nv.erreur, icon: Icons.error_outline, texte: licence.error!),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('nv-cle-licence'),
              controller: _cle,
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
              decoration: const InputDecoration(labelText: 'Clé de licence', prefixIcon: Icon(Icons.vpn_key_outlined)),
              onSubmitted: (_) => _activer(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('nv-activer'),
              onPressed: _enCours ? null : _activer,
              child: _enCours ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Activer'),
            ),
          ]),
        ),
      ],
    );
  }
}
