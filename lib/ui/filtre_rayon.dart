// lib/ui/filtre_rayon.dart
// Nouvelle interface — FILTRE DU RAYON (saisie guidée, maquette « Filtre », 4.13) :
//  - par numéro : « De » ET « À » obligatoires (une valeur sans l'autre est refusée), chiffres
//    seulement, De ≤ À, bornés de 1 au nombre de produits ; « 1 à total » = aucun filtre ;
//  - par ordre alphabétique : même règle de paire (De ET À), De ≤ À ;
//  - raccourci « Seulement les produits pas encore comptés (oublis) » : vrai filtre distinct du filtre
//    par numéro (les champs De / À ne montrent plus « Rattrapage / Oublis ») ;
//  - « Effacer le filtre » dans la fenêtre ; « Annuler » remet le filtre tel qu'il était (une valeur
//    tapée par erreur n'est jamais gardée : les champs sont repris du filtre APPLIQUÉ à chaque ouverture).
// Les champs ne sont pré-remplis qu'avec des valeurs du même type (numéros pour « par numéro »).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/models/product_filter.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/theme.dart';

/// Résultat d'un contrôle de filtre : le filtre à appliquer (aucun filtre = ProductFilter()) ou l'erreur.
class ControleFiltre {
  final ProductFilter? filtre;
  final String? erreur;
  const ControleFiltre.ok(ProductFilter this.filtre) : erreur = null;
  const ControleFiltre.erreur(String this.erreur) : filtre = null;
  bool get ok => filtre != null;
}

final _chiffres = RegExp(r'^\d+$');

/// Message de la règle « par numéro ».
String regleNumero(int total) => 'Renseignez « De » ET « À » (chiffres de 1 à $total, « De » ≤ « À »).';

/// Contrôle du filtre par numéro ([total] produits dans le rayon).
ControleFiltre controlerFiltreNumero(String de, String a, int total) {
  final d = de.trim(), f = a.trim();
  if (d.isEmpty || f.isEmpty) return ControleFiltre.erreur(regleNumero(total));
  if (!_chiffres.hasMatch(d) || !_chiffres.hasMatch(f)) return ControleFiltre.erreur('Chiffres seulement. ${regleNumero(total)}');
  final n1 = int.parse(d), n2 = int.parse(f);
  if (n1 < 1 || n2 < 1 || n1 > total || n2 > total) return ControleFiltre.erreur('Numéros de 1 à $total seulement. ${regleNumero(total)}');
  if (n1 > n2) return ControleFiltre.erreur('« De » doit être inférieur ou égal à « À ». ${regleNumero(total)}');
  if (n1 == 1 && n2 == total) return ControleFiltre.ok(ProductFilter()); // tout le rayon = aucun filtre
  return ControleFiltre.ok(ProductFilter(type: FilterType.numeric, from: '$n1', to: '$n2'));
}

/// Contrôle du filtre alphabétique (lettres / chiffres, De ET À, De ≤ À).
ControleFiltre controlerFiltreAlpha(String de, String a) {
  final d = de.trim().toUpperCase(), f = a.trim().toUpperCase();
  const regle = 'Renseignez « De » ET « À » (lettres, « De » avant « À »).';
  if (d.isEmpty || f.isEmpty) return const ControleFiltre.erreur(regle);
  if (d.compareTo(f) > 0) return const ControleFiltre.erreur('« De » doit venir avant « À » dans l\'alphabet. $regle');
  return ControleFiltre.ok(ProductFilter(type: FilterType.alphabetic, from: d, to: f));
}

/// Valeurs de départ des champs : seulement celles du filtre appliqué, du même type.
({String deNum, String aNum, String deAlpha, String aAlpha, FilterType type}) champsDepuis(ProductFilter f) {
  final numeroValide = f.type == FilterType.numeric && !f.estOublis && _chiffres.hasMatch(f.from) && _chiffres.hasMatch(f.to);
  final alpha = f.type == FilterType.alphabetic;
  return (
    deNum: numeroValide ? f.from : '',
    aNum: numeroValide ? f.to : '',
    deAlpha: alpha ? f.from : '',
    aAlpha: alpha ? f.to : '',
    type: alpha ? FilterType.alphabetic : FilterType.numeric,
  );
}

/// Libellé de la ligne réservée sous le champ de saisie (« Filtre : n° 10 à 40 · 31 produits »).
String? libelleFiltreActif(ProductFilter f, int produits) {
  if (!f.isActive) return null;
  final n = '$produits produit${produits > 1 ? 's' : ''}';
  if (f.estOublis) return 'Filtre : oublis (pas encore comptés) · $n';
  if (f.type == FilterType.numeric) return 'Filtre : n° ${f.from} à ${f.to} · $n';
  if (f.type == FilterType.alphabetic) return 'Filtre : ${f.from} à ${f.to} · $n';
  return null;
}

/// Choix fait dans la fenêtre.
sealed class ChoixFiltre {
  const ChoixFiltre();
}

class AppliquerFiltre extends ChoixFiltre {
  final ProductFilter filtre;
  const AppliquerFiltre(this.filtre);
}

class EffacerFiltre extends ChoixFiltre {
  const EffacerFiltre();
}

class FiltrerOublis extends ChoixFiltre {
  const FiltrerOublis();
}

/// Ouvre la fenêtre « Filtrer le rayon ». null : Annuler (rien ne change).
Future<ChoixFiltre?> ouvrirFiltreRayon(BuildContext context, {required ProductFilter actuel, required int total, required String rayon, int oublis = 0}) =>
    showDialog<ChoixFiltre>(
      context: context,
      builder: (_) => FenetreFiltre(actuel: actuel, total: total, rayon: rayon, oublis: oublis),
    );

class FenetreFiltre extends StatefulWidget {
  final ProductFilter actuel;
  final int total;
  final String rayon;
  final int oublis;
  const FenetreFiltre({super.key, required this.actuel, required this.total, required this.rayon, this.oublis = 0});

  @override
  State<FenetreFiltre> createState() => _FenetreFiltreState();
}

class _FenetreFiltreState extends State<FenetreFiltre> {
  late final TextEditingController _deNum, _aNum, _deAlpha, _aAlpha;
  late FilterType _type;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final c = champsDepuis(widget.actuel);
    _deNum = TextEditingController(text: c.deNum);
    _aNum = TextEditingController(text: c.aNum);
    _deAlpha = TextEditingController(text: c.deAlpha);
    _aAlpha = TextEditingController(text: c.aAlpha);
    _type = c.type;
  }

  @override
  void dispose() {
    for (final c in [_deNum, _aNum, _deAlpha, _aAlpha]) {
      c.dispose();
    }
    super.dispose();
  }

  void _appliquer() {
    final r = _type == FilterType.numeric ? controlerFiltreNumero(_deNum.text, _aNum.text, widget.total) : controlerFiltreAlpha(_deAlpha.text, _aAlpha.text);
    if (!r.ok) {
      setState(() => _erreur = r.erreur);
      return;
    }
    Navigator.of(context).pop(r.filtre!.isActive ? AppliquerFiltre(r.filtre!) : const EffacerFiltre());
  }

  Widget _paire(String l1, String l2, TextEditingController c1, TextEditingController c2, {required bool actif, required bool numero, required String cle}) {
    final nv = context.nv;
    final erreur = actif && _erreur != null;
    InputDecoration deco(String l, TextEditingController c) => InputDecoration(
          labelText: l,
          hintText: numero ? 'n°' : 'ex. A',
          enabledBorder: erreur && c.text.trim().isEmpty
              ? OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: nv.erreur.fg, width: 1.5))
              : null,
        );
    Widget champ(String l, TextEditingController c, String k) => TextField(
          key: ValueKey(k),
          controller: c,
          enabled: actif,
          keyboardType: numero ? TextInputType.number : TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: numero ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)] : [LengthLimitingTextInputFormatter(3)],
          decoration: deco(l, c),
          onChanged: (_) {
            if (_erreur != null) setState(() => _erreur = null);
          },
          onSubmitted: (_) => _appliquer(),
        );
    return Opacity(
      opacity: actif ? 1 : 0.55,
      child: Row(children: [
        Expanded(child: champ(l1, c1, '$cle-de')),
        const SizedBox(width: 10),
        Expanded(child: champ(l2, c2, '$cle-a')),
      ]),
    );
  }

  Widget _radio(FilterType t, String libelle) => RadioListTile<FilterType>(
        key: ValueKey('nv-filtre-type-${t.name}'),
        contentPadding: EdgeInsets.zero,
        dense: false,
        title: Text(libelle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        value: t,
        groupValue: _type,
        onChanged: (v) => setState(() {
          _type = v!;
          _erreur = null;
        }),
      );

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return NvCadreDialogue(
        key: const ValueKey('nv-fenetre-filtre'),
        titre: 'Filtrer le rayon',
        centre: false,
        aDroiteDuTitre: Text(widget.rayon, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, color: nv.gris)),
        contenu: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _radio(FilterType.numeric, 'Par numéro (1 à ${widget.total})'),
          _paire('De (n°)', 'À (n°)', _deNum, _aNum, actif: _type == FilterType.numeric, numero: true, cle: 'nv-filtre-num'),
          if (_erreur != null) ...[
            const SizedBox(height: 6),
            Text(_erreur!, key: const ValueKey('nv-filtre-erreur'), style: TextStyle(fontSize: 13, color: nv.erreur.fg, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 6),
          _radio(FilterType.alphabetic, 'Par ordre alphabétique'),
          _paire('De (lettre / texte)', 'À (lettre / texte)', _deAlpha, _aAlpha, actif: _type == FilterType.alphabetic, numero: false, cle: 'nv-filtre-alpha'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: nv.page, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Raccourci', style: TextStyle(fontSize: 12.5, color: nv.gris, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              OutlinedButton(
                key: const ValueKey('nv-filtre-oublis'),
                style: OutlinedButton.styleFrom(side: BorderSide(color: nv.ligne), shape: const StadiumBorder()),
                onPressed: () => Navigator.of(context).pop(const FiltrerOublis()),
                child: Text('Seulement les produits pas encore comptés (oublis : ${widget.oublis})', textAlign: TextAlign.center),
              ),
            ]),
          ),
        ]),
        boutons: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('nv-effacer-filtre'),
                style: OutlinedButton.styleFrom(foregroundColor: nv.erreur.fg, side: BorderSide(color: nv.erreur.fg, width: 1.5)),
                onPressed: () => Navigator.of(context).pop(const EffacerFiltre()),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Effacer le filtre')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const ValueKey('nv-appliquer-filtre'),
                onPressed: _appliquer,
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Appliquer')),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          TextButton(key: const ValueKey('nv-annuler-filtre'), onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        ]),
    );
  }
}
