// lib/ui/etats.dart
// États communs de la nouvelle interface : chargement, échec (jamais présenté comme une liste vide,
// « Réessayer » ou « Se reconnecter » si la session a expiré — même logique que
// lib/widgets/chargement_erreur.dart), liste vide.
import 'package:flutter/material.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:prestinv/widgets/reconnexion.dart';

class NvChargement extends StatelessWidget {
  final String? texte;
  const NvChargement({super.key, this.texte});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (texte != null) ...[const SizedBox(height: 12), Text(texte!, style: TextStyle(color: context.nv.gris))],
        ]),
      );
}

/// Échec de chargement (écran entier).
class NvErreur extends StatelessWidget {
  final Object erreur;
  final VoidCallback onRetry;
  const NvErreur(this.erreur, {super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final session = estSessionExpiree(erreur);
    final ton = context.nv.erreur;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SoftCard(
          fond: ton.bg,
          bordure: ton.fg.withValues(alpha: 0.35),
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(session ? Icons.lock_clock : Icons.cloud_off, color: ton.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(session ? 'Session expirée' : 'Chargement impossible',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ton.fg)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(messageErreur(erreur), style: TextStyle(color: ton.fg, fontSize: 15)),
            const SizedBox(height: 4),
            Text('Vos saisies restent enregistrées sur ce téléphone.', style: TextStyle(color: ton.fg, fontSize: 13)),
            const SizedBox(height: 14),
            if (session)
              ElevatedButton.icon(
                key: const ValueKey('nv-reconnecter'),
                onPressed: () async {
                  if (await demanderReconnexion(context)) onRetry();
                },
                icon: const Icon(Icons.login),
                label: const Text('Se reconnecter'),
              )
            else
              ElevatedButton.icon(key: const ValueKey('nv-reessayer'), onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ]),
        ),
      ),
    );
  }
}

class NvVide extends StatelessWidget {
  final IconData icon;
  final String titre;
  final String? detail;
  const NvVide({super.key, required this.icon, required this.titre, this.detail});

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: context.nv.gris.withValues(alpha: 0.6)),
            const SizedBox(height: 10),
            Text(titre, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: context.nv.encre)),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail!, textAlign: TextAlign.center, style: TextStyle(color: context.nv.gris)),
            ],
          ]),
        ),
      );
}

/// Libère des contrôleurs quand le widget quitte l'écran (après l'animation de fermeture d'une fenêtre).
class LibererApres extends StatefulWidget {
  final List<ChangeNotifier> objets;
  final Widget child;
  const LibererApres({super.key, required this.objets, required this.child});

  @override
  State<LibererApres> createState() => _LibererApresState();
}

class _LibererApresState extends State<LibererApres> {
  @override
  void dispose() {
    for (final o in widget.objets) {
      o.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Message court en bas d'écran (couleur d'état + libellé).
void nvMessage(BuildContext context, String texte, {TonEtat? ton, SnackBarAction? action, Duration duree = const Duration(seconds: 3), Key? key}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  final t = ton ?? context.nv.info;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    key: key,
    duration: duree,
    backgroundColor: t.bg,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.fg.withValues(alpha: 0.35))),
    action: action,
    content: Text(texte, style: TextStyle(color: t.fg, fontWeight: FontWeight.w600)),
  ));
}
