// lib/screens/cumul_history_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class CumulHistoryScreen extends StatelessWidget {
  const CumulHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EntryProvider>(context);
    final logs = provider.cumulLogs;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historique des Cumuls"),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: "Imprimer en PDF",
            onPressed: logs.isEmpty
                ? null
                : () => _generateAndPrintPdf(context, logs),
          )
        ],
      ),
      body: logs.isEmpty
          ? const Center(
        child: Text(
          "Aucun cumul effectué dans cette session.",
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      )
          : ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) {
          // Inversion pour avoir les plus récents en haut
          final log = logs[logs.length - 1 - index];

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.add, color: Colors.white),
              ),
              title: Text(log['name'] ?? 'Produit inconnu', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("CIP: ${log['cip']} • ${log['rayon']}"),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${log['oldQty']} + ${log['addedQty']} = ${log['newQty']}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                  Text(_formatDate(log['date']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return DateFormat('HH:mm:ss').format(dt);
    } catch (e) {
      return "";
    }
  }

  Future<void> _generateAndPrintPdf(BuildContext context, List<Map<String, dynamic>> logs) async {
    final doc = pw.Document();

    final tableData = [
      ['Heure', 'CIP', 'Produit', 'Avant', 'Ajout', 'Total', 'Rayon'],
      ...logs.map((log) => [
        _formatDate(log['date']),
        log['cip'],
        log['name'],
        log['oldQty'].toString(),
        log['addedQty'].toString(),
        log['newQty'].toString(),
        log['rayon']
      ]).toList()
    ];

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Rapport des Cumuls', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Généré le: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                context: context,
                data: tableData,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue),
                rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey))),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
              ),
              pw.Padding(padding: const pw.EdgeInsets.all(10)),
              pw.Text("Total des lignes cumulées : ${logs.length}"),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Rapport_Cumuls_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
    );
  }
}