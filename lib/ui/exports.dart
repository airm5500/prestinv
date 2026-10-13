// lib/ui/exports.dart
// Exports de la nouvelle interface (CSV, impression PDF) : MÊMES contenus et mêmes emplacements que
// les écrans d'origine (fichiers CSV dans Téléchargements, sinon partage ; PDF par l'impression
// Android). Les documents sont décrits ici une seule fois pour les nouveaux écrans ; les écrans
// d'origine gardent leur propre code, inchangé.
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/utils/journal.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Résultat d'un export CSV.
class ExportCsv {
  /// Chemin du fichier écrit dans Téléchargements (null : partagé depuis le dossier temporaire).
  final String? cheminTelechargements;
  const ExportCsv(this.cheminTelechargements);
}

class NvExports {
  NvExports._();

  static final _monnaie = NumberFormat.currency(locale: 'fr_FR', symbol: 'F', decimalDigits: 0);

  /// Impression (remplaçable dans les tests).
  static Future<void> Function(Future<Uint8List> Function() document, String nom) imprimer =
      (document, nom) => Printing.layoutPdf(onLayout: (_) => document(), name: nom);

  /// Partage de fichiers (remplaçable dans les tests).
  static Future<void> Function(List<XFile> fichiers, String texte) partager = (f, t) async {
    await Share.shareXFiles(f, text: t);
  };

  /// Écriture d'un CSV (remplaçable dans les tests) : Téléchargements sur Android, sinon partage.
  static Future<ExportCsv> Function(String contenu, String nomFichier, String texte) ecrireCsv = _ecrireCsv;

  static Future<ExportCsv> _ecrireCsv(String contenu, String nomFichier, String texte) async {
    if (Platform.isAndroid) {
      final dossier = Directory('/storage/emulated/0/Download');
      if (!await dossier.exists()) {
        try {
          await dossier.create(recursive: true);
        } catch (e) {
          journal('Dossier Téléchargements : $e');
        }
      }
      final f = File('${dossier.path}/$nomFichier');
      var ok = false;
      try {
        await f.writeAsString(contenu);
        ok = true;
      } catch (_) {
        var statut = await Permission.storage.status;
        if (!statut.isGranted) statut = await Permission.storage.request();
        if (statut.isGranted) {
          try {
            await f.writeAsString(contenu);
            ok = true;
          } catch (e) {
            journal('Écriture CSV : $e');
          }
        }
      }
      if (ok) return ExportCsv(f.path);
    }
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}/$nomFichier');
    await f.writeAsString(contenu);
    await partager([XFile(f.path)], texte);
    return const ExportCsv(null);
  }

  static String horodatage([DateTime? d]) => DateFormat('ddMMyyyy_HHmm').format(d ?? DateTime.now());

  static String nomPropre(String s) => s.replaceAll(RegExp(r'[^\w\s]+'), '');

  // ---------- Contenus CSV (identiques aux écrans d'origine) ----------

  /// Saisie guidée / rapide : « code_cip;quantite ».
  static String csvSaisies(List<Product> ps) {
    final b = StringBuffer()..writeln('code_cip;quantite');
    for (final p in ps) {
      b.writeln('${p.produitCip};${p.quantiteSaisie}');
    }
    return b.toString();
  }

  /// Récapitulatif : « CIP,Quantité ».
  static String csvRecap(List<Product> ps) {
    final b = StringBuffer();
    for (final p in ps) {
      b.writeln('${p.produitCip},${p.quantiteSaisie}');
    }
    return b.toString();
  }

  /// Collecte hors ligne : « Code;Quantite;Date ».
  static String csvCollecte(List<CollectedItem> items) {
    final b = StringBuffer()..writeln('Code;Quantite;Date');
    for (final i in items) {
      b.writeln('${i.code};${i.quantity};${i.dateScan}');
    }
    return b.toString();
  }

  /// Écarts (nouveau : export du tableau tablette) : « code_cip;designation;theorique;compte;ecart;valeur ».
  static String csvEcarts(List<Product> ps) {
    final b = StringBuffer()..writeln('code_cip;designation;theorique;compte;ecart;valeur');
    for (final p in ps) {
      final e = p.quantiteSaisie - p.quantiteInitiale;
      b.writeln('${p.produitCip};${p.produitName.replaceAll(';', ',')};${p.quantiteInitiale};${p.quantiteSaisie};$e;${(e * p.produitPrixAchat).round()}');
    }
    return b.toString();
  }

  // ---------- Documents PDF (mêmes tableaux que les écrans d'origine) ----------

  static Future<Uint8List> pdfEcarts(String titre, List<Product> ps) {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (_) => pw.Header(level: 0, text: 'Rapport des Écarts - $titre'),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          context: ctx,
          data: [
            ['CIP', 'Désignation', 'Stock Théo.', 'Stock Corrigé', 'Écart'],
            ...ps.map((p) => [p.produitCip, p.produitName, '${p.quantiteInitiale}', '${p.quantiteSaisie}', '${p.quantiteSaisie - p.quantiteInitiale}']),
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(5),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1),
          },
        ),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> pdfRecap(String rayon, List<Product> ps, {required double achat, required double vente, required double ecart}) {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(15),
      header: (_) => pw.Header(level: 0, text: 'Récapitulatif - $rayon'),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${c.pageNumber} sur ${c.pagesCount}', style: const pw.TextStyle(fontSize: 10)),
      ),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          data: [
            ['CIP', 'Désignation', 'Ecart', 'Rayon', 'Théo', 'Valorisation'],
            ...ps.map((p) {
              final e = p.quantiteSaisie - p.quantiteInitiale;
              return [p.produitCip, p.produitName, '$e', '${p.quantiteSaisie}', '${p.quantiteInitiale}', _monnaie.format(e * p.produitPrixAchat)];
            }),
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(1.5),
            1: const pw.FlexColumnWidth(6),
            2: const pw.FlexColumnWidth(0.8),
            3: const pw.FlexColumnWidth(0.8),
            4: const pw.FlexColumnWidth(0.8),
            5: const pw.FlexColumnWidth(1.5),
          },
        ),
        pw.Divider(height: 30),
        pw.Text('Total Achat: ${_monnaie.format(achat)}'),
        pw.Text('Total Vente: ${_monnaie.format(vente)}'),
        pw.Text('Total Écart Valorisé: ${_monnaie.format(ecart)}',
            style: pw.TextStyle(color: ecart >= 0 ? PdfColors.green : PdfColors.red, fontWeight: pw.FontWeight.bold)),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> pdfCollecte(List<CollectedItem> items) {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (_) => pw.Header(level: 0, text: 'Rapport de Collecte (Hors-ligne)'),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${c.pageNumber} sur ${c.pagesCount}', style: const pw.TextStyle(fontSize: 10)),
      ),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          context: ctx,
          data: [
            ['Code', 'Quantité', 'Date Scan'],
            ...items.map((i) => [i.code, '${i.quantity}', DateFormat('dd/MM/yyyy HH:mm').format(i.dateScan)]),
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
        ),
      ],
    ));
    return doc.save();
  }

  static String heure(String iso) {
    try {
      return DateFormat('HH:mm:ss').format(DateTime.parse(iso));
    } catch (_) {
      return '';
    }
  }

  static Future<Uint8List> pdfCumuls(List<Map<String, dynamic>> logs) {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Header(
          level: 0,
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Rapport des Cumuls', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.Text('Généré le: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'),
          ]),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          context: ctx,
          data: [
            ['Heure', 'CIP', 'Produit', 'Avant', 'Ajout', 'Total', 'Rayon'],
            ...logs.map((l) => [heure('${l['date']}'), '${l['cip']}', '${l['name']}', '${l['oldQty']}', '${l['addedQty']}', '${l['newQty']}', '${l['rayon']}']),
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue),
          rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey))),
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
        ),
        pw.Padding(padding: const pw.EdgeInsets.all(10)),
        pw.Text('Total des lignes cumulées : ${logs.length}'),
      ]),
    ));
    return doc.save();
  }

  static Future<Uint8List> pdfAnalyse({
    required String inventaire,
    required String emplacement,
    required double avant,
    required double apres,
    required int positifs,
    required int negatifs,
    required int corrects,
    Uint8List? graphique,
  }) {
    final total = positifs + negatifs + corrects;
    String pct(int n) => '${(total > 0 ? n / total * 100 : 0).toStringAsFixed(1)}%';
    final ecart = apres - avant;
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Header(level: 0, text: 'Rapport d\'Analyse d\'Inventaire', textStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Text('Inventaire: $inventaire'),
        pw.Text('Emplacement: $emplacement'),
        pw.Divider(height: 20, thickness: 1),
        pw.Header(level: 1, text: 'Valorisation de l\'inventaire'),
        pw.Text('Valeur Avant: ${_monnaie.format(avant)}'),
        pw.Text('Valeur Après: ${_monnaie.format(apres)}'),
        pw.Text('Écart Total: ${_monnaie.format(ecart)}', style: pw.TextStyle(color: ecart >= 0 ? PdfColors.green : PdfColors.red, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 20),
        pw.Header(level: 1, text: 'Répartition des Écarts (Quantité d\'articles)'),
        if (graphique != null) pw.Center(child: pw.SizedBox(width: 250, height: 250, child: pw.Image(pw.MemoryImage(graphique)))),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
          columnWidths: {0: const pw.FlexColumnWidth(2.5), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1)},
          border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          data: [
            ['Catégorie', 'Nombre d\'articles', 'Pourcentage'],
            ['Écarts Positifs', '$positifs', pct(positifs)],
            ['Écarts Négatifs', '$negatifs', pct(negatifs)],
            ['Stocks Corrects', '$corrects', pct(corrects)],
          ],
        ),
      ]),
    ));
    return doc.save();
  }
}

/// Montant en francs CFA (« −142 000 F »), espaces insécables comme fr_FR.
String francs(num v, {bool signeExplicite = false}) {
  final n = NumberFormat.decimalPattern('fr_FR').format(v.abs().round());
  final s = v < 0 ? '−' : (signeExplicite && v > 0 ? '+' : '');
  return '$s$n F';
}
