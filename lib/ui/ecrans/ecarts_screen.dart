// lib/ui/ecrans/ecarts_screen.dart
// Nouvelle interface — écarts (maquette C) : montants en F CFA (écart × prix d'achat), tri par valeur,
// bande rouge / verte + signe (jamais la couleur seule), compteur « à vérifier », correction
// avant / après / écart en direct (Précédent · Garder · Suivant, pavé « Corriger »).
// Téléphone : liste de cartes + feuille de correction ; tablette (≥ 900 dp) : menu latéral, tableau,
// bilan en valeur et correction à droite.
// Même logique que les écrans d'origine :
// - sans rayon (accueil) = GlobalVarianceScreen : fetchGlobalVariances / fetchTouchedProductsByRayon,
//   « vérifié » seulement après confirmation du serveur, obligation de tout traiter (Forcer la sortie) ;
// - avec rayon (saisie guidée) = VarianceScreen : produits du rayon dont compté ≠ théorique, impression.
// Corrections : corrigerQuantite (file des saisies puis envoi immédiat), messageEchecCorrection.
// Réglages (4.13) : « Masquer la quantité déjà comptée » → « compté » masqué (•••), quantité recomptée
// non pré-remplie, colonnes retirées du PDF / CSV ; « Afficher le stock théorique » désactivé →
// théorique masqué à l'écran ET dans le PDF / CSV.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_correction.dart';
import 'package:prestinv/scan/champ_douchette.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/ui/clavier.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/navigation.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:provider/provider.dart';

enum TriEcarts { valeur, manquants, surplus }

/// Valeur d'un écart au prix d'achat (F CFA).
double valeurEcart(Product p) => (p.quantiteSaisie - p.quantiteInitiale) * p.produitPrixAchat;

/// Liste triée / filtrée (tri par valeur absolue décroissante).
List<Product> trierEcarts(List<Product> ps, TriEcarts tri) {
  final l = switch (tri) {
    TriEcarts.valeur => List<Product>.of(ps),
    TriEcarts.manquants => ps.where((p) => p.quantiteSaisie < p.quantiteInitiale).toList(),
    TriEcarts.surplus => ps.where((p) => p.quantiteSaisie > p.quantiteInitiale).toList(),
  };
  l.sort((a, b) => valeurEcart(b).abs().compareTo(valeurEcart(a).abs()));
  return l;
}

class NvEcartsScreen extends StatefulWidget {
  final Inventory inventaire;

  /// Rayon de la saisie guidée (null : tout l'inventaire, depuis l'accueil).
  final Rayon? rayon;
  const NvEcartsScreen({super.key, required this.inventaire, this.rayon});

  @override
  State<NvEcartsScreen> createState() => _NvEcartsScreenState();
}

class _NvEcartsScreenState extends State<NvEcartsScreen> {
  late final ApiService _api;
  final _champ = TextEditingController();
  final _focus = FocusNode();
  Timer? _frappe;

  List<Product> _tous = [];
  List<Product> _affiches = [];
  List<Rayon> _rayons = [];
  Rayon? _filtreRayon;
  TriEcarts _tri = TriEcarts.valeur;
  bool _chargement = true;
  Object? _erreur;
  bool _impression = false;
  final Set<int> _verifies = {};

  // Correction en cours (feuille sur téléphone, panneau sur tablette).
  int? _index;
  String _saisie = '';
  bool _preRempli = true;
  bool _envoi = false;
  String? _erreurCorr;
  bool _feuille = false;
  StateSetter? _majFeuille;

  late final CibleDouchette _cibleScan;
  late final CibleDouchette _cibleSaisie;

  bool get _global => widget.rayon == null;
  bool get _large => Responsive.isExpanded(context);

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _api = ApiService(baseUrl: context.read<AppConfig>().currentApiUrl, cookie: () => auth.sessionCookie);
    _cibleScan = CibleDouchette(active: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true), onCode: _code);
    _cibleSaisie = CibleDouchette(
      active: () => mounted && (_feuille || (_large && _index != null && (ModalRoute.of(context)?.isCurrent ?? true))),
      onChiffres: (t) => t.split('').forEach(_touche),
      onEffacer: () => _touche('DEL'),
      onValider: () => _touche('OK'),
    );
    Douchette.instance.ajouter(_cibleScan);
    Douchette.instance.ajouter(_cibleSaisie);
    _charger();
  }

  @override
  void dispose() {
    Douchette.instance.retirer(_cibleScan);
    Douchette.instance.retirer(_cibleSaisie);
    _champ.dispose();
    _focus.dispose();
    _frappe?.cancel();
    super.dispose();
  }

  // ---------- Chargement (mêmes appels que les écrans d'origine) ----------

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      if (_global) {
        final r = await Future.wait([_api.fetchGlobalVariances(widget.inventaire.id), _api.fetchRayons(widget.inventaire.id)]);
        _tous = r[0] as List<Product>;
        _rayons = r[1] as List<Rayon>;
      } else {
        final ps = await _api.fetchProducts(widget.inventaire.id, widget.rayon!.id);
        _tous = ps.where((p) => p.quantiteSaisie != p.quantiteInitiale).toList();
      }
      if (!mounted) return;
      setState(() {
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

  Future<void> _changerRayon(Rayon? r) async {
    setState(() {
      _filtreRayon = r;
      _chargement = true;
      _erreur = null;
      _index = null;
    });
    try {
      final ps = r == null ? await _api.fetchGlobalVariances(widget.inventaire.id) : await _api.fetchTouchedProductsByRayon(widget.inventaire.id, r.id);
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
    final base = q.isEmpty ? _tous : _tous.where((p) => p.produitCip.contains(q) || p.produitName.toLowerCase().contains(q)).toList();
    _affiches = trierEcarts(base, _tri);
  }

  void _code(String code) => _rechercher(code);

  void _surTexte(String t) {
    setState(_filtrer);
    _frappe?.cancel();
    if (t.isNotEmpty) _frappe = Timer(const Duration(milliseconds: 500), () => _rechercher(t));
  }

  Future<void> _rechercher(String texte) async {
    final q = SaisieInput.nettoyerRecherche(texte);
    if (q.isEmpty) return;
    if (!_global) {
      // Rayon : recherche dans la liste chargée (comme VarianceScreen).
      final m = _tous.where((p) => p.produitCip.toLowerCase().contains(q.toLowerCase()) || p.produitName.toLowerCase().contains(q.toLowerCase())).toList();
      if (m.length == 1) {
        _champ.clear();
        setState(_filtrer);
        _ouvrir(_affiches.indexWhere((p) => p.id == m.first.id));
      } else if (m.isEmpty) {
        nvMessage(context, 'Ce produit n\'est pas dans la liste des écarts.', ton: context.nv.erreur);
      } else {
        setState(() => _affiches = trierEcarts(m, _tri));
      }
      return;
    }
    try {
      final r = await _api.fetchGlobalVariances(widget.inventaire.id, query: q);
      if (!mounted) return;
      if (r.length == 1) {
        _champ.clear();
        setState(() => _affiches = r);
        _ouvrir(0);
      } else if (r.isNotEmpty) {
        setState(() => _affiches = trierEcarts(r, _tri));
      } else {
        nvMessage(context, 'Ce produit n\'est pas dans la liste des écarts.', ton: context.nv.erreur);
      }
    } catch (e) {
      if (mounted) nvMessage(context, messageErreur(e), ton: context.nv.erreur);
    }
  }

  // ---------- Correction ----------

  void _maj(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _majFeuille?.call(() {});
  }

  bool get _compteMasque => context.read<AppConfig>().masquerDejaCompte;

  void _selectionner(int i) => _maj(() {
        _index = i;
        // Quantité déjà comptée masquée : rien n'est pré-rempli (sinon elle se lirait dans le champ).
        _saisie = _compteMasque ? '' : '${_affiches[i].quantiteSaisie}';
        _preRempli = !_compteMasque;
        _erreurCorr = null;
      });

  Future<void> _ouvrir(int i) async {
    if (i < 0 || i >= _affiches.length) return;
    _selectionner(i);
    if (_large) return;
    _feuille = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        _majFeuille = set;
        return SingleChildScrollView(child: _panneau(ctx, feuille: true));
      }),
    );
    _majFeuille = null;
    _feuille = false;
    if (mounted) setState(() {});
  }

  void _touche(String k) {
    if (_index == null || _envoi) return;
    if (k == 'OK') {
      _corriger();
    } else if (k == 'DEL') {
      _maj(() {
        _saisie = _preRempli ? '' : (_saisie.isEmpty ? '' : _saisie.substring(0, _saisie.length - 1));
        _preRempli = false;
      });
    } else {
      _maj(() {
        _saisie = SaisieInput.ajouterChiffre(_preRempli ? '' : _saisie, k);
        _preRempli = false;
        _erreurCorr = null;
      });
    }
  }

  Future<void> _corriger({int? garder}) async {
    final i = _index;
    if (i == null || _envoi) return;
    final p = _affiches[i];
    int qte;
    if (garder != null) {
      qte = garder;
    } else {
      final e = SaisieInput.erreurQuantite(_saisie);
      if (e != null) {
        _maj(() => _erreurCorr = e);
        return;
      }
      qte = SaisieInput.parseQuantite(_saisie)!;
    }
    _maj(() {
      _envoi = true;
      _erreurCorr = null;
    });
    String? echec;
    try {
      final r = await corrigerQuantite(
        inventoryId: widget.inventaire.id,
        inventoryName: widget.inventaire.libelle,
        product: p,
        quantite: qte,
        origine: OrigineSaisie.ecarts,
        rayonId: widget.rayon?.id ?? _filtreRayon?.id,
        rayonLibelle: widget.rayon?.libelle ?? _filtreRayon?.libelle,
        auteur: context.read<AuthProvider>().user?.login ?? '',
      );
      if (!r.estOk) echec = messageEchecCorrection(r);
    } catch (e) {
      echec = 'Enregistrement impossible sur l\'appareil : $e';
    }
    if (!mounted) return;
    if (echec != null) {
      _maj(() {
        _envoi = false;
        _erreurCorr = echec;
      });
      return;
    }
    _maj(() {
      _envoi = false;
      p.quantiteSaisie = qte;
      _verifies.add(p.id);
    });
    if (i < _affiches.length - 1) {
      _selectionner(i + 1);
    } else {
      if (_feuille) Navigator.of(context).pop();
      nvMessage(context, 'Fin de la liste atteinte.', ton: context.nv.info);
      _maj(() => _index = _large ? i : null);
    }
  }

  // ---------- Sortie, impression, export ----------

  Future<bool> _peutSortir() async {
    if (!_global || _affiches.isEmpty) return true;
    final reste = _affiches.where((p) => !_verifies.contains(p.id)).length;
    if (reste == 0) return true;
    final r = await nvDialogue<bool>(
      context,
      fermable: false,
      icone: Icons.priority_high,
      titre: 'Quitter la correction ?',
      message: 'Il reste encore $reste écart(s) à vérifier dans cette liste.\n\nVous avez l\'obligation de tous les traiter.',
      boutons: const [
        NvBouton('Rester et corriger', false, genre: NvGenre.principal),
        NvBouton('Forcer la sortie', true, genre: NvGenre.danger, key: ValueKey('nv-forcer-sortie')),
      ],
    );
    return r == true;
  }

  String get _titreDoc => widget.rayon?.libelle ?? (_filtreRayon?.libelle ?? widget.inventaire.libelle);

  Future<void> _imprimer() async {
    if (_impression || _affiches.isEmpty) return;
    setState(() => _impression = true);
    try {
      final ps = List<Product>.of(_affiches);
      final c = context.read<AppConfig>();
      await NvExports.imprimer(() => NvExports.pdfEcarts(_titreDoc, ps, theoVisible: c.showTheoreticalStock, compteVisible: !c.masquerDejaCompte),
          'Ecarts_${NvExports.nomPropre(_titreDoc)}');
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur lors de l\'impression : $e', ton: context.nv.erreur);
    } finally {
      if (mounted) setState(() => _impression = false);
    }
  }

  Future<void> _csv() async {
    if (_affiches.isEmpty) return;
    try {
      final c = context.read<AppConfig>();
      final r = await NvExports.ecrireCsv(NvExports.csvEcarts(_affiches, theoVisible: c.showTheoreticalStock, compteVisible: !c.masquerDejaCompte),
          'Ecarts_${NvExports.nomPropre(_titreDoc)}_${NvExports.horodatage()}.csv', 'Écarts $_titreDoc');
      if (mounted && r.cheminTelechargements != null) nvMessage(context, 'Export réussi dans Téléchargements.', ton: context.nv.ok);
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur export : $e', ton: context.nv.erreur);
    }
  }

  Future<void> _choisirRayon() async {
    final r = await nvMenu<({Rayon? r})>(context, titre: 'Emplacement', entrees: [
      const NvEntree(Icons.select_all, 'Tous les emplacements', (r: null)),
      for (final x in _rayons) NvEntree(x.id == _filtreRayon?.id ? Icons.radio_button_checked : Icons.place_outlined, x.libelle, (r: x)),
    ]);
    if (r != null && mounted && r.r?.id != _filtreRayon?.id) _changerRayon(r.r);
  }

  // ---------- Affichage ----------

  ({double manquants, double surplus}) get _bilan {
    double m = 0, s = 0;
    for (final p in _affiches) {
      final v = valeurEcart(p);
      if (v < 0) m += v;
      if (v > 0) s += v;
    }
    return (manquants: m, surplus: s);
  }

  Widget _panneau(BuildContext context, {required bool feuille}) {
    final i = _index;
    final nv = context.nv;
    final config = context.read<AppConfig>();
    if (i == null || i >= _affiches.length) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('Touchez une ligne pour la corriger.', style: TextStyle(color: nv.gris)),
      );
    }
    final p = _affiches[i];
    final nouveau = SaisieInput.parseQuantite(_saisie);
    final ecartApres = nouveau == null ? null : nouveau - p.quantiteInitiale;
    final ecart = p.quantiteSaisie - p.quantiteInitiale;
    final theo = config.showTheoreticalStock ? '${p.quantiteInitiale}' : '***';
    final compte = config.masquerDejaCompte ? '•••' : '${p.quantiteSaisie}';
    final couleurEcart = ecartApres == null ? nv.gris : (ecartApres < 0 ? nv.manquant : (ecartApres > 0 ? nv.surplus : nv.ok.fg));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(18, feuille ? 0 : 16, 18, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(p.produitName,
                  key: const ValueKey('nv-ecart-produit'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: nv.encre)),
            ),
            const SizedBox(width: 8),
            Pastille(signe(ecart), ton: ecart < 0 ? nv.erreur : nv.ok),
          ]),
          Text(
            [
              'CIP ${p.produitCip}',
              if ((p.locationLabel ?? widget.rayon?.libelle) != null) (p.locationLabel ?? widget.rayon!.libelle),
              '${i + 1} / ${_affiches.length}',
              if (_verifies.contains(p.id)) 'vérifié',
              // 4.16.1 (demande serveur 50) : qui a compté cette ligne (serveur à jour).
              if (p.auteur != null) 'compté par ${p.auteur}',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: nv.gris, fontSize: 13.5),
          ),
          if (!feuille)
            // Tablette (maquette C) : chiffres en une ligne, le tableau montre déjà le détail.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Théo $theo · compté $compte', style: TextStyle(color: nv.encre, fontSize: 15)),
            )
          else ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Chiffre('Théorique', theo)),
            const SizedBox(width: 6),
            Expanded(child: Chiffre('Compté', compte)),
            const SizedBox(width: 6),
            Expanded(child: Chiffre('Nouveau', nouveau == null ? '—' : '$nouveau')),
            const SizedBox(width: 6),
            Expanded(child: Chiffre('Écart', ecartApres == null || !config.showTheoreticalStock ? '—' : signe(ecartApres), couleur: couleurEcart)),
          ]),
          ],
          const SizedBox(height: 10),
          AfficheQuantite(
            label: 'Quantité recomptée',
            valeur: _saisie,
            proposee: _preRempli,
            erreur: _erreurCorr,
            aide: _preRempli ? 'pré-remplie, remplacée à la 1re touche' : null,
            droite: feuille || ecartApres == null || !config.showTheoreticalStock
                ? null
                : Text('écart après : ${signe(ecartApres)}', style: TextStyle(color: couleurEcart, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('nv-ecart-precedent'),
                onPressed: i > 0 && !_envoi ? () => _selectionner(i - 1) : null,
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('‹ Précédent')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('nv-garder'),
                onPressed: _envoi ? null : () => _corriger(garder: p.quantiteSaisie),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(config.masquerDejaCompte ? 'Garder' : 'Garder ${p.quantiteSaisie}')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('nv-ecart-suivant'),
                onPressed: i < _affiches.length - 1 && !_envoi ? () => _selectionner(i + 1) : null,
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Suivant ›')),
              ),
            ),
          ]),
          const SizedBox(height: 6),
        ]),
      ),
      NvPave(ok: 'Corriger', okActif: !_envoi, onKey: _touche, hauteur: feuille ? NvPave.hauteurPour(context) : 48),
      if (feuille)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextButton(
            key: const ValueKey('nv-fermer-correction'),
            onPressed: _envoi ? null : () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ),
    ]);
  }

  Widget _carte(BuildContext context, int i) {
    final p = _affiches[i];
    final nv = context.nv;
    final e = p.quantiteSaisie - p.quantiteInitiale;
    final v = valeurEcart(p);
    final ok = _verifies.contains(p.id);
    final config = context.read<AppConfig>();
    final theo = config.showTheoreticalStock ? '${p.quantiteInitiale}' : '***';
    final compte = config.masquerDejaCompte ? '•••' : '${p.quantiteSaisie}';
    final couleur = e < 0 ? nv.manquant : (e > 0 ? nv.surplus : nv.gris);
    return Opacity(
      opacity: ok ? 0.75 : 1,
      child: SoftCard(
        key: ValueKey('nv-ecart-${p.id}'),
        bande: e < 0 ? Pal.red : (e > 0 ? Pal.green : nv.ligne),
        onTap: () => _ouvrir(i),
        semantique: '${p.produitName}, écart ${signe(e)}, ${francs(v, signeExplicite: true)}${ok ? ', vérifié' : ', à vérifier'}',
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.produitName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: nv.encre)),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Théo $theo · compté $compte${p.locationLabel != null ? ' · ${p.locationLabel}' : ''}'),
                  if (ok) TextSpan(text: ' · vérifié ✓', style: TextStyle(color: nv.ok.fg, fontWeight: FontWeight.bold)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: nv.gris, fontSize: 13.5),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(signe(e), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: couleur)),
            Text(francs(v, signeExplicite: true), style: TextStyle(fontSize: 13.5, color: nv.gris)),
          ]),
        ]),
      ),
    );
  }

  Widget _tableau(BuildContext context) {
    final nv = context.nv;
    final theoVisible = context.read<AppConfig>().showTheoreticalStock;
    final compteVisible = !context.read<AppConfig>().masquerDejaCompte;
    TextStyle entete = TextStyle(color: nv.gris, fontWeight: FontWeight.bold, fontSize: 14);
    Widget cellule(String t, {TextAlign a = TextAlign.right, TextStyle? s, double? w}) {
      final texte = Text(t, textAlign: a, maxLines: w == null ? 2 : 1, overflow: TextOverflow.ellipsis, style: s);
      return w == null ? Expanded(child: texte) : SizedBox(width: w, child: texte);
    }

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            cellule('Produit', a: TextAlign.left, s: entete),
            cellule('Théo', s: entete, w: 44),
            cellule('Compté', s: entete, w: 62),
            cellule('Écart', s: entete, w: 50),
            cellule('Valeur', s: entete, w: 98),
            const SizedBox(width: 12),
            cellule('État', a: TextAlign.left, s: entete, w: 104),
          ]),
        ),
        Divider(height: 1, color: nv.ligne),
        Expanded(
          child: ListView.separated(
            key: const ValueKey('nv-tableau-ecarts'),
            itemCount: _affiches.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: nv.ligne),
            itemBuilder: (context, i) {
              final p = _affiches[i];
              final e = p.quantiteSaisie - p.quantiteInitiale;
              final ok = _verifies.contains(p.id);
              final sel = i == _index;
              final couleur = e < 0 ? nv.manquant : (e > 0 ? nv.surplus : nv.gris);
              return Material(
                color: sel ? nv.attente.bg : Colors.transparent,
                child: InkWell(
                  key: ValueKey('nv-ligne-ecart-${p.id}'),
                  onTap: () => _ouvrir(i),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Row(children: [
                        cellule(p.produitName, a: TextAlign.left, s: TextStyle(fontWeight: FontWeight.w800, color: nv.encre)),
                        cellule(theoVisible ? '${p.quantiteInitiale}' : '***', s: TextStyle(color: nv.encre), w: 44),
                        cellule(compteVisible ? '${p.quantiteSaisie}' : '•••', s: TextStyle(color: nv.encre), w: 62),
                        cellule(signe(e), s: TextStyle(color: couleur, fontWeight: FontWeight.w900), w: 50),
                        cellule(francs(valeurEcart(p), signeExplicite: true), s: TextStyle(color: nv.encre), w: 98),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 104,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Pastille(ok ? 'vérifié' : 'à vérifier', ton: ok ? nv.ok : nv.attente, icon: ok ? Icons.check : null),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _bilanCarte(BuildContext context, {bool compact = false}) {
    final nv = context.nv;
    final b = _bilan;
    final total = b.surplus - b.manquants;
    return SoftCard(
      key: const ValueKey('nv-bilan'),
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Bilan des écarts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: compact ? 15 : 17, color: nv.encre))),
          Text('au prix d\'achat', style: TextStyle(color: nv.gris, fontSize: 13)),
        ]),
        SizedBox(height: compact ? 8 : 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: total <= 0
                ? Container(color: nv.ligne)
                : Row(children: [
                    if (b.manquants < 0) Expanded(flex: (-b.manquants).round().clamp(1, 1 << 30), child: Container(color: Pal.red)),
                    if (b.surplus > 0) Expanded(flex: b.surplus.round().clamp(1, 1 << 30), child: Container(color: Pal.green)),
                  ]),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 10),
          _ligneBilan(context, Pal.red, 'Manquants', francs(b.manquants)),
          _ligneBilan(context, Pal.green, 'Surplus', francs(b.surplus, signeExplicite: true)),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Manquants ${francs(b.manquants)} · surplus ${francs(b.surplus, signeExplicite: true)}',
                style: TextStyle(color: nv.gris, fontSize: 13.5)),
          ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('Écart net', style: TextStyle(fontSize: 16, color: nv.gris))),
          Text(francs(b.manquants + b.surplus, signeExplicite: true),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: b.manquants + b.surplus < 0 ? nv.manquant : nv.surplus)),
        ]),
      ]),
    );
  }

  Widget _ligneBilan(BuildContext context, Color c, String l, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(child: Text('$l $v', style: TextStyle(color: context.nv.gris, fontSize: 14.5))),
        ]),
      );

  Widget _champScan(BuildContext context) => CadreScan(
        champ: ChampDouchette(
          key: const ValueKey('champ-scan'),
          controller: _champ,
          focusNode: _focus,
          autofocus: true,
          label: 'Scanner ou rechercher un produit',
          hint: 'CIP, nom…',
          onCode: _code,
          onTexte: _surTexte,
          onClavier: (v) {
            if (!v) {
              _champ.clear();
              setState(_filtrer);
            }
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final large = _large;
    final aVerifier = _affiches.where((p) => !_verifies.contains(p.id)).length;
    final b = _bilan;
    final pills = FiltrePills(
      labels: const ['Par valeur', 'Manquants', 'Surplus'],
      selected: _tri.index,
      onSelected: (i) => setState(() {
        _tri = TriEcarts.values[i];
        _filtrer();
        _index = null;
      }),
      apres: [
        if (_global && _rayons.isNotEmpty)
          ActionChip(
            key: const ValueKey('nv-filtre-rayon'),
            avatar: const Icon(Icons.filter_list, size: 18),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(_filtreRayon == null ? 'Rayon' : _filtreRayon!.libelle, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down, size: 20),
            ]),
            onPressed: _choisirRayon,
            shape: const StadiumBorder(),
            labelStyle: TextStyle(color: nv.action, fontWeight: FontWeight.bold),
          ),
      ],
    );

    Widget corps;
    if (_chargement) {
      corps = const NvChargement(texte: 'Chargement des écarts…');
    } else if (_erreur != null) {
      corps = NvErreur(_erreur!, onRetry: () => _rayons.isEmpty && _global ? _charger() : (_global ? _changerRayon(_filtreRayon) : _charger()));
    } else if (large) {
      corps = Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: _champScan(context)), const SizedBox(width: 12), pills]),
          const SizedBox(height: 12),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: _affiches.isEmpty
                    ? const SoftCard(child: NvVide(icon: Icons.check_circle_outline, titre: 'Aucun écart trouvé !', detail: 'Tout semble correct pour ce filtre.'))
                    : _tableau(context),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 360,
                child: ListView(children: [
                  _bilanCarte(context, compact: true),
                  const SizedBox(height: 10),
                  SoftCard(padding: EdgeInsets.zero, child: _panneau(context, feuille: false)),
                ]),
              ),
            ]),
          ),
        ]),
      );
    } else {
      final cols = Responsive.columns(context, compact: 1, medium: 2, expanded: 2);
      corps = RefreshIndicator(
        onRefresh: _global ? () => _changerRayon(_filtreRayon) : _charger,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          _champScan(context),
          const SizedBox(height: 12),
          pills,
          const SizedBox(height: 12),
          if (_affiches.isEmpty)
            const SizedBox(height: 260, child: NvVide(icon: Icons.check_circle_outline, titre: 'Aucun écart trouvé !', detail: 'Tout semble correct pour ce filtre.'))
          else
            ...cardColumn([for (var i = 0; i < _affiches.length; i++) _carte(context, i)], cols, spacing: 10),
        ]),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _peutSortir() && mounted) nav.pop();
      },
      child: NvScaffold(
        title: large ? 'Écarts à contrôler' : (widget.rayon == null ? 'Écarts' : 'Écarts · ${widget.rayon!.libelle}'),
        subtitle: large
            ? '${_affiches.length} produit(s) · $aVerifier à vérifier · ${_tri == TriEcarts.valeur ? 'trié par valeur' : (_tri == TriEcarts.manquants ? 'manquants' : 'surplus')}'
            : widget.inventaire.libelle,
        wide: true,
        rounded: true,
        actions: [
          if (large) ActionEntete(icon: Icons.file_download_outlined, tooltip: 'Exporter (CSV)', onPressed: _affiches.isEmpty ? null : _csv),
          ActionEntete(icon: Icons.print_outlined, tooltip: 'Imprimer les écarts (PDF)', onPressed: _affiches.isEmpty || _impression ? null : _imprimer),
          if (!large) ActionEntete(icon: Icons.refresh, tooltip: 'Actualiser la liste', onPressed: _global ? () => _changerRayon(_filtreRayon) : _charger),
        ],
        header: large || _chargement || _erreur != null
            ? const []
            : [
                Row(children: [
                  Expanded(child: KpiTile(francs(b.manquants), 'Manquants (F)')),
                  const SizedBox(width: 8),
                  Expanded(child: KpiTile(francs(b.surplus, signeExplicite: true), 'Surplus (F)')),
                  const SizedBox(width: 8),
                  Expanded(child: KpiTile('$aVerifier / ${_affiches.length}', 'À vérifier', highlight: true)),
                ]),
              ],
        menuLateral: NvMenuLateral(
          actif: Destination.ecarts,
          inventaire: widget.inventaire,
          onChoisir: (d) async {
            if (d == Destination.ecarts) return;
            if (!await _peutSortir() || !context.mounted) return;
            final nav = Navigator.of(context);
            final ctxNav = nav.context;
            nav.pop();
            if (d != Destination.accueil && ctxNav.mounted) await NvAller.vers(ctxNav, d, widget.inventaire);
          },
        ),
        body: corps,
      ),
    );
  }
}
