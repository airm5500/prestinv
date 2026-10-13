// lib/ui/ecrans/cumuls_screen.dart
// Nouvelle interface — historique des cumuls (« déjà compté → Ajouter ») de la session, avec
// impression PDF. Mêmes données que CumulHistoryScreen (EntryProvider.cumulLogs).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

class NvCumulsScreen extends StatelessWidget {
  const NvCumulsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<EntryProvider>().cumulLogs;
    final nv = context.nv;
    final cols = Responsive.columns(context, compact: 1, medium: 2, expanded: 2);
    return NvScaffold(
      title: 'Historique des cumuls',
      subtitle: '${logs.length} ajout(s) dans cette session',
      wide: true,
      actions: [
        ActionEntete(
          icon: Icons.print_outlined,
          tooltip: 'Imprimer en PDF',
          onPressed: logs.isEmpty
              ? null
              : () async {
                  try {
                    await NvExports.imprimer(() => NvExports.pdfCumuls(logs), 'Rapport_Cumuls_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}');
                  } catch (e) {
                    if (context.mounted) nvMessage(context, 'Erreur lors de l\'impression : $e', ton: context.nv.erreur);
                  }
                },
        ),
      ],
      body: logs.isEmpty
          ? const NvVide(icon: Icons.add_circle_outline, titre: 'Aucun cumul effectué dans cette session.')
          : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
              ...cardColumn([
                for (final log in logs.reversed)
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${log['name'] ?? 'Produit inconnu'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: nv.encre)),
                          Text('CIP ${log['cip']} · ${log['rayon']} · ${NvExports.heure('${log['date']}')}', style: TextStyle(color: nv.gris, fontSize: 13)),
                        ]),
                      ),
                      Text('${log['oldQty']} + ${log['addedQty']} = ${log['newQty']}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: nv.ok.fg)),
                    ]),
                  ),
              ], cols, spacing: 8),
            ]),
    );
  }
}
