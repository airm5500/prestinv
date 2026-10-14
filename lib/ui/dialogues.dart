// lib/ui/dialogues.dart
// Fenêtres et menus de la NOUVELLE interface (maquettes « Menu ⋮ et Quitter » et « Envoi ») :
//  - [nvDialogue] / [NvCadreDialogue] : fenêtre centrée arrondie, pastille d'icône, titre et message
//    centrés, boutons pleins (action principale ambre, secondaire bordée bleu nuit, discrète en texte) ;
//  - [nvMenu] : feuille du bas (poignée, lignes de 52 dp avec icône, action dangereuse en rouge) ;
//  - [nvEnvoiSaisies] : progression d'envoi modernisée (anneau, « 31 sur 50 saisies envoyées », barre),
//    l'envoi continue en arrière-plan si l'on ferme la fenêtre.
// Les écrans d'origine (lib/screens/…) gardent leurs fenêtres ; les éléments partagés (code
// administrateur, reconnexion, déconnexion) choisissent selon InterfaceVersion.useNew.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/theme.dart';

/// Rôle d'un bouton de fenêtre.
enum NvGenre { principal, secondaire, discret, danger }

class NvBouton<T> {
  final String libelle;
  final T valeur;
  final NvGenre genre;
  final Key? key;
  const NvBouton(this.libelle, this.valeur, {this.genre = NvGenre.secondaire, this.key});
}

/// Bouton de fenêtre au style de la maquette (48 dp au moins).
Widget nvBoutonFenetre(BuildContext context, {required String libelle, required NvGenre genre, required VoidCallback? onPressed, Key? key}) {
  final nv = context.nv;
  final texte = FittedBox(fit: BoxFit.scaleDown, child: Text(libelle, textAlign: TextAlign.center, maxLines: 2));
  switch (genre) {
    case NvGenre.principal:
      return FilledButton(key: key, onPressed: onPressed, child: texte);
    case NvGenre.secondaire:
      return OutlinedButton(key: key, onPressed: onPressed, child: texte);
    case NvGenre.discret:
      return TextButton(key: key, style: TextButton.styleFrom(foregroundColor: nv.gris), onPressed: onPressed, child: texte);
    case NvGenre.danger:
      return TextButton(key: key, style: TextButton.styleFrom(foregroundColor: nv.erreur.fg), onPressed: onPressed, child: texte);
  }
}

/// Rangée de boutons : deux boutons pleins côte à côte (secondaire puis principal), sinon les uns sous
/// les autres ; les boutons discrets / dangereux en texte, pleine largeur, en dessous.
Widget nvRangeeBoutons(BuildContext context, List<Widget> pleins, List<Widget> textes) {
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
    if (pleins.length == 2)
      Row(children: [Expanded(child: pleins[0]), const SizedBox(width: 10), Expanded(child: pleins[1])])
    else
      for (var i = 0; i < pleins.length; i++) ...[if (i > 0) const SizedBox(height: 8), pleins[i]],
    for (final t in textes) ...[const SizedBox(height: 4), t],
  ]);
}

/// Cadre de fenêtre de la nouvelle interface (à utiliser dans showDialog).
class NvCadreDialogue extends StatelessWidget {
  final IconData? icone;
  final TonEtat? ton;
  final String titre;
  final String? message;
  final Widget? contenu;

  /// Boutons (voir [nvRangeeBoutons]) déjà construits.
  final Widget? boutons;

  /// Titre aligné à gauche avec un complément à droite (fenêtre de formulaire, ex. filtre).
  final Widget? aDroiteDuTitre;
  final bool centre;
  const NvCadreDialogue({
    super.key,
    this.icone,
    this.ton,
    required this.titre,
    this.message,
    this.contenu,
    this.boutons,
    this.aDroiteDuTitre,
    this.centre = true,
  });

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final t = ton ?? nv.attente;
    final alignement = centre ? CrossAxisAlignment.center : CrossAxisAlignment.stretch;
    final styleTitre = TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: context.nvSombre ? nv.encre : Pal.navy);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (icone != null) ...[
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: t.bg, shape: BoxShape.circle),
                  child: Icon(icone, color: t.fg, size: 26),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (aDroiteDuTitre != null)
              Row(children: [
                Expanded(child: Semantics(header: true, child: Text(titre, style: styleTitre))),
                const SizedBox(width: 8),
                Flexible(child: aDroiteDuTitre!),
              ])
            else
              Semantics(header: true, child: Text(titre, textAlign: centre ? TextAlign.center : TextAlign.start, style: styleTitre)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: centre ? TextAlign.center : TextAlign.start, style: TextStyle(fontSize: 14.5, color: nv.gris, height: 1.35)),
            ],
            if (contenu != null) ...[const SizedBox(height: 14), Column(crossAxisAlignment: alignement, children: [contenu!])],
            if (boutons != null) ...[const SizedBox(height: 18), boutons!],
          ]),
        ),
      ),
    );
  }
}

/// Fenêtre de confirmation de la nouvelle interface ; renvoie la valeur du bouton touché (null si
/// fermée autrement).
Future<T?> nvDialogue<T>(
  BuildContext context, {
  Key? key,
  IconData? icone,
  TonEtat? ton,
  required String titre,
  String? message,
  Widget? contenu,
  required List<NvBouton<T>> boutons,
  bool fermable = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: fermable,
    builder: (ctx) {
      Widget bouton(NvBouton<T> b) =>
          nvBoutonFenetre(ctx, libelle: b.libelle, genre: b.genre, key: b.key, onPressed: () => Navigator.of(ctx).pop(b.valeur));
      final pleins = [
        for (final g in [NvGenre.secondaire, NvGenre.principal])
          for (final b in boutons.where((b) => b.genre == g)) bouton(b),
      ];
      final textes = [for (final b in boutons.where((b) => b.genre == NvGenre.discret || b.genre == NvGenre.danger)) bouton(b)];
      return NvCadreDialogue(
        key: key,
        icone: icone,
        ton: ton,
        titre: titre,
        message: message,
        contenu: contenu,
        boutons: nvRangeeBoutons(ctx, pleins, textes),
      );
    },
  );
}

/// Ligne d'un menu (feuille du bas).
class NvEntree<T> {
  final IconData icone;
  final String libelle;
  final T valeur;
  final bool danger;
  final bool actif;
  final String? detail;
  final Key? key;
  const NvEntree(this.icone, this.libelle, this.valeur, {this.danger = false, this.actif = true, this.detail, this.key});
}

/// Menu de la nouvelle interface : feuille du bas (maquette « Menu ⋮ »).
Future<T?> nvMenu<T>(BuildContext context, {String? titre, required List<NvEntree<T>> entrees, Key? key}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) => NvFeuilleMenu<T>(key: key, titre: titre, entrees: entrees),
  );
}

class NvFeuilleMenu<T> extends StatelessWidget {
  final String? titre;
  final List<NvEntree<T>> entrees;
  const NvFeuilleMenu({super.key, this.titre, required this.entrees});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (titre != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  header: true,
                  child: Text(titre!, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: context.nvSombre ? nv.encre : Pal.navy)),
                ),
              ),
            ),
          for (final e in entrees)
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: e.key,
                borderRadius: BorderRadius.circular(12),
                onTap: e.actif ? () => Navigator.of(context).pop(e.valeur) : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      Icon(e.icone, size: 22, color: !e.actif ? nv.ligne : (e.danger ? nv.erreur.fg : nv.action)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(e.libelle,
                              style: TextStyle(fontSize: 16, color: !e.actif ? nv.gris : (e.danger ? nv.erreur.fg : nv.encre), fontWeight: FontWeight.w500)),
                          if (e.detail != null) Text(e.detail!, style: TextStyle(fontSize: 13, color: nv.gris)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Envoi des saisies : progression modernisée (maquette « Envoi »)
// ---------------------------------------------------------------------------------------------

/// Avancement d'un envoi groupé.
class ProgressionEnvoi {
  final int fait;
  final int total;
  const ProgressionEnvoi(this.fait, this.total);
  double? get fraction => total <= 0 ? null : (fait / total).clamp(0, 1).toDouble();
}

/// Message de fin d'un envoi groupé (mêmes textes que les écrans d'origine).
String messageBilanEnvoi(BilanEnvoi bilan, int demandees) {
  if (bilan.complet && bilan.refusees == 0) return '${bilan.envoyees} article(s) traité(s) avec succès.';
  if (bilan.sessionExpiree) return SaisieQueue.messageSessionExpiree;
  if (bilan.envoyees > 0) {
    return 'Réseau instable : ${bilan.envoyees}/$demandees envoyé(s). Le reste est gardé sur l\'appareil (« À envoyer »).';
  }
  if (bilan.refusees > 0 && bilan.interruption == null) return '${bilan.refusees} saisie(s) refusée(s) par le serveur (voir « À envoyer »).';
  return 'Échec : ${bilan.interruption ?? 'Vérifiez votre connexion au serveur.'} Les saisies restent sur l\'appareil.';
}

/// Lance [envoyer] et affiche sa progression ; « Continuer la saisie » ferme la fenêtre sans arrêter
/// l'envoi (il se poursuit en arrière-plan). La fenêtre se ferme seule 2,5 s après la fin.
Future<BilanEnvoi> nvEnvoiSaisies(
  BuildContext context, {
  required Future<BilanEnvoi> Function(void Function(int fait, int total) progression) envoyer,
  required int demandees,
  String? sousTitre,
  bool themer = false,
}) async {
  final avancement = ValueNotifier<ProgressionEnvoi>(ProgressionEnvoi(0, demandees));
  final fin = ValueNotifier<String?>(null);
  var ouverte = true;
  final nav = Navigator.of(context);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final f = _FenetreEnvoi(avancement: avancement, fin: fin, sousTitre: sousTitre, onContinuer: () => Navigator.of(ctx).pop());
      return themer ? NvTheme(child: f) : f;
    },
  );
  nav.push(route).whenComplete(() => ouverte = false);
  final bilan = await envoyer((a, b) => avancement.value = ProgressionEnvoi(a, b));
  fin.value = messageBilanEnvoi(bilan, demandees);
  avancement.value = ProgressionEnvoi(bilan.envoyees, math.max(demandees, bilan.envoyees));
  await Future<void>.delayed(const Duration(milliseconds: 2500));
  if (ouverte && route.isActive) nav.removeRoute(route);
  // Libérés après la fermeture (animation comprise).
  Future<void>.delayed(const Duration(seconds: 1), () {
    avancement.dispose();
    fin.dispose();
  });
  return bilan;
}

class _FenetreEnvoi extends StatelessWidget {
  final ValueNotifier<ProgressionEnvoi> avancement;
  final ValueNotifier<String?> fin;
  final String? sousTitre;
  final VoidCallback onContinuer;
  const _FenetreEnvoi({required this.avancement, required this.fin, required this.sousTitre, required this.onContinuer});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return AnimatedBuilder(
      animation: Listenable.merge([avancement, fin]),
      builder: (context, _) {
        final a = avancement.value;
        final f = a.fraction;
        final pct = f == null ? '…' : '${(f * 100).round()} %';
        final termine = fin.value != null;
        return NvCadreDialogue(
          key: const ValueKey('nv-envoi-saisies'),
          titre: 'Envoi des saisies',
          centre: false,
          contenu: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(value: f, strokeWidth: 8, color: Pal.amber, backgroundColor: nv.ligne),
                  ),
                  Text(pct, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: nv.encre)),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a.fait} sur ${a.total} saisie(s) envoyée(s)',
                      key: const ValueKey('nv-envoi-compte'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: nv.encre)),
                  if (sousTitre != null) Text(sousTitre!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: nv.gris)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: f, minHeight: 8, color: Pal.amber, backgroundColor: nv.ligne),
            ),
            const SizedBox(height: 10),
            Text(
              termine ? fin.value! : 'Vous pouvez continuer à compter : l\'envoi se poursuit en arrière-plan.',
              key: const ValueKey('nv-envoi-message'),
              style: TextStyle(fontSize: termine ? 14 : 12.5, color: termine ? nv.encre : nv.gris, fontWeight: termine ? FontWeight.w600 : null),
            ),
          ]),
          boutons: nvBoutonFenetre(context,
              key: const ValueKey('nv-envoi-continuer'),
              libelle: termine ? 'Fermer' : 'Continuer la saisie',
              genre: NvGenre.secondaire,
              onPressed: onContinuer),
        );
      },
    );
  }
}

/// Message BLOQUANT « Veuillez sauvegarder vos saisies » (maquette « Envoi ») : une seule action,
/// « Envoyer maintenant ». Se termine quand elle est touchée.
Future<void> nvRappelSauvegarde(BuildContext context, {required int nombre, required Duration depuis, bool themer = false}) {
  final minutes = depuis.inMinutes;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final fenetre = PopScope(
        canPop: false,
        child: Builder(builder: (ctx) {
          final nv = ctx.nv;
          return Dialog(
            key: const ValueKey('nv-rappel-sauvegarde'),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Pal.amber, width: 3)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Semantics(
                    header: true,
                    child: Text('Veuillez sauvegarder vos saisies', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: nv.erreur.fg)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$nombre saisie(s) attendent depuis ${minutes < 1 ? 'moins d\'une minute' : '$minutes min'} (délai réglé dans Réglages). '
                    'Envoyez-les maintenant pour ne pas les perdre.',
                    style: TextStyle(fontSize: 15, color: nv.encre, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('nv-rappel-envoyer'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Envoyer maintenant'),
                  ),
                  const SizedBox(height: 8),
                  Text('Ce message revient tant que les saisies n\'ont pas été envoyées.', style: TextStyle(fontSize: 12.5, color: nv.gris)),
                ]),
              ),
            ),
          );
        }),
      );
      return themer ? NvTheme(child: fenetre) : fenetre;
    },
  );
}
