// lib/screens/a_envoyer_screen.dart
// « À envoyer » : TOUTES les saisies pas encore confirmées par le serveur, tous inventaires et tous
// rayons confondus (avant, elles n'étaient visibles qu'en rouvrant le bon rayon). États : en attente,
// envoi en cours, refusée (avec le motif, ex. inventaire clôturé). Envoi manuel de tout, renvoi ou
// suppression (après confirmation) d'une saisie refusée.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:provider/provider.dart';

class AEnvoyerScreen extends StatefulWidget {
  const AEnvoyerScreen({super.key});

  @override
  State<AEnvoyerScreen> createState() => _AEnvoyerScreenState();
}

class _AEnvoyerScreenState extends State<AEnvoyerScreen> {
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: bilan.complet && bilan.refusees == 0 ? Colors.green : Colors.orange.shade800,
      content: Text(morceaux.isEmpty ? 'Rien à envoyer.' : morceaux.join(' · ')),
    ));
  }

  Future<void> _supprimer(SaisieQueue q, SaisieLigne s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette saisie ?'),
        content: Text('${s.nom.isEmpty ? 'Ligne ${s.ligneId}' : s.nom}\nQuantité : ${s.quantite}\n\n'
            'Elle ne sera jamais envoyée au serveur.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) await q.abandonner(s.cle);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SaisieQueue>(builder: (context, q, _) {
      final lignes = q.lignes().where((s) => !s.envoyee).toList();
      final parInventaire = <String, List<SaisieLigne>>{};
      for (final s in lignes) {
        parInventaire.putIfAbsent(s.inventaireId, () => []).add(s);
      }
      final envoyeesRecentes = q.lignes().where((s) => s.envoyee).length;
      return Scaffold(
        appBar: AppBar(title: const Text('À envoyer')),
        body: Column(children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${q.enAttente()} en attente · ${q.refusees()} refusée(s)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('$envoyeesRecentes saisie(s) confirmée(s) par le serveur ces 7 derniers jours.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              if (q.derniereErreur != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(q.derniereErreur!, style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
                ),
              if (q.sessionExpiree)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Session expirée : reconnectez-vous, les saisies repartiront ensuite.',
                      style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _envoi || q.enAttente() == 0 ? null : () => _envoyerTout(q),
                  icon: _envoi
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload),
                  label: const Text('Envoyer maintenant'),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: lignes.isEmpty
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_done, size: 64, color: Colors.green),
                      SizedBox(height: 12),
                      Text('Tout est envoyé.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ]),
                  )
                : ListView(children: [
                    for (final e in parInventaire.entries) ...[
                      Container(
                        color: Colors.grey.shade200,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(
                          e.value.first.inventaireLibelle.isNotEmpty ? e.value.first.inventaireLibelle : 'Inventaire ${e.key}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final s in e.value) _ligne(q, s),
                    ],
                  ]),
          ),
        ]),
      );
    });
  }

  Widget _ligne(SaisieQueue q, SaisieLigne s) {
    final enVol = q.estEnVol(s.inventaireId, s.ligneId);
    final String etat;
    final Color couleur;
    final IconData icone;
    if (s.refusee) {
      etat = 'Refusée : ${s.motif ?? ''}';
      couleur = Colors.red.shade800;
      icone = Icons.block;
    } else if (enVol) {
      etat = 'Envoi en cours…';
      couleur = Colors.blue.shade800;
      icone = Icons.cloud_upload;
    } else {
      etat = s.motif == null ? 'En attente d\'envoi' : 'En attente (${s.motif})';
      couleur = Colors.orange.shade900;
      icone = Icons.schedule;
    }
    final rayon = s.rayonLibelle ??
        (s.origine == OrigineSaisie.rapide ? 'Saisie rapide' : (s.rayonId != null ? 'Rayon ${s.rayonId}' : null));
    final details = [
      if (s.cip.isNotEmpty) 'CIP ${s.cip}',
      if (rayon != null) rayon,
      _heure.format(s.modifieLe),
    ].join(' · ');
    return ListTile(
      leading: Icon(icone, color: couleur),
      title: Text(s.nom.isEmpty ? 'Ligne ${s.ligneId}' : s.nom, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$details\n$etat',
          style: TextStyle(color: couleur, fontSize: 12)),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${s.quantite}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
          ),
      ]),
    );
  }
}

/// Bandeau de l'accueil : saisies pas encore confirmées par le serveur (tous rayons). Invisible si 0.
class AEnvoyerBandeau extends StatelessWidget {
  const AEnvoyerBandeau({super.key});

  @override
  Widget build(BuildContext context) {
    final SaisieQueue q;
    try {
      q = Provider.of<SaisieQueue>(context);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final n = q.aTraiter();
    if (n == 0) return const SizedBox.shrink();
    final refusees = q.refusees();
    return Material(
      color: refusees > 0 ? Colors.red.shade50 : Colors.orange.shade50,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AEnvoyerScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(refusees > 0 ? Icons.sync_problem : Icons.cloud_upload, color: refusees > 0 ? Colors.red.shade800 : Colors.orange.shade900),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$n saisie(s) à envoyer${refusees > 0 ? ' dont $refusees refusée(s)' : ''}',
                style: TextStyle(fontWeight: FontWeight.bold, color: refusees > 0 ? Colors.red.shade900 : Colors.orange.shade900),
              ),
            ),
            const Text('Voir'),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
