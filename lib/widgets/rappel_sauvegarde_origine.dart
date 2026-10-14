// lib/widgets/rappel_sauvegarde_origine.dart
// Rappel BLOQUANT « Veuillez sauvegarder vos saisies » et progression d'envoi AU STYLE DE L'ANCIENNE
// INTERFACE (AlertDialog du thème d'origine, mêmes textes que l'envoi de la saisie guidée d'origine).
// Utilisés par le garde-fou global (lib/saisie/rappel_envoi.dart, branché dans main.dart) quand
// l'ancienne interface est active (4.13.1) : il remplace le rappel d'origine de la saisie guidée
// (bandeau de 5 s), pour ne pas doubler les messages. La nouvelle interface garde nvRappelSauvegarde /
// nvEnvoiSaisies (lib/ui/dialogues.dart).
import 'package:flutter/material.dart';
import 'package:prestinv/saisie/saisie_queue.dart';

/// Message bloquant (le retour arrière ne le ferme pas) ; se termine sur « Envoyer maintenant ».
Future<void> origineRappelSauvegarde(BuildContext context, {required int nombre, required Duration depuis}) {
  final minutes = depuis.inMinutes;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('origine-rappel-sauvegarde'),
        title: const Text('⚠️ Veuillez sauvegarder vos saisies'),
        content: Text(
          '$nombre saisie(s) attendent depuis ${minutes < 1 ? 'moins d\'une minute' : '$minutes min'} (délai réglé dans les paramètres). '
          'Envoyez-les maintenant pour ne pas les perdre.\n\n'
          'Ce message revient tant que les saisies n\'ont pas été envoyées.',
        ),
        actions: [
          ElevatedButton(
            key: const ValueKey('origine-rappel-envoyer'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Envoyer maintenant'),
          ),
        ],
      ),
    ),
  );
}

/// Envoi avec la progression d'origine (« Envoi... (3/7) », puis bilan affiché 2,5 s).
Future<BilanEnvoi> origineEnvoiSaisies(
  BuildContext context, {
  required Future<BilanEnvoi> Function(void Function(int fait, int total) progression) envoyer,
  required int demandees,
}) async {
  final message = ValueNotifier<String>('Connexion au serveur...');
  final nav = Navigator.of(context);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('origine-envoi-saisies'),
        content: ValueListenableBuilder<String>(
          valueListenable: message,
          builder: (context, value, _) {
            final fini = !value.toLowerCase().contains('envoi') && !value.startsWith('Connexion');
            return Row(children: [
              if (fini) const Icon(Icons.check_circle, color: Colors.green, size: 28) else const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(value)),
            ]);
          },
        ),
      ),
    ),
  );
  nav.push(route);
  final bilan = await envoyer((a, b) => message.value = 'Envoi... ($a/$b)');
  if (bilan.complet && bilan.refusees == 0) {
    message.value = '✅ ${bilan.envoyees} article(s) traité(s) avec succès.';
  } else if (bilan.sessionExpiree) {
    message.value = '❌ ${SaisieQueue.messageSessionExpiree}';
  } else if (bilan.envoyees > 0) {
    message.value = '⚠️ Réseau instable : ${bilan.envoyees}/$demandees envoyé(s). Le reste est gardé sur l\'appareil (« À envoyer »).';
  } else if (bilan.refusees > 0 && bilan.interruption == null) {
    message.value = '❌ ${bilan.refusees} saisie(s) refusée(s) par le serveur (voir « À envoyer »).';
  } else {
    message.value = '❌ Échec : ${bilan.interruption ?? 'Vérifiez votre connexion au serveur.'} Les saisies restent sur l\'appareil.';
  }
  await Future<void>.delayed(const Duration(milliseconds: 2500));
  if (route.isActive) nav.removeRoute(route);
  Future<void>.delayed(const Duration(seconds: 1), message.dispose);
  return bilan;
}
