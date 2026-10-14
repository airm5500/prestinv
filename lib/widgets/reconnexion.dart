// lib/widgets/reconnexion.dart
// Session expirée (401) : reconnexion dans une fenêtre, SANS quitter l'écran en cours. Les saisies
// gardées sur l'appareil (file persistante) ne sont pas touchées et repartent après la reconnexion.
import 'package:flutter/material.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

/// Ouvre la fenêtre de reconnexion. Renvoie `true` si la reconnexion a réussi.
Future<bool> demanderReconnexion(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ReconnexionDialog(),
  );
  if (ok == true) SaisieQueue.instance?.signalerReconnexion();
  return ok == true;
}

class ReconnexionDialog extends StatefulWidget {
  const ReconnexionDialog({super.key});

  @override
  State<ReconnexionDialog> createState() => _ReconnexionDialogState();
}

class _ReconnexionDialogState extends State<ReconnexionDialog> {
  final _login = TextEditingController();
  final _motDePasse = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _login.text = Provider.of<AuthProvider>(context, listen: false).user?.login ?? '';
  }

  @override
  void dispose() {
    _login.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    if (_login.text.trim().isEmpty || _motDePasse.text.isEmpty) {
      setState(() => _erreur = 'Identifiant et mot de passe requis.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final config = Provider.of<AppConfig>(context, listen: false);
    final ok = await auth.login(_login.text.trim(), _motDePasse.text, config);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _enCours = false;
        _erreur = auth.errorMessage ?? 'Connexion impossible.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => InterfaceVersion.useNew.value ? NvTheme(child: Builder(builder: _nouveau)) : _ancien();

  /// Nouvelle interface : même fenêtre (mêmes champs, même bouton « Se reconnecter »), nouveau style.
  Widget _nouveau(BuildContext context) => NvCadreDialogue(
        icone: Icons.lock_clock,
        ton: context.nv.attente,
        titre: 'Session expirée',
        message: 'Reconnectez-vous pour continuer. Les saisies déjà faites sont gardées sur l\'appareil.',
        contenu: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _login, decoration: const InputDecoration(labelText: 'Identifiant'), enabled: !_enCours),
          const SizedBox(height: 10),
          TextField(
            controller: _motDePasse,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mot de passe'),
            enabled: !_enCours,
            onSubmitted: (_) => _valider(),
          ),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erreur!, style: TextStyle(color: context.nv.erreur.fg, fontWeight: FontWeight.w600)),
            ),
        ]),
        boutons: nvRangeeBoutons(context, [
          nvBoutonFenetre(context, libelle: 'Annuler', genre: NvGenre.secondaire, onPressed: _enCours ? null : () => Navigator.of(context).pop(false)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Pal.amber, foregroundColor: Pal.onAmber),
            onPressed: _enCours ? null : _valider,
            child: _enCours
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Pal.onAmber))
                : const FittedBox(fit: BoxFit.scaleDown, child: Text('Se reconnecter')),
          ),
        ], const []),
      );

  Widget _ancien() => AlertDialog(
        title: const Text('Session expirée'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reconnectez-vous pour continuer. Les saisies déjà faites sont gardées sur l\'appareil.'),
            const SizedBox(height: 12),
            TextField(controller: _login, decoration: const InputDecoration(labelText: 'Identifiant'), enabled: !_enCours),
            const SizedBox(height: 8),
            TextField(
              controller: _motDePasse,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
              enabled: !_enCours,
              onSubmitted: (_) => _valider(),
            ),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erreur!, style: TextStyle(color: Colors.red.shade800)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: _enCours ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: _enCours ? null : _valider,
            child: _enCours
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Se reconnecter'),
          ),
        ],
      );
}
