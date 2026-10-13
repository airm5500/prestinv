// lib/ui/clavier.dart
// Pavé numérique de la nouvelle interface (maquettes A, B, C) : touches blanches, Effacer gris,
// validation ambre. Mêmes codes de touches que le pavé d'origine (« 0 »…« 9 », « DEL », « OK ») :
// les écrans les traitent avec la même logique (SaisieInput).
import 'package:flutter/material.dart';
import 'package:prestinv/ui/theme.dart';

class NvPave extends StatelessWidget {
  final ValueChanged<String> onKey;

  /// Libellé de la touche de validation (« OK › », « Corriger »…).
  final String ok;

  /// Faux pendant un envoi : validation verrouillée (sablier).
  final bool okActif;

  /// Hauteur d'une touche (48 dp au moins).
  final double hauteur;

  const NvPave({super.key, required this.onKey, this.ok = 'OK', this.okActif = true, this.hauteur = 56});

  /// Hauteur conseillée selon la hauteur d'écran (Sunmi V2s : 640 dp utiles environ).
  static double hauteurPour(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return h < 680 ? 48 : (h < 760 ? 52 : 58);
  }

  @override
  Widget build(BuildContext context) {
    Widget rangee(List<String> ks) => Row(children: [for (final k in ks) Expanded(child: _touche(context, k))]);
    return Container(
      color: context.nv.page,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        rangee(['1', '2', '3']),
        rangee(['4', '5', '6']),
        rangee(['7', '8', '9']),
        rangee(['DEL', '0', 'OK']),
      ]),
    );
  }

  Widget _touche(BuildContext context, String k) {
    final nv = context.nv;
    final estOk = k == 'OK';
    final estDel = k == 'DEL';
    final actif = !estOk || okActif;
    final fond = estOk ? Pal.amber : (estDel ? nv.toucheSpeciale : nv.touche);
    final texte = estOk ? Pal.onAmber : nv.encre;
    Widget contenu;
    if (estOk && !okActif) {
      contenu = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Pal.onAmber));
    } else if (estDel) {
      contenu = Icon(Icons.backspace_outlined, color: texte, size: 24);
    } else {
      contenu = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(estOk ? ok : k, style: TextStyle(fontSize: estOk ? 22 : 26, fontWeight: FontWeight.bold, color: texte)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Semantics(
        button: true,
        enabled: actif,
        label: estDel ? 'Effacer' : (estOk ? ok : k),
        excludeSemantics: true,
        child: Material(
          color: fond,
          elevation: context.nvSombre ? 0 : 0.6,
          shadowColor: const Color(0x3314213D),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: ValueKey('touche-$k'),
            borderRadius: BorderRadius.circular(12),
            onTap: actif ? () => onKey(k) : null,
            child: SizedBox(height: hauteur, child: Center(child: contenu)),
          ),
        ),
      ),
    );
  }
}

/// Grand affichage de la quantité saisie (cadre bleu nuit, chiffre en gros).
class AfficheQuantite extends StatelessWidget {
  final String label;
  final String valeur;

  /// Valeur proposée (grisée, remplacée au premier chiffre tapé).
  final bool proposee;
  final String? erreur;
  final Widget? droite;
  final String? aide;
  const AfficheQuantite({super.key, required this.label, required this.valeur, this.proposee = false, this.erreur, this.droite, this.aide});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return Semantics(
      label: '$label : ${valeur.isEmpty ? 'vide' : valeur}${proposee ? ' (proposée)' : ''}',
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        decoration: BoxDecoration(
          color: nv.carte,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: erreur != null ? nv.erreur.fg : nv.action, width: 2.5),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(proposee ? '$label (proposée)' : label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: nv.gris, fontSize: 13.5)),
              Text(valeur.isEmpty ? ' ' : valeur,
                  key: const ValueKey('nv-quantite'),
                  maxLines: 1,
                  style: TextStyle(fontSize: 38, height: 1.15, fontWeight: FontWeight.w800, color: proposee ? nv.gris : nv.encre)),
              if (erreur != null)
                Text(erreur!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: nv.erreur.fg, fontSize: 13, fontWeight: FontWeight.w600))
              else if (aide != null)
                Text(aide!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: nv.gris, fontSize: 12.5)),
            ]),
          ),
          if (droite != null) droite!,
        ]),
      ),
    );
  }
}

/// Petit bouton arrondi (−1 / +1).
class PetitBouton extends StatelessWidget {
  final String texte;
  final VoidCallback onPressed;
  final String? semantique;
  const PetitBouton(this.texte, {super.key, required this.onPressed, this.semantique});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(minimumSize: const Size(52, 48), padding: const EdgeInsets.symmetric(horizontal: 8), shape: const StadiumBorder()),
          child: Text(texte, semanticsLabel: semantique, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      );
}
