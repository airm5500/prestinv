// lib/ui/presentation_style.dart
// Composants de présentation de la nouvelle interface : copie adaptée de prestige_vente_app
// (lib/widgets/presentation_style.dart : NavyHeader, SoftCard, KpiTile, StatusBadge, ThinProgress,
// SegmentedPills, PresentationScaffold), mêmes conventions, plus le mode sombre (couleurs lues dans
// `context.nv`) et des cibles tactiles de 48 dp au moins.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';

/// En-tête bleu nuit arrondi (maquettes A, B, C), sous la barre d'état.
/// Tablette : fond bleu sur toute la largeur, contenu aligné sur la largeur du corps.
class NavyHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final bool rounded;
  final bool wide;

  /// Barre de progression fine sous le titre (saisie guidée : produit n / total).
  final double? progression;

  /// Bouton Retour forcé (null : affiché si la route peut revenir en arrière).
  final bool? retour;

  const NavyHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.children = const [],
    this.rounded = true,
    this.wide = false,
    this.progression,
    this.retour,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = retour ?? (Navigator.of(context).canPop() && !EmbeddedPane.of(context));
    final inset = Responsive.sideInset(context, wide: wide);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(
          color: context.nv.entete,
          borderRadius: rounded ? const BorderRadius.vertical(bottom: Radius.circular(24)) : null,
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(4 + inset, 4, 4 + inset, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (canPop)
                  IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Semantics(
                      header: true,
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.2)),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.headerMuted, fontSize: 13)),
                  ]),
                ),
                ...actions,
              ]),
              if (progression != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progression!.clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      color: Pal.amber,
                    ),
                  ),
                ),
              for (final c in children) Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: c),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bouton d'action de l'en-tête bleu (fond légèrement éclairci, 48 dp).
class ActionEntete extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const ActionEntete({super.key, required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          icon: Icon(icon, color: onPressed == null ? Colors.white38 : Colors.white),
        ),
      );
}

/// Tuile de chiffre clé dans l'en-tête bleu.
class KpiTile extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;
  const KpiTile(this.value, this.label, {super.key, this.highlight = false});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label : $value',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: highlight ? Pal.amber : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: highlight ? Pal.onAmber : const Color(0xFFDCE6F2), fontWeight: highlight ? FontWeight.w600 : null)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: highlight ? Pal.onAmber : Colors.white)),
            ),
          ]),
        ),
      );
}

/// Pastille d'état : libellé + couleur (jamais la couleur seule).
class Pastille extends StatelessWidget {
  final String text;
  final TonEtat ton;
  final IconData? icon;
  const Pastille(this.text, {super.key, required this.ton, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: ton.bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ton.fg, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          if (icon != null) ...[const SizedBox(width: 3), Icon(icon, size: 13, color: ton.fg)],
        ]),
      );
}

/// Carte arrondie (fond carte, ombre douce) ; [bande] : filet de couleur à gauche (écarts).
class SoftCard extends StatelessWidget {
  final Widget child;
  final Color? bande;
  final Color? bordure;
  final Color? fond;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final String? semantique;
  const SoftCard({super.key, required this.child, this.bande, this.bordure, this.fond, this.onTap, this.padding = const EdgeInsets.all(14), this.semantique});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    Widget contenu = Padding(padding: padding, child: child);
    if (bande != null) {
      contenu = IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: bande),
          Expanded(child: contenu),
        ]),
      );
    }
    Widget carte = Material(
      color: fond ?? nv.carte,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? contenu : InkWell(onTap: onTap, child: contenu),
    );
    carte = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: bordure != null ? Border.all(color: bordure!, width: 1.5) : null,
        boxShadow: context.nvSombre ? null : const [BoxShadow(color: Color(0x1214213D), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: carte,
    );
    if (semantique != null) carte = Semantics(button: onTap != null, label: semantique, child: carte);
    return carte;
  }
}

/// Barre de progression fine avec légende.
class ThinProgress extends StatelessWidget {
  final double value;
  final String? left;
  final String? right;
  final Color color;
  const ThinProgress({super.key, required this.value, this.left, this.right, this.color = Pal.amber});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (left != null || right != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(child: Text(left ?? '', style: TextStyle(fontSize: 13, color: context.nv.gris))),
              if (right != null) Text(right!, style: TextStyle(fontSize: 13, color: context.nv.gris)),
            ]),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 6, backgroundColor: context.nv.ligne, color: color),
        ),
      ]);
}

/// Filtres en pastilles sur fond clair (« Tous 34 », « À faire 9 », « Par valeur »…).
class FiltrePills extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<Widget> apres;
  const FiltrePills({super.key, required this.labels, required this.selected, required this.onSelected, this.apres = const []});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < labels.length; i++)
        Semantics(
          selected: i == selected,
          button: true,
          child: Material(
            color: i == selected ? (context.nvSombre ? nv.action : Pal.navy) : nv.carte,
            shape: StadiumBorder(side: BorderSide(color: i == selected ? Colors.transparent : nv.ligne, width: 1.5)),
            child: InkWell(
              key: ValueKey('filtre-$i'),
              customBorder: const StadiumBorder(),
              onTap: () => onSelected(i),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(labels[i],
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: i == selected ? (context.nvSombre ? Pal.navyFonce : Colors.white) : nv.action)),
                ),
              ),
            ),
          ),
        ),
      ...apres,
    ]);
  }
}

/// Titre de section en petites capitales (« DERNIÈRES SAISIES »).
class SectionTitre extends StatelessWidget {
  final String texte;
  final Widget? trailing;
  const SectionTitre(this.texte, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(texte.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: context.nv.gris)),
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Bandeau arrondi d'information (« 14 saisies sur le téléphone, pas encore envoyées [Envoyer] »).
class Bandeau extends StatelessWidget {
  final TonEtat ton;
  final String texte;
  final String? detail;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final Key? actionKey;
  const Bandeau({super.key, required this.ton, required this.texte, this.detail, this.icon, this.action, this.onAction, this.onTap, this.actionKey});

  @override
  Widget build(BuildContext context) {
    final contenu = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, color: ton.fg, size: 22), const SizedBox(width: 10)] else ...[
          Container(width: 10, height: 10, decoration: BoxDecoration(color: ton.fg, shape: BoxShape.circle)),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(texte, style: TextStyle(color: ton.fg, fontWeight: FontWeight.bold, fontSize: 14.5)),
            if (detail != null) Text(detail!, style: TextStyle(color: ton.fg, fontSize: 13)),
          ]),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          ElevatedButton(key: actionKey, onPressed: onAction, child: Text(action!)),
        ],
      ]),
    );
    return Material(
      color: ton.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: ton.fg.withValues(alpha: 0.35))),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? contenu : InkWell(onTap: onTap, child: contenu),
    );
  }
}

/// Cadre vert « Scanner prêt » autour du champ de la douchette (maquette B) : le champ garde son
/// comportement (focus permanent, clavier à la demande), seule sa présentation change.
class CadreScan extends StatelessWidget {
  final Widget champ;
  final bool actif;
  const CadreScan({super.key, required this.champ, this.actif = true});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final theme = Theme.of(context);
    final sansBord = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none);
    return Container(
      decoration: BoxDecoration(
        color: nv.scan.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: actif ? Pal.green : nv.ligne, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: Colors.transparent,
            border: sansBord,
            enabledBorder: sansBord,
            focusedBorder: sansBord,
            labelStyle: TextStyle(color: nv.scan.fg, fontWeight: FontWeight.bold),
            floatingLabelStyle: TextStyle(color: nv.scan.fg, fontWeight: FontWeight.bold),
            prefixIconColor: nv.scan.fg,
            suffixIconColor: nv.scan.fg,
          ),
        ),
        child: champ,
      ),
    );
  }
}

/// Tuile de chiffre sur fond de carte (« Stock théorique 12 », « Déjà compté — »).
class Chiffre extends StatelessWidget {
  final String label;
  final String value;
  final Color? couleur;
  const Chiffre(this.label, this.value, {super.key, this.couleur});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label : $value',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: context.nv.page, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: context.nv.gris)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: couleur ?? context.nv.encre)),
            ),
          ]),
        ),
      );
}

/// Cadre d'écran de la nouvelle interface : en-tête bleu, corps centré à largeur maximale sur tablette,
/// barre du bas facultative ; [menuLateral] (tablette ≥ 900 dp) : menu bleu à gauche (maquette C).
class NvScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> header;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? menuLateral;
  final double? progression;
  final bool wide;
  final bool rounded;
  final bool? retour;

  const NvScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.header = const [],
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.menuLateral,
    this.progression,
    this.wide = false,
    this.rounded = true,
    this.retour,
  });

  @override
  Widget build(BuildContext context) {
    final avecMenu = menuLateral != null && Responsive.isExpanded(context);
    final colonne = Column(children: [
      NavyHeader(
        title: title,
        subtitle: subtitle,
        actions: actions,
        rounded: rounded && !avecMenu,
        wide: wide,
        progression: progression,
        retour: avecMenu ? false : retour,
        children: header,
      ),
      Expanded(child: avecMenu ? body : ContentWidth(wide: wide, child: body)),
    ]);
    return Scaffold(
      backgroundColor: context.nv.page,
      bottomNavigationBar: avecMenu || bottomNavigationBar == null ? null : BottomBarWidth(wide: wide, child: bottomNavigationBar!),
      floatingActionButton: floatingActionButton,
      body: avecMenu
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 280, child: menuLateral),
              Expanded(child: MediaQuery.removePadding(context: context, removeLeft: true, child: PaneSize(child: colonne))),
            ])
          : colonne,
    );
  }
}

/// Texte d'aide discret sous un bloc.
class Aide extends StatelessWidget {
  final String texte;
  const Aide(this.texte, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(texte, style: TextStyle(fontSize: 13, color: context.nv.gris)),
      );
}

/// Écart signé (« +8 », « −5 ») avec vrai signe moins.
String signe(num n) => n > 0 ? '+$n' : (n < 0 ? '−${-n}' : '0');
