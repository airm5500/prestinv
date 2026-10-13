// lib/ui/ecrans/versement_screen.dart
// Nouvelle interface — verser la collecte dans un inventaire OUVERT (choisi ou créé) : choix de
// l'inventaire, choix Remplacer / Ajouter pour les produits déjà comptés, progression, arrêt sans
// rien perdre, puis rapport ; reprise d'un versement interrompu. Même logique que VersementScreen
// (MoteurVersement, CollecteStore.marquerVersees, fetchTousInventairesOuverts).
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/rapport_versement_screen.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

class NvVersementScreen extends StatefulWidget {
  final Versement? reprise;
  const NvVersementScreen({super.key, this.reprise});

  @override
  State<NvVersementScreen> createState() => _NvVersementScreenState();
}

class _NvVersementScreenState extends State<NvVersementScreen> {
  late final ApiService _api;
  List<Inventory>? _inventaires;
  Object? _erreur;
  List<CollectedItem> _collecte = [];
  MoteurVersement? _moteur;
  AvancementVersement? _avancement;
  bool _enCours = false;
  bool _arret = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    _api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
    if (widget.reprise == null) {
      _charger();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirmerReprise());
    }
  }

  Future<void> _charger() async {
    setState(() {
      _inventaires = null;
      _erreur = null;
    });
    try {
      final collecte = await CollecteStore.lire();
      final inv = await _api.fetchTousInventairesOuverts();
      if (!mounted) return;
      setState(() {
        _collecte = collecte;
        _inventaires = inv;
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  List<CollectedItem> get _aVerser => _collecte.where((i) => !i.versee).toList();

  Future<void> _nouvelInventaire() async {
    final cree = await Navigator.of(context).push<Inventory>(nvRoute(const NvCreationInventaireScreen()));
    if (!mounted || cree == null) return;
    await _charger();
    final trouve = _inventaires?.where((i) => i.id == cree.id).firstOrNull ?? (cree.id.isEmpty ? null : cree);
    if (trouve != null && mounted) await _choisir(trouve);
  }

  Future<void> _choisir(Inventory inv) async {
    final items = _aVerser;
    if (items.isEmpty) {
      nvMessage(context, 'Rien à verser : toute la collecte est déjà versée.');
      return;
    }
    var mode = context.read<AppConfig>().isCumulEnabled ? ModeDejaCompte.ajouter : ModeDejaCompte.remplacer;
    final total = items.fold<int>(0, (s, i) => s + i.quantity);
    final codes = items.map((i) => i.code).toSet().length;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final nv = ctx.nv;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('Verser la collecte', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: nv.encre)),
                const SizedBox(height: 4),
                Text('$codes code(s), $total unité(s) vers « ${inv.libelle} ».', style: TextStyle(color: nv.gris, fontSize: 15)),
                const SectionTitre('Produit déjà compté dans cet inventaire'),
                for (final m in ModeDejaCompte.values) ...[
                  SoftCard(
                    key: ValueKey('mode-${m.name}'),
                    onTap: () => setD(() => mode = m),
                    bordure: mode == m ? nv.action : null,
                    semantique: '${m.libelle} : ${m.aide}${mode == m ? ', choisi' : ''}',
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(mode == m ? Icons.radio_button_checked : Icons.radio_button_off, color: mode == m ? nv.action : nv.gris),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.libelle, style: TextStyle(fontWeight: FontWeight.bold, color: nv.encre)),
                          Text(m.aide, style: TextStyle(color: nv.gris, fontSize: 13.5)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
                const Aide('Le serveur reçoit toujours la quantité TOTALE : verser deux fois ne crée aucun doublon.'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(key: const ValueKey('confirmer-versement'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Verser'))),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    await _executer(Versement.depuisCollecte(items, inventaireId: inv.id, inventaireLibelle: inv.libelle, mode: mode));
  }

  Future<void> _confirmerReprise() async {
    final v = widget.reprise!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reprendre le versement'),
        content: Text('« ${v.inventaireLibelle} » : ${v.aReprendre.length} ligne(s) à reprendre '
            '(${v.versees.length} déjà versée(s), elles ne sont pas renvoyées). Déjà comptés : ${v.mode.libelle}.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Plus tard')),
          FilledButton(key: const ValueKey('confirmer-reprise'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reprendre')),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      Navigator.of(context).pop();
      return;
    }
    await _executer(v);
  }

  Future<void> _executer(Versement v) async {
    final auth = context.read<AuthProvider>();
    final moteur = MoteurVersement(
      api: _api,
      queue: context.read<SaisieQueue>(),
      auteur: auth.user?.login ?? '',
      surLigneVersee: (l, v) => CollecteStore.marquerVersees(l.codes.toSet(), v.inventaireLibelle, l.verseeLe ?? DateTime.now()),
    );
    setState(() {
      _moteur = moteur;
      _enCours = true;
      _arret = false;
      _avancement = AvancementVersement(0, v.aReprendre.length, 'Préparation…');
    });
    final fini = await moteur.executer(v, onAvancement: (a) {
      if (mounted) setState(() => _avancement = a);
    });
    if (!mounted) return;
    setState(() => _enCours = false);
    Navigator.of(context).pushReplacement(nvRoute(NvRapportVersementScreen(versement: fini)));
  }

  Future<void> _annuler() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrêter le versement ?'),
        content: const Text('Ce qui est déjà envoyé reste envoyé. Le reste pourra être repris plus tard depuis la collecte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Continuer')),
          FilledButton(key: const ValueKey('confirmer-arret'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Arrêter')),
        ],
      ),
    );
    if (ok == true) {
      _moteur?.annuler();
      if (mounted) setState(() => _arret = true);
    }
  }

  Widget _progression(BuildContext context) {
    final a = _avancement;
    final nv = context.nv;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SoftCard(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Versement en cours…', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: nv.encre)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    key: const ValueKey('progression-versement'), value: a == null || a.total == 0 ? null : a.fraction, minHeight: 10, backgroundColor: nv.ligne),
              ),
              const SizedBox(height: 8),
              Text(a == null ? '' : '${a.fait} / ${a.total}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: nv.encre)),
              Text(a?.etape ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: nv.gris)),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const ValueKey('arreter-versement'),
                onPressed: _arret ? null : _annuler,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(_arret ? 'Arrêt après la ligne en cours…' : 'Arrêter (sans rien perdre)'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _choix(BuildContext context) {
    if (_erreur != null) return NvErreur(_erreur!, onRetry: _charger);
    final inv = _inventaires;
    if (inv == null) return const NvChargement();
    final aVerser = _aVerser;
    final nv = context.nv;
    final cols = Responsive.columns(context, compact: 1, medium: 2, expanded: 2);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Bandeau(
        ton: aVerser.isEmpty ? nv.ok : nv.info,
        icon: aVerser.isEmpty ? Icons.check_circle : Icons.upload,
        texte: aVerser.isEmpty
            ? 'Toute la collecte est déjà versée.'
            : '${aVerser.length} ligne(s) à verser (${aVerser.fold<int>(0, (s, i) => s + i.quantity)} unité(s))',
        detail: aVerser.isEmpty ? null : 'Choisissez l\'inventaire OUVERT qui les recevra.',
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('versement-nouvel-inventaire'),
        onPressed: _nouvelInventaire,
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('Nouvel inventaire…'),
      ),
      const SectionTitre('Inventaires ouverts'),
      if (inv.isEmpty)
        const SizedBox(height: 160, child: NvVide(icon: Icons.inventory_2_outlined, titre: 'Aucun inventaire ouvert.'))
      else
        ...cardColumn([
          for (final i in inv)
            SoftCard(
              key: ValueKey('versement-inv-${i.id}'),
              onTap: aVerser.isEmpty ? null : () => _choisir(i),
              semantique: 'Verser dans ${i.libelle}',
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Expanded(child: Text(i.libelle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: nv.encre))),
                Icon(Icons.upload, color: aVerser.isEmpty ? nv.ligne : nv.action),
              ]),
            ),
        ], cols, spacing: 8),
    ]);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_enCours,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _enCours) _annuler();
        },
        child: NvScaffold(
          title: 'Verser la collecte',
          subtitle: widget.reprise != null ? 'Reprise : ${widget.reprise!.inventaireLibelle}' : 'Dans un inventaire ouvert',
          wide: true,
          body: _enCours || widget.reprise != null ? _progression(context) : _choix(context),
        ),
      );
}
