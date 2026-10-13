// lib/utils/app_utils.dart

import 'package:flutter/material.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';

/// Affiche une boîte de dialogue de progression centrée qui écoute les changements
/// d'un ValueNotifier pour mettre à jour son message en temps réel.
void showProgressDialog(BuildContext context, ValueNotifier<String> progressNotifier) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: progressNotifier,
          builder: (context, value, child) {
            // Affiche une icône de succès quand le message ne contient plus "Envoi"
            bool isFinished = !value.toLowerCase().contains('envoi');
            return Row(
              children: [
                if (isFinished)
                  const Icon(Icons.check_circle, color: Colors.green, size: 28)
                else
                  const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(child: Text(value)),
              ],
            );
          },
        ),
      );
    },
  );
}

/// Gère la déconnexion de l'utilisateur.
/// Vérifie s'il y a des données non envoyées et demande confirmation avant de continuer.
Future<void> performLogout(BuildContext context) async {
  final saisies = SaisieQueue.instance;
  final entryProvider = Provider.of<EntryProvider>(context, listen: false);
  final enAttente = saisies != null ? saisies.aTraiter() : (entryProvider.hasUnsyncedData ? 1 : 0);

  bool shouldLogout = true;
  // Des saisies ne sont pas encore confirmées par le serveur : elles restent enregistrées sur
  // l'appareil (file persistante) et repartiront à la prochaine connexion.
  if (enAttente > 0) {
    if (!context.mounted) return;

    shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Données non envoyées'),
        content: Text(saisies != null
            ? '$enAttente saisie(s) ne sont pas encore enregistrée(s) sur le serveur. Elles restent gardées sur cet appareil '
                '(Accueil → « À envoyer ») et repartiront à la prochaine connexion. Voulez-vous vous déconnecter ?'
            : 'Certaines modifications n\'ont pas été envoyées au serveur. Voulez-vous continuer ?'),
        actions: [
          TextButton(
            child: const Text('ANNULER'),
            onPressed: () => Navigator.of(ctx).pop(false), // L'utilisateur ne veut pas se déconnecter
          ),
          TextButton(
            child: const Text('OUI, QUITTER'),
            onPressed: () => Navigator.of(ctx).pop(true), // L'utilisateur confirme la déconnexion
          ),
        ],
      ),
    ) ?? false; // Si l'utilisateur ferme la pop-up, on considère 'false'
  }

  // Si l'utilisateur a cliqué sur "ANNULER", ou si le contexte n'est plus valide après le dialogue, on ne fait rien
  if (!shouldLogout || !context.mounted) return;

  // On procède à la déconnexion
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final appConfig = Provider.of<AppConfig>(context, listen: false);

  await authProvider.logout(appConfig);

  // On s'assure une dernière fois que le widget est toujours "monté" avant de naviguer
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false,
    );
  }
}