// lib/widgets/chargement_erreur.dart
// Bandeaux communs (repris de prestige_vente_app, lib/widgets/sync_status.dart) : un ÉCHEC de
// chargement n'est jamais présenté comme une liste vide. Message clair + « Réessayer » ; si la session
// a expiré, « Se reconnecter » (les saisies gardées sur l'appareil ne sont pas perdues).
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/widgets/reconnexion.dart';

/// Message lisible d'une erreur de chargement.
String messageErreur(Object e) => e is ApiLoadException ? e.message : e.toString().replaceFirst('Exception: ', '');

bool estSessionExpiree(Object? e) => e is ApiLoadException && e.sessionExpiree;

/// Échec de chargement en bandeau (au-dessus d'un contenu déjà affiché).
class LoadErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool sessionExpiree;
  const LoadErrorBanner({super.key, required this.message, this.onRetry, this.sessionExpiree = false});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF5C2C2)),
        ),
        child: Row(children: [
          Icon(sessionExpiree ? Icons.lock_clock : Icons.cloud_off, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: Colors.red.shade900, fontSize: 13))),
          if (sessionExpiree)
            TextButton(
              onPressed: () async {
                if (await demanderReconnexion(context)) onRetry?.call();
              },
              child: const Text('Se reconnecter'),
            )
          else if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ]),
      );
}

/// Écran entier quand rien n'a pu être chargé (au lieu de « aucun résultat »).
class LoadErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool sessionExpiree;
  const LoadErrorView({super.key, required this.message, required this.onRetry, this.sessionExpiree = false});

  /// Construit la vue depuis l'erreur levée (session expirée reconnue).
  factory LoadErrorView.depuis(Object erreur, {Key? key, required VoidCallback onRetry}) =>
      LoadErrorView(key: key, message: messageErreur(erreur), onRetry: onRetry, sessionExpiree: estSessionExpiree(erreur));

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(sessionExpiree ? Icons.lock_clock : Icons.cloud_off, size: 56, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(sessionExpiree ? 'Session expirée' : 'Chargement impossible',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            if (sessionExpiree)
              ElevatedButton.icon(
                onPressed: () async {
                  if (await demanderReconnexion(context)) onRetry();
                },
                icon: const Icon(Icons.login),
                label: const Text('Se reconnecter'),
              )
            else
              ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ]),
        ),
      );
}
