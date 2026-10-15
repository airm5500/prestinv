// lib/ui/ecrans/saisie_guidee_screen.dart
// Nouvelle interface — saisie guidée d'un rayon (maquette « Saisie », 4.13) : produit par produit, grand
// chiffre, pavé ambre, état d'envoi du produit précédent, douchette toujours prête (un scan ouvre le
// produit). En-tête : rayon, nuage, (envoi manuel) icône d'envoi avec pastille du nombre de saisies non
// envoyées, menu ⋮ (feuille du bas) ; barre de progression avec « 15 / 126 » sur la même ligne.
// Sous l'en-tête : champ de la douchette + bouton de filtre à sa droite, puis une ligne RÉSERVÉE au
// détail du filtre (« Retirer ») ; le nom du produit a toujours deux lignes réservées (échelle du texte
// comprise) : l'écran ne bouge jamais d'un produit à l'autre. Même logique que la saisie guidée de l'écran d'origine (InventoryEntryScreen) :
// EntryProvider (rayons, produits, filtres, position mémorisée, quantité → file des saisies AVANT
// envoi), cumul « déjà compté » (vérification locale), seuil « grande quantité », fin de rayon,
// sécurité de sortie, rappel d'envoi, récapitulatif, écarts du rayon, export CSV, historique des cumuls.
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/cumuls_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/feuille_quantite.dart';
import 'package:prestinv/ui/ecrans/recap_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_commune.dart';
import 'package:prestinv/ui/ecrans/widgets_saisie.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/filtre_rayon.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:provider/provider.dart';

class NvSaisieGuideeScreen extends StatefulWidget {
  final Inventory inventaire;
  final String rayonId;

  /// Ouvert depuis le choix du rayon (« Changer de rayon » y revient) ; sinon (« Reprendre ») le choix
  /// du rayon est ouvert à sa place.
  final bool depuisChoixRayon;
  const NvSaisieGuideeScreen({super.key, required this.inventaire, required this.rayonId, this.depuisChoixRayon = false});

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
        final ajouter = await demanderRemplacerAjouter(context, nom: produit.produitName, existant: existant, saisie: saisie, masquer: config.masquerDejaCompte);
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
    nvDialogue<String>(
      context,
      key: const ValueKey('nv-fin-rayon'),
      icone: reste > 0 ? Icons.priority_high : Icons.check,
      ton: reste > 0 ? context.nv.attente : context.nv.ok,
      titre: reste > 0 ? 'Rayon incomplet' : 'Fin du rayon',
      message: reste > 0
          ? 'Il reste $reste produit(s) jamais touchés.\n\nVoulez-vous les traiter maintenant ?'
          : 'Tous les produits ont été touchés. Voulez-vous envoyer les données ?',
      boutons: [
        if (reste > 0) const NvBouton('Traiter les oublis', 'oublis', genre: NvGenre.principal),
        const NvBouton('Envoyer', 'envoyer', genre: NvGenre.secondaire),
        const NvBouton('Non', 'non', genre: NvGenre.discret),
      ],
    ).then((r) {
      if (!mounted) return;
      if (r == 'oublis') provider.filtrerOublis();
      if (r == 'envoyer') envoyerInventaire();
    });
  }

  void _sessionNonTerminee() {
    final provider = entry;
    provider.acknowledgedPendingSession();
    nvDialogue<bool>(
      context,
      icone: Icons.cloud_upload_outlined,
      titre: 'Saisie non terminée',
      message: 'Des saisies non envoyées de la dernière session ont été trouvées. Voulez-vous les envoyer maintenant ?',
      boutons: const [
        NvBouton('Non', false, genre: NvGenre.secondaire),
        NvBouton('Oui, envoyer', true, genre: NvGenre.principal),
      ],
    ).then((r) {
      if (r == true && mounted) envoyerInventaire();
    });
  }

  // ---------- Filtre et menus ----------

  Future<void> _filtre() async {
    final provider = entry;
    final rayon = provider.selectedRayon;
    final choix = await ouvrirFiltreRayon(
      context,
      actuel: provider.activeFilter,
      total: provider.totalProductsInRayon,
      rayon: rayon == null ? '' : libelleRayon(rayon),
      oublis: provider.uncountedProductsCount,
    );
    if (!mounted) return;
    switch (choix) {
      case AppliquerFiltre(:final filtre):
        await provider.applyFilter(filtre, inventoryId);
      case EffacerFiltre():
        await provider.applyFilter(ProductFilter(type: FilterType.none), inventoryId);
      case FiltrerOublis():
        provider.filtrerOublis();
      case null:
        break; // Annuler : le filtre reste tel qu'il était
    }
    reprendreFocusScan();
  }

  Future<void> _retirerFiltre() async {
    await entry.applyFilter(ProductFilter(type: FilterType.none), inventoryId);
    reprendreFocusScan();
  }

  Future<void> _allerA() async {
    final provider = entry;
    final ctrl = TextEditingController();
    final saisie = await showDialog<String>(
      context: context,
      builder: (ctx) => LibererApres(
        objets: [ctrl],
        child: NvCadreDialogue(
          icone: Icons.find_in_page_outlined,
          ton: ctx.nv.info,
          titre: 'Aller au produit',
          contenu: TextField(
            controller: ctrl,
            autofocus: true,
            inputFormatters: SaisieInput.rechercheFormatters,
            decoration: const InputDecoration(hintText: 'Position (ex. 45), nom ou code', prefixIcon: Icon(Icons.directions)),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          boutons: nvRangeeBoutons(ctx, [
            nvBoutonFenetre(ctx, libelle: 'Annuler', genre: NvGenre.secondaire, onPressed: () => Navigator.of(ctx).pop()),
            nvBoutonFenetre(ctx, libelle: 'Aller', genre: NvGenre.principal, onPressed: () => Navigator.of(ctx).pop(ctrl.text)),
          ], const []),
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
      final choisi = await Navigator.of(context).push<Product>(
          nvRoute(NvRecapScreen(inventoryId: inventoryId, rayonId: rayon.id, rayonName: libelleRayon(rayon), produits: produits, retourSaisie: true)));
      // Une ligne touchée dans le récapitulatif : retour à la saisie sur ce produit.
      if (choisi != null && mounted) {
        final p = provider.products.where((x) => x.id == choisi.id).firstOrNull;
        if (p == null && provider.activeFilter.isActive) {
          await provider.applyFilter(ProductFilter(type: FilterType.none), inventoryId);
        }
        final cible = provider.products.where((x) => x.id == choisi.id).firstOrNull;
        if (cible != null) provider.jumpToProduct(cible, inventoryId);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      nvMessage(context, 'Erreur : $e', ton: context.nv.erreur);
    }
    reprendreFocusScan();
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

  /// PDF des écarts du rayon (mêmes lignes que l'écran Écarts du rayon), réglages de masquage appliqués.
  Future<void> _pdfEcarts() async {
    final rayon = entry.selectedRayon;
    if (rayon == null) return;
    final ecarts = entry.allProducts.where((p) => p.quantiteSaisie != p.quantiteInitiale).toList();
    if (ecarts.isEmpty) {
      nvMessage(context, 'Aucun écart dans ce rayon.', ton: context.nv.info);
      return;
    }
    try {
      await NvExports.imprimer(
          () => NvExports.pdfEcarts(rayon.libelle, ecarts, theoVisible: config.showTheoreticalStock, compteVisible: !config.masquerDejaCompte),
          'Ecarts_${NvExports.nomPropre(rayon.libelle)}');
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur lors de l\'impression : $e', ton: context.nv.erreur);
    }
  }

  /// « Changer de rayon » : retour au choix du rayon (sécurité de sortie d'abord).
  Future<void> _changerRayon() async {
    final nav = Navigator.of(context);
    if (!await securiteSortie() || !mounted) return;
    if (widget.depuisChoixRayon) {
      nav.pop();
    } else {
      nav.pushReplacement(nvRoute(NvChoixRayonScreen(inventaire: inventaire)));
    }
  }

  Future<void> _quitter() async {
    final nav = Navigator.of(context);
    if (await securiteSortie() && mounted) nav.pop();
  }

  Future<void> _menu() async {
    final provider = entry;
    final rayon = provider.selectedRayon;
    final v = await nvMenu<String>(context, key: const ValueKey('nv-feuille-menu'), entrees: [
      const NvEntree(Icons.list_alt, 'Récapitulatif du rayon', 'recap'),
      const NvEntree(Icons.find_in_page_outlined, 'Aller au produit…', 'aller'),
      NvEntree(Icons.playlist_add_check, 'Voir les oublis (${provider.uncountedProductsCount})', 'oublis'),
      const NvEntree(Icons.swap_horiz, 'Changer de rayon', 'rayon'),
      const NvEntree(Icons.cloud_upload_outlined, 'Envoyer les saisies maintenant', 'envoyer', key: ValueKey('nv-menu-envoyer')),
      NvEntree(Icons.compare_arrows, 'Écarts du rayon', 'ecarts', actif: rayon != null),
      NvEntree(Icons.print_outlined, 'Imprimer / PDF des écarts du rayon', 'pdf', actif: rayon != null),
      const NvEntree(Icons.file_download_outlined, 'Exporter le rayon (CSV)', 'export'),
      const NvEntree(Icons.history, 'Historique des cumuls', 'cumuls'),
      const NvEntree(Icons.close, 'Quitter la saisie', 'quitter', danger: true, key: ValueKey('nv-menu-quitter')),
    ]);
    if (!mounted) return;
    switch (v) {
      case 'aller':
        _allerA();
      case 'oublis':
        provider.filtrerOublis();
      case 'recap':
        _recap();
      case 'rayon':
        _changerRayon();
      case 'ecarts':
        if (rayon != null) Navigator.of(context).push(nvRoute(NvEcartsScreen(inventaire: inventaire, rayon: rayon)));
      case 'pdf':
        _pdfEcarts();
      case 'export':
        _exporterRayon();
      case 'cumuls':
        Navigator.of(context).push(nvRoute(const NvCumulsScreen()));
      case 'envoyer':
        envoyerInventaire();
      case 'quitter':
        _quitter();
    }
    reprendreFocusScan();
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
        Flexible(
          child: Text(texte,
              key: const ValueKey('nv-etat-precedent'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ton.fg, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  /// Hauteur réservée au nom du produit : TOUJOURS deux lignes (calculée avec l'échelle du texte),
  /// pour que rien ne bouge entre un nom court et un nom long.
  static const _tailleNom = 19.0, _interligneNom = 1.2;

  Widget _carteProduit(BuildContext context, EntryProvider provider, Product p, AppConfig appConfig) {
    final nv = context.nv;
    final touche = p.dtUpdated != null || provider.isProductTouched(p.id);
    final hauteurNom = MediaQuery.textScalerOf(context).scale(_tailleNom) * _interligneNom * 2;
    final dejaCompte = !touche ? '—' : (appConfig.masquerDejaCompte ? '•••' : '${p.quantiteSaisie}');
    return SoftCard(
      key: const ValueKey('nv-carte-produit'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          key: const ValueKey('nv-zone-nom'),
          height: hauteurNom,
          child: Text(p.produitName,
              key: const ValueKey('nv-produit-courant'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              strutStyle: const StrutStyle(fontSize: _tailleNom, height: _interligneNom, forceStrutHeight: true),
              style: TextStyle(fontSize: _tailleNom, fontWeight: FontWeight.w800, color: nv.encre, height: _interligneNom)),
        ),
        const SizedBox(height: 2),
        Text('CIP ${p.produitCip} · PV ${francs(p.produitPrixUni)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: nv.gris, fontSize: 13.5)),
        const SizedBox(height: 10),
        Row(children: [
          if (appConfig.showTheoreticalStock) ...[
            Expanded(child: Chiffre('Stock théorique', '${p.quantiteInitiale}', couleur: p.quantiteInitiale < 0 ? nv.erreur.fg : null)),
            const SizedBox(width: 8),
          ],
          Expanded(child: Chiffre('Déjà compté', dejaCompte, couleur: touche ? nv.action : null, key: const ValueKey('nv-deja-compte'))),
          const SizedBox(width: 8),
          Expanded(child: Chiffre('Prix achat', francs(p.produitPrixAchat))),
        ]),
      ]),
    );
  }

  /// Champ de la douchette avec, à sa droite, le bouton de filtre (bleu plein si un filtre est actif).
  Widget _champEtFiltre(BuildContext context, EntryProvider provider) {
    final nv = context.nv;
    final actif = provider.activeFilter.isActive;
    final bleu = context.nvSombre ? nv.action : bleuFiltre;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: ChampScanNv(
          controller: champScanCtrl,
          focusNode: champScanFocus,
          label: 'Scanner prêt · ou tapez la quantité',
          hint: 'Clavier : recherche par nom',
          onCode: surCodeChamp,
          onTexte: surFrappe,
          onClavier: surClavier,
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        button: true,
        label: actif ? 'Filtrer le rayon (filtre actif)' : 'Filtrer le rayon',
        excludeSemantics: true,
        child: Material(
          color: actif ? bleu : nv.carte,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: bleu, width: 2)),
          child: InkWell(
            key: const ValueKey('nv-filtre'),
            borderRadius: BorderRadius.circular(12),
            onTap: provider.allProducts.isEmpty ? null : _filtre,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(actif ? Icons.filter_alt : Icons.filter_alt_outlined, color: actif ? (context.nvSombre ? Pal.navyFonce : Colors.white) : bleu),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Ligne RÉSERVÉE sous le champ (hauteur fixe, l'écran ne bouge jamais) : détail du filtre en bleu et
  /// « ✕ Retirer », sinon « Pas encore de filtre appliqué ».
  Widget _ligneFiltre(BuildContext context, EntryProvider provider) {
    final nv = context.nv;
    final texte = libelleFiltreActif(provider.activeFilter, provider.totalProducts);
    final bleu = context.nvSombre ? nv.action : bleuFiltre;
    final hauteur = math.max(48.0, MediaQuery.textScalerOf(context).scale(14) * 1.4 + 8);
    return SizedBox(
      key: const ValueKey('nv-ligne-filtre'),
      height: hauteur,
      child: Row(children: [
        Icon(Icons.filter_alt_outlined, size: 18, color: texte == null ? nv.gris : bleu),
        const SizedBox(width: 6),
        // Texte à sa largeur (nœud d'accessibilité ajusté au texte : contraste mesuré sur le texte).
        Flexible(
          flex: 50,
          child: Semantics(
            container: true,
            child: Text(texte ?? 'Pas encore de filtre appliqué',
                key: const ValueKey('nv-texte-filtre'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: texte == null ? FontWeight.w500 : FontWeight.w800, color: texte == null ? nv.gris : bleu)),
          ),
        ),
        const Spacer(),
        if (texte != null)
          TextButton.icon(
            key: const ValueKey('nv-retirer-filtre'),
            style: TextButton.styleFrom(
              foregroundColor: bleu,
              backgroundColor: nv.info.bg,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: StadiumBorder(side: BorderSide(color: bleu)),
              textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            onPressed: _retirerFiltre,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Retirer'),
          ),
      ]),
    );
  }

  /// Envoi manuel (4.14.1) : icône SEULE, comme le nuage voisin (aucun fond ni contour), orange
  /// (avion en papier « envoyer »), pastille rouge = saisies non envoyées ; zone de toucher 48 × 48 dp.
  Widget _boutonEnvoi(BuildContext context, int nombre) => Semantics(
        button: true,
        label: 'Envoyer les saisies ($nombre en attente)',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Stack(clipBehavior: Clip.none, children: [
            InkResponse(
              key: const ValueKey('nv-envoyer-badge'),
              radius: 24,
              onTap: envoyerInventaire,
              child: const SizedBox(width: 48, height: 48, child: Icon(Icons.send_rounded, color: Pal.amber, size: 26)),
            ),
            if (nombre > 0)
              Positioned(
                top: 0,
                right: -4,
                child: Container(
                  key: const ValueKey('nv-badge-attente'),
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: const Color(0xFFD92D20), borderRadius: BorderRadius.circular(11), border: Border.all(color: context.nv.entete, width: 2)),
                  alignment: Alignment.center,
                  child: Text(nombre > 99 ? '99+' : '$nombre', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
        ),
      );

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
      corps = ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), children: [
        if (provider.allProducts.isNotEmpty) ...[_champEtFiltre(context, provider), _ligneFiltre(context, provider)],
        SizedBox(
          height: 240,
          child: NvVide(
            icon: Icons.inventory_2_outlined,
            titre: provider.activeFilter.isActive ? 'Aucun produit correspondant au filtre.' : 'Aucun produit dans cet emplacement.',
          ),
        ),
      ]);
    } else {
      final haut = <Widget>[
        _champEtFiltre(context, provider),
        _ligneFiltre(context, provider),
        _carteProduit(context, provider, p, appConfig),
      ];
      final pave = clavierTexte ? const SizedBox.shrink() : NvPave(ok: 'OK ›', onKey: _touche, okActif: true, hauteur: NvPave.hauteurPour(context));
      final large = Responsive.columns(context) > 1;
      final liste = Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 6), children: haut),
        if (afficherResultats)
          Positioned.fill(top: 76, child: ListeResultats(produits: resultats, stockVisible: appConfig.showTheoreticalStock, onTap: choisirResultat)),
      ]);
      // Quantité tapée (et rappel compact du produit) ÉPINGLÉE juste au-dessus du pavé, hors de la
      // liste qui défile : toujours visible sans défilement, quel que soit l'écran (640 dp de haut,
      // texte agrandi) et même pendant la recherche par nom (clavier système ouvert, pavé masqué).
      // Maquette : quantité puis Précédent · Récapitulatif · Suivant, juste au-dessus du pavé. Le rappel
      // du produit est DANS la ligne de quantité (aucune hauteur en plus).
      final boutons =
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
              key: const ValueKey('nv-recap'),
              tooltip: 'Récapitulatif du rayon',
              style: IconButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: context.nv.ligne)),
              onPressed: _recap,
              icon: Icon(Icons.list_alt, color: context.nv.action),
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
          ]);
      final quantite = Container(
        key: const ValueKey('nv-zone-quantite'),
        color: context.nv.page,
        padding: EdgeInsets.fromLTRB(large ? 8 : 16, 6, large ? 8 : 16, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AfficheQuantite(
            label: 'Quantité comptée',
            valeur: _quantite,
            erreur: _erreur,
            compact: true,
            droite: _etatPrecedent(context, q),
            detail: Text(p.produitName,
                key: const ValueKey('nv-produit-compact'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.nv.encre)),
          ),
          const SizedBox(height: 8),
          boutons,
        ]),
      );
      corps = large
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: liste),
              SizedBox(width: 380, child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [quantite, pave, const SizedBox(height: 16)])),
            ])
          : Column(children: [Expanded(child: liste), quantite, pave]);
    }

    final manuel = appConfig.sendMode == SendMode.collect;
    final enAttente = q.enAttente(inventaireId: inventoryId);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await securiteSortie() && mounted) nav.pop();
      },
      child: NvScaffold(
        title: rayon == null ? 'Rayon' : libelleRayon(rayon),
        wide: true,
        progression: p == null || total == 0 ? null : position / total,
        progressionTexte: p == null || total == 0 ? null : '$position / $total',
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
          if (manuel) _boutonEnvoi(context, enAttente),
          IconButton(
            key: const ValueKey('nv-menu-guidee'),
            tooltip: 'Plus d\'actions',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _menu,
          ),
        ],
        body: corps,
      ),
    );
  }
}

/// Bleu du filtre (maquette : #1F5FBF), contrasté sur le fond de page et sur le fond « info ».
const bleuFiltre = Color(0xFF1F5FBF);

/// Libellé d'un rayon (« S1A0T2 – CANNES »).
String libelleRayon(Rayon r) => r.code.isEmpty || r.code == r.libelle ? r.libelle : '${r.code} – ${r.libelle}';
