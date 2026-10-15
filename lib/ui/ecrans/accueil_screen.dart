// lib/ui/ecrans/accueil_screen.dart
// Nouvelle interface — ACCUEIL (maquette « Main » validée par le pharmacien, 4.13) :
//  - en-tête : « PRESTIGE INVENTAIRE », nom de la pharmacie, « Bienvenu(e), Prénom Nom », puces
//    Local ⇄ Distant et Licence, Déconnexion ;
//  - « Créer un inventaire » (administrateur / pharmacien, les autres comptes si le réglage l'autorise ;
//    profil inconnu : code administrateur — lib/inventaire/autorisation_creation.dart) ;
//  - « Voir les inventaires (N) » : flèche ▼ qui déroule la liste par le bas (▲ pour replier). Chaque
//    ligne : nom, détail, % d'avancement, bouton « Commencer → » (0 %), « Poursuivre → » (0,1 à 99,9 %),
//    « Revérifier → » (100 %). Le % est calculé AU DÉROULÉ, une ligne après l'autre (indicateur par
//    ligne, jamais de blocage), puis gardé (lib/ui/avancement.dart) ; rien n'est calculé au lancement ;
//  - choisir un inventaire ouvre l'écran de l'inventaire (sélection obligatoire avant toute saisie) ;
//  - « Collecte » (nombre de produits scannés) en bas ; barre du bas Accueil · Scanner · Analyse ·
//    Réglages (Scanner : feuille « Scanner pour… »).
// Mêmes données et même logique qu'avant : InventoryProvider.fetchInventories (rafraîchi à chaque retour
// sur l'accueil), SaisieQueue (bandeau « à envoyer »), rappels de licence, performLogout. Un échec du
// serveur n'est jamais une liste vide.
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/autorisation_creation.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/feuille_scanner.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/navigation.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/app_utils.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:prestinv/widgets/pin_admin.dart';
import 'package:provider/provider.dart';

/// Calculs d'avancement de la liste de l'accueil : un inventaire après l'autre, seulement ceux dont
/// l'avancement n'est pas encore connu (ou tous si [forcer]). Une session expirée ou un serveur
/// injoignable arrête la suite (inutile d'enchaîner les échecs).
class CalculsListe extends ChangeNotifier {
  final AvancementCalcul _calcul = AvancementCalcul();
  final List<String> _file = [];
  final Map<String, Object> _erreurs = {};
  bool _boucle = false;
  bool _ferme = false;

  CalculsListe() {
    _calcul.addListener(notifyListeners);
  }

  /// Inventaire en cours de calcul.
  String? get enCours => _calcul.enCours ? _calcul.inventaireId : null;

  /// En attente de calcul (indicateur sur la ligne).
  bool attend(String id) => _file.contains(id) || enCours == id;

  Object? erreur(String id) => _erreurs[id];

  void demander(ApiService Function() api, Iterable<String> ids, {bool forcer = false}) {
    for (final id in ids) {
      if (_file.contains(id) || enCours == id) continue;
      if (!forcer && AvancementCalcul.enCache(id) != null) continue;
      _erreurs.remove(id);
      _file.add(id);
    }
    notifyListeners();
    if (!_boucle) _executer(api);
  }

  Future<void> _executer(ApiService Function() api) async {
    _boucle = true;
    while (_file.isNotEmpty && !_ferme) {
      final id = _file.first;
      final fin = await _calcul.actualiser(api(), id);
      if (_ferme) break;
      _file.remove(id);
      if (fin == FinAvancement.erreur) {
        final e = _calcul.erreurPour(id);
        if (e != null) _erreurs[id] = e;
        if (estSessionExpiree(e) || (e is ApiLoadException && e.reseau)) {
          for (final x in _file) {
            if (e != null) _erreurs[x] = e;
          }
          _file.clear();
        }
      }
      if (!_ferme) notifyListeners();
    }
    _boucle = false;
  }

  /// Arrête tout (repli de la liste, sortie de l'écran) : la réponse attendue est ignorée.
  void arreter() {
    _file.clear();
    _calcul.annuler();
    if (!_ferme) notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _file.clear();
    _calcul.annuler();
    _calcul.removeListener(notifyListeners);
    _calcul.dispose();
    super.dispose();
  }
}

/// Crée un inventaire depuis la nouvelle interface : droit de création (profil, réglage, code
/// administrateur), écran de création, puis relecture de la liste des inventaires (InventoryProvider)
/// pour renvoyer l'inventaire avec son identifiant (retrouvé par son libellé si le serveur ne l'a pas
/// donné). null : rien de créé. [codesCollectes] (création depuis la collecte, 4.15) : inventaire des
/// seuls produits collectés, sur leurs emplacements.
Future<Inventory?> creerInventaireNv(BuildContext context, {String libelleInitial = '', List<String>? codesCollectes}) async {
  if (!await verifierDroitCreation(context) || !context.mounted) return null;
  final cree = await Navigator.of(context)
      .push<Inventory>(nvRoute(NvCreationInventaireScreen(libelleInitial: libelleInitial, codesCollectes: codesCollectes)));
  if (cree == null || !context.mounted) return null;
  return retrouverInventaire(context, cree);
}

/// Relit les inventaires ouverts (InventoryProvider : SEULE source des listes de la nouvelle
/// interface) et renvoie [cree] tel qu'il y figure (par identifiant, sinon par libellé).
Future<Inventory?> retrouverInventaire(BuildContext context, Inventory cree) async {
  final config = context.read<AppConfig>();
  final auth = context.read<AuthProvider>();
  final provider = context.read<InventoryProvider>();
  final api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
  await provider.fetchInventories(api, maxResult: config.maxResult);
  final liste = provider.inventories;
  if (cree.id.isNotEmpty) return liste.where((i) => i.id == cree.id).firstOrNull ?? cree;
  String cle(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return liste.where((i) => cle(i.libelle) == cle(cree.libelle)).firstOrNull;
}

/// Droit de créer un inventaire (voir lib/inventaire/autorisation_creation.dart) ; demande le code
/// administrateur si le profil est inconnu. Renvoie vrai si la création peut continuer.
Future<bool> verifierDroitCreation(BuildContext context) async {
  final acces = accesCreationDe(context);
  switch (acces) {
    case AccesCreation.autorise:
      return true;
    case AccesCreation.codeAdmin:
      return demanderPinAdmin(context, motif: 'Créer un inventaire : le profil de ce compte n\'est pas connu du terminal. Code administrateur demandé.');
    case AccesCreation.refuse:
      await nvDialogue<void>(context,
          icone: Icons.lock_outline,
          titre: 'Création réservée',
          message: context.read<AuthProvider>().user?.droitCreation == false
              ? 'Votre compte n\'a pas le droit « Créer un inventaire » dans Prestige. Demandez-le au pharmacien.'
              : 'La création d\'un inventaire est réservée à l\'administrateur et au pharmacien '
                  '(réglage « Autoriser la création d\'inventaire aux autres comptes »).',
          boutons: const [NvBouton('OK', null, genre: NvGenre.principal)]);
      return false;
  }
}

AccesCreation accesCreationDe(BuildContext context) => accesCreation(
      adminOuPharmacien: context.read<AuthProvider>().user?.adminOuPharmacien,
      autresComptesAutorises: context.read<AppConfig>().creationAutresComptes,
      droitServeur: context.read<AuthProvider>().user?.droitCreation,
    );

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
  bool _deroule = false;
  int? _scannes;
  final _calculs = CalculsListe();

  @override
  void initState() {
    super.initState();
    InventaireCourant.lire().then((id) {
      if (mounted && id != null) setState(() => _courantId = id);
    });
    _lireCollecte();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rafraichir();
      if (!_alerteMontree) _rappelLicence();
    });
  }

  @override
  void dispose() {
    _calculs.dispose();
    super.dispose();
  }

  ApiService _api() {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    return ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
  }

  Future<void> _lireCollecte() async {
    final items = await CollecteStore.lire();
    if (mounted) setState(() => _scannes = items.where((i) => !i.versee).length);
  }

  /// Relit la liste des inventaires (au lancement, au retour sur l'accueil, en tirant la liste).
  Future<void> _rafraichir({bool recalculer = false}) async {
    if (!mounted) return;
    final config = context.read<AppConfig>();
    final provider = context.read<InventoryProvider>();
    await provider.fetchInventories(_api(), maxResult: config.maxResult);
    if (!mounted) return;
    if (_deroule) _calculs.demander(_api, provider.inventories.map((i) => i.id), forcer: recalculer);
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
    nvDialogue<void>(context,
        icone: Icons.warning_amber_rounded,
        ton: grave ? context.nv.erreur : context.nv.attente,
        titre: 'Licence',
        message: message,
        boutons: const [NvBouton('OK', null, genre: NvGenre.principal)]);
  }

  /// Inventaire pour le menu latéral (tablette) et la présélection : choisi sur l'appareil, sinon celui
  /// de la dernière saisie, sinon le premier.
  Inventory? _courant(List<Inventory> invs, SaisieQueue? q) {
    if (invs.isEmpty) return null;
    final choisi = invs.where((i) => i.id == _courantId).firstOrNull;
    if (choisi != null) return choisi;
    final derniere = q?.lignes().reversed.where((s) => invs.any((i) => i.id == s.inventaireId)).firstOrNull;
    if (derniere != null) return invs.firstWhere((i) => i.id == derniere.inventaireId);
    return invs.first;
  }

  void _basculer(List<Inventory> invs) {
    setState(() => _deroule = !_deroule);
    if (_deroule) {
      _calculs.demander(_api, invs.map((i) => i.id));
    } else {
      _calculs.arreter();
    }
  }

  /// Toute navigation depuis l'accueil : au retour, liste des inventaires et collecte relues.
  Future<void> _apres(Future<void> Function() ouvrir) async {
    await ouvrir();
    if (!mounted) return;
    final id = await InventaireCourant.lire();
    if (!mounted) return;
    setState(() => _courantId = id ?? _courantId);
    _lireCollecte();
    await _rafraichir();
  }

  Future<void> _ouvrir(Inventory inv) => _apres(() {
        setState(() => _courantId = inv.id);
        return NvAller.inventaire(context, inv);
      });

  Future<void> _nouvelInventaire() async {
    final cree = await creerInventaireNv(context);
    if (!mounted || cree == null) {
      if (mounted) await _rafraichir();
      return;
    }
    setState(() {
      _nouveauId = cree.id;
      _deroule = true;
    });
    // L'inventaire créé est sélectionné : son écran s'ouvre directement.
    await _ouvrir(cree);
  }

  Future<void> _scanner(List<Inventory> invs, Inventory? courant) async {
    var liste = invs;
    if (liste.isEmpty) {
      await _rafraichir();
      if (!mounted) return;
      liste = context.read<InventoryProvider>().inventories;
    }
    final choix = await ouvrirFeuilleScanner(context, inventaires: liste, courantId: courant?.id);
    if (!mounted || choix == null) return;
    switch (choix) {
      case ScannerCollecte():
        await _apres(() => NvAller.collecte(context));
      case ScannerInventaire(:final inventaire):
        setState(() => _courantId = inventaire.id);
        await InventaireCourant.ecrire(inventaire.id);
        if (mounted) await _apres(() => NvAller.scan(context, inventaire));
    }
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

  Future<void> _aller(Destination d, Inventory? inv) => _apres(() => NvAller.vers(context, d, inv));

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
    final nv = context.nv;
    final invs = provider.inventories;
    final courant = _courant(invs, q);
    final user = auth.user;
    final officine = (user?.officine ?? '').trim();
    final local = config.apiMode == ApiMode.local;
    final jours = licence.daysRemaining;
    final acces = accesCreation(
        adminOuPharmacien: user?.adminOuPharmacien, autresComptesAutorises: config.creationAutresComptes, droitServeur: user?.droitCreation);

    final enTete = <Widget>[
      Wrap(spacing: 8, runSpacing: 8, children: [
        _PuceEntete(
          key: const ValueKey('nv-mode-api'),
          icon: local ? Icons.wifi : Icons.public,
          texte: local ? 'Local' : 'Distant',
          semantique: 'Mode de connexion : ${local ? 'local' : 'distant'}. Toucher pour changer.',
          onTap: () => config.setApiMode(local ? ApiMode.distant : ApiMode.local),
        ),
        _PuceEntete(icon: Icons.verified_outlined, texte: 'Licence : $jours j', alerte: jours < 30, semantique: 'Licence : $jours jours restants'),
      ]),
    ];

    final liste = <Widget>[
      if (q != null && q.aTraiter() > 0) ...[
        Bandeau(
          key: const ValueKey('nv-bandeau-a-envoyer'),
          ton: q.refusees() > 0 ? nv.erreur : nv.attente,
          texte: '${q.aTraiter()} saisie(s) sur le téléphone, pas encore envoyée(s)${q.refusees() > 0 ? ' dont ${q.refusees()} refusée(s)' : ''}',
          action: _envoi ? 'Envoi…' : 'Envoyer',
          actionKey: const ValueKey('nv-envoyer-tout'),
          onAction: _envoi || q.enAttente() == 0 ? null : () => _envoyerTout(q!),
          onTap: () => _aller(Destination.aEnvoyer, courant),
        ),
        const SizedBox(height: 12),
      ],
      if (acces != AccesCreation.refuse) ...[
        FilledButton.icon(
          key: const ValueKey('nouvel-inventaire'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          onPressed: _nouvelInventaire,
          icon: Icon(acces == AccesCreation.codeAdmin ? Icons.lock_outline : Icons.add_circle_outline, size: 22),
          label: const Text('Créer un inventaire'),
        ),
        const SizedBox(height: 12),
      ],
      _LigneDerouler(
        nombre: invs.length,
        ouvert: _deroule,
        chargement: provider.isLoading,
        onTap: () => _basculer(invs),
      ),
      const SizedBox(height: 8),
      if (provider.error != null)
        SizedBox(height: 320, child: NvErreur(provider.errorObject ?? provider.error!, onRetry: _rafraichir))
      else if (!_deroule)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Text('Touchez la flèche pour dérouler la liste et choisir l\'inventaire à saisir.',
              key: const ValueKey('nv-aide-derouler'), textAlign: TextAlign.center, style: TextStyle(color: nv.gris, fontSize: 14.5)),
        )
      else if (provider.isLoading && invs.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: NvChargement())
      else if (invs.isEmpty)
        const SizedBox(height: 160, child: NvVide(icon: Icons.inventory_2_outlined, titre: 'Aucun inventaire ouvert'))
      else
        ListenableBuilder(
          listenable: _calculs,
          builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final inv in invs) ...[
              _LigneInventaire(
                inventaire: inv,
                nouveau: inv.id == _nouveauId,
                lignesLocales: q?.lignes(inventaireId: inv.id).map((s) => s.ligneId).toList() ?? const [],
                enAttente: q?.aTraiter(inventaireId: inv.id) ?? 0,
                calcul: _calculs.attend(inv.id),
                erreur: _calculs.erreur(inv.id),
                onTap: () => _ouvrir(inv),
              ),
              const SizedBox(height: 8),
            ],
          ]),
        ),
    ];

    final collecte = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: _BoutonCollecte(scannes: _scannes, onTap: () => _aller(Destination.collecte, courant)),
    );

    return NvScaffold(
      surtitre: 'Prestige Inventaire',
      title: officine.isEmpty ? 'Inventaire' : officine,
      subtitle: user == null ? null : 'Bienvenu(e), ${user.nomComplet}',
      retour: false,
      wide: true,
      actions: [
        ActionEntete(icon: Icons.logout, tooltip: 'Déconnexion', onPressed: () => performLogout(context)),
      ],
      header: enTete,
      menuLateral: NvMenuLateral(actif: Destination.accueil, inventaire: courant, onChoisir: (d) => _aller(d, courant)),
      piedDeCorps: Responsive.isExpanded(context) ? null : collecte,
      bottomNavigationBar: NavigationBar(
        key: const ValueKey('nv-barre-bas'),
        selectedIndex: 0,
        height: 68,
        backgroundColor: nv.carte,
        indicatorColor: nv.info.bg,
        onDestinationSelected: (i) {
          switch (i) {
            case 1:
              _scanner(invs, courant);
            case 2:
              _aller(Destination.analyse, courant);
            case 3:
              _aller(Destination.reglages, courant);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Analyse'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Réglages'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _rafraichir(recalculer: true),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          ...liste,
          if (Responsive.isExpanded(context)) ...[const SizedBox(height: 8), _BoutonCollecte(scannes: _scannes, onTap: () => _aller(Destination.collecte, courant))],
        ]),
      ),
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

/// « Voir les inventaires (N) » avec la flèche ▼ / ▲.
class _LigneDerouler extends StatelessWidget {
  final int nombre;
  final bool ouvert;
  final bool chargement;
  final VoidCallback onTap;
  const _LigneDerouler({required this.nombre, required this.ouvert, required this.chargement, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return Semantics(
      button: true,
      expanded: ouvert,
      label: 'Voir les inventaires, $nombre. ${ouvert ? 'Toucher pour replier' : 'Toucher pour dérouler'}',
      excludeSemantics: true,
      child: Material(
        color: nv.carte,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: nv.ligne)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('nv-voir-inventaires'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(
                  child: Text(chargement && nombre == 0 ? 'Voir les inventaires' : 'Voir les inventaires ($nombre)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: nv.action)),
                ),
                Text(ouvert ? 'Replier' : 'Dérouler', style: TextStyle(fontSize: 13.5, color: nv.gris)),
                const SizedBox(width: 4),
                Icon(ouvert ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, key: ValueKey(ouvert ? 'nv-fleche-haut' : 'nv-fleche-bas'), color: nv.action, size: 28),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Couleurs du bouton d'une ligne (Commencer bleu clair, Poursuivre orange, Revérifier vert).
(Color fond, Color texte, Color pct) couleursAction(BuildContext context, ActionInventaire a) {
  final nv = context.nv;
  return switch (a) {
    ActionInventaire.commencer => (nv.info.bg, nv.info.fg, nv.gris),
    ActionInventaire.poursuivre => (Pal.amber, Pal.onAmber, nv.attente.fg),
    ActionInventaire.reverifier => (const Color(0xFF15803D), Colors.white, nv.ok.fg),
    ActionInventaire.inconnu => (nv.neutre.bg, nv.neutre.fg, nv.gris),
  };
}

class _LigneInventaire extends StatelessWidget {
  final Inventory inventaire;
  final bool nouveau;
  final List<int> lignesLocales;
  final int enAttente;
  final bool calcul;
  final Object? erreur;
  final VoidCallback onTap;
  const _LigneInventaire({
    required this.inventaire,
    required this.nouveau,
    required this.lignesLocales,
    required this.enAttente,
    required this.calcul,
    required this.erreur,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final r = AvancementCalcul.enCache(inventaire.id);
    final etat = etatAvancement(r, lignesLocales: lignesLocales);
    final (fond, texte, couleurPct) = couleursAction(context, etat.action);
    final details = [
      if (nouveau) 'Nouveau — créé depuis ce terminal',
      if (r != null) '${r.total} rayon(s)',
      if (etat.comptes != null && etat.total != null) '${etat.comptes} / ${etat.total} produits',
      if (r == null && calcul) 'Calcul de l\'avancement…',
      if (r == null && !calcul && erreur != null) 'Avancement non lu (${estSessionExpiree(erreur) ? 'session expirée' : 'réseau'})',
      if (enAttente > 0) '$enAttente à envoyer',
    ].join(' · ');
    final pct = pourcentageAffiche(etat);
    return SoftCard(
      key: ValueKey('nv-ligne-inv-${inventaire.id}'),
      onTap: onTap,
      bordure: nv.ligne,
      semantique: '${inventaire.libelle}, avancement $pct. ${etat.action.libelle}',
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inventaire.libelle,
                key: ValueKey('nv-inv-${inventaire.id}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: nv.encre)),
            if (details.isNotEmpty)
              Text(details, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: nouveau ? nv.ok.fg : nv.gris, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 56,
          child: calcul && r == null
              ? const Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(key: ValueKey('nv-calcul-ligne'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(pct, key: ValueKey('nv-pct-${inventaire.id}'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: couleurPct)),
                ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 112),
          child: FilledButton(
            key: ValueKey('nv-ouvrir-${inventaire.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: fond,
              foregroundColor: texte,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            onPressed: onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(etat.action.libelle, key: ValueKey('nv-action-${inventaire.id}')),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward, size: 16),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// « Collecte · N produits scannés → » (maquette, en bas de l'accueil).
class _BoutonCollecte extends StatelessWidget {
  final int? scannes;
  final VoidCallback onTap;
  const _BoutonCollecte({required this.scannes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final n = scannes;
    final detail = n == null ? '' : (n == 0 ? 'Aucun produit scanné' : '$n produit(s) scanné(s)');
    return Semantics(
      button: true,
      label: 'Collecte. $detail',
      excludeSemantics: true,
      child: Material(
        color: nv.ok.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: nv.ok.fg.withValues(alpha: 0.3))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('nv-tuile-collecte'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(Icons.download_for_offline_outlined, color: nv.ok.fg, size: 24),
                const SizedBox(width: 10),
                Text('Collecte', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: nv.ok.fg)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(detail, key: const ValueKey('nv-collecte-compte'), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: nv.ok.fg)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward, size: 18, color: nv.ok.fg),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
