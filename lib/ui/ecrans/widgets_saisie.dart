// lib/ui/ecrans/widgets_saisie.dart
// Nouvelle interface — éléments d'affichage partagés par la saisie guidée et le scan continu :
// champ de la douchette dans son cadre vert, journal des dernières saisies (maquette B, données de
// lib/scan/journal_scans.dart : entreesJournal), résultats d'une recherche au clavier.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/scan/champ_douchette.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/scan/journal_scans.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

/// Champ de la douchette (clé « champ-scan », comme l'écran d'origine) dans le cadre « Scanner prêt ».
class ChampScanNv extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onCode;
  final ValueChanged<String> onTexte;
  final ValueChanged<bool> onClavier;
  final String label;
  final String hint;
  const ChampScanNv({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCode,
    required this.onTexte,
    required this.onClavier,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) => CadreScan(
        champ: ChampDouchette(
          key: const ValueKey('champ-scan'),
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          label: label,
          hint: hint,
          onCode: onCode,
          onTexte: onTexte,
          onClavier: onClavier,
        ),
      );
}

TonEtat tonJournal(BuildContext context, EtatJournal e) => switch (e) {
      EtatJournal.enAttente => context.nv.attente,
      EtatJournal.envoi => context.nv.info,
      EtatJournal.envoye => context.nv.ok,
      EtatJournal.erreur => context.nv.erreur,
      EtatJournal.aVerifier => context.nv.erreur,
    };

/// Journal des dernières saisies (les plus récentes d'abord) : produit, quantité, état d'envoi ;
/// toucher une saisie la corrige ; un code sans saisie (« à vérifier ») se relance s'il le peut.
class NvJournal extends StatelessWidget {
  final String inventaireId;
  final List<ScanSansSaisie> sansSaisie;
  final ValueChanged<SaisieLigne> onCorriger;
  final ValueChanged<ScanSansSaisie> onRelancer;
  final int max;
  const NvJournal({super.key, required this.inventaireId, required this.sansSaisie, required this.onCorriger, required this.onRelancer, this.max = 10});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<SaisieQueue>();
    final entrees = entreesJournal(queue, inventaireId, sansSaisie, max: max);
    final heure = DateFormat('HH:mm');
    final nv = context.nv;
    if (entrees.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(children: [
          Icon(Icons.qr_code_scanner, size: 56, color: nv.gris.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text('Scannez le produit suivant', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: nv.gris)),
        ]),
      );
    }
    return Column(key: const ValueKey('journal-scans'), children: [
      for (final e in entrees)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LigneJournal(
            entree: e,
            heure: heure,
            onTap: e.saisie != null ? () => onCorriger(e.saisie!) : (e.scan!.aRelancer ? () => onRelancer(e.scan!) : null),
          ),
        ),
    ]);
  }
}

class _LigneJournal extends StatelessWidget {
  final EntreeJournal entree;
  final DateFormat heure;
  final VoidCallback? onTap;
  const _LigneJournal({required this.entree, required this.heure, this.onTap});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final s = entree.saisie;
    final c = entree.scan;
    final ton = tonJournal(context, entree.etat);
    final titre = s != null ? (s.nom.isEmpty ? 'Ligne ${s.ligneId}' : s.nom) : 'Code ${CodeScan.affichage(c!.code)} inconnu';
    final detail = s != null
        ? [
            heure.format(entree.quand),
            if (s.rayonLibelle != null && s.rayonLibelle!.isNotEmpty) s.rayonLibelle!,
            if (s.refusee && s.motif != null) s.motif!,
          ].join(' · ')
        : '${heure.format(entree.quand)} · ${c!.raison}';
    final etat = libelleEtat(entree.etat);
    return SoftCard(
      key: ValueKey(s != null ? 'journal-${s.ligneId}' : 'journal-code-${c!.code}-${c.quand.microsecondsSinceEpoch}'),
      onTap: onTap,
      bordure: s == null ? nv.erreur.fg.withValues(alpha: 0.45) : null,
      semantique: '$titre. ${s != null ? 'Quantité ${s.quantite}. ' : ''}$etat. $detail',
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: nv.encre)),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: nv.gris)),
          ]),
        ),
        const SizedBox(width: 8),
        if (s != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('${s.quantite}', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: nv.encre)),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 104),
          child: Pastille(etat, ton: ton, icon: entree.etat == EtatJournal.envoye ? Icons.check : null),
        ),
      ]),
    );
  }
}

/// Résultats d'une recherche au clavier (par nom ou code).
class ListeResultats extends StatelessWidget {
  final List<Product> produits;
  final bool stockVisible;
  final ValueChanged<Product> onTap;
  const ListeResultats({super.key, required this.produits, required this.stockVisible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return Container(
      color: nv.page,
      child: produits.isEmpty
          ? Center(child: Text('Aucun produit trouvé', style: TextStyle(color: nv.gris)))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: produits.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = produits[i];
                return SoftCard(
                  onTap: () => onTap(p),
                  semantique: p.produitName,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.produitName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: nv.encre)),
                    Text(
                      [
                        'CIP ${p.produitCip}',
                        if (stockVisible) 'théo. ${p.quantiteInitiale}',
                        'PV ${francs(p.produitPrixUni)}',
                      ].join(' · '),
                      style: TextStyle(color: nv.gris, fontSize: 13),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}
