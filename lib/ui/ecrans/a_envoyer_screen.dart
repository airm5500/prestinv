// lib/ui/ecrans/a_envoyer_screen.dart
// Nouvelle interface — « À envoyer » : toutes les saisies pas encore confirmées par le serveur, par
// inventaire, avec leur état (en attente / envoi / refusée et motif). Même logique que AEnvoyerScreen :
// Envoyer maintenant (SaisieQueue.envoyer), remettre en attente ou supprimer (après confirmation) une
// saisie refusée, reconnexion si la session a expiré.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

class NvAEnvoyerScreen extends StatefulWidget {
  const NvAEnvoyerScreen({super.key});

  @override
  State<NvAEnvoyerScreen> createState() => _NvAEnvoyerScreenState();
}

class _NvAEnvoyerScreenState extends State<NvAEnvoyerScreen> {
  bool _envoi = false;
  static final _heure = DateFormat('dd/MM HH:mm');

  Future<void> _envoyerTout(SaisieQueue q) async {
    setState(() => _envoi = true);
    final bilan = await q.envoyer();
    if (!mounted) return;
    setState(() => _envoi = false);
    final morceaux = <String>[
      if (bilan.envoyees > 0) '${bilan.envoyees} envoyée(s)',
      if (bilan.refusees > 0) '${bilan.refusees} refusée(s)',
      if (bilan.restantes > 0) '${bilan.restantes} toujours en attente',
      if (bilan.interruption != null) bilan.interruption!,
    ];
    nvMessage(context, morceaux.isEmpty ? 'Rien à envoyer.' : morceaux.join(' · '),
        ton: bilan.complet && bilan.refusees == 0 ? context.nv.ok : context.nv.attente);
  }

  Future<void> _supprimer(SaisieQueue q, SaisieLigne s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette saisie ?'),
        content: Text('${s.nom.isEmpty ? 'Ligne ${s.ligneId}' : s.nom}\nQuantité : ${s.quantite}\n\nElle ne sera jamais envoyée au serveur.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Supprimer', style: TextStyle(color: ctx.nv.erreur.fg))),
        ],
      ),
    );
    if (ok == true) await q.abandonner(s.cle);
  }

  @override
  Widget build(BuildContext context) {
    final q = context.watch<SaisieQueue>();
    final nv = context.nv;
    final lignes = q.lignes().where((s) => !s.envoyee).toList().reversed.toList();
    final parInventaire = <String, List<SaisieLigne>>{};
    for (final s in lignes) {
      parInventaire.putIfAbsent(s.inventaireId, () => []).add(s);
    }
    final confirmees = q.lignes().where((s) => s.envoyee).length;
    final cols = Responsive.columns(context, compact: 1, medium: 2, expanded: 2);

    return NvScaffold(
      title: 'À envoyer',
      subtitle: '$confirmees saisie(s) confirmée(s) ces 7 derniers jours',
      wide: true,
      header: [
        Row(children: [
          Expanded(child: KpiTile('${q.enAttente()}', 'En attente', highlight: q.enAttente() > 0)),
          const SizedBox(width: 8),
          Expanded(child: KpiTile('${q.refusees()}', 'Refusée(s)')),
        ]),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
        if (q.derniereErreur != null) ...[
          Bandeau(ton: nv.erreur, icon: Icons.error_outline, texte: q.derniereErreur!),
          const SizedBox(height: 10),
        ],
        if (q.sessionExpiree) ...[
          Bandeau(
            ton: nv.erreur,
            icon: Icons.lock_clock,
            texte: 'Session expirée',
            detail: 'Reconnectez-vous : les saisies repartiront ensuite.',
            action: 'Se reconnecter',
            onAction: () => demanderReconnexion(context),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          key: const ValueKey('nv-envoyer-maintenant'),
          onPressed: _envoi || q.enAttente() == 0 ? null : () => _envoyerTout(q),
          icon: _envoi ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
          label: const Text('Envoyer maintenant'),
        ),
        if (lignes.isEmpty)
          const SizedBox(height: 280, child: NvVide(icon: Icons.cloud_done_outlined, titre: 'Tout est envoyé.'))
        else
          for (final e in parInventaire.entries) ...[
            SectionTitre(e.value.first.inventaireLibelle.isNotEmpty ? e.value.first.inventaireLibelle : 'Inventaire ${e.key}',
                trailing: Pastille('${e.value.length}', ton: nv.neutre)),
            ...cardColumn([for (final s in e.value) _ligne(context, q, s)], cols, spacing: 8),
          ],
      ]),
    );
  }

  Widget _ligne(BuildContext context, SaisieQueue q, SaisieLigne s) {
    final nv = context.nv;
    final enVol = q.estEnVol(s.inventaireId, s.ligneId);
    final (String etat, TonEtat ton) = s.refusee
        ? ('refusée : ${s.motif ?? ''}', nv.erreur)
        : enVol
            ? ('envoi en cours…', nv.info)
            : (s.motif == null ? 'en attente d\'envoi' : 'en attente (${s.motif})', nv.attente);
    final rayon = s.rayonLibelle ?? (s.origine == OrigineSaisie.rapide ? 'Scan continu' : (s.rayonId != null ? 'Rayon ${s.rayonId}' : null));
    final details = [if (s.cip.isNotEmpty) 'CIP ${s.cip}', if (rayon != null) rayon, _heure.format(s.modifieLe)].join(' · ');
    return SoftCard(
      key: ValueKey('nv-a-envoyer-${s.cle}'),
      bande: ton.fg,
      semantique: '${s.nom}, quantité ${s.quantite}, $etat',
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.nom.isEmpty ? 'Ligne ${s.ligneId}' : s.nom, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: nv.encre)),
            Text(details, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: nv.gris, fontSize: 13)),
            const SizedBox(height: 4),
            Text(etat, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: ton.fg, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
        Text('${s.quantite}', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: nv.encre)),
        if (s.refusee)
          PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (v) {
              if (v == 'renvoyer') q.renvoyer(s.cle);
              if (v == 'supprimer') _supprimer(q, s);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'renvoyer', child: Text('Remettre en attente')),
              PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
            ],
          )
        else
          const SizedBox(width: 10),
      ]),
    );
  }
}
