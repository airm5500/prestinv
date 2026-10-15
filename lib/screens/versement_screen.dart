// lib/screens/versement_screen.dart
// Verser la collecte hors ligne dans un inventaire OUVERT (choisi ou créé) : choix de l'inventaire,
// choix global pour les lignes déjà comptées (Remplacer / Ajouter), confirmation, barre de progression,
// annulation sûre, puis rapport. Reprise d'un versement interrompu ([reprise]).
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/screens/creation_inventaire_screen.dart';
import 'package:prestinv/screens/rapport_versement_screen.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:provider/provider.dart';

class VersementScreen extends StatefulWidget {
  /// Versement interrompu à reprendre (sinon : nouveau versement de la collecte).
  final Versement? reprise;
  const VersementScreen({super.key, this.reprise});

  @override
  State<VersementScreen> createState() => _VersementScreenState();
}

class _VersementScreenState extends State<VersementScreen> {
  late final ApiService _api;
  List<Inventory>? _inventaires;
  Object? _erreurListe;
  List<CollectedItem> _collecte = [];

  MoteurVersement? _moteur;
  AvancementVersement? _avancement;
  bool _enCours = false;
  bool _annulationDemandee = false;

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
      _erreurListe = null;
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
      if (mounted) setState(() => _erreurListe = e);
    }
  }

  List<CollectedItem> get _aVerser => _collecte.where((i) => !i.versee).toList();

  /// « Nouvel inventaire… » : 4.15, l'inventaire créé ne contient QUE les produits à verser, sur leurs
  /// emplacements (avant : tous les produits de tous les emplacements), puis il est proposé au versement.
  Future<void> _nouvelInventaire() async {
    final codes = [for (final i in _aVerser) i.code];
    final cree = await Navigator.of(context).push<Inventory>(MaterialPageRoute(
        builder: (_) => CreationInventaireScreen(codesCollectes: codes.isEmpty ? null : codes)));
    if (!mounted || cree == null) return;
    await _charger();
    String cle(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final trouve = _inventaires?.where((i) => i.id == cree.id && cree.id.isNotEmpty).firstOrNull ??
        _inventaires?.where((i) => cle(i.libelle) == cle(cree.libelle)).firstOrNull ??
        (cree.id.isEmpty ? null : cree);
    if (trouve != null && mounted) await _choisir(trouve);
  }

  Future<void> _choisir(Inventory inv) async {
    final items = _aVerser;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rien à verser : toute la collecte est déjà versée.')));
      return;
    }
    final config = context.read<AppConfig>();
    // Réglage existant : Cumul activé → « Ajouter » proposé ; sinon « Remplacer » (comme la saisie).
    var mode = config.isCumulEnabled ? ModeDejaCompte.ajouter : ModeDejaCompte.remplacer;
    final total = items.fold<int>(0, (s, i) => s + i.quantity);
    final codes = items.map((i) => i.code).toSet().length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Verser la collecte'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$codes code(s), $total unité(s) vers « ${inv.libelle} ».'),
            const SizedBox(height: 12),
            const Text('Si un produit est DÉJÀ COMPTÉ dans cet inventaire :', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final m in ModeDejaCompte.values)
              RadioListTile<ModeDejaCompte>(
                key: ValueKey('mode-${m.name}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: m,
                groupValue: mode,
                title: Text(m.libelle),
                subtitle: Text(m.aide),
                onChanged: (v) => setD(() => mode = v!),
              ),
            const SizedBox(height: 4),
            Text('Le serveur reçoit toujours la quantité TOTALE : verser deux fois ne crée aucun doublon.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(key: const ValueKey('confirmer-versement'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Verser')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final v = Versement.depuisCollecte(items, inventaireId: inv.id, inventaireLibelle: inv.libelle, mode: mode);
    await _executer(v);
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
          ElevatedButton(key: const ValueKey('confirmer-reprise'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reprendre')),
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
      _annulationDemandee = false;
      _avancement = AvancementVersement(0, v.aReprendre.length, 'Préparation…');
    });
    final fini = await moteur.executer(v, onAvancement: (a) {
      if (mounted) setState(() => _avancement = a);
    });
    if (!mounted) return;
    setState(() => _enCours = false);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => RapportVersementScreen(versement: fini)));
  }

  Future<void> _annuler() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrêter le versement ?'),
        content: const Text('Ce qui est déjà envoyé reste envoyé. Le reste pourra être repris plus tard depuis la collecte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Continuer')),
          ElevatedButton(key: const ValueKey('confirmer-arret'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Arrêter')),
        ],
      ),
    );
    if (ok == true) {
      _moteur?.annuler();
      if (mounted) setState(() => _annulationDemandee = true);
    }
  }

  Widget _progression() {
    final a = _avancement;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Versement en cours…', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        LinearProgressIndicator(key: const ValueKey('progression-versement'), value: a == null || a.total == 0 ? null : a.fraction, minHeight: 8),
        const SizedBox(height: 8),
        Text(a == null ? '' : '${a.fait} / ${a.total}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(a?.etape ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const ValueKey('arreter-versement'),
          onPressed: _annulationDemandee ? null : _annuler,
          icon: const Icon(Icons.stop_circle_outlined),
          label: Text(_annulationDemandee ? 'Arrêt après la ligne en cours…' : 'Arrêter (sans rien perdre)'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enCours,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _enCours) _annuler();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Verser la collecte')),
        body: SafeArea(child: _enCours || widget.reprise != null ? _progression() : _choix()),
      ),
    );
  }

  Widget _choix() {
    if (_erreurListe != null) return LoadErrorView.depuis(_erreurListe!, onRetry: _charger);
    final inv = _inventaires;
    if (inv == null) return const Center(child: CircularProgressIndicator());
    final aVerser = _aVerser;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          aVerser.isEmpty
              ? 'Toute la collecte est déjà versée.'
              : '${aVerser.length} ligne(s) à verser (${aVerser.fold<int>(0, (s, i) => s + i.quantity)} unité(s)). Choisissez l\'inventaire OUVERT :',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: OutlinedButton.icon(
          key: const ValueKey('versement-nouvel-inventaire'),
          onPressed: _nouvelInventaire,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Nouvel inventaire…'),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: inv.isEmpty
            ? const Center(child: Text('Aucun inventaire ouvert.'))
            : ListView.builder(
                itemCount: inv.length,
                itemBuilder: (_, i) => Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    key: ValueKey('versement-inv-${inv[i].id}'),
                    title: Text(inv[i].libelle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.upload),
                    onTap: aVerser.isEmpty ? null : () => _choisir(inv[i]),
                  ),
                ),
              ),
      ),
    ]);
  }
}
