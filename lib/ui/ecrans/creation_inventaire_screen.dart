// lib/ui/ecrans/creation_inventaire_screen.dart
// Nouvelle interface — nouvel inventaire depuis le terminal : libellé + type, confirmation, création
// par le serveur ; renvoie l'inventaire créé (ou l'existant choisi en cas de doublon). Même logique
// que CreationInventaireScreen (CreationInventaire, LibelleInventaire, reconnexion si session expirée).
// 4.15 — Depuis la collecte ([codesCollectes]) : plus de choix du type ni de l'emplacement. Les produits
// collectés sont retrouvés sur le serveur, un récapitulatif « N produits, M emplacements » (et les codes
// non retrouvés) est affiché, puis l'inventaire est créé avec CES produits seulement, sur leurs
// emplacements (comme Prestige : voir CreationInventaire.creerDepuisCollecte).
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/preparation_collecte.dart';
import 'package:prestinv/inventaire/produits_collecte.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

class NvCreationInventaireScreen extends StatefulWidget {
  final String libelleInitial;
  final CreationInventaire? service;

  /// Codes de la collecte (création « avec ces produits ») : l'inventaire ne contient que ces produits,
  /// sur leurs emplacements. null : création classique.
  final List<String>? codesCollectes;
  const NvCreationInventaireScreen({super.key, this.libelleInitial = '', this.service, this.codesCollectes});

  @override
  State<NvCreationInventaireScreen> createState() => _NvCreationInventaireScreenState();
}

class _NvCreationInventaireScreenState extends State<NvCreationInventaireScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _libelle = TextEditingController(text: widget.libelleInitial);
  TypeInventaire _type = TypeInventaire.emplacement;
  late final CreationInventaire _service;
  bool _enCours = false;
  String? _erreur;

  // --- Depuis la collecte (4.15) ---
  bool get _depuisCollecte => widget.codesCollectes != null;
  PreparationCollecte? _prep;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    _service = widget.service ?? CreationInventaire(ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie));
    if (_depuisCollecte) {
      _prep = PreparationCollecte(_service, widget.codesCollectes!)..addListener(_rafraichir);
      WidgetsBinding.instance.addPostFrameCallback((_) => _analyser());
    }
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  Future<void> _analyser() async {
    if (!mounted) return;
    await _prep!.analyser();
    final e = _prep!.analyse?.erreur;
    if (e != null && e.sessionExpiree && mounted) {
      final ok = await demanderReconnexion(context);
      if (ok && mounted) await _prep!.analyser();
    }
  }

  @override
  void dispose() {
    _prep?.removeListener(_rafraichir);
    _prep?.dispose();
    _libelle.dispose();
    super.dispose();
  }

  static String _pluriel(int n, String mot) => '$n $mot${n > 1 ? 's' : ''}';

  Future<void> _creer() async {
    if (_enCours) return;
    setState(() => _erreur = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final prep = _prep;
    final a = prep?.analyse;
    if (_depuisCollecte && (a == null || !prep!.creationPossible)) {
      setState(() => _erreur = 'Aucun produit de la collecte à mettre dans l\'inventaire.');
      return;
    }
    final libelle = LibelleInventaire.normaliser(_libelle.text);
    final reprise = prep?.sansProduits != null;
    if (!reprise) {
      final confirme = await nvDialogue<bool>(
        context,
        icone: Icons.add_circle_outline,
        ton: context.nv.info,
        titre: 'Créer l\'inventaire ?',
        message: a != null
            ? '« $libelle »\n${_pluriel(a.inclus.length, 'produit')} collecté${a.inclus.length > 1 ? 's' : ''}, '
                '${_pluriel(a.emplacements.length, 'emplacement')}\n\n${_portee(prep!)}'
            : '« $libelle » (${_type.valeur})\n\n'
                'Le serveur y met TOUS les produits actifs de l\'officine, avec leur stock théorique, '
                'à compter ensuite. Cela peut prendre jusqu\'à une minute.',
        boutons: const [
          NvBouton('Annuler', false, genre: NvGenre.secondaire),
          NvBouton('Créer', true, genre: NvGenre.principal, key: ValueKey('confirmer-creation')),
        ],
      );
      if (confirme != true || !mounted) return;
    }
    setState(() => _enCours = true);
    final r = prep != null ? await prep.creer(libelle) : await _service.creer(libelle, _type);
    if (!mounted) return;
    setState(() => _enCours = false);
    await _issue(r, libelle);
  }

  /// Ce que contiendra l'inventaire créé depuis la collecte.
  static String _portee(PreparationCollecte prep) => prep.limiteAuxProduits == false
      ? 'Ce serveur Prestige ne sait pas limiter un inventaire à une liste de produits : l\'inventaire contiendra '
          'TOUS les produits actifs de ces emplacements (et seulement eux). La collecte y est ensuite versée.'
      : 'Comme dans Prestige : l\'inventaire ne contient QUE ces produits, et à l\'ouverture seuls leurs emplacements '
          'sont proposés. La collecte y est ensuite versée.';

  Future<void> _issue(ResultatCreation r, String libelle) async {
    switch (r.issue) {
      case IssueCreation.creee:
        final detail = r.retenus != null
            ? ' : ${_pluriel(r.retenus!, 'produit')}'
            : (r.lignes != null ? ' : ${r.lignes} produit(s)' : '');
        nvMessage(context, 'Inventaire « ${r.inventaire?.libelle ?? libelle} » créé$detail.', ton: context.nv.ok);
        // Identifiant inconnu (absent de la liste relue) : l'appelant le retrouve par son libellé.
        Navigator.of(context).pop(r.inventaire ?? Inventory(id: '', libelle: libelle));
      case IssueCreation.doublon:
        final ouvrir = await nvDialogue<bool>(
          context,
          icone: Icons.priority_high,
          titre: 'Libellé déjà utilisé',
          message: '${r.message}\nAucun inventaire n\'a été créé.'
              '${_prep != null ? '\n« Utiliser celui-ci » y ajoute les produits collectés.' : ''}',
          boutons: const [
            NvBouton('Changer le libellé', false, genre: NvGenre.secondaire),
            NvBouton('Utiliser celui-ci', true, genre: NvGenre.principal, key: ValueKey('utiliser-existant')),
          ],
        );
        if (ouvrir != true || !mounted) return;
        final prep = _prep;
        if (prep == null || r.inventaire == null) {
          Navigator.of(context).pop(r.inventaire);
          return;
        }
        setState(() => _enCours = true);
        final r2 = await prep.utiliser(r.inventaire!);
        if (!mounted) return;
        setState(() => _enCours = false);
        await _issue(r2, libelle);
      case IssueCreation.session:
        setState(() => _erreur = r.message);
        final ok = await demanderReconnexion(context);
        if (ok && mounted) setState(() => _erreur = 'Reconnecté : touchez à nouveau « ${_libelleBouton()} ».');
      default:
        setState(() => _erreur = r.message);
    }
  }

  String _libelleBouton() => _prep?.sansProduits != null ? 'Ajouter les produits' : 'Créer l\'inventaire';

  /// Création depuis la collecte : récapitulatif des produits retrouvés et de leurs emplacements.
  List<Widget> _sectionCollecte(BuildContext context) {
    final nv = context.nv;
    final prep = _prep!;
    final a = prep.analyse;
    if (prep.analyseEnCours || a == null) {
      return [
        const SectionTitre('Contenu de l\'inventaire'),
        SoftCard(
          key: const ValueKey('recherche-produits'),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(child: Text('Recherche des produits collectés sur le serveur…', style: TextStyle(color: nv.encre))),
          ]),
        ),
      ];
    }
    if (a.erreur != null) {
      return [
        const SectionTitre('Contenu de l\'inventaire'),
        Bandeau(
          key: const ValueKey('collecte-erreur'),
          ton: nv.attente,
          icon: Icons.cloud_off,
          texte: 'Produits de la collecte non retrouvés',
          detail: '${a.erreur!.message}\nRien n\'est créé tant que les produits ne sont pas retrouvés.',
          action: 'Réessayer',
          actionKey: const ValueKey('collecte-reessayer'),
          onAction: _enCours ? null : _analyser,
        ),
      ];
    }
    final emplacements = a.emplacements;
    final nonInclus = [...a.introuvables.map(CodeScan.affichage), ...a.sansEmplacement.map((p) => p.cip.isEmpty ? p.nom : p.cip)];
    return [
      const SectionTitre('Contenu de l\'inventaire'),
      SoftCard(
        key: const ValueKey('recap-collecte'),
        semantique: '${_pluriel(a.inclus.length, 'produit')}, ${_pluriel(emplacements.length, 'emplacement')}',
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_pluriel(a.inclus.length, 'produit')}, ${_pluriel(emplacements.length, 'emplacement')}',
              key: const ValueKey('recap-collecte-titre'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: nv.encre)),
          const SizedBox(height: 6),
          for (final e in emplacements)
            Padding(
              key: ValueKey('recap-emplacement-${e.rayon.id}'),
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(Icons.place_outlined, size: 18, color: nv.gris),
                const SizedBox(width: 8),
                Expanded(child: Text(e.rayon.libelle.isEmpty ? e.rayon.id : e.rayon.libelle, style: TextStyle(color: nv.encre))),
                Text(_pluriel(e.produits, 'produit'), style: TextStyle(color: nv.gris, fontSize: 13.5)),
              ]),
            ),
        ]),
      ),
      if (nonInclus.isNotEmpty) ...[
        const SizedBox(height: 8),
        Bandeau(
          key: const ValueKey('recap-non-retrouves'),
          ton: nv.attente,
          icon: Icons.help_outline,
          texte: '${_pluriel(nonInclus.length, 'code')} hors de l\'inventaire',
          detail: '${nonInclus.take(5).join(', ')}${nonInclus.length > 5 ? '…' : ''}\n'
              'Non retrouvé${nonInclus.length > 1 ? 's' : ''} sur le serveur (ou sans emplacement) : '
              'signalé${nonInclus.length > 1 ? 's' : ''} « non reconnu${nonInclus.length > 1 ? 's' : ''} » au versement.',
        ),
      ],
      if (a.nonAnalyses > 0) ...[
        const SizedBox(height: 8),
        Bandeau(
          ton: nv.attente,
          icon: Icons.warning_amber,
          texte: '${a.nonAnalyses} code(s) au-delà de ${ProduitsCollecte.maxCodes}',
          detail: 'Ils ne sont pas dans cet inventaire : versez-les ensuite dans un inventaire existant.',
        ),
      ],
      if (!a.creationPossible) ...[
        const SizedBox(height: 8),
        Text('Aucun produit de la collecte n\'a été retrouvé sur le serveur : rien à créer.',
            key: const ValueKey('collecte-aucun'), style: TextStyle(color: nv.gris)),
      ] else ...[
        const SizedBox(height: 12),
        Bandeau(
          key: const ValueKey('recap-portee'),
          ton: prep.limiteAuxProduits == false ? nv.attente : nv.info,
          icon: Icons.info_outline,
          texte: prep.limiteAuxProduits == false ? 'Tous les produits de ces emplacements' : 'Seulement ces produits',
          detail: _portee(prep),
        ),
      ],
      if (prep.sansProduits != null) ...[
        const SizedBox(height: 8),
        Bandeau(
          key: const ValueKey('produits-a-ajouter'),
          ton: nv.erreur,
          icon: Icons.sync_problem,
          texte: 'Inventaire « ${prep.sansProduits!.libelle} » créé sans ses produits',
          detail: 'Touchez « Ajouter les produits » : rien n\'est recréé.',
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final prep = _prep;
    final bloque = _enCours || (prep != null && !prep.creationPossible);
    return NvScaffold(
      title: 'Nouvel inventaire',
      subtitle: _depuisCollecte ? 'Depuis la collecte' : 'Créé sur le serveur Prestige',
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SoftCard(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      key: const ValueKey('libelle-inventaire'),
                      controller: _libelle,
                      enabled: !_enCours && prep?.sansProduits == null,
                      maxLength: LibelleInventaire.max,
                      textCapitalization: TextCapitalization.sentences,
                      validator: LibelleInventaire.erreur,
                      decoration: const InputDecoration(labelText: 'Libellé de l\'inventaire', hintText: 'ex. Inventaire réserve octobre', errorMaxLines: 3),
                    ),
                  ),
                  if (_depuisCollecte) ..._sectionCollecte(context) else ...[
                    const SectionTitre('Type'),
                    for (final t in TypeInventaire.values) ...[
                      SoftCard(
                        key: ValueKey('type-${t.name}'),
                        onTap: _enCours ? null : () => setState(() => _type = t),
                        bordure: _type == t ? nv.action : null,
                        semantique: '${t.valeur} : ${t.libelle}${_type == t ? ', choisi' : ''}',
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Icon(_type == t ? Icons.radio_button_checked : Icons.radio_button_off, color: _type == t ? nv.action : nv.gris),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t.valeur, style: TextStyle(fontWeight: FontWeight.bold, color: nv.encre)),
                              Text(t.libelle, style: TextStyle(color: nv.gris, fontSize: 13.5)),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Bandeau(
                      ton: nv.info,
                      icon: Icons.info_outline,
                      texte: 'Tous les produits actifs de l\'officine',
                      detail: 'Stock théorique repris, rien de compté. Le type ne change que le classement dans Prestige. '
                          'L\'inventaire apparaît ensuite dans la liste et s\'ouvre comme les autres.',
                    ),
                  ],
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(_erreur!, key: const ValueKey('erreur-creation'), style: TextStyle(color: nv.erreur.fg, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('bouton-creer'),
                    onPressed: bloque ? null : _creer,
                    icon: _enCours ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
                    label: Text(_enCours ? 'Création en cours…' : _libelleBouton()),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
