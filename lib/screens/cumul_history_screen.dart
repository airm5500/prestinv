// lib/screens/cumul_history_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:prestinv/ui/exports.dart';

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
              // 4.16.2 : auteur du comptage précédent (serveur à jour), sur la même ligne.
              subtitle: Text("CIP: ${log['cip']} • ${log['rayon']}${log['comptePar'] is String ? " • déjà compté par ${log['comptePar']}" : ''}"),
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

  // 4.16.3 : même rapport que la nouvelle interface (colonne « Auteur », plusieurs pages si besoin).
  Future<void> _generateAndPrintPdf(BuildContext context, List<Map<String, dynamic>> logs) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => NvExports.pdfCumuls(logs),
      name: 'Rapport_Cumuls_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
    );
  }
}