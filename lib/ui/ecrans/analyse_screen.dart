// lib/ui/ecrans/analyse_screen.dart
// Nouvelle interface — ANALYSE (onglet de la barre du bas depuis la 4.13, maquette « Analyse ») :
//  1. choix de l'inventaire (l'inventaire en cours est présélectionné), puis de l'emplacement ;
//  2. « Tous les emplacements » (proposé d'office) : liste des emplacements avec, pour chacun, l'écart
//     valorisé au prix d'achat, le nombre de produits en écart et « comptés / total », totaux en haut.
//     Calcul avec la route existante (produits de l'emplacement, GET …/details), un emplacement après
//     l'autre : progression, Annuler, résultats partiels gardés, jamais d'écran figé. Toucher une ligne
//     ouvre l'aperçu de cet emplacement (sans nouvelle requête) ;
//  3. un emplacement choisi : aperçu inchangé — valeur du stock avant / après au prix d'achat, écart en
//     F CFA, répartition surplus / manquants / justes (camembert), impression PDF.
// Réglage « Afficher le stock théorique » désactivé : la valeur avant (stock théorique valorisé) est
// masquée, à l'écran comme dans le PDF. Même logique que AnalysisScreen pour l'aperçu.
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
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart' show libelleRayon;
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:provider/provider.dart';

/// Bilan d'un emplacement (ou de tous) : mêmes règles que l'aperçu (écart = compté − théorique,
/// valorisé au prix d'achat, sur toutes les lignes de l'emplacement).
class BilanEmplacement {
  final int produits;
  final int comptes;
  final int enEcart;
  final double ecartValorise;
  const BilanEmplacement({required this.produits, required this.comptes, required this.enEcart, required this.ecartValorise});

  factory BilanEmplacement.de(List<Product> ps) {
    var comptes = 0, enEcart = 0;
    double v = 0;
    for (final p in ps) {
      if (p.dtUpdated != null) comptes++;
      final e = p.quantiteSaisie - p.quantiteInitiale;
      if (e != 0) enEcart++;
      v += e * p.produitPrixAchat;
    }
    return BilanEmplacement(produits: ps.length, comptes: comptes, enEcart: enEcart, ecartValorise: v);
  }

  static BilanEmplacement somme(Iterable<BilanEmplacement> bs) => BilanEmplacement(
        produits: bs.fold(0, (s, b) => s + b.produits),
        comptes: bs.fold(0, (s, b) => s + b.comptes),
        enEcart: bs.fold(0, (s, b) => s + b.enEcart),
        ecartValorise: bs.fold(0.0, (s, b) => s + b.ecartValorise),
      );
}

class NvAnalyseScreen extends StatefulWidget {
  /// Inventaire présélectionné (inventaire en cours).
  final Inventory? inventaireInitial;
  const NvAnalyseScreen({super.key, this.inventaireInitial});

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

  // « Tous les emplacements » : produits lus par emplacement (calcul progressif, annulable).
  bool _tous = false;
  final Map<String, List<Product>> _parRayon = {};
  int _generation = 0;
  bool _calculTous = false;
  int _rayonEnCours = 0;
  Object? _erreurTous;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _api = ApiService(baseUrl: context.read<AppConfig>().currentApiUrl, cookie: () => auth.sessionCookie);
    _demarrer();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _demarrer() async {
    await _chargerInventaires();
    if (!mounted || _erreur != null) return;
    final initial = widget.inventaireInitial;
    final trouve = initial == null ? null : (_inventaires.where((i) => i.id == initial.id).firstOrNull ?? initial);
    if (trouve != null) await _choisirInventaire(trouve);
  }

  /// Calcule (ou complète) « Tous les emplacements » : un emplacement après l'autre.
  Future<void> _calculerTous() async {
    final inv = _inventaire;
    if (inv == null || _calculTous) return;
    final gen = ++_generation;
    setState(() {
      _calculTous = true;
      _erreurTous = null;
    });
    for (var i = 0; i < _rayons.length; i++) {
      final r = _rayons[i];
      if (_parRayon.containsKey(r.id)) continue;
      if (!mounted || gen != _generation) return;
      setState(() => _rayonEnCours = i + 1);
      try {
        final ps = await _api.fetchProducts(inv.id, r.id);
        if (!mounted || gen != _generation) return;
        setState(() => _parRayon[r.id] = ps);
      } catch (e) {
        if (!mounted || gen != _generation) return;
        setState(() {
          _erreurTous = e;
          _calculTous = false;
        });
        return;
      }
    }
    if (mounted && gen == _generation) setState(() => _calculTous = false);
  }

  void _annulerTous() {
    _generation++;
    setState(() => _calculTous = false);
    nvMessage(context, 'Calcul arrêté : les emplacements déjà lus restent affichés.', ton: context.nv.neutre);
  }

  void _choisirTous() {
    setState(() {
      _tous = true;
      _rayon = null;
      _produits = [];
    });
    _calculerTous();
  }

  /// Ligne de la liste « Tous » touchée : aperçu de l'emplacement, sans nouvelle requête.
  void _voirRayon(Rayon r) {
    final ps = _parRayon[r.id];
    if (ps == null) {
      _choisirRayon(r);
      return;
    }
    setState(() {
      _rayon = r;
      _produits = ps;
    });
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
    _generation++;
    setState(() {
      _inventaire = inv;
      _rayons = [];
      _rayon = null;
      _produits = [];
      _parRayon.clear();
      _calculTous = false;
      _erreurTous = null;
      _tous = false;
    });
    await _executer(() async => _rayons = await _api.fetchRayons(inv.id), () => _choisirInventaire(inv));
    // « Tous les emplacements » proposé d'office (maquette).
    if (mounted && _erreur == null && _rayons.isNotEmpty) _choisirTous();
  }

  Future<void> _choisirRayon(Rayon r) async {
    final inv = _inventaire;
    if (inv == null) return;
    setState(() {
      _rayon = r;
      _produits = [];
      _tous = false;
    });
    await _executer(() async {
      _produits = await _api.fetchProducts(inv.id, r.id);
      _parRayon[r.id] = _produits;
    }, () => _choisirRayon(r));
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
          avantVisible: context.read<AppConfig>().showTheoreticalStock,
        ),
        'Analyse_${NvExports.nomPropre(_rayon?.libelle ?? '')}',
      );
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur lors de l\'impression PDF : $e', ton: context.nv.erreur);
    }
  }

  /// Vrai après un choix dans la feuille (un choix « Tous » renvoie null comme une fermeture).
  bool _choixFait = false;

  Future<T?> _choisir<T>(String titre, List<T> items, String Function(T) libelle) async {
    _choixFait = false;
    final r = await showModalBottomSheet<({T v})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(titre, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ctx.nvSombre ? ctx.nv.encre : Pal.navy)),
            ),
            for (final i in items)
              ListTile(
                minTileHeight: 52,
                title: Text(libelle(i), style: TextStyle(fontWeight: i == null ? FontWeight.bold : null)),
                onTap: () => Navigator.pop(ctx, (v: i)),
              ),
          ]),
        ),
      ),
    );
    _choixFait = r != null;
    return r?.v;
  }

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

  /// Liste « Tous les emplacements » : totaux, progression, une ligne par emplacement.
  List<Widget> _listeTous(BuildContext context) {
    final nv = context.nv;
    final lus = [for (final r in _rayons) if (_parRayon[r.id] != null) BilanEmplacement.de(_parRayon[r.id]!)];
    final total = BilanEmplacement.somme(lus);
    final avancement = total.produits == 0 ? 0 : (total.comptes / total.produits * 100).round();
    final couleurTotal = total.ecartValorise < 0 ? nv.manquant : (total.ecartValorise > 0 ? nv.surplus : nv.encre);
    return [
      Row(children: [
        Expanded(child: Chiffre('Écart total', francs(total.ecartValorise, signeExplicite: true), couleur: couleurTotal, key: const ValueKey('nv-analyse-total-ecart'))),
        const SizedBox(width: 8),
        Expanded(child: Chiffre('Produits en écart', '${total.enEcart}', key: const ValueKey('nv-analyse-total-produits'))),
        const SizedBox(width: 8),
        Expanded(child: Chiffre('Avancement', '$avancement %')),
      ]),
      if (_calculTous) ...[
        const SizedBox(height: 10),
        Row(key: const ValueKey('nv-analyse-progression'), children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Emplacement $_rayonEnCours/${_rayons.length}', style: TextStyle(color: nv.encre, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: _rayons.isEmpty ? null : _parRayon.length / _rayons.length, minHeight: 6, backgroundColor: nv.ligne),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          TextButton(key: const ValueKey('nv-analyse-annuler'), onPressed: _annulerTous, child: const Text('Annuler')),
        ]),
      ],
      if (_erreurTous != null) ...[
        const SizedBox(height: 10),
        Bandeau(
          key: const ValueKey('nv-analyse-erreur'),
          ton: nv.erreur,
          icon: estSessionExpiree(_erreurTous) ? Icons.lock_clock : Icons.cloud_off,
          texte: 'Analyse incomplète',
          detail: messageErreur(_erreurTous!),
          action: 'Réessayer',
          onAction: _calculerTous,
        ),
      ] else if (!_calculTous && _parRayon.length < _rayons.length) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _calculerTous, icon: const Icon(Icons.play_arrow), label: const Text('Terminer le calcul')),
      ],
      const SectionTitre('Par emplacement (toucher pour le détail)'),
      for (final r in _rayons) ...[
        _ligneEmplacement(context, r),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _ligneEmplacement(BuildContext context, Rayon r) {
    final nv = context.nv;
    final ps = _parRayon[r.id];
    final b = ps == null ? null : BilanEmplacement.de(ps);
    final couleur = b == null ? nv.gris : (b.ecartValorise < 0 ? nv.manquant : (b.ecartValorise > 0 ? nv.surplus : nv.gris));
    return SoftCard(
      key: ValueKey('nv-analyse-ligne-${r.id}'),
      onTap: () => _voirRayon(r),
      semantique: b == null
          ? '${libelleRayon(r)}, pas encore lu'
          : '${libelleRayon(r)}, ${b.enEcart} produits en écart, écart ${francs(b.ecartValorise, signeExplicite: true)}',
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(libelleRayon(r), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: nv.encre)),
              Text(b == null ? (_calculTous ? 'Lecture…' : 'Pas encore lu') : '${b.enEcart} produit(s) en écart · ${b.comptes}/${b.produits}',
                  style: TextStyle(color: nv.gris, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          if (b == null && _calculTous)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (b != null)
            Text(francs(b.ecartValorise, signeExplicite: true), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: couleur)),
          Icon(Icons.chevron_right, color: nv.gris),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final s = _stats;
    final theoVisible = context.watch<AppConfig>().showTheoreticalStock;
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
                  if (i != null && mounted) _choisirInventaire(i);
                }),
      const SizedBox(height: 10),
      _selecteur(context,
          key: const ValueKey('nv-analyse-rayon'),
          label: 'Emplacement',
          valeur: _rayon?.displayName ?? (_tous ? 'Tous les emplacements' : null),
          onTap: _rayons.isEmpty
              ? null
              : () async {
                  final r = await _choisir<Rayon?>('Choisir un emplacement', [null, ..._rayons], (x) => x?.displayName ?? 'Tous les emplacements');
                  if (!mounted) return;
                  if (r != null) {
                    _parRayon.containsKey(r.id) ? _voirRayon(r) : _choisirRayon(r);
                  } else if (_choixFait) {
                    _choisirTous();
                  }
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
                  Expanded(child: Chiffre('Valeur avant', theoVisible ? francs(s.avant) : '•••')),
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
    final retourTous = _rayon != null && _parRayon.length > 1
        ? <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('nv-analyse-retour-tous'),
                onPressed: () => setState(() {
                  _rayon = null;
                  _produits = [];
                  _tous = true;
                }),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Tous les emplacements'),
              ),
            ),
          ]
        : const <Widget>[];
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
      if (_tous && _rayon == null && _rayons.isNotEmpty) {
        corps = ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          if (large) ...selecteurs else ...[...selecteurs],
          const SizedBox(height: 12),
          ..._listeTous(context),
        ]);
      } else {
      corps = large
          ? ListView(padding: const EdgeInsets.all(20), children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...selecteurs, aide])),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: resultats)),
              ]),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [...selecteurs, const SizedBox(height: 12), ...retourTous, aide, ...resultats]);
      }
    }
    return NvScaffold(
      title: 'Analyse',
      subtitle: _rayon?.displayName ?? (_tous ? 'Tous les emplacements' : 'Valeur des écarts par emplacement'),
      wide: true,
      actions: [ActionEntete(icon: Icons.print_outlined, tooltip: 'Imprimer l\'analyse', onPressed: total == 0 ? null : _imprimer)],
      body: corps,
    );
  }
}
