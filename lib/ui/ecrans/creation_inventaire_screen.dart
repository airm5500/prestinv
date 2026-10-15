// lib/ui/ecrans/creation_inventaire_screen.dart
// Nouvelle interface — nouvel inventaire depuis le terminal : libellé + type, confirmation, création
// par le serveur ; renvoie l'inventaire créé (ou l'existant choisi en cas de doublon). Même logique
// que CreationInventaireScreen (CreationInventaire, LibelleInventaire, reconnexion si session expirée).
// 4.14.1 — Depuis la collecte ([codesCollectes]) : plus de choix du type ; l'EMPLACEMENT des produits
// collectés est recherché et présélectionné (le plus fréquent), modifiable (autre emplacement trouvé ou
// « Autre emplacement… » parmi tous ceux de l'officine) ; seul cet emplacement est envoyé au serveur
// (avant : aucun → TOUS les emplacements). Rien n'est créé tant qu'aucun emplacement n'est choisi.
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/emplacement_collecte.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

class NvCreationInventaireScreen extends StatefulWidget {
  final String libelleInitial;
  final CreationInventaire? service;

  /// Codes de la collecte (création « avec ces produits ») : l'inventaire est limité à UN emplacement,
  /// celui des produits collectés (présélectionné, modifiable). null : création classique.
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

  // --- Depuis la collecte (4.14.1) ---
  bool get _depuisCollecte => widget.codesCollectes != null;
  bool _rechercheEmplacements = false;
  AnalyseEmplacements? _analyse;
  Rayon? _emplacement;

  /// Tous les emplacements de l'officine (chargés au premier « Autre emplacement… »).
  List<Rayon>? _tous;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    _service = widget.service ?? CreationInventaire(ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie));
    if (_depuisCollecte) WidgetsBinding.instance.addPostFrameCallback((_) => _chercherEmplacements());
  }

  Future<void> _chercherEmplacements() async {
    if (!mounted) return;
    setState(() => _rechercheEmplacements = true);
    final a = await EmplacementsCollecte.analyser(_service.api, widget.codesCollectes ?? const []);
    if (!mounted) return;
    setState(() {
      _rechercheEmplacements = false;
      _analyse = a;
      _emplacement ??= a.propose;
    });
  }

  /// « Autre emplacement… » : liste de TOUS les emplacements de l'officine, avec recherche.
  Future<void> _autreEmplacement() async {
    if (_tous == null) {
      try {
        final l = await _service.api.fetchEmplacementsOfficine();
        if (!mounted) return;
        setState(() => _tous = l);
      } on ApiLoadException catch (e) {
        if (!mounted) return;
        if (e.sessionExpiree) {
          setState(() => _erreur = e.message);
          final ok = await demanderReconnexion(context);
          if (ok && mounted) setState(() => _erreur = null);
        } else {
          nvMessage(context, e.message, ton: context.nv.erreur);
        }
        return;
      }
    }
    if (!mounted) return;
    final choisi = await showModalBottomSheet<Rayon>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ChoixEmplacement(emplacements: _tous!, actuel: _emplacement),
    );
    if (choisi != null && mounted) setState(() => _emplacement = choisi);
  }

  static String _nom(Rayon r) => r.code.isEmpty || r.code == r.libelle ? r.libelle : '${r.libelle} (${r.code})';

  @override
  void dispose() {
    _libelle.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (_enCours) return;
    setState(() => _erreur = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final emplacement = _emplacement;
    if (_depuisCollecte && emplacement == null) {
      setState(() => _erreur = 'Choisissez l\'emplacement de l\'inventaire.');
      return;
    }
    final libelle = LibelleInventaire.normaliser(_libelle.text);
    final confirme = await nvDialogue<bool>(
      context,
      icone: Icons.add_circle_outline,
      ton: context.nv.info,
      titre: 'Créer l\'inventaire ?',
      message: emplacement != null
          ? '« $libelle »\nEmplacement : ${_nom(emplacement)}\n\n'
              'Le serveur y met les produits actifs de CET emplacement seulement, avec leur stock théorique ; '
              'la collecte y est ensuite versée.'
          : '« $libelle » (${_type.valeur})\n\n'
              'Le serveur y met TOUS les produits actifs de l\'officine, avec leur stock théorique, '
              'à compter ensuite. Cela peut prendre jusqu\'à une minute.',
      boutons: const [
        NvBouton('Annuler', false, genre: NvGenre.secondaire),
        NvBouton('Créer', true, genre: NvGenre.principal, key: ValueKey('confirmer-creation')),
      ],
    );
    if (confirme != true || !mounted) return;
    setState(() => _enCours = true);
    final r = emplacement != null
        ? await _service.creer(libelle, TypeInventaire.emplacement, valeurs: [emplacement.id])
        : await _service.creer(libelle, _type);
    if (!mounted) return;
    setState(() => _enCours = false);
    switch (r.issue) {
      case IssueCreation.creee:
        nvMessage(context, 'Inventaire « $libelle » créé${r.lignes != null ? ' : ${r.lignes} produit(s)' : ''}.', ton: context.nv.ok);
        // Identifiant inconnu (absent de la liste relue) : l'appelant le retrouve par son libellé.
        Navigator.of(context).pop(r.inventaire ?? Inventory(id: '', libelle: libelle));
      case IssueCreation.doublon:
        final ouvrir = await nvDialogue<bool>(
          context,
          icone: Icons.priority_high,
          titre: 'Libellé déjà utilisé',
          message: '${r.message}\nAucun inventaire n\'a été créé.',
          boutons: const [
            NvBouton('Changer le libellé', false, genre: NvGenre.secondaire),
            NvBouton('Utiliser celui-ci', true, genre: NvGenre.principal),
          ],
        );
        if (ouvrir == true && mounted) Navigator.of(context).pop(r.inventaire);
      case IssueCreation.session:
        setState(() => _erreur = r.message);
        final ok = await demanderReconnexion(context);
        if (ok && mounted) setState(() => _erreur = 'Reconnecté : touchez à nouveau « Créer ».');
      default:
        setState(() => _erreur = r.message);
    }
  }

  /// Création depuis la collecte : emplacement présélectionné (celui des produits collectés), modifiable.
  List<Widget> _sectionEmplacement(BuildContext context) {
    final nv = context.nv;
    final a = _analyse;
    final trouves = a?.trouves ?? const <EmplacementTrouve>[];
    final choisi = _emplacement;
    final horsListe = choisi != null && !trouves.any((t) => t.rayon.id == choisi.id);
    final ailleurs = choisi == null ? 0 : trouves.where((t) => t.rayon.id != choisi.id).fold<int>(0, (s, t) => s + t.codes);
    Widget carte(Rayon r, String detail) {
      final actif = choisi?.id == r.id;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SoftCard(
          key: ValueKey('emplacement-${r.id}'),
          onTap: _enCours ? null : () => setState(() => _emplacement = r),
          bordure: actif ? nv.action : null,
          semantique: '${_nom(r)} : $detail${actif ? ', choisi' : ''}',
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(actif ? Icons.radio_button_checked : Icons.radio_button_off, color: actif ? nv.action : nv.gris),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_nom(r), style: TextStyle(fontWeight: FontWeight.bold, color: nv.encre)),
                Text(detail, style: TextStyle(color: nv.gris, fontSize: 13.5)),
              ]),
            ),
          ]),
        ),
      );
    }

    return [
      const SectionTitre('Emplacement'),
      if (_rechercheEmplacements)
        SoftCard(
          key: const ValueKey('recherche-emplacements'),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(child: Text('Recherche de l\'emplacement des produits collectés…', style: TextStyle(color: nv.encre))),
          ]),
        )
      else ...[
        for (final t in trouves) carte(t.rayon, '${t.codes} produit(s) de la collecte'),
        if (horsListe) carte(choisi, 'Choisi dans la liste des emplacements'),
        if (a != null && a.erreur != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Bandeau(
              key: const ValueKey('emplacements-erreur'),
              ton: nv.attente,
              icon: Icons.cloud_off,
              texte: 'Emplacement des produits non retrouvé',
              detail: '${a.erreur!.message}\nChoisissez l\'emplacement avec « Autre emplacement… », ou réessayez.',
              action: 'Réessayer',
              actionKey: const ValueKey('emplacements-reessayer'),
              onAction: _chercherEmplacements,
            ),
          )
        else if (a != null && trouves.isEmpty && !horsListe)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Aucun produit de la collecte n\'a été retrouvé sur le serveur : choisissez l\'emplacement.',
                key: const ValueKey('emplacements-aucun'), style: TextStyle(color: nv.gris)),
          ),
        OutlinedButton.icon(
          key: const ValueKey('autre-emplacement'),
          onPressed: _enCours ? null : _autreEmplacement,
          icon: const Icon(Icons.list_alt),
          label: const Text('Autre emplacement…'),
        ),
      ],
      const SizedBox(height: 12),
      Bandeau(
        ton: nv.info,
        icon: Icons.info_outline,
        texte: choisi == null ? 'Un seul emplacement' : 'Seulement « ${_nom(choisi)} »',
        detail: 'Le serveur y met les produits actifs de cet emplacement (stock théorique repris, rien de compté), '
            'puis la collecte y est versée.'
            '${ailleurs > 0 ? ' $ailleurs produit(s) de la collecte rangé(s) ailleurs seront signalés « non reconnus » au versement.' : ''}',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
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
                      enabled: !_enCours,
                      maxLength: LibelleInventaire.max,
                      textCapitalization: TextCapitalization.sentences,
                      validator: LibelleInventaire.erreur,
                      decoration: const InputDecoration(labelText: 'Libellé de l\'inventaire', hintText: 'ex. Inventaire réserve octobre', errorMaxLines: 3),
                    ),
                  ),
                  if (_depuisCollecte) ..._sectionEmplacement(context) else ...[
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
                    onPressed: _enCours || (_depuisCollecte && _emplacement == null) ? null : _creer,
                    icon: _enCours ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
                    label: Text(_enCours ? 'Création en cours…' : 'Créer l\'inventaire'),
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


/// Liste de tous les emplacements de l'officine, avec recherche (code ou libellé).
class _ChoixEmplacement extends StatefulWidget {
  final List<Rayon> emplacements;
  final Rayon? actuel;
  const _ChoixEmplacement({required this.emplacements, this.actuel});

  @override
  State<_ChoixEmplacement> createState() => _ChoixEmplacementState();
}

class _ChoixEmplacementState extends State<_ChoixEmplacement> {
  String _filtre = '';

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final f = _filtre.trim().toLowerCase();
    final liste = widget.emplacements.where((r) => f.isEmpty || r.libelle.toLowerCase().contains(f) || r.code.toLowerCase().contains(f)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Choisir l\'emplacement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: nv.encre)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('recherche-emplacement'),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher (libellé ou code)'),
                onChanged: (v) => setState(() => _filtre = v),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: liste.isEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Text('Aucun emplacement.', textAlign: TextAlign.center, style: TextStyle(color: nv.gris)))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: liste.length,
                      itemBuilder: (_, i) {
                        final r = liste[i];
                        final actif = widget.actuel?.id == r.id;
                        return ListTile(
                          key: ValueKey('choix-emplacement-${r.id}'),
                          minTileHeight: 48,
                          leading: Icon(actif ? Icons.radio_button_checked : Icons.radio_button_off, color: actif ? nv.action : nv.gris),
                          title: Text(r.libelle.isEmpty ? r.code : r.libelle),
                          subtitle: r.code.isEmpty || r.code == r.libelle ? null : Text(r.code),
                          onTap: () => Navigator.pop(context, r),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
