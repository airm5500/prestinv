// lib/widgets/bandeau_attente_serveur.dart
// 5.0.2 — Bandeau NON BLOQUANT des deux interfaces : « N saisies en attente d'envoi (serveur injoignable) ».
// Affiché seulement quand des saisies attendent ET que le dernier essai d'envoi n'a pas eu de réponse utilisable
// du serveur (éteint, injoignable, 5xx, délai dépassé). Il ne prend pas le focus et n'interrompt pas la saisie :
// les quantités sont gardées sur l'appareil et partent seules au retour du serveur (SaisieQueue).
// 5.0.4 : heure du serveur fausse (refus 423) → « N saisies en attente d'envoi. » suivi du message du serveur, tel quel.
import 'package:flutter/material.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

class BandeauAttenteServeur extends StatelessWidget {
  /// File observée (par défaut : celle de l'application, fournie par Provider).
  final SaisieQueue? file;
  const BandeauAttenteServeur({super.key, this.file});

  @override
  Widget build(BuildContext context) {
    SaisieQueue? q = file;
    if (q == null) {
      try {
        q = Provider.of<SaisieQueue>(context, listen: false);
      } catch (_) {
        q = null; // écran monté sans file (tests, aperçus) : rien à afficher
      }
    }
    final queue = q;
    if (queue == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final texte = queue.messageAttenteServeur;
        if (texte == null) return const SizedBox.shrink();
        // 5.0.4 : heure du serveur fausse : le message du serveur, tel quel, en entier (plus long).
        final horloge = queue.horlogeServeurBloquee;
        final ton = context.nv.attente;
        return Semantics(
          liveRegion: true,
          container: true,
          label: texte,
          child: ExcludeSemantics(
            child: Container(
              key: const ValueKey('bandeau-attente-serveur'),
              width: double.infinity,
              color: ton.bg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Icon(horloge ? Icons.schedule : Icons.cloud_off, size: 18, color: ton.fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(texte,
                      maxLines: horloge ? 6 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ton.fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
