// lib/collecte/rapport_versement.dart
// Rapport d'un versement de la collecte : texte, CSV (séparateur « ; », lisible par Excel) et PDF.
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/scan/code_scan.dart';

final DateFormat _date = DateFormat('dd/MM/yyyy HH:mm');

String libelleStatut(Versement v) => switch (v.statut) {
      StatutVersement.termine => v.nonReconnues.isEmpty ? 'Terminé' : 'Terminé (codes non reconnus)',
      StatutVersement.interrompu => 'Interrompu — à reprendre',
      StatutVersement.enCours => 'En cours',
    };

String libelleEtatLigne(LigneVersement l, ModeDejaCompte mode) => switch (l.etat) {
      EtatLigneVersement.versee => l.dejaComptee ? (mode == ModeDejaCompte.ajouter ? 'Déjà compté — ajouté' : 'Déjà compté — remplacé') : 'Versé',
      EtatLigneVersement.nonReconnue => 'Code non reconnu',
      EtatLigneVersement.erreur => 'Erreur — à reverser',
      EtatLigneVersement.aVerser => 'À verser',
      EtatLigneVersement.regroupee => 'Regroupé',
    };

/// Résumé en quelques lignes (partage par message).
String resumeVersement(Versement v) {
  final b = StringBuffer()
    ..writeln('Versement de la collecte dans « ${v.inventaireLibelle} »')
    ..writeln('${_date.format(v.debut)} — ${libelleStatut(v)} — déjà comptés : ${v.mode.libelle}')
    ..writeln('Versés : ${v.nouvelles.length} · Déjà comptés remplacés : ${v.remplacees.length} · '
        'ajoutés : ${v.ajoutees.length} · Non reconnus : ${v.nonReconnues.length} · '
        'Erreurs : ${v.erreurs.length} · Restent : ${v.aVerser.length}');
  if (v.interruption != null) b.writeln('Interruption : ${v.interruption}');
  return b.toString();
}

String _csv(String s) => s.contains(';') || s.contains('"') || s.contains('\n') ? '"${s.replaceAll('"', '""')}"' : s;

/// CSV : une ligne par code collecté.
String rapportCsv(Versement v) {
  final b = StringBuffer()
    ..writeln('Inventaire;${_csv(v.inventaireLibelle)}')
    ..writeln('Date;${_date.format(v.debut)}')
    ..writeln('Déjà comptés;${v.mode.libelle}')
    ..writeln('Statut;${_csv(libelleStatut(v))}')
    ..writeln()
    ..writeln('Code;Quantité collectée;Résultat;CIP;Produit;Déjà compté;Quantité envoyée;Raison');
  for (final l in v.lignes) {
    b.writeln([
      _csv(CodeScan.affichage(l.code)),
      l.quantiteCollectee,
      _csv(libelleEtatLigne(l, v.mode)),
      _csv(l.cip),
      _csv(l.nom),
      l.quantiteExistante ?? '',
      l.etat == EtatLigneVersement.versee ? (l.quantiteCible ?? '') : '',
      _csv(l.raison ?? ''),
    ].join(';'));
  }
  return b.toString();
}

/// Texte compatible avec les polices standard du PDF (Latin-1) : tirets longs, points de suspension,
/// apostrophes typographiques, flèches… remplacés.
String _pdf(String s) {
  final t = s
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('…', '...')
      .replaceAll('’', "'")
      .replaceAll('→', '->')
      .replaceAll('✓', 'OK')
      .replaceAll(CodeScan.gsVisible, '<GS>')
      .replaceAll(CodeScan.gs, '<GS>');
  return String.fromCharCodes(t.runes.map((r) => r > 0xFF ? 0x3F : r));
}

/// PDF A4 (plusieurs pages si besoin).
Future<Uint8List> rapportPdf(Versement v) async {
  final doc = pw.Document();
  List<List<String>> table(Iterable<LigneVersement> ls, {bool raison = false}) => [
        for (final l in ls)
          [
            _pdf(l.code),
            '${l.quantiteCollectee}',
            _pdf(l.nom.isEmpty ? l.cip : '${l.cip} ${l.nom}'),
            l.quantiteExistante?.toString() ?? '',
            l.quantiteCible?.toString() ?? '',
            if (raison) _pdf(l.raison ?? libelleEtatLigne(l, v.mode)),
          ]
      ];
  pw.Widget section(String titre, Iterable<LigneVersement> ls, {bool raison = false}) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 10),
          pw.Text(_pdf('$titre (${ls.length})'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          if (ls.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: ['Code', 'Qté collectée', 'Produit', 'Déjà compté', 'Qté envoyée', if (raison) 'Raison'].map(_pdf).toList(),
              data: table(ls, raison: raison),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
        ],
      );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    header: (c) => pw.Text(_pdf('Versement de la collecte - ${v.inventaireLibelle}'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
    footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight, child: pw.Text('Page ${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 9))),
    build: (c) => [
      pw.Text(_pdf(resumeVersement(v)), style: const pw.TextStyle(fontSize: 10)),
      section('Versés (nouveaux)', v.nouvelles),
      section('Déjà comptés - remplacés', v.remplacees),
      section('Déjà comptés - ajoutés', v.ajoutees),
      section('Codes non reconnus', v.nonReconnues, raison: true),
      section('Erreurs (à reverser)', v.erreurs, raison: true),
      if (v.aVerser.isNotEmpty) section('Restent à verser', v.aVerser, raison: true),
    ],
  ));
  return doc.save();
}

/// Nom de fichier du rapport (sans extension).
String nomFichierRapport(Versement v) =>
    'Versement_${v.inventaireLibelle.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_${DateFormat('ddMMyyyy_HHmm').format(v.debut)}';
