// lib/ui/ecrans/accueil_screen.dart
// Nouvelle interface — accueil = tableau de bord de l'inventaire en cours (maquette A ; tablette :
// menu latéral, maquette C). Remplace l'accueil d'origine ET la liste « Choisir un inventaire » :
// - inventaire en cours en tête (avancement connu sur l'appareil, rayons terminés s'ils ont été lus),
//   bouton « Actualiser l'avancement » (calcul À LA DEMANDE, lib/ui/avancement.dart — jamais
//   automatique), « À envoyer » avec Envoyer, bouton « Reprendre » au dernier rayon ouvert ;
// - Saisie guidée, Scan continu, Écarts, Restants, Collecte hors ligne ;
// - autres inventaires ouverts (choix de l'inventaire en cours) et « Nouvel inventaire » ;
// - barre du bas Accueil · Scanner · Écarts · Réglages.
// Mêmes données et même logique que l'accueil d'origine (HomeScreen) et InventoryListScreen :
// InventoryProvider.fetchInventories, SaisieQueue (À envoyer), rappels de licence, Local / Distant,
// Analyse, Déconnexion (performLogout). Un échec du serveur n'est jamais une liste vide.
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/navigation.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/app_utils.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

class NvAccueilScreen extends StatefulWidget {
  const NvAccueilScreen({super.key});

  @override
  State<NvAccueilScreen> createState() => _NvAccueilScreenState();
}

class _NvAccueilScreenState extends State<NvAccueilScreen> {
  /// Rappel de licence déjà montré dans cette session (comme l'accueil d'origine).
  static bool _alerteMontree = false;

  String? _courantId;
  String? _nouveauId;
  bool _envoi = false;

  /// Avancement calculé à la demande (résultat gardé avec son heure ; aucun calcul automatique).
  final _avancement = AvancementCalcul();
  String? _avancementLu;

  @override
  void initState() {
    super.initState();
    InventaireCourant.lire().then((id) {
      if (mounted && id != null) setState(() => _courantId = id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rafraichir();
      if (!_alerteMontree) _rappelLicence();
    });
  }

  @override
  void dispose() {
    _avancement.annuler();
    _avancement.dispose();
    super.dispose();
  }

  ApiService _api() {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    return ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
  }

  Future<void> _rafraichir() async {
    if (!mounted) return;
    final config = context.read<AppConfig>();
    await context.read<InventoryProvider>().fetchInventories(_api(), maxResult: config.maxResult);
  }

  void _rappelLicence() {
    final jours = context.read<LicenseProvider>().daysRemaining;
    String? message;
    var grave = false;
    if (jours <= 1) {
      message = 'ATTENTION : votre licence expire DEMAIN !';
      grave = true;
    } else if (jours <= 7) {
      message = 'Rappel : il vous reste moins d\'une semaine de licence ($jours jours).';
      grave = true;
    } else if (jours == 30 || jours == 29) {
      message = 'Information : votre licence expire dans 1 mois.';
    } else if (jours == 90 || jours == 89) {
      message = 'Information : votre licence expire dans 3 mois.';
    }
    if (message == null) return;
    _alerteMontree = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: grave ? ctx.nv.erreur.fg : ctx.nv.attente.fg, size: 32),
        title: const Text('Licence'),
        content: Text(message!),
        actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  /// Inventaire en cours : choisi sur l'appareil, sinon celui de la dernière saisie, sinon le premier.
  Inventory? _courant(List<Inventory> invs, SaisieQueue? q) {
    if (invs.isEmpty) return null;
    final choisi = invs.where((i) => i.id == _courantId).firstOrNull;
    if (choisi != null) return choisi;
    final derniere = q?.lignes().reversed.where((s) => invs.any((i) => i.id == s.inventaireId)).firstOrNull;
    if (derniere != null) return invs.firstWhere((i) => i.id == derniere.inventaireId);
    return invs.first;
  }

  void _choisir(Inventory inv) {
    if (_avancement.enCours && _avancement.inventaireId != inv.id) _avancement.annuler();
    setState(() => _courantId = inv.id);
    InventaireCourant.ecrire(inv.id);
  }

  Future<void> _nouvelInventaire() async {
    final cree = await Navigator.of(context).push<Inventory>(nvRoute(const NvCreationInventaireScreen()));
    if (!mounted || cree == null) return;
    setState(() => _nouveauId = cree.id);
    if (cree.id.isNotEmpty) _choisir(cree);
    await _rafraichir();
  }

  /// « Actualiser l'avancement » : mêmes requêtes que « Choisir un rayon », sur demande seulement.
  Future<void> _actualiserAvancement(Inventory inv) async {
    if (_avancement.enCours) return; // anti double appui
    await _avancement.actualiser(_api(), inv.id);
  }

  /// Annuler : arrêt immédiat (la réponse déjà demandée sera ignorée), l'avancement précédent reste.
  void _annulerAvancement() {
    if (!_avancement.enCours) return;
    _avancement.annuler();
    nvMessage(context, 'Actualisation de l\'avancement annulée.', ton: context.nv.neutre);
  }

  Future<void> _envoyerTout(SaisieQueue q) async {
    if (_envoi) return;
    setState(() => _envoi = true);
    final bilan = await q.envoyer();
    if (!mounted) return;
    setState(() => _envoi = false);
    final morceaux = <String>[
      if (bilan.envoyees > 0) '${bilan.envoyees} envoyée(s)',
      if (bilan.refusees > 0) '${bilan.refusees} refusée(s)',
      if (bilan.restantes > 0) '${bilan.restantes} toujours en attente',
      if (bilan.interruption != null) bilan.interruption!,
    ];
    nvMessage(context, morceaux.isEmpty ? 'Rien à envoyer.' : morceaux.join(' · '),
        ton: bilan.complet && bilan.refusees == 0 ? context.nv.ok : context.nv.attente);
  }

  Future<void> _aller(Destination d, Inventory? inv) async {
    await NvAller.vers(context, d, inv);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final config = context.watch<AppConfig>();
    final auth = context.watch<AuthProvider>();
    final licence = context.watch<LicenseProvider>();
    SaisieQueue? q;
    try {
      q = context.watch<SaisieQueue>();
    } catch (_) {}
    final invs = provider.inventories;
    final courant = _courant(invs, q);
    if (courant != null && courant.id != _avancementLu) {
      _avancementLu = courant.id;
      _avancement.charger(courant.id);
    }
    final user = auth.user;
    final sousTitre = [
      if ((user?.officine ?? '').isNotEmpty) user!.officine,
      if ((user?.firstName ?? '').isNotEmpty) user!.firstName,
    ].join(' · ');
    final large = Responsive.isExpanded(context);
    final local = config.apiMode == ApiMode.local;
    final jours = licence.daysRemaining;

    final enTete = <Widget>[
      Wrap(spacing: 8, runSpacing: 8, children: [
        _PuceEntete(
          key: const ValueKey('nv-mode-api'),
          icon: local ? Icons.wifi : Icons.public,
          texte: local ? 'Local' : 'Distant',
          semantique: 'Mode de connexion : ${local ? 'local' : 'distant'}. Toucher pour changer.',
          onTap: () => config.setApiMode(local ? ApiMode.distant : ApiMode.local),
        ),
        _PuceEntete(
          icon: Icons.verified_outlined,
          texte: 'Licence : $jours j',
          alerte: jours < 30,
          semantique: 'Licence : $jours jours restants',
        ),
      ]),
      if (courant != null)
        ListenableBuilder(
          listenable: _avancement,
          builder: (context, _) => _CarteEnCours(
            inventaire: courant,
            queue: q,
            avancement: _avancement,
            onActualiser: () => _actualiserAvancement(courant),
            onAnnuler: _annulerAvancement,
          ),
        ),
    ];

    final blocsPrincipaux = <Widget>[
      if (q != null && q.aTraiter() > 0) ...[
        Bandeau(
          key: const ValueKey('nv-bandeau-a-envoyer'),
          ton: q.refusees() > 0 ? context.nv.erreur : context.nv.attente,
          texte: '${q.aTraiter()} saisie(s) sur le téléphone, pas encore envoyée(s)${q.refusees() > 0 ? ' dont ${q.refusees()} refusée(s)' : ''}',
          action: _envoi ? 'Envoi…' : 'Envoyer',
          actionKey: const ValueKey('nv-envoyer-tout'),
          onAction: _envoi || q.enAttente() == 0 ? null : () => _envoyerTout(q!),
          onTap: () => _aller(Destination.aEnvoyer, courant),
        ),
        const SizedBox(height: 12),
      ],
      if (courant != null) ...[
        _BoutonReprendre(inventaire: courant, queue: q, onTap: (rayonId, scan) async {
          if (scan) {
            await NvAller.scan(context, courant);
          } else {
            await NvAller.guidee(context, courant, rayonId: rayonId);
          }
          if (mounted) setState(() {});
        }),
        _CarteMode(
          key: const ValueKey('nv-saisie-guidee'),
          icon: Icons.format_list_bulleted,
          titre: 'Saisie guidée',
          detail: 'Rayon par rayon, produit par produit',
          fond: context.nv.info.bg,
          couleur: context.nv.info.fg,
          onTap: () => _aller(Destination.guidee, courant),
        ),
        const SizedBox(height: 10),
        _CarteMode(
          key: const ValueKey('nv-scan-continu'),
          icon: Icons.qr_code_scanner,
          titre: 'Scan continu',
          detail: 'Scanner puis quantité, sans rayon',
          fond: context.nv.attente.bg,
          couleur: context.nv.attente.fg,
          onTap: () => _aller(Destination.scan, courant),
        ),
      ],
    ];

    final tuiles = Row(children: [
      Expanded(
        child: _Tuile(
          key: const ValueKey('nv-tuile-ecarts'),
          icon: Icons.compare_arrows,
          texte: 'Écarts',
          actif: courant != null,
          onTap: () => _aller(Destination.ecarts, courant),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _Tuile(
          key: const ValueKey('nv-tuile-restants'),
          icon: Icons.hourglass_bottom,
          texte: 'Restants',
          actif: courant != null,
          onTap: () => _aller(Destination.restants, courant),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _Tuile(
          key: const ValueKey('nv-tuile-collecte'),
          icon: Icons.download_for_offline_outlined,
          texte: 'Collecte',
          onTap: () => _aller(Destination.collecte, courant),
        ),
      ),
    ]);

    final listeInventaires = <Widget>[
      SectionTitre(
        invs.length > 1 ? 'Inventaires ouverts (${invs.length})' : 'Inventaires ouverts',
        trailing: TextButton.icon(
          key: const ValueKey('nouvel-inventaire'),
          onPressed: _nouvelInventaire,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Nouveau'),
        ),
      ),
      if (provider.isLoading)
        const Padding(padding: EdgeInsets.all(24), child: NvChargement())
      else if (provider.error != null)
        SizedBox(height: 300, child: NvErreur(provider.errorObject ?? provider.error!, onRetry: _rafraichir))
      else if (invs.isEmpty)
        const SizedBox(height: 160, child: NvVide(icon: Icons.inventory_2_outlined, titre: 'Aucun inventaire ouvert', detail: 'Créez-en un avec « Nouveau ».'))
      else
        for (final inv in invs) ...[
          _LigneInventaire(
            inventaire: inv,
            courant: inv.id == courant?.id,
            nouveau: inv.id == _nouveauId,
            enAttente: q?.aTraiter(inventaireId: inv.id) ?? 0,
            onTap: () => _choisir(inv),
          ),
          const SizedBox(height: 8),
        ],
    ];

    final Widget corps;
    if (large) {
      corps = RefreshIndicator(
        onRefresh: _rafraichir,
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...blocsPrincipaux, const SizedBox(height: 12), tuiles])),
            const SizedBox(width: 20),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: listeInventaires)),
          ]),
        ]),
      );
    } else {
      final colonnes = Responsive.columns(context, compact: 1, medium: 2, expanded: 2);
      corps = RefreshIndicator(
        onRefresh: _rafraichir,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          if (colonnes > 1)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...blocsPrincipaux, const SizedBox(height: 12), tuiles])),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: listeInventaires)),
            ])
          else ...[
            ...blocsPrincipaux,
            const SizedBox(height: 12),
            tuiles,
            ...listeInventaires,
          ],
        ]),
      );
    }

    return NvScaffold(
      title: 'Inventaire',
      subtitle: sousTitre.isEmpty ? null : sousTitre,
      retour: false,
      wide: true,
      actions: [
        ActionEntete(icon: Icons.pie_chart_outline, tooltip: 'Analyse', onPressed: () => _aller(Destination.analyse, courant)),
        ActionEntete(icon: Icons.logout, tooltip: 'Déconnexion', onPressed: () => performLogout(context)),
      ],
      header: enTete,
      menuLateral: NvMenuLateral(actif: Destination.accueil, inventaire: courant, onChoisir: (d) => _aller(d, courant)),
      bottomNavigationBar: NavigationBar(
        key: const ValueKey('nv-barre-bas'),
        selectedIndex: 0,
        height: 68,
        backgroundColor: context.nv.carte,
        indicatorColor: context.nv.info.bg,
        onDestinationSelected: (i) => _aller(const [Destination.accueil, Destination.scan, Destination.ecarts, Destination.reglages][i], courant),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
          NavigationDestination(icon: Icon(Icons.compare_arrows), label: 'Écarts'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Réglages'),
        ],
      ),
      body: corps,
    );
  }
}

/// Puce de l'en-tête (mode de connexion, licence).
class _PuceEntete extends StatelessWidget {
  final IconData icon;
  final String texte;
  final bool alerte;
  final String semantique;
  final VoidCallback? onTap;
  const _PuceEntete({super.key, required this.icon, required this.texte, required this.semantique, this.alerte = false, this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: semantique,
        excludeSemantics: true,
        child: Material(
          color: alerte ? Pal.amber : Colors.white.withValues(alpha: 0.12),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: alerte ? Pal.onAmber : Colors.white),
                  const SizedBox(width: 6),
                  Text(texte, style: TextStyle(color: alerte ? Pal.onAmber : Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.swap_horiz, size: 16, color: alerte ? Pal.onAmber : Colors.white70)],
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Carte « EN COURS » dans l'en-tête bleu : inventaire, saisies sur l'appareil, rayons terminés.
/// Avancement : celui calculé sur demande (« Actualiser l'avancement », avec son heure) s'il existe,
/// sinon celui lu par l'écran « Choisir un rayon » (comme avant).
class _CarteEnCours extends StatelessWidget {
  final Inventory inventaire;
  final SaisieQueue? queue;
  final AvancementCalcul avancement;
  final VoidCallback onActualiser;
  final VoidCallback onAnnuler;
  const _CarteEnCours({required this.inventaire, required this.queue, required this.avancement, required this.onActualiser, required this.onAnnuler});

  @override
  Widget build(BuildContext context) {
    final lignes = queue?.lignes(inventaireId: inventaire.id) ?? const <SaisieLigne>[];
    final envoyees = lignes.where((s) => s.envoyee).length;
    final entry = context.watch<EntryProvider>();
    final calcule = avancement.resultat(inventaire.id);
    final Map<String, int> statuts;
    final int total;
    if (calcule != null) {
      statuts = calcule.statuts;
      total = calcule.total;
    } else {
      statuts = entry.inventoryId == inventaire.id && entry.rayons.isNotEmpty ? entry.rayonStatuses : const <String, int>{};
      total = entry.inventoryId == inventaire.id ? entry.rayons.length : 0;
    }
    final termines = statuts.values.where((s) => s == 2).length;
    final enCours = statuts.values.where((s) => s == 1).length;
    final pct = total > 0 && (statuts.isNotEmpty || calcule != null) ? ((termines + enCours * 0.5) / total * 100).round() : null;
    final details = [
      '${lignes.length} saisie(s) sur ce téléphone · $envoyees envoyée(s)',
      if (total > 0 && (statuts.isNotEmpty || calcule != null)) '$termines rayon(s) terminé(s) sur $total',
      if (calcule != null && enCours > 0) '$enCours commencé(s)',
    ].join(' · ');
    final calculIci = avancement.enCours && avancement.inventaireId == inventaire.id;
    final calculAilleurs = avancement.enCours && !calculIci;
    final erreur = avancement.erreurPour(inventaire.id);
    final heure = calcule == null
        ? null
        : 'Avancement à ${calcule.heure()}${calcule.inconnus > 0 ? ' · ${calcule.inconnus} rayon(s) non lu(s)' : ''}';
    return Semantics(
      container: true,
      label: 'Inventaire en cours : ${inventaire.libelle}. $details${pct != null ? '. Avancement $pct pour cent' : ''}${heure != null ? '. $heure' : ''}',
      child: Container(
        key: const ValueKey('nv-en-cours'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('EN COURS', style: TextStyle(color: Pal.headerMuted, fontSize: 12.5, letterSpacing: 0.8)),
                Text(inventaire.libelle,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
            ),
            if (pct != null)
              Container(
                key: const ValueKey('nv-avancement-pct'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Pal.amber, borderRadius: BorderRadius.circular(999)),
                child: Text('$pct %', style: const TextStyle(color: Pal.onAmber, fontWeight: FontWeight.bold)),
              ),
          ]),
          if (total > 0 && statuts.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  if (termines > 0) Expanded(flex: termines, child: Container(color: const Color(0xFF4ADE80))),
                  if (enCours > 0) Expanded(flex: enCours, child: Container(color: Pal.amber)),
                  if (total - termines - enCours > 0) Expanded(flex: total - termines - enCours, child: Container(color: Colors.white.withValues(alpha: 0.2))),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(details, style: const TextStyle(color: Color(0xFFDCE6F2), fontSize: 13.5)),
          const SizedBox(height: 8),
          if (calculIci)
            _ProgressionAvancement(avancement: avancement, onAnnuler: onAnnuler)
          else
            Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                key: const ValueKey('nv-actualiser-avancement'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white54,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  // Style du thème (police de l'application), seulement plus gras.
                  textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                onPressed: calculAilleurs ? null : onActualiser,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Actualiser l\'avancement'),
              ),
              if (heure != null)
                Text(heure, key: const ValueKey('nv-avancement-heure'), style: const TextStyle(color: Pal.headerMuted, fontSize: 13)),
            ]),
          if (erreur != null && !calculIci) _ErreurAvancement(erreur: erreur, onReessayer: onActualiser),
        ]),
      ),
    );
  }
}

/// Calcul en cours : « Rayon 3/12 », barre de progression, Annuler (placé à droite, loin du bouton
/// d'origine : un double appui sur « Actualiser » ne peut pas annuler).
class _ProgressionAvancement extends StatelessWidget {
  final AvancementCalcul avancement;
  final VoidCallback onAnnuler;
  const _ProgressionAvancement({required this.avancement, required this.onAnnuler});

  @override
  Widget build(BuildContext context) {
    final n = avancement.rayons;
    final texte = n == 0 ? 'Lecture des rayons…' : 'Rayon ${avancement.rayon}/$n';
    return Semantics(
      liveRegion: true,
      label: 'Calcul de l\'avancement : $texte',
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(texte, key: const ValueKey('nv-avancement-progression'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: n == 0 ? null : (avancement.rayon - 1).clamp(0, n) / n,
                minHeight: 6,
                color: Pal.amber,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        TextButton(
          key: const ValueKey('nv-annuler-avancement'),
          style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48), textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600)),
          onPressed: onAnnuler,
          child: const Text('Annuler'),
        ),
      ]),
    );
  }
}

/// Échec du calcul : motif exact (réseau, session…), le dernier avancement connu reste affiché.
class _ErreurAvancement extends StatelessWidget {
  final Object erreur;
  final VoidCallback onReessayer;
  const _ErreurAvancement({required this.erreur, required this.onReessayer});

  @override
  Widget build(BuildContext context) {
    final session = estSessionExpiree(erreur);
    return Container(
      key: const ValueKey('nv-avancement-erreur'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      decoration: BoxDecoration(color: const Color(0xFF7F1D1D).withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(session ? Icons.lock_clock : Icons.cloud_off, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Avancement non actualisé : ${AvancementCalcul.motif(erreur)}',
                style: const TextStyle(color: Colors.white, fontSize: 13.5)),
          ),
        ]),
        if (session)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('nv-avancement-reconnecter'),
              style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
              onPressed: () async {
                if (await demanderReconnexion(context)) onReessayer();
              },
              child: const Text('Se reconnecter'),
            ),
          ),
      ]),
    );
  }
}

/// « Reprendre : rayon … » (dernière saisie guidée) ou « Reprendre le scan continu ».
class _BoutonReprendre extends StatelessWidget {
  final Inventory inventaire;
  final SaisieQueue? queue;
  final void Function(String? rayonId, bool scan) onTap;
  const _BoutonReprendre({required this.inventaire, required this.queue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final derniere = queue?.lignes(inventaireId: inventaire.id).reversed
        .where((s) => s.origine == OrigineSaisie.guidee || s.origine == OrigineSaisie.rapide)
        .firstOrNull;
    if (derniere == null) return const SizedBox.shrink();
    final scan = derniere.origine == OrigineSaisie.rapide || derniere.rayonId == null;
    final texte = scan ? 'Reprendre le scan continu' : 'Reprendre : rayon ${derniere.rayonLibelle ?? derniere.rayonId}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('nv-reprendre'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 17, fontWeight: FontWeight.bold)),
          onPressed: () => onTap(scan ? null : derniere.rayonId, scan),
          icon: const Icon(Icons.play_arrow_rounded, size: 26),
          label: Text(texte, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _CarteMode extends StatelessWidget {
  final IconData icon;
  final String titre;
  final String detail;
  final Color fond;
  final Color couleur;
  final VoidCallback onTap;
  const _CarteMode({super.key, required this.icon, required this.titre, required this.detail, required this.fond, required this.couleur, required this.onTap});

  @override
  Widget build(BuildContext context) => SoftCard(
        onTap: onTap,
        semantique: '$titre : $detail',
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: couleur, size: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.nv.encre)),
              Text(detail, style: TextStyle(color: context.nv.gris, fontSize: 14.5)),
            ]),
          ),
          Icon(Icons.chevron_right, color: context.nv.gris),
        ]),
      );
}

class _Tuile extends StatelessWidget {
  final IconData icon;
  final String texte;
  final bool actif;
  final VoidCallback onTap;
  const _Tuile({super.key, required this.icon, required this.texte, required this.onTap, this.actif = true});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: actif ? 1 : 0.45,
        child: SoftCard(
          onTap: actif ? onTap : null,
          semantique: texte,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(children: [
            Icon(icon, color: context.nv.action, size: 26),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, child: Text(texte, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: context.nv.encre))),
          ]),
        ),
      );
}

class _LigneInventaire extends StatelessWidget {
  final Inventory inventaire;
  final bool courant;
  final bool nouveau;
  final int enAttente;
  final VoidCallback onTap;
  const _LigneInventaire({required this.inventaire, required this.courant, required this.nouveau, required this.enAttente, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return SoftCard(
      onTap: onTap,
      bordure: courant ? nv.action : null,
      semantique: '${inventaire.libelle}${courant ? ', inventaire en cours' : ', toucher pour le choisir'}',
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Icon(courant ? Icons.radio_button_checked : Icons.radio_button_off, color: courant ? nv.action : nv.gris),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inventaire.libelle, key: ValueKey('nv-inv-${inventaire.id}'), maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: nv.encre)),
            if (nouveau) Text('Nouveau — créé depuis ce terminal', style: TextStyle(color: nv.ok.fg, fontSize: 13)),
          ]),
        ),
        if (enAttente > 0) Pastille('$enAttente à envoyer', ton: nv.attente) else if (courant) Pastille('en cours', ton: nv.info),
      ]),
    );
  }
}
