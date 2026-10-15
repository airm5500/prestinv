// lib/screens/creation_inventaire_screen.dart
// Nouvel inventaire depuis le terminal : libellé + type, confirmation, création par le serveur.
// Renvoie (Navigator.pop) l'inventaire créé — ou l'inventaire existant choisi en cas de doublon.
// 4.15 — Depuis la collecte ([codesCollectes], écran « Verser la collecte » › « Nouvel inventaire… ») :
// plus de choix du type ; récapitulatif « N produits, M emplacements » puis inventaire de CES produits
// seulement, sur leurs emplacements (avant : tous les produits de tous les emplacements). Même logique
// que la nouvelle interface (PreparationCollecte, CreationInventaire.creerDepuisCollecte).
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/preparation_collecte.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

class CreationInventaireScreen extends StatefulWidget {
  /// Libellé proposé (ex. « Collecte du 13/10/2026 »).
  final String libelleInitial;

  /// Tests : service de création (sinon celui de l'application).
  final CreationInventaire? service;

  /// Codes de la collecte : l'inventaire ne contient que ces produits. null : création classique.
  final List<String>? codesCollectes;

  const CreationInventaireScreen({super.key, this.libelleInitial = '', this.service, this.codesCollectes});

  @override
  State<CreationInventaireScreen> createState() => _CreationInventaireScreenState();
}

class _CreationInventaireScreenState extends State<CreationInventaireScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _libelle = TextEditingController(text: widget.libelleInitial);
  TypeInventaire _type = TypeInventaire.emplacement;
  late final CreationInventaire _service;
  bool _enCours = false;
  String? _erreur;
  PreparationCollecte? _prep;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    _service = widget.service ?? CreationInventaire(ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie));
    if (widget.codesCollectes != null) {
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

  String _portee() => _prep?.limiteAuxProduits == false
      ? 'Ce serveur Prestige ne sait pas limiter un inventaire à une liste de produits : l\'inventaire contiendra TOUS '
          'les produits actifs de ces emplacements (et seulement eux). La collecte y est ensuite versée.'
      : 'Comme dans Prestige : l\'inventaire ne contient QUE ces produits ; à l\'ouverture, seuls leurs emplacements '
          'sont proposés. La collecte y est ensuite versée.';

  Future<void> _creer() async {
    if (_enCours) return; // double appui
    setState(() => _erreur = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final prep = _prep;
    final a = prep?.analyse;
    if (prep != null && (a == null || !prep.creationPossible)) {
      setState(() => _erreur = 'Aucun produit de la collecte à mettre dans l\'inventaire.');
      return;
    }
    final libelle = LibelleInventaire.normaliser(_libelle.text);
    if (prep?.sansProduits == null) {
      final confirme = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Créer l\'inventaire ?'),
          content: Text(a != null
              ? '« $libelle »\n${_pluriel(a.inclus.length, 'produit')}, ${_pluriel(a.emplacements.length, 'emplacement')}\n\n${_portee()}'
              : '« $libelle » (${_type.valeur})\n\n'
                  'Le serveur y met TOUS les produits actifs de l\'officine, avec leur stock théorique, '
                  'à compter ensuite. Cela peut prendre jusqu\'à une minute.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(key: const ValueKey('confirmer-creation'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Créer')),
          ],
        ),
      );
      if (confirme != true || !mounted) return;
    }
    setState(() => _enCours = true);
    final r = prep != null ? await prep.creer(libelle) : await _service.creer(libelle, _type);
    if (!mounted) return;
    setState(() => _enCours = false);
    await _issue(r, libelle);
  }

  Future<void> _issue(ResultatCreation r, String libelle) async {
    switch (r.issue) {
      case IssueCreation.creee:
        final detail = r.retenus != null ? ' : ${_pluriel(r.retenus!, 'produit')}' : (r.lignes != null ? ' : ${r.lignes} produit(s)' : '');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green, content: Text('Inventaire « ${r.inventaire?.libelle ?? libelle} » créé$detail.')));
        Navigator.of(context).pop(r.inventaire ?? Inventory(id: '', libelle: libelle));
      case IssueCreation.doublon:
        final ouvrir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Libellé déjà utilisé'),
            content: Text('${r.message}\nAucun inventaire n\'a été créé.'
                '${_prep != null ? '\n« Utiliser celui-ci » y ajoute les produits collectés.' : ''}'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Changer le libellé')),
              ElevatedButton(key: const ValueKey('utiliser-existant'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Utiliser celui-ci')),
            ],
          ),
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

  Widget _encadre(Widget enfant, {Color? couleur, Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(color: couleur ?? Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
        child: enfant,
      );

  List<Widget> _sectionCollecte() {
    final prep = _prep!;
    final a = prep.analyse;
    if (prep.analyseEnCours || a == null) {
      return [
        _encadre(
            const Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Expanded(child: Text('Recherche des produits collectés sur le serveur…')),
            ]),
            key: const ValueKey('recherche-produits')),
      ];
    }
    if (a.erreur != null) {
      return [
        _encadre(
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Produits de la collecte non retrouvés', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${a.erreur!.message}\nRien n\'est créé tant que les produits ne sont pas retrouvés.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  key: const ValueKey('collecte-reessayer'), onPressed: _enCours ? null : _analyser, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
            ]),
            couleur: Colors.orange.shade50,
            key: const ValueKey('collecte-erreur')),
      ];
    }
    final emplacements = a.emplacements;
    final nonInclus = [...a.introuvables.map(CodeScan.affichage), ...a.sansEmplacement.map((p) => p.cip.isEmpty ? p.nom : p.cip)];
    return [
      _encadre(
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${_pluriel(a.inclus.length, 'produit')}, ${_pluriel(emplacements.length, 'emplacement')}',
                key: const ValueKey('recap-collecte-titre'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            for (final e in emplacements)
              Padding(
                key: ValueKey('recap-emplacement-${e.rayon.id}'),
                padding: const EdgeInsets.only(top: 4),
                child: Text('• ${e.rayon.libelle.isEmpty ? e.rayon.id : e.rayon.libelle} : ${_pluriel(e.produits, 'produit')}'),
              ),
          ]),
          couleur: Colors.grey.shade100,
          key: const ValueKey('recap-collecte')),
      if (nonInclus.isNotEmpty)
        _encadre(
            Text('${_pluriel(nonInclus.length, 'code')} hors de l\'inventaire (non retrouvés sur le serveur ou sans emplacement, '
                'signalés au versement) : ${nonInclus.take(5).join(', ')}${nonInclus.length > 5 ? '…' : ''}'),
            couleur: Colors.orange.shade50,
            key: const ValueKey('recap-non-retrouves')),
      if (!a.creationPossible)
        _encadre(const Text('Aucun produit de la collecte n\'a été retrouvé sur le serveur : rien à créer.'),
            couleur: Colors.orange.shade50, key: const ValueKey('collecte-aucun'))
      else
        _encadre(Text(_portee(), style: const TextStyle(fontSize: 13)),
            couleur: prep.limiteAuxProduits == false ? Colors.orange.shade50 : null, key: const ValueKey('recap-portee')),
      if (prep.sansProduits != null)
        _encadre(Text('Inventaire « ${prep.sansProduits!.libelle} » créé sans ses produits : touchez « Ajouter les produits » (rien n\'est recréé).'),
            couleur: Colors.red.shade50, key: const ValueKey('produits-a-ajouter')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final prep = _prep;
    final bloque = _enCours || (prep != null && !prep.creationPossible);
    return Scaffold(
      appBar: AppBar(title: Text(prep != null ? 'Nouvel inventaire (collecte)' : 'Nouvel inventaire')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    key: const ValueKey('libelle-inventaire'),
                    controller: _libelle,
                    enabled: !_enCours && prep?.sansProduits == null,
                    maxLength: LibelleInventaire.max,
                    textCapitalization: TextCapitalization.sentences,
                    validator: LibelleInventaire.erreur,
                    decoration: const InputDecoration(
                      labelText: 'Libellé de l\'inventaire',
                      hintText: 'ex. Inventaire réserve octobre',
                      errorMaxLines: 3,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (prep != null) ...[
                    const Text('Contenu de l\'inventaire', style: TextStyle(fontWeight: FontWeight.bold)),
                    ..._sectionCollecte(),
                  ] else ...[
                    const Text('Type', style: TextStyle(fontWeight: FontWeight.bold)),
                    for (final t in TypeInventaire.values)
                      RadioListTile<TypeInventaire>(
                        key: ValueKey('type-${t.name}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: t,
                        groupValue: _type,
                        title: Text(t.valeur),
                        subtitle: Text(t.libelle),
                        onChanged: _enCours ? null : (v) => setState(() => _type = v!),
                      ),
                    _encadre(const Text(
                      'Le serveur crée l\'inventaire avec tous les produits actifs de l\'officine (stock théorique repris, '
                      'rien de compté). Le type ne change que le classement dans Prestige. L\'inventaire apparaît ensuite '
                      'dans la liste et s\'ouvre comme les autres.',
                      style: TextStyle(fontSize: 13),
                    )),
                  ],
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(_erreur!, key: const ValueKey('erreur-creation'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    key: const ValueKey('bouton-creer'),
                    onPressed: bloque ? null : _creer,
                    icon: _enCours
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add),
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
