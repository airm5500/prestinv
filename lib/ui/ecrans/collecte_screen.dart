// lib/ui/ecrans/collecte_screen.dart
// Nouvelle interface — collecte hors ligne : scanner un code (douchette toujours prête), quantité au
// pavé (additionnée si le code est déjà dans la liste et pas encore versé), liste locale, verser dans
// un inventaire, rapports de versement, reprise d'un versement interrompu, CSV, impression, vider.
// Même logique et même stockage que CollectionScreen (CollecteStore, clé « collection_data »).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/scan/champ_douchette.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/ui/clavier.dart';
import 'package:prestinv/ui/ecrans/rapport_versement_screen.dart';
import 'package:prestinv/ui/ecrans/versement_screen.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NvCollecteScreen extends StatefulWidget {
  const NvCollecteScreen({super.key});

  @override
  State<NvCollecteScreen> createState() => _NvCollecteScreenState();
}

class _NvCollecteScreenState extends State<NvCollecteScreen> {
  final _champ = TextEditingController();
  final _focus = FocusNode();
  List<CollectedItem> _items = [];
  bool _chargement = false;
  bool _impression = false;
  bool _feuille = false;
  Versement? _aReprendre;
  late final CibleDouchette _cible;
  static final _date = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _cible = CibleDouchette(active: () => mounted && !_feuille && (ModalRoute.of(context)?.isCurrent ?? true), onCode: _scan);
    Douchette.instance.ajouter(_cible);
    _charger();
  }

  @override
  void dispose() {
    Douchette.instance.retirer(_cible);
    _champ.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    final items = await CollecteStore.lire();
    final reprise = await StockageVersements.aReprendre();
    if (!mounted) return;
    setState(() {
      _items = items;
      _aReprendre = reprise;
      _chargement = false;
    });
  }

  Future<void> _enregistrer() => CollecteStore.ecrire(_items);

  List<CollectedItem> get _nonVersees => _items.where((i) => !i.versee).toList();

  Future<void> _verser() async {
    await Navigator.of(context).push(nvRoute(const NvVersementScreen()));
    if (mounted) await _charger();
  }

  Future<void> _reprendre() async {
    final v = _aReprendre;
    if (v == null) return;
    await Navigator.of(context).push(nvRoute(NvVersementScreen(reprise: v)));
    if (mounted) await _charger();
  }

  Future<void> _rapports() async {
    final tous = await StockageVersements.lire();
    if (!mounted) return;
    final choisi = await showModalBottomSheet<Versement>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final nv = ctx.nv;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              const Text('Rapports de versement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (tous.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Aucun versement pour l\'instant.', style: TextStyle(color: nv.gris))),
              for (final v in tous)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftCard(
                    onTap: () => Navigator.pop(ctx, v),
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${DateFormat('dd/MM HH:mm').format(v.debut)} — ${v.inventaireLibelle}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${v.versees.length} versé(s), ${v.nonReconnues.length} non reconnu(s), ${v.erreurs.length + v.aVerser.length} à reprendre',
                          style: TextStyle(color: nv.gris)),
                    ]),
                  ),
                ),
            ]),
          ),
        );
      },
    );
    if (choisi == null || !mounted) return;
    await Navigator.of(context).push(nvRoute(NvRapportVersementScreen(versement: choisi)));
    if (mounted) await _charger();
  }

  Future<void> _vider() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vider la liste ?'),
        content: const Text('Attention, toutes les données collectées seront perdues.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Vider', style: TextStyle(color: ctx.nv.erreur.fg))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _items.clear());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('collection_data');
  }

  Future<void> _supprimer(CollectedItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la ligne ?'),
        content: Text('Code : ${item.code}\nQuantité : ${item.quantity}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Supprimer', style: TextStyle(color: ctx.nv.erreur.fg))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _items.remove(item));
    await _enregistrer();
    if (mounted) nvMessage(context, 'Ligne supprimée.', duree: const Duration(seconds: 1));
  }

  void _scan(String brut) {
    final code = SaisieInput.nettoyerRecherche(brut);
    if (code.isEmpty) return;
    _champ.clear();
    _quantite(code);
  }

  void _ajouter(String code, int q) {
    setState(() {
      final existant = _items.where((i) => i.code == code && !i.versee).firstOrNull;
      if (existant != null) {
        existant.quantity += q;
        _items.remove(existant);
        _items.insert(0, existant);
      } else {
        _items.insert(0, CollectedItem(code: code, quantity: q, dateScan: DateTime.now()));
      }
    });
    _enregistrer();
    nvMessage(context, 'Ajouté : $code (qté : $q)', ton: context.nv.ok, duree: const Duration(seconds: 1));
  }

  Future<void> _quantite(String code) async {
    var saisie = '';
    StateSetter? maj;
    BuildContext? fctx;
    void touche(String k) {
      final c = fctx;
      if (c == null) return;
      if (k == 'OK') {
        final q = int.tryParse(saisie) ?? 0;
        if (q > 0) _ajouter(code, q);
        Navigator.of(c).pop();
      } else if (k == 'DEL') {
        maj?.call(() => saisie = saisie.isEmpty ? '' : saisie.substring(0, saisie.length - 1));
      } else {
        maj?.call(() => saisie = SaisieInput.ajouterChiffre(saisie, k));
      }
    }

    final cible = CibleDouchette(active: () => _feuille, onChiffres: (t) => t.split('').forEach(touche), onEffacer: () => touche('DEL'), onValider: () => touche('OK'));
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
          fctx = ctx;
          return StatefulBuilder(builder: (ctx, set) {
            maj = set;
            final nv = ctx.nv;
            return SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Ajout à la collecte', style: TextStyle(color: nv.gris)),
                    Text('Code $code', key: const ValueKey('nv-collecte-code'), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: nv.encre)),
                    const SizedBox(height: 10),
                    AfficheQuantite(label: 'Quantité', valeur: saisie, aide: 'Additionnée si le code est déjà dans la liste'),
                  ]),
                ),
                NvPave(onKey: touche, hauteur: NvPave.hauteurPour(ctx)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Annuler', style: TextStyle(color: nv.erreur.fg))),
                ),
              ]),
            );
          });
        },
      );
    } finally {
      _feuille = false;
      Douchette.instance.retirer(cible);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focus.canRequestFocus) _focus.requestFocus();
      });
    }
  }

  Future<void> _csv() async {
    if (_items.isEmpty) {
      nvMessage(context, 'La liste est vide.');
      return;
    }
    try {
      final nom = 'inventaireCollection_${NvExports.horodatage()}.csv';
      final r = await NvExports.ecrireCsv(NvExports.csvCollecte(_items), nom, 'Export Inventaire');
      if (mounted && r.cheminTelechargements != null) nvMessage(context, 'Fichier sauvegardé dans Téléchargements :\n$nom', ton: context.nv.ok);
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur export : $e', ton: context.nv.erreur);
    }
  }

  Future<void> _imprimer() async {
    if (_impression || _items.isEmpty) return;
    setState(() => _impression = true);
    try {
      final items = List<CollectedItem>.of(_items);
      await NvExports.imprimer(() => NvExports.pdfCollecte(items), 'Collecte_${NvExports.horodatage()}');
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur impression : $e', ton: context.nv.erreur);
    } finally {
      if (mounted) setState(() => _impression = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final nonVersees = _nonVersees;
    final unites = nonVersees.fold<int>(0, (s, i) => s + i.quantity);
    final cols = Responsive.columns(context, compact: 1, medium: 2, expanded: 3);
    return NvScaffold(
      title: 'Collecte hors ligne',
      subtitle: 'Sans réseau · versement possible plus tard',
      wide: true,
      actions: [
        ActionEntete(icon: Icons.receipt_long, tooltip: 'Rapports de versement', onPressed: _rapports),
        PopupMenuButton<String>(
          tooltip: 'Plus',
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) {
            if (v == 'csv') _csv();
            if (v == 'pdf') _imprimer();
            if (v == 'vider') _vider();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'csv', enabled: _items.isNotEmpty, child: const Text('Générer le CSV (Téléchargements)')),
            PopupMenuItem(value: 'pdf', enabled: _items.isNotEmpty && !_impression, child: const Text('Imprimer la liste')),
            PopupMenuItem(value: 'vider', enabled: _items.isNotEmpty, child: const Text('Vider la liste')),
          ],
        ),
      ],
      header: [
        Row(children: [
          Expanded(child: KpiTile('${nonVersees.length}', 'À verser')),
          const SizedBox(width: 8),
          Expanded(child: KpiTile('$unites', 'Unités')),
          const SizedBox(width: 8),
          Expanded(child: KpiTile('${_items.length - nonVersees.length}', 'Versés')),
        ]),
      ],
      body: _chargement
          ? const NvChargement()
          : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
              CadreScan(
                champ: ChampDouchette(
                  key: const ValueKey('champ-scan'),
                  controller: _champ,
                  focusNode: _focus,
                  label: 'Scanner un code',
                  hint: 'EAN, code-barres…',
                  onCode: _scan,
                ),
              ),
              const SizedBox(height: 12),
              if (_aReprendre != null) ...[
                Bandeau(
                  key: const ValueKey('bandeau-reprise'),
                  ton: nv.attente,
                  icon: Icons.warning_amber,
                  texte: 'Versement interrompu vers « ${_aReprendre!.inventaireLibelle} »',
                  detail: '${_aReprendre!.aReprendre.length} ligne(s) à reprendre ; ce qui est envoyé reste envoyé.',
                  action: 'Reprendre',
                  onAction: _reprendre,
                ),
                const SizedBox(height: 12),
              ] else if (_items.isNotEmpty && nonVersees.isEmpty) ...[
                Bandeau(key: const ValueKey('bandeau-collecte-versee'), ton: nv.ok, icon: Icons.check_circle, texte: 'Collecte entièrement versée'),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                key: const ValueKey('verser-collecte'),
                onPressed: nonVersees.isEmpty ? null : _verser,
                icon: const Icon(Icons.upload),
                label: const Text('Verser dans un inventaire'),
              ),
              const SectionTitre('Codes collectés'),
              if (_items.isEmpty)
                const SizedBox(height: 220, child: NvVide(icon: Icons.list_alt, titre: 'Aucune donnée collectée.', detail: 'Scannez des produits pour commencer.'))
              else
                ...cardColumn([
                  for (final item in _items)
                    SoftCard(
                      key: ValueKey('nv-collecte-${item.code}-${item.versee}'),
                      bande: item.versee ? Pal.green : null,
                      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.code, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: nv.encre)),
                            Text(_date.format(item.dateScan), style: TextStyle(color: nv.gris, fontSize: 13)),
                            if (item.versee)
                              Text('versé le ${DateFormat('dd/MM HH:mm').format(item.verseLe!)} dans « ${item.verseDans ?? ''} »',
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: nv.ok.fg, fontSize: 13, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        Text('${item.quantity}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21, color: nv.encre)),
                        IconButton(
                          tooltip: 'Supprimer cette ligne',
                          icon: Icon(Icons.delete_outline, color: nv.erreur.fg),
                          onPressed: () => _supprimer(item),
                        ),
                      ]),
                    ),
                ], cols, spacing: 8),
            ]),
    );
  }
}
