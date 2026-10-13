// lib/ui/ecrans/recap_screen.dart
// Nouvelle interface — récapitulatif d'un rayon : totaux achat / vente / écart valorisé, détail par
// produit (cartes sur téléphone, tableau sur tablette), CSV (copie ou fichier partagé) et PDF.
// Même logique et mêmes documents que RecapScreen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class NvRecapScreen extends StatefulWidget {
  final String inventoryId;
  final String rayonId;
  final String rayonName;
  final List<Product>? produits;
  const NvRecapScreen({super.key, required this.inventoryId, required this.rayonId, required this.rayonName, this.produits});

  @override
  State<NvRecapScreen> createState() => _NvRecapScreenState();
}

class _NvRecapScreenState extends State<NvRecapScreen> {
  List<Product>? _produits;
  Object? _erreur;
  bool _impression = false;

  @override
  void initState() {
    super.initState();
    if (widget.produits != null) {
      _produits = widget.produits;
    } else {
      _charger();
    }
  }

  Future<void> _charger() async {
    setState(() => _erreur = null);
    final auth = context.read<AuthProvider>();
    try {
      final ps = await ApiService(baseUrl: context.read<AppConfig>().currentApiUrl, cookie: () => auth.sessionCookie).fetchProducts(widget.inventoryId, widget.rayonId);
      if (mounted) setState(() => _produits = ps);
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  ({double achat, double vente, double ecart}) get _totaux {
    double a = 0, v = 0, e = 0;
    for (final p in _produits ?? const <Product>[]) {
      a += p.quantiteSaisie * p.produitPrixAchat;
      v += p.quantiteSaisie * p.produitPrixUni;
      e += (p.quantiteSaisie - p.quantiteInitiale) * p.produitPrixAchat;
    }
    return (achat: a, vente: v, ecart: e);
  }

  Future<void> _imprimer() async {
    final ps = _produits;
    if (_impression || ps == null || ps.isEmpty) return;
    setState(() => _impression = true);
    final t = _totaux;
    try {
      await NvExports.imprimer(() => NvExports.pdfRecap(widget.rayonName, ps, achat: t.achat, vente: t.vente, ecart: t.ecart), 'Recap_${NvExports.nomPropre(widget.rayonName)}');
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur lors de l\'impression : $e', ton: context.nv.erreur);
    } finally {
      if (mounted) setState(() => _impression = false);
    }
  }

  Future<void> _csv() async {
    final ps = _produits;
    if (ps == null || ps.isEmpty) return;
    final contenu = NvExports.csvRecap(ps);
    final choix = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exporter les données CSV'),
        content: const Text('Générer le fichier CSV à partir des données affichées ?'),
        actions: [
          TextButton.icon(onPressed: () => Navigator.pop(ctx, 'copier'), icon: const Icon(Icons.copy), label: const Text('Copier le texte')),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'fichier'), icon: const Icon(Icons.file_download), label: const Text('Générer et partager')),
        ],
      ),
    );
    if (!mounted || choix == null) return;
    if (choix == 'copier') {
      await Clipboard.setData(ClipboardData(text: contenu));
      if (mounted) nvMessage(context, 'Contenu du CSV copié dans le presse-papiers !', ton: context.nv.ok);
      return;
    }
    try {
      final horo = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final propre = widget.rayonName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      final dossier = await getTemporaryDirectory();
      final f = File('${dossier.path}/inventaire_${propre}_$horo.csv');
      await f.writeAsString(contenu);
      await NvExports.partager([XFile(f.path)], 'Export CSV : ${widget.rayonName}');
    } catch (e) {
      if (mounted) nvMessage(context, 'Export impossible : $e', ton: context.nv.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final ps = _produits;
    final t = _totaux;
    Widget corps;
    if (_erreur != null) {
      corps = NvErreur(_erreur!, onRetry: _charger);
    } else if (ps == null) {
      corps = const NvChargement();
    } else if (ps.isEmpty) {
      corps = const NvVide(icon: Icons.inventory_2_outlined, titre: 'Aucun produit à afficher.');
    } else if (Responsive.isExpanded(context)) {
      corps = Padding(
        padding: const EdgeInsets.all(20),
        child: SoftCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                headingTextStyle: TextStyle(color: nv.gris, fontWeight: FontWeight.bold),
                dataTextStyle: TextStyle(color: nv.encre),
                columns: const [
                  DataColumn(label: Text('Désignation')),
                  DataColumn(label: Text('Écart'), numeric: true),
                  DataColumn(label: Text('Compté'), numeric: true),
                  DataColumn(label: Text('Théo.'), numeric: true),
                  DataColumn(label: Text('Valeur écart'), numeric: true),
                ],
                rows: [
                  for (final p in ps)
                    DataRow(cells: [
                      DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(p.produitName, overflow: TextOverflow.ellipsis))),
                      DataCell(Text(signe(p.quantiteSaisie - p.quantiteInitiale), style: TextStyle(color: _couleur(context, p), fontWeight: FontWeight.bold))),
                      DataCell(Text('${p.quantiteSaisie}')),
                      DataCell(Text('${p.quantiteInitiale}')),
                      DataCell(Text(francs((p.quantiteSaisie - p.quantiteInitiale) * p.produitPrixAchat, signeExplicite: true),
                          style: TextStyle(color: _couleur(context, p), fontWeight: FontWeight.bold))),
                    ]),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      final cols = Responsive.columns(context, compact: 1, medium: 2, expanded: 2);
      corps = ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
        ...cardColumn([
          for (final p in ps)
            SoftCard(
              bande: p.quantiteSaisie < p.quantiteInitiale ? Pal.red : (p.quantiteSaisie > p.quantiteInitiale ? Pal.green : null),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.produitName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: nv.encre)),
                    Text('Théo ${p.quantiteInitiale} · compté ${p.quantiteSaisie}', style: TextStyle(color: nv.gris, fontSize: 13.5)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(signe(p.quantiteSaisie - p.quantiteInitiale), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _couleur(context, p))),
                  Text(francs((p.quantiteSaisie - p.quantiteInitiale) * p.produitPrixAchat, signeExplicite: true), style: TextStyle(color: nv.gris, fontSize: 13)),
                ]),
              ]),
            ),
        ], cols, spacing: 8),
      ]);
    }
    return NvScaffold(
      title: 'Récapitulatif',
      subtitle: widget.rayonName,
      wide: true,
      actions: [
        ActionEntete(icon: Icons.upload_file, tooltip: 'Exporter en CSV', onPressed: ps == null || ps.isEmpty ? null : _csv),
        ActionEntete(icon: Icons.print_outlined, tooltip: 'Imprimer le récapitulatif', onPressed: ps == null || ps.isEmpty || _impression ? null : _imprimer),
      ],
      header: [
        Row(children: [
          Expanded(child: KpiTile(francs(t.achat), 'Total achat')),
          const SizedBox(width: 8),
          Expanded(child: KpiTile(francs(t.vente), 'Total vente')),
          const SizedBox(width: 8),
          Expanded(child: KpiTile(francs(t.ecart, signeExplicite: true), 'Écart valorisé', highlight: true)),
        ]),
      ],
      body: corps,
    );
  }

  Color _couleur(BuildContext context, Product p) {
    final e = p.quantiteSaisie - p.quantiteInitiale;
    return e < 0 ? context.nv.manquant : (e > 0 ? context.nv.surplus : context.nv.gris);
  }
}
