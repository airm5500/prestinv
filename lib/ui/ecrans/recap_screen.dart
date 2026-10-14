// lib/ui/ecrans/recap_screen.dart
// Nouvelle interface — récapitulatif d'un rayon (maquette « Recap », 4.13) : filtre Tous / Déjà comptés
// / Pas comptés (avec compteurs ; « compté » = compté sur le serveur OU saisi sur ce téléphone), totaux
// achat / vente / écart valorisé, détail par produit numéroté (cartes sur téléphone, tableau sur
// tablette), CSV (copie ou fichier partagé) et PDF. Ouvert depuis la saisie guidée : toucher une ligne
// y revient sur ce produit. Réglage « Afficher le stock théorique » appliqué à l'écran et au PDF.
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
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/dialogues.dart';
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

  /// Ouvert depuis la saisie guidée : toucher une ligne y revient sur ce produit (renvoyé par pop).
  final bool retourSaisie;
  const NvRecapScreen({super.key, required this.inventoryId, required this.rayonId, required this.rayonName, this.produits, this.retourSaisie = false});

  @override
  State<NvRecapScreen> createState() => _NvRecapScreenState();
}

/// Filtre du récapitulatif.
enum FiltreRecap { tous, comptes, pasComptes }

class _NvRecapScreenState extends State<NvRecapScreen> {
  List<Product>? _produits;
  Object? _erreur;
  bool _impression = false;
  FiltreRecap _filtre = FiltreRecap.tous;

  /// Compté sur le serveur, ou saisi sur ce téléphone (même non envoyé).
  bool _compte(Product p, SaisieQueue? q) => p.dtUpdated != null || q?.ligne(widget.inventoryId, p.id) != null;

  List<Product> _filtres(SaisieQueue? q) {
    final ps = _produits ?? const <Product>[];
    return switch (_filtre) {
      FiltreRecap.tous => ps,
      FiltreRecap.comptes => ps.where((p) => _compte(p, q)).toList(),
      FiltreRecap.pasComptes => ps.where((p) => !_compte(p, q)).toList(),
    };
  }

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
      final theo = context.read<AppConfig>().showTheoreticalStock;
      await NvExports.imprimer(() => NvExports.pdfRecap(widget.rayonName, ps, achat: t.achat, vente: t.vente, ecart: t.ecart, theoVisible: theo),
          'Recap_${NvExports.nomPropre(widget.rayonName)}');
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
    final choix = await nvDialogue<String>(
      context,
      icone: Icons.upload_file,
      ton: context.nv.info,
      titre: 'Exporter les données CSV',
      message: 'Générer le fichier CSV à partir des données affichées ?',
      boutons: const [
        NvBouton('Copier le texte', 'copier', genre: NvGenre.secondaire),
        NvBouton('Générer et partager', 'fichier', genre: NvGenre.principal),
      ],
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
    SaisieQueue? q;
    try {
      q = context.watch<SaisieQueue>();
    } catch (_) {}
    final theoVisible = context.watch<AppConfig>().showTheoreticalStock;
    final tous = _produits;
    final ps = tous == null ? null : _filtres(q);
    final nbComptes = tous?.where((p) => _compte(p, q)).length ?? 0;
    final t = _totaux;
    final numeros = {for (var i = 0; i < (tous?.length ?? 0); i++) tous![i].id: i + 1};
    String theo(Product p) => theoVisible ? '${p.quantiteInitiale}' : '***';
    Widget corps;
    if (_erreur != null) {
      corps = NvErreur(_erreur!, onRetry: _charger);
    } else if (ps == null) {
      corps = const NvChargement();
    } else if (ps.isEmpty) {
      corps = NvVide(
          icon: Icons.inventory_2_outlined,
          titre: tous!.isEmpty ? 'Aucun produit à afficher.' : (_filtre == FiltreRecap.comptes ? 'Aucun produit compté.' : 'Tout est compté dans ce rayon.'));
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
                dataTextStyle: TextStyle(color: nv.encre, fontWeight: FontWeight.w600),
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('N°'), numeric: true),
                  DataColumn(label: Text('Désignation')),
                  DataColumn(label: Text('Écart'), numeric: true),
                  DataColumn(label: Text('Compté'), numeric: true),
                  DataColumn(label: Text('Théo.'), numeric: true),
                  DataColumn(label: Text('Valeur écart'), numeric: true),
                ],
                rows: [
                  for (final p in ps)
                    DataRow(onSelectChanged: widget.retourSaisie ? (_) => Navigator.of(context).pop(p) : null, cells: [
                      DataCell(Text('${numeros[p.id]}')),
                      DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(p.produitName, overflow: TextOverflow.ellipsis))),
                      DataCell(Text(signe(p.quantiteSaisie - p.quantiteInitiale), style: TextStyle(color: _couleur(context, p), fontWeight: FontWeight.bold))),
                      DataCell(Text('${p.quantiteSaisie}')),
                      DataCell(Text(theo(p))),
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
        if (widget.retourSaisie) const Aide('Toucher une ligne : retour à la saisie sur ce produit.'),
        ...cardColumn([
          for (final p in ps)
            SoftCard(
              key: ValueKey('nv-recap-${p.id}'),
              bande: p.quantiteSaisie < p.quantiteInitiale ? Pal.red : (p.quantiteSaisie > p.quantiteInitiale ? Pal.green : null),
              onTap: widget.retourSaisie ? () => Navigator.of(context).pop(p) : null,
              semantique: '${numeros[p.id]}. ${p.produitName}',
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(children: [
                SizedBox(width: 34, child: Text('${numeros[p.id]}', style: TextStyle(color: nv.gris, fontSize: 13))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.produitName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: nv.encre)),
                    Text(_compte(p, q) ? 'Théo ${theo(p)} · compté ${q?.ligne(widget.inventoryId, p.id)?.quantite ?? p.quantiteSaisie}' : 'Théo ${theo(p)} · pas compté',
                        style: TextStyle(color: nv.gris, fontSize: 13.5)),
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
    final filtres = tous == null
        ? const <Widget>[]
        : [
            _SegmentsRecap(
              selection: _filtre,
              libelles: ['Tous (${tous.length})', 'Déjà comptés ($nbComptes)', 'Pas comptés (${tous.length - nbComptes})'],
              onChoisir: (f) => setState(() => _filtre = f),
            ),
            const SizedBox(height: 10),
          ];
    return NvScaffold(
      title: 'Récapitulatif du rayon',
      subtitle: tous == null ? widget.rayonName : '${widget.rayonName} · $nbComptes / ${tous.length}',
      wide: true,
      actions: [
        ActionEntete(icon: Icons.upload_file, tooltip: 'Exporter en CSV', onPressed: ps == null || ps.isEmpty ? null : _csv),
        ActionEntete(icon: Icons.print_outlined, tooltip: 'Imprimer le récapitulatif', onPressed: ps == null || ps.isEmpty || _impression ? null : _imprimer),
      ],
      header: [
        ...filtres,
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

/// Sélecteur Tous / Déjà comptés / Pas comptés (dans l'en-tête bleu, maquette Recap).
class _SegmentsRecap extends StatelessWidget {
  final FiltreRecap selection;
  final List<String> libelles;
  final ValueChanged<FiltreRecap> onChoisir;
  const _SegmentsRecap({required this.selection, required this.libelles, required this.onChoisir});

  @override
  Widget build(BuildContext context) {
    const cles = ['nv-recap-tous', 'nv-recap-comptes', 'nv-recap-pas-comptes'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (final f in FiltreRecap.values) ...[
          if (f.index > 0) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              selected: f == selection,
              button: true,
              child: Material(
                color: f == selection ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: ValueKey(cles[f.index]),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChoisir(f),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text(libelles[f.index],
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: f == selection ? FontWeight.bold : FontWeight.w500,
                                color: f == selection ? Pal.navy : Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
