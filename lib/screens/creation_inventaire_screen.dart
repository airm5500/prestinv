// lib/screens/creation_inventaire_screen.dart
// Nouvel inventaire depuis le terminal : libellé + type, confirmation, création par le serveur.
// Renvoie (Navigator.pop) l'inventaire créé — ou l'inventaire existant choisi en cas de doublon.
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

class CreationInventaireScreen extends StatefulWidget {
  /// Libellé proposé (ex. « Collecte du 13/10/2026 »).
  final String libelleInitial;

  /// Tests : service de création (sinon celui de l'application).
  final CreationInventaire? service;

  const CreationInventaireScreen({super.key, this.libelleInitial = '', this.service});

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
    if (_enCours) return; // double appui
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
          ElevatedButton(key: const ValueKey('confirmer-creation'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Créer')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green,
            content: Text('Inventaire « $libelle » créé${r.lignes != null ? ' : ${r.lignes} produit(s)' : ''}.')));
        Navigator.of(context).pop(r.inventaire ?? Inventory(id: '', libelle: libelle));
      case IssueCreation.doublon:
        final ouvrir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Libellé déjà utilisé'),
            content: Text('${r.message}\nAucun inventaire n\'a été créé.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Changer le libellé')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Utiliser celui-ci')),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel inventaire')),
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
                    enabled: !_enCours,
                    maxLength: LibelleInventaire.max,
                    textCapitalization: TextCapitalization.sentences,
                    validator: LibelleInventaire.erreur,
                    decoration: const InputDecoration(
                      labelText: 'Libellé de l\'inventaire',
                      hintText: 'ex. Inventaire réserve octobre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Text(
                      'Le serveur crée l\'inventaire avec tous les produits actifs de l\'officine (stock théorique repris, '
                      'rien de compté). Le type ne change que le classement dans Prestige. L\'inventaire apparaît ensuite '
                      'dans la liste et s\'ouvre comme les autres.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(_erreur!, key: const ValueKey('erreur-creation'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    key: const ValueKey('bouton-creer'),
                    onPressed: _enCours ? null : _creer,
                    icon: _enCours
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add),
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
