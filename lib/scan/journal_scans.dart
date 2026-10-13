// lib/scan/journal_scans.dart
// Journal des dernières saisies du scan continu (maquette B) : les 10 dernières, avec le produit, la
// quantité et l'état d'envoi (en attente / envoi… / envoyé / erreur), et les codes introuvables « à
// vérifier ». Toucher une saisie la corrige ; « Corriger la dernière » corrige la plus récente.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:provider/provider.dart';

/// Code lu qui n'a pas abouti à une saisie (introuvable, recherche impossible).
class ScanSansSaisie {
  final String code;
  final DateTime quand;

  /// Raison affichée (« pas dans cet inventaire », « serveur injoignable »…).
  final String raison;

  /// Recherche impossible (réseau) : toucher la ligne relance la recherche.
  final bool aRelancer;
  const ScanSansSaisie(this.code, this.quand, this.raison, {this.aRelancer = false});
}

enum EtatJournal { enAttente, envoi, envoye, erreur, aVerifier }

class EntreeJournal {
  final DateTime quand;
  final EtatJournal etat;
  final SaisieLigne? saisie;
  final ScanSansSaisie? scan;
  const EntreeJournal.saisie(SaisieLigne s, this.quand, this.etat)
      : saisie = s,
        scan = null;
  EntreeJournal.scan(ScanSansSaisie s)
      : saisie = null,
        scan = s,
        quand = s.quand,
        etat = EtatJournal.aVerifier;
}

/// Les [max] dernières entrées (saisies de l'inventaire + codes sans saisie), la plus récente d'abord.
List<EntreeJournal> entreesJournal(SaisieQueue queue, String inventaireId, List<ScanSansSaisie> sansSaisie, {int max = 10}) {
  final entrees = <EntreeJournal>[
    for (final s in queue.lignes(inventaireId: inventaireId))
      EntreeJournal.saisie(
          s,
          s.modifieLe,
          s.envoyee
              ? EtatJournal.envoye
              : s.refusee
                  ? EtatJournal.erreur
                  : queue.estEnVol(inventaireId, s.ligneId)
                      ? EtatJournal.envoi
                      : EtatJournal.enAttente),
    for (final c in sansSaisie) EntreeJournal.scan(c),
  ]..sort((a, b) => b.quand.compareTo(a.quand));
  return entrees.take(max).toList();
}

String libelleEtat(EtatJournal e) => switch (e) {
      EtatJournal.enAttente => 'en attente',
      EtatJournal.envoi => 'envoi…',
      EtatJournal.envoye => 'envoyé',
      EtatJournal.erreur => 'erreur',
      EtatJournal.aVerifier => 'à vérifier',
    };

Color couleurEtat(EtatJournal e) => switch (e) {
      EtatJournal.enAttente => Colors.orange.shade800,
      EtatJournal.envoi => Colors.blue.shade700,
      EtatJournal.envoye => Colors.green.shade700,
      EtatJournal.erreur => Colors.red.shade700,
      EtatJournal.aVerifier => Colors.red.shade700,
    };

class JournalScans extends StatelessWidget {
  final String inventaireId;
  final List<ScanSansSaisie> sansSaisie;
  final ValueChanged<SaisieLigne> onCorriger;
  final ValueChanged<ScanSansSaisie>? onRelancer;

  /// Scans lus mais pas encore traités (rafale).
  final int scansEnAttente;
  final int max;

  const JournalScans({
    super.key,
    required this.inventaireId,
    required this.sansSaisie,
    required this.onCorriger,
    this.onRelancer,
    this.scansEnAttente = 0,
    this.max = 10,
  });

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<SaisieQueue>();
    final entrees = entreesJournal(queue, inventaireId, sansSaisie, max: max);
    final derniere = entrees.where((e) => e.saisie != null).firstOrNull;
    final enAttente = queue.enAttente(inventaireId: inventaireId);
    final envoyees = queue.lignes(inventaireId: inventaireId).where((s) => s.envoyee).length;
    final heure = DateFormat('HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                '$enAttente en attente · $envoyees envoyée(s)${scansEnAttente > 0 ? ' · $scansEnAttente scan(s) à traiter' : ''}',
                key: const ValueKey('journal-resume'),
                style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (derniere != null)
              TextButton.icon(
                key: const ValueKey('corriger-derniere'),
                onPressed: () => onCorriger(derniere.saisie!),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Corriger la dernière'),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Text('Dernières saisies', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
        Expanded(
          child: entrees.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    const Text('Scannez le produit suivant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                  ]),
                )
              : ListView.separated(
                  key: const ValueKey('journal-scans'),
                  itemCount: entrees.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = entrees[i];
                    final s = e.saisie;
                    final c = e.scan;
                    final titre = s != null ? (s.nom.isEmpty ? 'Ligne ${s.ligneId}' : s.nom) : 'Code ${CodeScan.affichage(c!.code)}';
                    final detail = s != null
                        ? '${heure.format(e.quand)} · ${s.cip}${s.rayonLibelle != null && s.rayonLibelle!.isNotEmpty ? ' · ${s.rayonLibelle}' : ''}'
                            '${s.refusee && s.motif != null ? '\n${s.motif}' : ''}'
                        : '${heure.format(e.quand)} · ${c!.raison}';
                    return InkWell(
                      key: ValueKey(s != null ? 'journal-${s.ligneId}' : 'journal-code-${c!.code}-${c.quand.microsecondsSinceEpoch}'),
                      onTap: s != null ? () => onCorriger(s) : (c!.aRelancer && onRelancer != null ? () => onRelancer!(c) : null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              if (s != null) Text('${s.quantite}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                if (e.etat == EtatJournal.envoye) Icon(Icons.check, size: 14, color: couleurEtat(e.etat)),
                                Flexible(
                                  child: Text(libelleEtat(e.etat),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: couleurEtat(e.etat))),
                                ),
                              ]),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
