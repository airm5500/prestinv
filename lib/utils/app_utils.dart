// lib/utils/app_utils.dart

import 'package:flutter/material.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:provider/provider.dart';

/// Affiche une boîte de dialogue de progression centrée qui écoute les changements
/// d'un ValueNotifier pour mettre à jour son message.
void showProgressDialog(BuildContext context, ValueNotifier<String> progressNotifier) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: progressNotifier,
          builder: (context, value, child) {
            // On peut ajouter une icône de succès à la fin
            bool isFinished = !value.toLowerCase().contains('envoi');
            return Row(
              children: [
                if (isFinished)
                  const Icon(Icons.check_circle, color: Colors.green)
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

/// Gère la déconnexion de l'utilisateur et la navigation vers l'écran de connexion.
void performLogout(BuildContext context) {
  // On récupère les providers nécessaires sans écouter les changements
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final appConfig = Provider.of<AppConfig>(context, listen: false);

  // On appelle la méthode de déconnexion
  authProvider.logout(appConfig);

  // On navigue vers l'écran de connexion et on supprime l'historique de navigation
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
  );
}