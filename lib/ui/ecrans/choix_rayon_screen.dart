// lib/ui/ecrans/choix_rayon_screen.dart
// Nouvelle interface — choix du rayon (maquette A/B, au centre) : rayons avec leur état (pas commencé /
// commencé / terminé, lu par EntryProvider.loadRayonStatuses comme le sélecteur d'origine), saisies en
// attente d'envoi par rayon (file des saisies), filtres Tous / À faire / En cours / Terminés,
// recherche. Toucher un rayon ouvre la saisie guidée de ce rayon.
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

class NvChoixRayonScreen extends StatefulWidget {
  final Inventory inventaire;
  const NvChoixRayonScreen({super.key, required this.inventaire});

  @override
  State<NvChoixRayonScreen> createState() => _NvChoixRayonScreenState();
}

class _NvChoixRayonScreenState extends State<NvChoixRayonScreen> {
  late final ApiService _api;
  int _filtre = 0;
  bool _recherche = false;
  final _texte = TextEditingController();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _api = ApiService(baseUrl: context.read<AppConfig>().currentApiUrl, cookie: () => auth.sessionCookie);
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    if (!mounted) return;
    final p = context.read<EntryProvider>();
    p.auteur = context.read<AuthProvider>().user?.login ?? '';
    p.ouvrirInventaire(widget.inventaire.id, libelle: widget.inventaire.libelle);
    await p.fetchRayons(_api, widget.inventaire.id);
  }

  Future<void> _ouvrir(Rayon r) async {
    await Navigator.of(context).push(nvRoute(NvSaisieGuideeScreen(inventaire: widget.inventaire, rayonId: r.id)));
    if (!mounted) return;
    context.read<EntryProvider>().loadRayonStatuses(_api, widget.inventaire.id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntryProvider>();
    final q = context.watch<SaisieQueue>();
    final nv = context.nv;
    final rayons = provider.rayons;
    final statuts = provider.rayonStatuses;
    int nb(int? s) => rayons.where((r) => statuts[r.id] == s).length;
    final labels = ['Tous ${rayons.length}', 'À faire ${nb(0)}', 'En cours ${nb(1)}', 'Terminés ${nb(2)}'];
    final t = _texte.text.toLowerCase();
    final visibles = rayons.where((r) {
      if (_filtre > 0 && statuts[r.id] != _filtre - 1) return false;
      return t.isEmpty || r.displayName.toLowerCase().contains(t);
    }).toList();

    Widget corps;
    if (provider.error != null && rayons.isEmpty) {
      corps = NvErreur(provider.errorObject ?? provider.error!, onRetry: _charger);
    } else if (provider.isLoading && rayons.isEmpty) {
      corps = const NvChargement(texte: 'Chargement des rayons…');
    } else if (rayons.isEmpty) {
      corps = const NvVide(icon: Icons.location_off_outlined, titre: 'Aucun emplacement dans cet inventaire.');
    } else {
      final cols = Responsive.columns(context, compact: 1, medium: 2, expanded: 3);
      corps = RefreshIndicator(
        onRefresh: () => provider.loadRayonStatuses(_api, widget.inventaire.id),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          FiltrePills(labels: labels, selected: _filtre, onSelected: (i) => setState(() => _filtre = i)),
          const SizedBox(height: 12),
          if (visibles.isEmpty)
            const SizedBox(height: 200, child: NvVide(icon: Icons.search_off, titre: 'Aucun emplacement trouvé'))
          else
            ...cardColumn([
              for (final r in visibles) _CarteRayon(rayon: r, statut: statuts[r.id], enAttente: q.enAttente(inventaireId: widget.inventaire.id, rayonId: r.id), onTap: () => _ouvrir(r)),
            ], cols, spacing: 10),
        ]),
      );
    }

    return NvScaffold(
      title: 'Choisir un rayon',
      subtitle: widget.inventaire.libelle,
      wide: true,
      actions: [
        ActionEntete(
          icon: _recherche ? Icons.search_off : Icons.search,
          tooltip: _recherche ? 'Fermer la recherche' : 'Rechercher un rayon',
          onPressed: () => setState(() {
            _recherche = !_recherche;
            if (!_recherche) _texte.clear();
          }),
        ),
      ],
      header: [
        if (_recherche)
          TextField(
            key: const ValueKey('nv-recherche-rayon'),
            controller: _texte,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: nv.encre),
            decoration: const InputDecoration(hintText: 'Code ou nom du rayon', prefixIcon: Icon(Icons.search)),
          ),
      ],
      body: corps,
    );
  }
}

class _CarteRayon extends StatelessWidget {
  final Rayon rayon;
  final int? statut;
  final int enAttente;
  final VoidCallback onTap;
  const _CarteRayon({required this.rayon, required this.statut, required this.enAttente, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final (IconData icone, String etat, TonEtat ton) = switch (statut) {
      2 => (Icons.check, 'terminé', nv.ok),
      1 => (Icons.contrast, 'commencé', nv.attente),
      0 => (Icons.radio_button_unchecked, 'pas commencé', nv.neutre),
      _ => (Icons.more_horiz, 'état en lecture…', nv.neutre),
    };
    return SoftCard(
      key: ValueKey('nv-rayon-${rayon.id}'),
      onTap: onTap,
      semantique: '${libelleRayon(rayon)}, $etat${enAttente > 0 ? ', $enAttente en attente d\'envoi' : ''}',
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: ton.bg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icone, color: ton.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(libelleRayon(rayon), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: nv.encre)),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: etat, style: TextStyle(color: nv.gris)),
                if (enAttente > 0) TextSpan(text: ' · $enAttente en attente d\'envoi', style: TextStyle(color: nv.attente.fg, fontWeight: FontWeight.bold)),
              ]),
              style: const TextStyle(fontSize: 14),
            ),
            if (statut == 2) ...[
              const SizedBox(height: 6),
              const ThinProgress(value: 1, color: Pal.green),
            ],
          ]),
        ),
        Icon(Icons.chevron_right, color: nv.gris),
      ]),
    );
  }
}
