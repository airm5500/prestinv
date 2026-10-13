// lib/ui/ecrans/connexion_screen.dart
// Nouvelle interface — connexion. Même logique que l'écran d'origine (LoginScreen) : identifiants
// mémorisés (« Rester connecté », mot de passe dans le stockage sécurisé), AuthProvider.login,
// choix Local / Distant, accès à la Configuration ; succès → accueil (InterfaceVersion.home()).
import 'package:flutter/material.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/lancement_screen.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NvConnexionScreen extends StatefulWidget {
  const NvConnexionScreen({super.key});

  @override
  State<NvConnexionScreen> createState() => _NvConnexionScreenState();
}

class _NvConnexionScreenState extends State<NvConnexionScreen> {
  final _login = TextEditingController();
  final _motDePasse = TextEditingController();
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _chargerIdentifiants();
  }

  Future<void> _chargerIdentifiants() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.rememberMe) {
      _login.text = prefs.getString('savedLogin') ?? '';
      final mdp = await IdentifiantsSecurises.instance.lire();
      if (!mounted) return;
      _motDePasse.text = mdp ?? '';
    }
  }

  @override
  void dispose() {
    _login.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    final auth = context.read<AuthProvider>();
    final config = context.read<AppConfig>();
    final ok = await auth.login(_login.text.trim(), _motDePasse.text.trim(), config);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InterfaceVersion.home()));
    } else {
      nvMessage(context, auth.errorMessage ?? 'Une erreur est survenue.', ton: context.nv.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final auth = context.watch<AuthProvider>();
    final config = context.watch<AppConfig>();
    final local = config.apiMode == ApiMode.local;
    return CadreEntree(
      titre: 'Prestige Inventaire',
      sousTitre: 'Connexion',
      actions: [
        ActionEntete(
          icon: Icons.settings_outlined,
          tooltip: 'Configuration',
          onPressed: () => Navigator.of(context).push(nvRoute(const NvConfigScreen())),
        ),
      ],
      enfants: [
        SoftCard(
          padding: const EdgeInsets.all(18),
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Bonjour', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: nv.encre)),
              Text('Identifiez-vous pour compter le stock.', style: TextStyle(color: nv.gris)),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('nv-identifiant'),
                controller: _login,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Identifiant', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('nv-mot-de-passe'),
                controller: _motDePasse,
                obscureText: !_visible,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _visible ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
                    icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _visible = !_visible),
                  ),
                ),
                onSubmitted: (_) => _connecter(),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                title: const Text('Rester connecté'),
                value: auth.rememberMe,
                onChanged: (v) => auth.setRememberMe(v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('nv-connexion'),
                onPressed: auth.isLoading ? null : _connecter,
                child: auth.isLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Connexion'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        SoftCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: SwitchListTile(
            key: const ValueKey('nv-mode-connexion'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Mode de connexion'),
            subtitle: Text(local ? 'Local (Wi-Fi de l\'officine)' : 'Distant'),
            value: local,
            onChanged: (v) => config.setApiMode(v ? ApiMode.local : ApiMode.distant),
          ),
        ),
      ],
    );
  }
}
