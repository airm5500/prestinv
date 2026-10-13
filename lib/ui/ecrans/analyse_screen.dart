// lib/ui/ecrans/analyse_screen.dart
// Nouvelle interface — analyse d'un emplacement : valeur du stock avant / après au prix d'achat,
// écart en F CFA, répartition surplus / manquants / justes (camembert, avec libellés et pourcentages),
// impression PDF. Même logique que AnalysisScreen (inventaires, rayons, produits du rayon).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

class NvAnalyseScreen extends StatefulWidget {
  const NvAnalyseScreen({super.key});

  @override
  State<NvAnalyseScreen> createState() => _NvAnalyseScreenState();
}

class _NvAnalyseScreenState extends State<NvAnalyseScreen> {
  late final ApiService _api;
  final _graphique = GlobalKey();
  List<Inventory> _inventaires = [];
  Inventory? _inventaire;
  List<Rayon> _rayons = [];
  Rayon? _rayon;
  List<Product> _produits = [];
  bool _chargement = false;
  Object? _erreur;
  VoidCallback? _reessayer;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _api = ApiService(baseUrl: context.read<AppConfig>().currentApiUrl, cookie: () => auth.sessionCookie);
    _chargerInventaires();
  }

  Future<void> _executer(Future<void> Function() f, VoidCallback reessayer) async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await f();
    } catch (e) {
      _erreur = e;
      _reessayer = reessayer;
    }
    if (mounted) setState(() => _chargement = false);
  }

  Future<void> _chargerInventaires() => _executer(() async => _inventaires = await _api.fetchInventories(maxResult: 100), _chargerInventaires);

  Future<void> _choisirInventaire(Inventory inv) async {
    setState(() {
      _inventaire = inv;
      _rayons = [];
      _rayon = null;
      _produits = [];
    });
    await _executer(() async => _rayons = await _api.fetchRayons(inv.id), () => _choisirInventaire(inv));
  }

  Future<void> _choisirRayon(Rayon r) async {
    final inv = _inventaire;
    if (inv == null) return;
    setState(() {
      _rayon = r;
      _produits = [];
    });
    await _executer(() async => _produits = await _api.fetchProducts(inv.id, r.id), () => _choisirRayon(r));
  }

  ({int pos, int neg, int ok, double avant, double apres}) get _stats {
    var pos = 0, neg = 0, ok = 0;
    double avant = 0, apres = 0;
    for (final p in _produits) {
      final e = p.quantiteSaisie - p.quantiteInitiale;
      if (e > 0) {
        pos++;
      } else if (e < 0) {
        neg++;
      } else {
        ok++;
      }
      avant += p.quantiteInitiale * p.produitPrixAchat;
      apres += p.quantiteSaisie * p.produitPrixAchat;
    }
    return (pos: pos, neg: neg, ok: ok, avant: avant, apres: apres);
  }

  Future<void> _imprimer() async {
    final s = _stats;
    Uint8List? image;
    try {
      final boundary = _graphique.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      final img = await boundary?.toImage(pixelRatio: 3);
      final data = await img?.toByteData(format: ui.ImageByteFormat.png);
      image = data?.buffer.asUint8List();
    } catch (_) {}
    try {
      await NvExports.imprimer(
        () => NvExports.pdfAnalyse(
          inventaire: _inventaire?.libelle ?? 'N/A',
          emplacement: _rayon?.displayName ?? 'N/A',
          avant: s.avant,
          apres: s.apres,
          positifs: s.pos,
          negatifs: s.neg,
          corrects: s.ok,
          graphique: image,
        ),
        'Analyse_${NvExports.nomPropre(_rayon?.libelle ?? '')}',
      );
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur lors de l\'impression PDF : $e', ton: context.nv.erreur);
    }
  }

  Future<T?> _choisir<T>(String titre, List<T> items, String Function(T) libelle) => showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: ListView(shrinkWrap: true, children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(titre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              for (final i in items) ListTile(title: Text(libelle(i)), onTap: () => Navigator.pop(ctx, i)),
            ]),
          ),
        ),
      );

  Widget _selecteur(BuildContext context, {required Key key, required String label, required String? valeur, required VoidCallback? onTap}) {
    final nv = context.nv;
    return SoftCard(
      key: key,
      onTap: onTap,
      semantique: '$label : ${valeur ?? 'à choisir'}',
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: nv.gris, fontSize: 13)),
            Text(valeur ?? 'Choisir…', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: valeur == null ? nv.gris : nv.encre)),
          ]),
        ),
        Icon(Icons.expand_more, color: onTap == null ? nv.ligne : nv.action),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final s = _stats;
    final total = _produits.length;
    String pct(int n) => '${(total > 0 ? n / total * 100 : 0).toStringAsFixed(1)} %';
    final selecteurs = [
      _selecteur(context,
          key: const ValueKey('nv-analyse-inventaire'),
          label: 'Inventaire',
          valeur: _inventaire?.libelle,
          onTap: _inventaires.isEmpty
              ? null
              : () async {
                  final i = await _choisir('Choisir un inventaire', _inventaires, (x) => x.libelle);
                  if (i != null) _choisirInventaire(i);
                }),
      const SizedBox(height: 10),
      _selecteur(context,
          key: const ValueKey('nv-analyse-rayon'),
          label: 'Emplacement',
          valeur: _rayon?.displayName,
          onTap: _rayons.isEmpty
              ? null
              : () async {
                  final r = await _choisir('Choisir un emplacement', _rayons, (x) => x.displayName);
                  if (r != null) _choisirRayon(r);
                }),
    ];

    final sections = <(String, int, Color)>[
      ('Surplus (écarts positifs)', s.pos, Pal.green),
      ('Manquants (écarts négatifs)', s.neg, Pal.red),
      ('Justes (stock correct)', s.ok, Pal.blue),
    ];
    final resultats = total == 0
        ? <Widget>[]
        : [
            SoftCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('$total article(s) analysés', style: TextStyle(fontWeight: FontWeight.bold, color: nv.encre)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Chiffre('Valeur avant', francs(s.avant))),
                  const SizedBox(width: 8),
                  Expanded(child: Chiffre('Valeur après', francs(s.apres))),
                ]),
                const SizedBox(height: 8),
                Chiffre('Écart total', francs(s.apres - s.avant, signeExplicite: true), couleur: s.apres - s.avant < 0 ? nv.manquant : nv.surplus),
              ]),
            ),
            const SectionTitre('Répartition des articles'),
            SoftCard(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                RepaintBoundary(
                  key: _graphique,
                  child: Container(
                    color: nv.carte,
                    height: 210,
                    child: PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 44,
                      sections: [
                        for (final (_, n, c) in sections)
                          if (n > 0)
                            PieChartSectionData(
                              value: n.toDouble(),
                              color: c,
                              radius: 56,
                              title: pct(n),
                              titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                      ],
                    )),
                  ),
                ),
                const SizedBox(height: 12),
                for (final (l, n, c) in sections)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(width: 14, height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(l, style: TextStyle(color: nv.encre))),
                      Text('$n (${pct(n)})', style: TextStyle(fontWeight: FontWeight.bold, color: nv.encre)),
                    ]),
                  ),
              ]),
            ),
          ];

    final large = Responsive.columns(context) > 1;
    Widget corps;
    if (_erreur != null) {
      corps = ListView(padding: const EdgeInsets.all(16), children: [
        ...selecteurs,
        SizedBox(height: 360, child: NvErreur(_erreur!, onRetry: () => _reessayer?.call())),
      ]);
    } else {
      final aide = _chargement
          ? const Padding(padding: EdgeInsets.all(32), child: NvChargement())
          : (total == 0
              ? const SizedBox(height: 220, child: NvVide(icon: Icons.pie_chart_outline, titre: 'Choisissez un inventaire et un emplacement.'))
              : const SizedBox.shrink());
      corps = large
          ? ListView(padding: const EdgeInsets.all(20), children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...selecteurs, aide])),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: resultats)),
              ]),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [...selecteurs, const SizedBox(height: 12), aide, ...resultats]);
    }
    return NvScaffold(
      title: 'Analyse',
      subtitle: _rayon?.displayName ?? 'Valeur des écarts par emplacement',
      wide: true,
      actions: [ActionEntete(icon: Icons.print_outlined, tooltip: 'Imprimer l\'analyse', onPressed: total == 0 ? null : _imprimer)],
      body: corps,
    );
  }
}
