// lib/ui/ecrans/creation_inventaire_screen.dart
// Nouvelle interface — nouvel inventaire depuis le terminal : libellé + type, confirmation, création
// par le serveur ; renvoie l'inventaire créé (ou l'existant choisi en cas de doublon). Même logique
// que CreationInventaireScreen (CreationInventaire, LibelleInventaire, reconnexion si session expirée).
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

class NvCreationInventaireScreen extends StatefulWidget {
  final String libelleInitial;
  final CreationInventaire? service;
  const NvCreationInventaireScreen({super.key, this.libelleInitial = '', this.service});

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

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    _service = widget.service ?? CreationInventaire(ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie));
  }

  @override
  void dispose() {
    _libelle.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (_enCours) return;
    setState(() => _erreur = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final libelle = LibelleInventaire.normaliser(_libelle.text);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créer l\'inventaire ?'),
        content: Text('« $libelle » (${_type.valeur})\n\n'
            'Le serveur y met TOUS les produits actifs de l\'officine, avec leur stock théorique, '
            'à compter ensuite. Cela peut prendre jusqu\'à une minute.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(key: const ValueKey('confirmer-creation'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Créer')),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _enCours = true);
    final r = await _service.creer(libelle, _type);
    if (!mounted) return;
    setState(() => _enCours = false);
    switch (r.issue) {
      case IssueCreation.creee:
        nvMessage(context, 'Inventaire « $libelle » créé${r.lignes != null ? ' : ${r.lignes} produit(s)' : ''}.', ton: context.nv.ok);
        Navigator.of(context).pop(r.inventaire ?? Inventory(id: '', libelle: libelle));
      case IssueCreation.doublon:
        final ouvrir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Libellé déjà utilisé'),
            content: Text('${r.message}\nAucun inventaire n\'a été créé.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Changer le libellé')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Utiliser celui-ci')),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return NvScaffold(
      title: 'Nouvel inventaire',
      subtitle: 'Créé sur le serveur Prestige',
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
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(_erreur!, key: const ValueKey('erreur-creation'), style: TextStyle(color: nv.erreur.fg, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('bouton-creer'),
                    onPressed: _enCours ? null : _creer,
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
