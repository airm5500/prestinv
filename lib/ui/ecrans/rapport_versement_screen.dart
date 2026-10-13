// lib/ui/ecrans/rapport_versement_screen.dart
// Nouvelle interface — rapport d'un versement de la collecte : compteurs, détail par catégorie (codes
// non reconnus en tête, avec quantité et raison), export PDF / CSV et partage, « Reprendre » si des
// lignes restent. Mêmes documents que RapportVersementScreen (rapportPdf, rapportCsv).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prestinv/collecte/rapport_versement.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/ui/ecrans/versement_screen.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:share_plus/share_plus.dart';

class NvRapportVersementScreen extends StatelessWidget {
  final Versement versement;

  /// Tests : dossier des fichiers exportés (sinon dossier temporaire de l'application).
  static Future<Directory> Function() dossierExport = getTemporaryDirectory;

  const NvRapportVersementScreen({super.key, required this.versement});

  Future<void> _exporter(BuildContext context, {required bool pdf, required bool csv}) async {
    try {
      final nom = nomFichierRapport(versement);
      final d = await dossierExport();
      final fichiers = <XFile>[];
      if (pdf) {
        final f = File('${d.path}/$nom.pdf');
        await f.writeAsBytes(await rapportPdf(versement), flush: true);
        fichiers.add(XFile(f.path, mimeType: 'application/pdf'));
      }
      if (csv) {
        final f = File('${d.path}/$nom.csv');
        await f.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(rapportCsv(versement))], flush: true);
        fichiers.add(XFile(f.path, mimeType: 'text/csv'));
      }
      await NvExports.partager(fichiers, resumeVersement(versement));
    } catch (e) {
      if (context.mounted) nvMessage(context, 'Export impossible : $e', ton: context.nv.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = versement;
    final nv = context.nv;
    final date = DateFormat('dd/MM/yyyy HH:mm');
    Widget compteur(String l, int n, TonEtat ton, Key k) => Container(
          key: k,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: ton.bg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ton.fg)),
            Text(l, maxLines: 2, style: TextStyle(fontSize: 12.5, color: ton.fg)),
          ]),
        );
    Widget section(String titre, List<LigneVersement> ls, {bool ouverte = false, Key? key}) => ls.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SoftCard(
              padding: EdgeInsets.zero,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: key,
                  initiallyExpanded: ouverte,
                  title: Text('$titre (${ls.length})', style: TextStyle(fontWeight: FontWeight.bold, color: nv.encre)),
                  children: [
                    for (final l in ls)
                      ListTile(
                        dense: true,
                        title: Text(l.nom.isEmpty ? 'Code ${CodeScan.affichage(l.code)}' : l.nom, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            'code ${CodeScan.affichage(l.code)}',
                            'collecté ${l.quantiteCollectee}',
                            if (l.quantiteExistante != null) 'déjà compté ${l.quantiteExistante}',
                            if (l.etat == EtatLigneVersement.versee && l.quantiteCible != null) 'envoyé ${l.quantiteCible}',
                            if (l.raison != null) l.raison!,
                          ].join(' · '),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
    final compteurs = [
      compteur('versés', v.nouvelles.length, nv.ok, const ValueKey('nb-verses')),
      compteur('déjà comptés remplacés', v.remplacees.length, nv.info, const ValueKey('nb-remplaces')),
      compteur('déjà comptés ajoutés', v.ajoutees.length, nv.info, const ValueKey('nb-ajoutes')),
      compteur('codes non reconnus', v.nonReconnues.length, nv.erreur, const ValueKey('nb-non-reconnus')),
      compteur('erreurs', v.erreurs.length, nv.erreur, const ValueKey('nb-erreurs')),
      if (v.aVerser.isNotEmpty) compteur('à verser', v.aVerser.length, nv.attente, const ValueKey('nb-a-verser')),
    ];
    final cols = Responsive.columns(context, compact: 2, medium: 3, expanded: 6);
    return NvScaffold(
      title: 'Rapport de versement',
      subtitle: '« ${v.inventaireLibelle} » · ${date.format(v.debut)}',
      wide: true,
      actions: [
        ActionEntete(icon: Icons.picture_as_pdf_outlined, tooltip: 'PDF', onPressed: () => _exporter(context, pdf: true, csv: false)),
        ActionEntete(icon: Icons.table_view_outlined, tooltip: 'CSV', onPressed: () => _exporter(context, pdf: false, csv: true)),
        ActionEntete(icon: Icons.share_outlined, tooltip: 'Partager', onPressed: () => _exporter(context, pdf: true, csv: true)),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
        Text('Déjà comptés : ${v.mode.libelle} · ${libelleStatut(v)}', style: TextStyle(color: nv.gris, fontSize: 14.5)),
        const SizedBox(height: 10),
        if (v.interruption != null) ...[
          Bandeau(key: const ValueKey('interruption-versement'), ton: nv.attente, icon: Icons.warning_amber, texte: v.interruption!),
          const SizedBox(height: 10),
        ],
        ...cardRows(compteurs, cols, gap: 8).map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: r)),
        if (!v.complet) ...[
          const SizedBox(height: 4),
          FilledButton.icon(
            key: const ValueKey('reprendre-versement'),
            onPressed: () => Navigator.of(context).pushReplacement(nvRoute(NvVersementScreen(reprise: v))),
            icon: const Icon(Icons.replay),
            label: Text('Reprendre (${v.aReprendre.length} ligne(s))'),
          ),
        ],
        const SizedBox(height: 12),
        section('Codes non reconnus', v.nonReconnues, ouverte: true, key: const ValueKey('section-non-reconnus')),
        section('Erreurs — à reverser', v.erreurs, ouverte: true),
        section('Restent à verser', v.aVerser, ouverte: true),
        section('Versés', v.nouvelles),
        section('Déjà comptés — remplacés', v.remplacees),
        section('Déjà comptés — ajoutés', v.ajoutees),
        section('Regroupés (même produit)', v.lignes.where((l) => l.etat == EtatLigneVersement.regroupee).toList()),
      ]),
    );
  }
}
