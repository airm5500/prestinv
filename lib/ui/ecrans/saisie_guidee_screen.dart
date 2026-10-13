// lib/ui/ecrans/saisie_guidee_screen.dart
// Nouvelle interface — saisie guidée d'un rayon (maquette A, à gauche) : produit par produit, grand
// chiffre, pavé ambre, état d'envoi du produit précédent, douchette toujours prête (un scan ouvre le
// produit). Même logique que la saisie guidée de l'écran d'origine (InventoryEntryScreen) :
// EntryProvider (rayons, produits, filtres, position mémorisée, quantité → file des saisies AVANT
// envoi), cumul « déjà compté » (vérification locale), seuil « grande quantité », fin de rayon,
// sécurité de sortie, rappel d'envoi, récapitulatif, écarts du rayon, export CSV, historique des cumuls.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/product_filter.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/ui/clavier.dart';
import 'package:prestinv/ui/ecrans/cumuls_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/feuille_quantite.dart';
import 'package:prestinv/ui/ecrans/recap_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_commune.dart';
import 'package:prestinv/ui/ecrans/widgets_saisie.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:provider/provider.dart';

class NvSaisieGuideeScreen extends StatefulWidget {
  final Inventory inventaire;
  final String rayonId;
  const NvSaisieGuideeScreen({super.key, required this.inventaire, required this.rayonId});

  @override
  State<NvSaisieGuideeScreen> createState() => _NvSaisieGuideeScreenState();
}

class _NvSaisieGuideeScreenState extends State<NvSaisieGuideeScreen> with DouchetteCibleMixin, SaisieCommune {
  String _quantite = '';
  String? _erreur;
  int? _produitAffiche;
  int? _precedentId;
  bool _pendingVu = false;

  @override
  Inventory get inventaire => widget.inventaire;

  @override
  bool get modeScan => false;

  @override
  void Function(String key)? get toucheGuidee => _touche;

  @override
  void initState() {
    super.initState();
    initSaisie();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  @override
  void dispose() {
    disposeSaisie();
    super.dispose();
  }

  Future<void> _charger() async {
    if (!mounted) return;
    final p = entry;
    p.auteur = context.read<AuthProvider>().user?.login ?? '';
    p.ouvrirInventaire(inventoryId, libelle: inventaire.libelle);
    if (p.inventoryId != inventoryId || p.rayons.isEmpty) await p.fetchRayons(api, inventoryId);
    if (!mounted) return;
    if (p.error == null && p.selectedRayon?.id != widget.rayonId) await p.fetchProducts(api, inventoryId, widget.rayonId);
    if (!mounted) return;
    relancerRappel();
    reprendreFocusScan();
  }

  // ---------- Pavé et validation (même logique que l'écran d'origine) ----------

  void _touche(String k) {
    if (k == 'DEL') {
      if (_quantite.isNotEmpty) setState(() => _quantite = _quantite.substring(0, _quantite.length - 1));
    } else if (k == 'OK') {
      _valider();
    } else {
      setState(() {
        _quantite = SaisieInput.ajouterChiffre(_quantite, k);
        _erreur = null;
      });
    }
  }

  Future<void> _valider() async {
    if (!mounted || validationEnCours) return;
    validationEnCours = true;
    try {
      await _validerEtAvancer();
    } finally {
      validationEnCours = false;
      reprendreFocusScan();
      fileScans.relancer();
    }
  }

  Future<void> _validerEtAvancer() async {
    final provider = entry;
    final e = SaisieInput.erreurQuantite(_quantite);
    if (e != null) {
      setState(() => _erreur = e);
      return;
    }
    final saisie = SaisieInput.parseQuantite(_quantite)!;
    var total = saisie;
    final produit = provider.currentProduct;
    if (produit == null) return;
    if (config.isCumulEnabled) {
      final existant = await provider.checkExistingQuantityLocal(produit.produitCip);
      if (!mounted) return;
      if (existant != null) {
        final ajouter = await demanderRemplacerAjouter(context, nom: produit.produitName, existant: existant, saisie: saisie);
        if (ajouter == null) return;
        if (ajouter) {
          total = existant + saisie;
          provider.addCumulLog(produit, existant, saisie);
        }
      }
    }
    if (total > config.largeValueThreshold) {
      if (!mounted || !await confirmerGrandeQuantite(context, total)) return;
    }
    try {
      await provider.updateQuantity(total.toString(), inventoryId);
    } catch (e) {
      if (mounted) nvMessage(context, 'Enregistrement impossible sur l\'appareil : $e', ton: context.nv.erreur);
      return;
    }
    if (!mounted) return;
    _precedentId = produit.id;
    relancerRappel();
    if (config.sendMode == SendMode.direct) envoyerDirect(produit);
    final dernier = provider.currentProductIndex >= provider.totalProducts - 1;
    if (dernier && provider.totalProducts > 0) {
      arreterRappel();
      _finDeRayon();
    } else {
      provider.nextProduct(inventoryId);
      setState(() => _quantite = '');
      reprendreFocusScan();
    }
  }

  void _finDeRayon() {
    final provider = entry;
    final reste = provider.uncountedProductsCount;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reste > 0 ? 'Rayon incomplet' : 'Fin du rayon'),
        content: Text(reste > 0
            ? 'Il reste $reste produit(s) jamais touchés.\n\nVoulez-vous les traiter maintenant ?'
            : 'Tous les produits ont été touchés. Voulez-vous envoyer les données ?'),
        actions: [
          if (reste > 0)
            FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  provider.filterToUncounted();
                },
                child: const Text('Traiter les oublis')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Non')),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                envoyerInventaire();
              },
              child: const Text('Envoyer')),
        ],
      ),
    );
  }

  void _sessionNonTerminee() {
    final provider = entry;
    provider.acknowledgedPendingSession();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saisie non terminée'),
        content: const Text('Des saisies non envoyées de la dernière session ont été trouvées. Voulez-vous les envoyer maintenant ?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Non')),
          FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                envoyerInventaire();
              },
              child: const Text('Oui, envoyer')),
        ],
      ),
    );
  }

  // ---------- Menus ----------

  String _libelleFiltre(ProductFilter f) {
    if (!f.isActive) return '';
    if (f.from == 'Rattrapage') return 'oublis';
    final prefixe = f.type == FilterType.numeric ? 'n° ' : '';
    return 'filtre $prefixe${f.from} à $prefixe${f.to}';
  }

  Future<void> _filtre() async {
    final provider = entry;
    final actuel = provider.activeFilter;
    final total = provider.totalProductsInRayon;
    final deNum = TextEditingController(text: actuel.type == FilterType.numeric ? actuel.from : '');
    final aNum = TextEditingController(text: actuel.type == FilterType.numeric ? actuel.to : '');
    final deAlpha = TextEditingController(text: actuel.type == FilterType.alphabetic ? actuel.from : '');
    final aAlpha = TextEditingController(text: actuel.type == FilterType.alphabetic ? actuel.to : '');
    var type = actuel.type == FilterType.none ? FilterType.numeric : actuel.type;
    await showDialog<void>(
      context: context,
      builder: (ctx) => LibererApres(
        objets: [deNum, aNum, deAlpha, aAlpha],
        child: StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Filtrer le rayon'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            RadioListTile<FilterType>(
              contentPadding: EdgeInsets.zero,
              title: Text('Par numéro (1 à $total)'),
              value: FilterType.numeric,
              groupValue: type,
              onChanged: (v) => setD(() => type = v!),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: deNum,
                    enabled: type == FilterType.numeric,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    decoration: const InputDecoration(labelText: 'De (n°)')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: aNum,
                    enabled: type == FilterType.numeric,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    decoration: const InputDecoration(labelText: 'À (n°)')),
              ),
            ]),
            const SizedBox(height: 12),
            RadioListTile<FilterType>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Par ordre alphabétique'),
              value: FilterType.alphabetic,
              groupValue: type,
              onChanged: (v) => setD(() => type = v!),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: deAlpha,
                    enabled: type == FilterType.alphabetic,
                    inputFormatters: [LengthLimitingTextInputFormatter(3)],
                    decoration: const InputDecoration(labelText: 'De (texte)')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: aAlpha,
                    enabled: type == FilterType.alphabetic,
                    inputFormatters: [LengthLimitingTextInputFormatter(3)],
                    decoration: const InputDecoration(labelText: 'À (texte)')),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                var filtre = ProductFilter();
                if (type == FilterType.numeric) {
                  var de = int.tryParse(deNum.text) ?? 0;
                  var a = int.tryParse(aNum.text) ?? 0;
                  if (de <= 0) de = 1;
                  if (a > total) a = total;
                  if (a == 0) a = total;
                  if (de > a) {
                    nvMessage(ctx, 'Erreur : « De » doit être inférieur à « À »', ton: ctx.nv.erreur);
                    return;
                  }
                  filtre = ProductFilter(type: FilterType.numeric, from: '$de', to: '$a');
                } else {
                  final de = deAlpha.text.toUpperCase();
                  final a = aAlpha.text.toUpperCase();
                  if (de.isEmpty || a.isEmpty) {
                    nvMessage(ctx, 'Erreur : les champs ne peuvent pas être vides', ton: ctx.nv.erreur);
                    return;
                  }
                  if (de.compareTo(a) > 0) {
                    nvMessage(ctx, 'Erreur : « De » doit être alphabétiquement avant « À »', ton: ctx.nv.erreur);
                    return;
                  }
                  filtre = ProductFilter(type: FilterType.alphabetic, from: de, to: a);
                }
                provider.applyFilter(filtre, inventoryId);
                Navigator.of(ctx).pop();
              },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
      ),
    );
    reprendreFocusScan();
  }

  Future<void> _allerA() async {
    final provider = entry;
    final ctrl = TextEditingController();
    final saisie = await showDialog<String>(
      context: context,
      builder: (ctx) => LibererApres(
        objets: [ctrl],
        child: AlertDialog(
        title: const Text('Aller au produit'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          inputFormatters: SaisieInput.rechercheFormatters,
          decoration: const InputDecoration(hintText: 'Position (ex. 45), nom ou code', prefixIcon: Icon(Icons.directions)),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Aller')),
        ],
      ),
      ),
    );
    if (!mounted || saisie == null || saisie.isEmpty) return;
    final produits = provider.products;
    var cible = -1;
    if (RegExp(r'^\d+$').hasMatch(saisie)) {
      final pos = int.parse(saisie);
      if (pos > 0 && pos <= produits.length) cible = pos - 1;
    }
    if (cible == -1) {
      cible = produits.indexWhere((p) => p.produitCip.contains(saisie) || p.produitName.toLowerCase().contains(saisie.toLowerCase()));
    }
    if (cible != -1) {
      provider.jumpToProduct(produits[cible], inventoryId);
      nvMessage(context, 'Position ${cible + 1} : ${produits[cible].produitName}', ton: context.nv.ok, duree: const Duration(seconds: 1));
    } else {
      nvMessage(context, 'Aucun produit trouvé.', ton: context.nv.erreur);
    }
    reprendreFocusScan();
  }

  Future<void> _recap() async {
    final provider = entry;
    final rayon = provider.selectedRayon;
    if (rayon == null) return;
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final produits = await api.fetchProducts(inventoryId, rayon.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(nvRoute(NvRecapScreen(inventoryId: inventoryId, rayonId: rayon.id, rayonName: rayon.libelle, produits: produits)));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      nvMessage(context, 'Erreur : $e', ton: context.nv.erreur);
    }
  }

  Future<void> _exporterRayon() async {
    final provider = entry;
    final rayon = provider.selectedRayon;
    if (rayon == null) return;
    if (provider.allProducts.isEmpty) {
      nvMessage(context, 'Aucune donnée à exporter.');
      return;
    }
    try {
      final nom = 'Export_${NvExports.nomPropre('Rayon_${rayon.libelle}')}_${NvExports.horodatage()}.csv';
      final r = await NvExports.ecrireCsv(NvExports.csvSaisies(provider.allProducts), nom, 'Export CSV Rayon_${rayon.libelle}');
      if (mounted && r.cheminTelechargements != null) nvMessage(context, 'Export réussi dans Téléchargements :\n$nom', ton: context.nv.ok);
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur export : $e', ton: context.nv.erreur);
    }
  }

  void _menu(String v) {
    final provider = entry;
    final rayon = provider.selectedRayon;
    switch (v) {
      case 'aller':
        _allerA();
      case 'filtre':
        _filtre();
      case 'sansfiltre':
        provider.applyFilter(ProductFilter(type: FilterType.none), inventoryId);
      case 'oublis':
        provider.filterToUncounted();
      case 'recap':
        _recap();
      case 'ecarts':
        if (rayon != null) Navigator.of(context).push(nvRoute(NvEcartsScreen(inventaire: inventaire, rayon: rayon)));
      case 'export':
        _exporterRayon();
      case 'cumuls':
        Navigator.of(context).push(nvRoute(const NvCumulsScreen()));
      case 'envoyer':
        envoyerInventaire();
    }
  }

  // ---------- Affichage ----------

  Widget _etatPrecedent(BuildContext context, SaisieQueue q) {
    final id = _precedentId;
    if (id == null) return const SizedBox.shrink();
    final s = q.ligne(inventoryId, id);
    if (s == null) return const SizedBox.shrink();
    final nv = context.nv;
    final (texte, ton) = s.envoyee
        ? ('précédent envoyé', nv.ok)
        : s.refusee
            ? ('précédent refusé', nv.erreur)
            : ('précédent en attente', nv.attente);
    return Semantics(
      label: texte,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: ton.fg, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(texte, key: const ValueKey('nv-etat-precedent'), style: TextStyle(color: ton.fg, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _carteProduit(BuildContext context, EntryProvider provider, Product p, AppConfig appConfig) {
    final nv = context.nv;
    final touche = p.dtUpdated != null || provider.isProductTouched(p.id);
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(p.produitName,
            key: const ValueKey('nv-produit-courant'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: nv.encre, height: 1.2)),
        const SizedBox(height: 2),
        Text('CIP ${p.produitCip} · PV ${francs(p.produitPrixUni)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: nv.gris, fontSize: 13.5)),
        const SizedBox(height: 10),
        Row(children: [
          if (appConfig.showTheoreticalStock) ...[
            Expanded(child: Chiffre('Stock théorique', '${p.quantiteInitiale}', couleur: p.quantiteInitiale < 0 ? nv.erreur.fg : null)),
            const SizedBox(width: 8),
          ],
          Expanded(child: Chiffre('Déjà compté', touche ? '${p.quantiteSaisie}' : '—', couleur: touche ? nv.action : null)),
          const SizedBox(width: 8),
          Expanded(child: Chiffre('Prix achat', francs(p.produitPrixAchat))),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntryProvider>();
    final appConfig = context.watch<AppConfig>();
    final q = context.watch<SaisieQueue>();
    final rayon = provider.selectedRayon ?? provider.rayons.where((r) => r.id == widget.rayonId).firstOrNull;
    final p = provider.currentProduct;

    if (p != null && p.id != _produitAffiche) {
      _produitAffiche = p.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _quantite = '';
          _erreur = null;
        });
        reprendreFocusScan();
      });
    }
    if (provider.hasPendingSession && !_pendingVu) {
      _pendingVu = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sessionNonTerminee();
      });
    }

    final idxGlobal = p == null ? -1 : provider.allProducts.indexWhere((x) => x.id == p.id);
    final position = (idxGlobal != -1 ? idxGlobal : provider.currentProductIndex) + 1;
    final total = provider.totalProductsInRayon;
    final filtre = _libelleFiltre(provider.activeFilter);
    final sousTitre = p == null
        ? inventaire.libelle
        : [
            'Produit $position / $total',
            if (filtre.isNotEmpty) '$filtre (${provider.currentProductIndex + 1}/${provider.totalProducts})',
          ].join(' · ');

    Widget corps;
    if (provider.error != null) {
      corps = NvErreur(provider.errorObject ?? provider.error!, onRetry: () {
        if (provider.rayons.isEmpty) {
          _charger();
        } else {
          provider.fetchProducts(api, inventoryId, widget.rayonId);
        }
      });
    } else if (provider.isLoading && provider.products.isEmpty) {
      corps = const NvChargement(texte: 'Chargement du rayon…');
    } else if (p == null) {
      corps = NvVide(
        icon: Icons.inventory_2_outlined,
        titre: provider.activeFilter.isActive ? 'Aucun produit correspondant au filtre.' : 'Aucun produit dans cet emplacement.',
      );
    } else {
      final haut = <Widget>[
        ChampScanNv(
          controller: champScanCtrl,
          focusNode: champScanFocus,
          label: 'Scanner prêt · ou tapez la quantité',
          hint: 'Clavier : recherche par nom',
          onCode: surCodeChamp,
          onTexte: surFrappe,
          onClavier: surClavier,
        ),
        const SizedBox(height: 12),
        _carteProduit(context, provider, p, appConfig),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('nv-precedent'),
              onPressed: provider.currentProductIndex > 0 ? () => provider.previousProduct(inventoryId) : null,
              icon: const Icon(Icons.chevron_left),
              label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Précédent')),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            key: const ValueKey('nv-aller-a'),
            tooltip: 'Aller au produit',
            onPressed: _allerA,
            icon: const Icon(Icons.find_in_page_outlined),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('nv-suivant'),
              onPressed: provider.currentProductIndex < provider.totalProducts - 1 ? () => provider.nextProduct(inventoryId) : null,
              icon: const Icon(Icons.chevron_right),
              label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Suivant')),
            ),
          ),
        ]),
      ];
      final pave = clavierTexte ? const SizedBox.shrink() : NvPave(ok: 'OK ›', onKey: _touche, okActif: true, hauteur: NvPave.hauteurPour(context));
      final large = Responsive.columns(context) > 1;
      final liste = Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), children: haut),
        if (afficherResultats)
          Positioned.fill(top: 84, child: ListeResultats(produits: resultats, stockVisible: appConfig.showTheoreticalStock, onTap: choisirResultat)),
      ]);
      // Quantité tapée (et rappel compact du produit) ÉPINGLÉE juste au-dessus du pavé, hors de la
      // liste qui défile : toujours visible sans défilement, quel que soit l'écran (640 dp de haut,
      // texte agrandi) et même pendant la recherche par nom (clavier système ouvert, pavé masqué).
      final quantite = Container(
        key: const ValueKey('nv-zone-quantite'),
        color: context.nv.page,
        padding: EdgeInsets.fromLTRB(large ? 8 : 16, 6, large ? 8 : 16, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(p.produitName,
              key: const ValueKey('nv-produit-compact'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.nv.encre)),
          const SizedBox(height: 4),
          AfficheQuantite(
            label: 'Quantité comptée',
            valeur: _quantite,
            erreur: _erreur,
            droite: _etatPrecedent(context, q),
          ),
        ]),
      );
      corps = large
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: liste),
              SizedBox(width: 380, child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [quantite, pave, const SizedBox(height: 16)])),
            ])
          : Column(children: [Expanded(child: liste), quantite, pave]);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await securiteSortie() && mounted) nav.pop();
      },
      child: NvScaffold(
        title: rayon == null ? 'Rayon' : libelleRayon(rayon),
        subtitle: sousTitre,
        wide: true,
        progression: p == null || total == 0 ? null : position / total,
        actions: [
          Semantics(
            label: provider.inventaireAJour ? 'Serveur à jour' : 'Envoi au serveur en attente',
            child: Tooltip(
              message: provider.inventaireAJour ? 'Serveur à jour' : 'Envoi au serveur…',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(provider.inventaireAJour ? Icons.cloud_done : Icons.cloud_upload,
                    color: provider.inventaireAJour ? const Color(0xFF6EE7A0) : Pal.amber),
              ),
            ),
          ),
          ActionEntete(
            icon: provider.activeFilter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
            tooltip: 'Filtrer le rayon',
            onPressed: rayon == null || provider.allProducts.isEmpty ? null : _filtre,
          ),
          PopupMenuButton<String>(
            key: const ValueKey('nv-menu-guidee'),
            tooltip: 'Plus',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'envoyer', child: Text('Envoyer les données')),
              const PopupMenuItem(value: 'aller', child: Text('Aller au produit…')),
              const PopupMenuItem(value: 'filtre', child: Text('Filtrer…')),
              if (provider.activeFilter.isActive) const PopupMenuItem(value: 'sansfiltre', child: Text('Retirer le filtre')),
              PopupMenuItem(value: 'oublis', child: Text('Voir les oublis (${provider.uncountedProductsCount})')),
              const PopupMenuItem(value: 'recap', child: Text('Récapitulatif du rayon')),
              const PopupMenuItem(value: 'ecarts', child: Text('Écarts du rayon')),
              const PopupMenuItem(value: 'export', child: Text('Exporter le rayon (CSV)')),
              const PopupMenuItem(value: 'cumuls', child: Text('Historique des cumuls')),
            ],
          ),
        ],
        body: corps,
      ),
    );
  }
}

/// Libellé d'un rayon (« S1A0T2 – CANNES »).
String libelleRayon(Rayon r) => r.code.isEmpty || r.code == r.libelle ? r.libelle : '${r.code} – ${r.libelle}';
