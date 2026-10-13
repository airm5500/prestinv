// lib/ui/ecrans/restants_screen.dart
// Nouvelle interface — restants (produits jamais comptés). Même logique que UncountedScreen :
// fetchUntouchedProducts / fetchUntouchedProductsByRayon, filtre par emplacement (état des rayons),
// filtre sur le stock théorique, recherche / scan (douchette), saisie enregistrée sur l'appareil puis
// envoyée ; le produit ne quitte la liste qu'après confirmation du serveur (champ vide refusé).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_correction.dart';
import 'package:prestinv/scan/champ_douchette.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/ui/clavier.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:provider/provider.dart';

/// Filtre sur le stock théorique (mêmes opérateurs que l'écran d'origine).
enum FiltreStock { aucun, inferieur, superieur, inferieurEgal, superieurEgal, different, egal }

extension FiltreStockLibelle on FiltreStock {
  String get symbole => switch (this) {
        FiltreStock.aucun => '',
        FiltreStock.inferieur => '<',
        FiltreStock.superieur => '>',
        FiltreStock.inferieurEgal => '≤',
        FiltreStock.superieurEgal => '≥',
        FiltreStock.different => '≠',
        FiltreStock.egal => '=',
      };
  String get libelle => switch (this) {
        FiltreStock.aucun => 'Aucun filtre',
        FiltreStock.superieur => 'Supérieur à (>)',
        FiltreStock.inferieur => 'Inférieur à (<)',
        FiltreStock.superieurEgal => 'Supérieur ou égal (≥)',
        FiltreStock.inferieurEgal => 'Inférieur ou égal (≤)',
        FiltreStock.egal => 'Égal à (=)',
        FiltreStock.different => 'Différent de (≠)',
      };
  bool garde(int stock, int v) => switch (this) {
        FiltreStock.aucun => true,
        FiltreStock.inferieur => stock < v,
        FiltreStock.superieur => stock > v,
        FiltreStock.inferieurEgal => stock <= v,
        FiltreStock.superieurEgal => stock >= v,
        FiltreStock.different => stock != v,
        FiltreStock.egal => stock == v,
      };
}

class NvRestantsScreen extends StatefulWidget {
  final Inventory inventaire;
  const NvRestantsScreen({super.key, required this.inventaire});

  @override
  State<NvRestantsScreen> createState() => _NvRestantsScreenState();
}

class _NvRestantsScreenState extends State<NvRestantsScreen> {
  late final ApiService _api;
  final _champ = TextEditingController();
  final _focus = FocusNode();
  Timer? _frappe;
  List<Product> _tous = [];
  List<Product> _affiches = [];
  List<Rayon> _rayons = [];
  Rayon? _rayon;
  Object? _erreur;
  Object? _erreurRayons;
  bool _chargement = true;
  FiltreStock _filtre = FiltreStock.aucun;
  int _valeur = 0;
  bool _feuille = false;
  late final CibleDouchette _cible;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _api = ApiService(baseUrl: context.read<AppConfig>().currentApiUrl, cookie: () => auth.sessionCookie);
    _cible = CibleDouchette(active: () => mounted && !_feuille && (ModalRoute.of(context)?.isCurrent ?? true), onCode: _rechercher);
    Douchette.instance.ajouter(_cible);
    _chargerRayons();
  }

  @override
  void dispose() {
    Douchette.instance.retirer(_cible);
    _champ.dispose();
    _focus.dispose();
    _frappe?.cancel();
    super.dispose();
  }

  Future<void> _chargerRayons() async {
    try {
      final r = await _api.fetchRayons(widget.inventaire.id);
      if (!mounted) return;
      setState(() {
        _rayons = r;
        _erreurRayons = null;
      });
      context.read<EntryProvider>().loadRayonStatuses(_api, widget.inventaire.id);
    } catch (e) {
      if (mounted) setState(() => _erreurRayons = e);
    }
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final ps = _rayon != null
          ? await _api.fetchUntouchedProductsByRayon(widget.inventaire.id, _rayon!.id)
          : await _api.fetchUntouchedProducts(widget.inventaire.id);
      if (!mounted) return;
      setState(() {
        _tous = ps;
        _filtrer();
        _chargement = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e;
          _chargement = false;
        });
      }
    }
  }

  void _filtrer() {
    final q = _champ.text.toLowerCase();
    _affiches = _tous
        .where((p) => (q.isEmpty || p.produitCip.contains(q) || p.produitName.toLowerCase().contains(q)) && _filtre.garde(p.quantiteInitiale, _valeur))
        .toList();
  }

  void _surTexte(String t) {
    setState(_filtrer);
    _frappe?.cancel();
    if (t.isNotEmpty) _frappe = Timer(const Duration(milliseconds: 500), () => _rechercher(t));
  }

  Future<void> _rechercher(String texte) async {
    final q = SaisieInput.nettoyerRecherche(texte);
    if (q.isEmpty) return;
    try {
      final r = _rayon != null
          ? await _api.fetchUntouchedProductsByRayon(widget.inventaire.id, _rayon!.id, query: q)
          : await _api.fetchUntouchedProducts(widget.inventaire.id, query: q);
      if (!mounted) return;
      if (r.length == 1) {
        _champ.clear();
        setState(_filtrer);
        _saisir(r.first);
      } else if (r.isNotEmpty) {
        setState(() {
          _tous = r;
          _filtrer();
        });
      } else {
        nvMessage(context, 'Aucun restant pour « ${CodeOuTexte.court(q)} ».', ton: context.nv.attente);
      }
    } catch (e) {
      if (mounted) nvMessage(context, messageErreur(e), ton: context.nv.erreur);
    }
  }

  Future<void> _choisirRayon() async {
    final statuts = context.read<EntryProvider>().rayonStatuses;
    final r = await showModalBottomSheet<({Rayon? r})>(
      context: context,
      builder: (ctx) {
        final nv = ctx.nv;
        return SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: const Text('Tous les emplacements', style: TextStyle(fontWeight: FontWeight.bold)), onTap: () => Navigator.pop(ctx, (r: null))),
            for (final x in _rayons)
              ListTile(
                selected: x.id == _rayon?.id,
                title: Text('${x.code} - ${x.libelle}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: switch (statuts[x.id]) {
                  2 => Pastille('terminé', ton: nv.ok),
                  1 => Pastille('commencé', ton: nv.attente),
                  _ => null,
                },
                onTap: () => Navigator.pop(ctx, (r: x)),
              ),
          ]),
        );
      },
    );
    if (r == null || !mounted || r.r?.id == _rayon?.id) return;
    setState(() => _rayon = r.r);
    _charger();
  }

  Future<void> _filtreStock() async {
    var type = _filtre;
    final ctrl = TextEditingController(text: '$_valeur');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => LibererApres(
        objets: [ctrl],
        child: StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Filtrer par stock théorique'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in FiltreStock.values)
              RadioListTile<FiltreStock>(contentPadding: EdgeInsets.zero, dense: true, value: f, groupValue: type, title: Text(f.libelle), onChanged: (v) => setD(() => type = v!)),
            if (type != FiltreStock.aucun)
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Valeur de référence', hintText: 'Ex : 0'),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Appliquer')),
          ],
        ),
      ),
      ),
    );
    final v = int.tryParse(ctrl.text) ?? 0;
    if (ok == true && mounted) {
      setState(() {
        _filtre = type;
        _valeur = v;
        _filtrer();
      });
    }
  }

  /// Saisie d'un restant (feuille avec pavé « Enregistrer »).
  Future<void> _saisir(Product p) async {
    var saisie = '';
    var envoi = false;
    String? erreur;
    StateSetter? maj;
    final config = context.read<AppConfig>();
    final auteur = context.read<AuthProvider>().user?.login ?? '';
    final entry = context.read<EntryProvider>();

    Future<void> touche(BuildContext ctx, String k) async {
      if (envoi) return;
      if (k == 'DEL') {
        maj?.call(() => saisie = saisie.isEmpty ? '' : saisie.substring(0, saisie.length - 1));
      } else if (k != 'OK') {
        maj?.call(() {
          saisie = SaisieInput.ajouterChiffre(saisie, k);
          erreur = null;
        });
      } else {
        final e = SaisieInput.erreurQuantite(saisie);
        if (e != null) {
          maj?.call(() => erreur = e);
          return;
        }
        final q = SaisieInput.parseQuantite(saisie)!;
        maj?.call(() {
          envoi = true;
          erreur = null;
        });
        String? echec;
        try {
          final r = await corrigerQuantite(
            inventoryId: widget.inventaire.id,
            inventoryName: widget.inventaire.libelle,
            product: p,
            quantite: q,
            origine: OrigineSaisie.restants,
            rayonId: _rayon?.id,
            rayonLibelle: _rayon?.libelle,
            auteur: auteur,
          );
          if (!r.estOk) echec = messageEchecCorrection(r);
        } catch (e) {
          echec = 'Enregistrement impossible sur l\'appareil : $e';
        }
        if (echec != null) {
          maj?.call(() {
            envoi = false;
            erreur = echec;
          });
          return;
        }
        if (ctx.mounted) Navigator.of(ctx).pop();
        if (!mounted) return;
        nvMessage(context, '${p.produitName} : $q saisi', ton: context.nv.ok, duree: const Duration(seconds: 2));
        setState(() {
          _tous.removeWhere((x) => x.id == p.id);
          _filtrer();
        });
        entry.loadRayonStatuses(_api, widget.inventaire.id);
      }
    }

    late final CibleDouchette cible;
    BuildContext? feuilleCtx;
    cible = CibleDouchette(
      active: () => _feuille,
      onChiffres: (t) {
        final c = feuilleCtx;
        if (c != null) t.split('').forEach((k) => touche(c, k));
      },
      onEffacer: () {
        final c = feuilleCtx;
        if (c != null) touche(c, 'DEL');
      },
      onValider: () {
        final c = feuilleCtx;
        if (c != null) touche(c, 'OK');
      },
    );
    Douchette.instance.ajouter(cible);
    _feuille = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (ctx) {
          feuilleCtx = ctx;
          return StatefulBuilder(builder: (ctx, set) {
            maj = set;
            final nv = ctx.nv;
            return SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(p.produitName, key: const ValueKey('nv-restant-produit'), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: nv.encre)),
                    Text('CIP ${p.produitCip}${p.locationLabel != null ? ' · ${p.locationLabel}' : ''}', style: TextStyle(color: nv.gris)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Chiffre('Stock théorique', config.showTheoreticalStock ? '${p.quantiteInitiale}' : '***')),
                      const SizedBox(width: 8),
                      Expanded(child: Chiffre('Prix achat', francs(p.produitPrixAchat))),
                    ]),
                    const SizedBox(height: 10),
                    AfficheQuantite(label: 'Quantité comptée', valeur: saisie, erreur: erreur),
                  ]),
                ),
                NvPave(ok: 'Enregistrer', okActif: !envoi, onKey: (k) => touche(ctx, k), hauteur: NvPave.hauteurPour(ctx)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextButton(
                    key: const ValueKey('nv-restant-annuler'),
                    onPressed: envoi ? null : () => Navigator.of(ctx).pop(),
                    child: Text('Annuler', style: TextStyle(color: nv.erreur.fg)),
                  ),
                ),
              ]),
            );
          });
        },
      );
    } finally {
      _feuille = false;
      Douchette.instance.retirer(cible);
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focus.canRequestFocus) _focus.requestFocus();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final config = context.watch<AppConfig>();
    context.watch<EntryProvider>();
    final cols = Responsive.columns(context, compact: 1, medium: 2, expanded: 3);

    final filtres = Wrap(spacing: 8, runSpacing: 8, children: [
      ActionChip(
        key: const ValueKey('nv-restants-rayon'),
        avatar: const Icon(Icons.location_on_outlined, size: 18),
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(_rayon == null ? 'Tous les emplacements' : _rayon!.libelle, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
        onPressed: _rayons.isEmpty ? null : _choisirRayon,
        labelStyle: TextStyle(color: nv.action, fontWeight: FontWeight.bold),
        shape: const StadiumBorder(),
      ),
      ActionChip(
        key: const ValueKey('nv-restants-stock'),
        avatar: Icon(_filtre == FiltreStock.aucun ? Icons.filter_alt_outlined : Icons.filter_alt, size: 18),
        label: Text(_filtre == FiltreStock.aucun ? 'Stock théo.' : 'Stock ${_filtre.symbole} $_valeur'),
        onPressed: _filtreStock,
        labelStyle: TextStyle(color: nv.action, fontWeight: FontWeight.bold),
        shape: const StadiumBorder(),
      ),
    ]);

    Widget corps;
    if (_chargement) {
      corps = const NvChargement(texte: 'Chargement des restants…');
    } else if (_erreur != null) {
      corps = NvErreur(_erreur!, onRetry: _charger);
    } else {
      corps = RefreshIndicator(
        onRefresh: _charger,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          if (_erreurRayons != null) ...[
            Bandeau(
              ton: nv.erreur,
              icon: Icons.cloud_off,
              texte: 'Emplacements non chargés',
              detail: messageErreur(_erreurRayons!),
              action: 'Réessayer',
              onAction: _chargerRayons,
            ),
            const SizedBox(height: 10),
          ],
          CadreScan(
            champ: ChampDouchette(
              key: const ValueKey('champ-scan'),
              controller: _champ,
              focusNode: _focus,
              label: 'Scanner ou rechercher',
              hint: 'CIP, nom…',
              onCode: _rechercher,
              onTexte: _surTexte,
            ),
          ),
          const SizedBox(height: 12),
          filtres,
          const SizedBox(height: 12),
          if (_affiches.isEmpty)
            SizedBox(
              height: 240,
              child: NvVide(
                icon: Icons.task_alt,
                titre: _tous.isEmpty ? 'Aucun produit restant' : 'Aucun produit pour ce filtre',
                detail: _tous.isEmpty ? 'Tout a été compté dans ce périmètre.' : null,
              ),
            )
          else
            ...cardColumn([
              for (final p in _affiches)
                SoftCard(
                  key: ValueKey('nv-restant-${p.id}'),
                  onTap: () => _saisir(p),
                  semantique: '${p.produitName}, stock théorique ${config.showTheoreticalStock ? p.quantiteInitiale : 'masqué'}. Toucher pour saisir.',
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.produitName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: nv.encre)),
                        Text('CIP ${p.produitCip}${p.locationLabel != null ? ' · ${p.locationLabel}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: nv.gris, fontSize: 13.5)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('théo.', style: TextStyle(color: nv.gris, fontSize: 12)),
                      Text(config.showTheoreticalStock ? '${p.quantiteInitiale}' : '***',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: p.quantiteInitiale < 0 ? nv.manquant : nv.encre)),
                    ]),
                  ]),
                ),
            ], cols, spacing: 10),
        ]),
      );
    }

    return NvScaffold(
      title: 'Restants à faire',
      subtitle: widget.inventaire.libelle,
      wide: true,
      actions: [ActionEntete(icon: Icons.refresh, tooltip: 'Actualiser la liste', onPressed: _charger)],
      header: [
        Row(children: [
          Expanded(child: KpiTile(_chargement ? '…' : '${_tous.length}', 'Produits restants', highlight: !_chargement && _tous.isNotEmpty)),
          const SizedBox(width: 8),
          Expanded(child: KpiTile(_rayon?.libelle ?? 'Tous', 'Emplacement')),
        ]),
      ],
      body: corps,
    );
  }
}

/// Texte court pour un message (code ou recherche).
class CodeOuTexte {
  CodeOuTexte._();
  static String court(String s) => s.length > 24 ? '${s.substring(0, 24)}…' : s;
}
