// lib/screens/rapport_versement_screen.dart
// Rapport d'un versement de la collecte : compteurs, détail par catégorie (dont les CODES NON RECONNUS
// avec leur quantité et la raison), export PDF / CSV et partage ; « Reprendre » si des lignes restent.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prestinv/collecte/rapport_versement.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/screens/versement_screen.dart';
import 'package:share_plus/share_plus.dart';

/// Partage de fichiers (remplaçable dans les tests).
typedef PartageFichiers = Future<void> Function(List<XFile> fichiers, String texte);

class RapportVersementScreen extends StatelessWidget {
  final Versement versement;

  /// Tests : partage remplacé (sinon feuille de partage Android).
  static PartageFichiers partager = (fichiers, texte) async {
    await Share.shareXFiles(fichiers, text: texte);
  };

  /// Tests : dossier des fichiers exportés (sinon dossier temporaire de l'application).
  static Future<Directory> Function() dossierExport = getTemporaryDirectory;

  const RapportVersementScreen({super.key, required this.versement});

  Future<File> _ecrire(String nom, List<int> octets) async {
    final d = await dossierExport();
    final f = File('${d.path}/$nom');
    await f.writeAsBytes(octets, flush: true);
    return f;
  }

  Future<void> _exporter(BuildContext context, {required bool pdf, required bool csv}) async {
    final messager = ScaffoldMessenger.of(context);
    try {
      final nom = nomFichierRapport(versement);
      final fichiers = <XFile>[];
      if (pdf) {
        final Uint8List octets = await rapportPdf(versement);
        fichiers.add(XFile((await _ecrire('$nom.pdf', octets)).path, mimeType: 'application/pdf'));
      }
      if (csv) {
        // BOM : accents lus correctement par Excel.
        final octets = [0xEF, 0xBB, 0xBF, ...utf8.encode(rapportCsv(versement))];
        fichiers.add(XFile((await _ecrire('$nom.csv', octets)).path, mimeType: 'text/csv'));
      }
      await partager(fichiers, resumeVersement(versement));
    } catch (e) {
      messager.showSnackBar(SnackBar(content: Text('Export impossible : $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = versement;
    final date = DateFormat('dd/MM/yyyy HH:mm');
    Widget compteur(String libelle, int n, Color c, Key k) => Container(
          key: k,
          constraints: const BoxConstraints(minWidth: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.4))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
            Text(libelle, style: const TextStyle(fontSize: 12)),
          ]),
        );
    Widget section(String titre, List<LigneVersement> ls, {bool raison = false, Key? key}) => ls.isEmpty
        ? const SizedBox.shrink()
        : ExpansionTile(
            key: key,
            initiallyExpanded: raison,
            title: Text('$titre (${ls.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapport de versement'),
        actions: [
          IconButton(key: const ValueKey('export-pdf'), tooltip: 'PDF', icon: const Icon(Icons.picture_as_pdf), onPressed: () => _exporter(context, pdf: true, csv: false)),
          IconButton(key: const ValueKey('export-csv'), tooltip: 'CSV', icon: const Icon(Icons.table_view), onPressed: () => _exporter(context, pdf: false, csv: true)),
          IconButton(key: const ValueKey('partager-rapport'), tooltip: 'Partager', icon: const Icon(Icons.share), onPressed: () => _exporter(context, pdf: true, csv: true)),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          ListTile(
            title: Text('« ${v.inventaireLibelle} »', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${date.format(v.debut)} · déjà comptés : ${v.mode.libelle} · ${libelleStatut(v)}'),
          ),
          if (v.interruption != null)
            Container(
              key: const ValueKey('interruption-versement'),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(v.interruption!, style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              compteur('versés', v.nouvelles.length, Colors.green.shade700, const ValueKey('nb-verses')),
              compteur('déjà comptés remplacés', v.remplacees.length, Colors.blue.shade700, const ValueKey('nb-remplaces')),
              compteur('déjà comptés ajoutés', v.ajoutees.length, Colors.blue.shade700, const ValueKey('nb-ajoutes')),
              compteur('codes non reconnus', v.nonReconnues.length, Colors.red.shade700, const ValueKey('nb-non-reconnus')),
              compteur('erreurs', v.erreurs.length, Colors.red.shade700, const ValueKey('nb-erreurs')),
              if (v.aVerser.isNotEmpty) compteur('à verser', v.aVerser.length, Colors.orange.shade800, const ValueKey('nb-a-verser')),
            ]),
          ),
          if (!v.complet)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ElevatedButton.icon(
                key: const ValueKey('reprendre-versement'),
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => VersementScreen(reprise: v))),
                icon: const Icon(Icons.replay),
                label: Text('Reprendre (${v.aReprendre.length} ligne(s))'),
              ),
            ),
          section('Codes non reconnus', v.nonReconnues, raison: true, key: const ValueKey('section-non-reconnus')),
          section('Erreurs — à reverser', v.erreurs, raison: true),
          section('Restent à verser', v.aVerser, raison: true),
          section('Versés', v.nouvelles),
          section('Déjà comptés — remplacés', v.remplacees),
          section('Déjà comptés — ajoutés', v.ajoutees),
          section('Regroupés (même produit)', v.lignes.where((l) => l.etat == EtatLigneVersement.regroupee).toList()),
        ]),
      ),
    );
  }
}
