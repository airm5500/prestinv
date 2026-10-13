// lib/ui/ecrans/feuille_quantite.dart
// Nouvelle interface — quantité après un scan (maquette B, à droite) et fenêtres communes à la saisie
// guidée et au scan continu. MÊME LOGIQUE que la fenêtre « Saisie Rapide » de l'écran d'origine
// (InventoryEntryScreen._openQuickEntryDialog, _verifierDejaCompte, _saveScannedQuantity) :
// - quantité proposée (réglage « Quantité proposée après un scan »), remplacée au premier chiffre ;
// - −1 / +1, bornes 0 à 99 999, champ vide refusé, OK verrouillé pendant le traitement ;
// - Cumul activé : vérification « déjà compté » (saisie en attente sur l'appareil, sinon serveur) ;
//   échec de la vérification = rien n'est enregistré (jamais « jamais compté » par défaut) ; produit
//   déjà compté → choix explicite Remplacer / Ajouter (boutons de la feuille ou fenêtre) ;
// - seuil « grande quantité » confirmé ; enregistrement sur l'appareil AVANT de fermer ;
// - douchette : chiffres, Retour arrière, Entrée = OK, Échap = Annuler ; un code scanné pendant que la
//   feuille est ouverte attend son tour (champ de scan invisible gardant le focus).
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/scan/champ_douchette.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/scan/retour_scan.dart';
import 'package:prestinv/ui/clavier.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';

/// Choix explicite pour un produit déjà compté : true = Ajouter, false = Remplacer, null = Annuler.
Future<bool?> demanderRemplacerAjouter(BuildContext context, {required String nom, required int existant, required int saisie}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final nv = ctx.nv;
      return AlertDialog(
        key: const ValueKey('nv-choix-deja-compte'),
        title: const Text('Déjà compté'),
        scrollable: true,
        content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(nom, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: nv.attente.bg, borderRadius: BorderRadius.circular(12)),
            child: Text('Déjà compté : $existant. Vous saisissez $saisie.', style: TextStyle(color: nv.attente.fg, fontSize: 15)),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            key: const ValueKey('nv-remplacer'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: TexteFleche('Remplacer', '$saisie'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const ValueKey('nv-ajouter'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: TexteFleche('Ajouter', '${existant + saisie}'),
          ),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Annuler'))],
      );
    },
  );
}

/// Seuil « grande quantité » : confirmation explicite.
Future<bool> confirmerGrandeQuantite(BuildContext context, int total) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Grande quantité'),
      content: Text('Total : $total. Confirmer ?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Non')),
        FilledButton(key: const ValueKey('nv-confirmer-grande'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Oui')),
      ],
    ),
  );
  return r == true;
}

/// Plusieurs produits pour un code : l'opérateur choisit.
Future<Product?> choisirParmi(BuildContext context, String code, List<Product> produits) => showDialog<Product>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Code ${CodeScan.affichage(code)} : plusieurs produits', maxLines: 2, overflow: TextOverflow.ellipsis),
        children: [
          for (final p in produits.take(20))
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Text('${p.produitCip} — ${p.produitName}', maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
          SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(), child: Text('Annuler', style: TextStyle(color: ctx.nv.erreur.fg))),
        ],
      ),
    );

/// Le produit est-il déjà compté (cumul) ? Saisie en attente sur l'appareil, sinon serveur ; en cas
/// d'échec, l'opérateur réessaie ou annule (ok: false → rien n'est enregistré).
Future<({bool ok, int? quantite})> verifierDejaCompte(
    BuildContext ctx, ApiService api, SaisieQueue? queue, String inventoryId, Product product) async {
  final locale = queue?.ligne(inventoryId, product.id);
  if (locale != null && locale.enAttente) return (ok: true, quantite: locale.quantite);
  while (true) {
    if (!ctx.mounted) return (ok: false, quantite: null);
    showDialog<void>(context: ctx, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final q = await api.verifierDejaCompte(inventoryId, product.produitCip, ligneId: product.id);
      if (ctx.mounted) Navigator.of(ctx).pop();
      return (ok: true, quantite: q);
    } on ApiLoadException catch (e) {
      if (ctx.mounted) Navigator.of(ctx).pop();
      if (!ctx.mounted) return (ok: false, quantite: null);
      final reessayer = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (d) => AlertDialog(
          title: const Text('Vérification impossible'),
          content: Text('${e.message}\n\n'
              'On ne peut pas savoir si ce produit a déjà été compté : la quantité n\'est PAS enregistrée. '
              'Réessayez (ou annulez et rescannez plus tard).'),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Réessayer')),
          ],
        ),
      );
      if (reessayer != true) return (ok: false, quantite: null);
    }
  }
}

/// Contexte d'une feuille de quantité (fourni par l'écran qui l'ouvre).
class ContexteFeuille {
  final String inventoryId;
  final ApiService api;
  final AppConfig config;
  final EntryProvider provider;

  /// Retour sonore / vibration (réglages de l'appareil).
  final void Function(TypeRetour) retour;

  /// Code lu pendant que la feuille est ouverte (mis en file par l'écran).
  final ValueChanged<String> recevoirCode;

  /// Enregistre la quantité (sur l'appareil, puis envoi selon le mode). Renvoie faux si impossible.
  final Future<bool> Function(Product p, int quantite) enregistrer;

  const ContexteFeuille({
    required this.inventoryId,
    required this.api,
    required this.config,
    required this.provider,
    required this.retour,
    required this.recevoirCode,
    required this.enregistrer,
  });
}

/// Ouvre la feuille de quantité pour [product]. [dejaCompte] : quantité déjà comptée connue ;
/// [correction] : quantité actuelle d'une saisie du journal (remplacée, sans question).
/// Se termine quand la feuille est fermée.
Future<void> ouvrirFeuilleQuantite(BuildContext context, ContexteFeuille c, Product product, {int? dejaCompte, int? correction}) async {
  final proposee = correction ?? c.config.quantiteScanDefaut;
  final qte = ValueNotifier<String>(proposee?.toString() ?? '');
  final estProposee = ValueNotifier<bool>(proposee != null);
  final erreur = ValueNotifier<String?>(null);
  final catcher = TextEditingController();
  final catcherFocus = FocusNode();
  var okEnCours = false;
  var ouverte = true;
  BuildContext? feuilleCtx;

  void poser(String t) {
    qte.value = t;
    estProposee.value = false;
    erreur.value = null;
  }

  Future<void> valider(BuildContext ctx, {bool? ajouter}) async {
    if (okEnCours) return;
    final e = SaisieInput.erreurQuantite(qte.value);
    if (e != null) {
      c.retour(TypeRetour.erreur);
      erreur.value = e;
      return;
    }
    final saisie = SaisieInput.parseQuantite(qte.value)!;
    okEnCours = true;
    try {
      var total = saisie;
      if (c.config.isCumulEnabled && correction == null) {
        final verif = await verifierDejaCompte(ctx, c.api, c.provider.queue, c.inventoryId, product);
        if (!verif.ok) return; // rien n'est enregistré, la feuille reste ouverte
        final existant = verif.quantite;
        if (existant != null && ctx.mounted) {
          // Choix fait sur la feuille, valable seulement si la quantité vérifiée est celle affichée.
          final choix = ajouter != null && existant == dejaCompte
              ? ajouter
              : await demanderRemplacerAjouter(ctx, nom: product.produitName, existant: existant, saisie: saisie);
          if (choix == null) return;
          if (choix) {
            total = existant + saisie;
            c.provider.addCumulLog(product, existant, saisie);
          }
        }
      }
      if (total > SaisieInput.maxQuantite) {
        c.retour(TypeRetour.erreur);
        erreur.value = 'Total $total : au-delà de ${SaisieInput.maxQuantite}, non enregistré.';
        return;
      }
      if (total > c.config.largeValueThreshold && ctx.mounted) {
        if (!await confirmerGrandeQuantite(ctx, total)) return;
      }
      final ok = await c.enregistrer(product, total);
      if (!ok) {
        c.retour(TypeRetour.erreur);
        return;
      }
      if (ctx.mounted) Navigator.of(ctx).pop();
    } finally {
      okEnCours = false;
    }
  }

  void appui(String key, {bool? ajouter}) {
    final ctx = feuilleCtx;
    if (okEnCours || ctx == null) return;
    if (key == 'OK') {
      valider(ctx, ajouter: ajouter);
    } else if (key == 'DEL') {
      if (estProposee.value) {
        poser('');
      } else if (qte.value.isNotEmpty) {
        poser(qte.value.substring(0, qte.value.length - 1));
      }
    } else if (key == '+1' || key == '-1') {
      final v = SaisieInput.parseQuantite(qte.value) ?? 0;
      poser('${(v + (key == '+1' ? 1 : -1)).clamp(0, SaisieInput.maxQuantite)}');
    } else {
      poser(SaisieInput.ajouterChiffre(estProposee.value ? '' : qte.value, key));
    }
  }

  final cible = CibleDouchette(
    active: () => ouverte,
    onChiffres: (t) => t.split('').forEach(appui),
    onEffacer: () => appui('DEL'),
    onValider: () => appui('OK'),
    onEchap: () {
      final ctx = feuilleCtx;
      if (!okEnCours && ctx != null && ctx.mounted) Navigator.of(ctx).pop();
    },
  );
  Douchette.instance.ajouter(cible);
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) {
        feuilleCtx = ctx;
        return _Liberer(
          objets: [qte, estProposee, erreur, catcher, catcherFocus],
          child: _FeuilleQuantite(
            product: product,
            config: c.config,
            dejaCompte: dejaCompte,
            correction: correction,
            qte: qte,
            estProposee: estProposee,
            erreur: erreur,
            catcher: ChampDouchette(
              key: const ValueKey('champ-scan-feuille'),
              controller: catcher,
              focusNode: catcherFocus,
              onCode: c.recevoirCode,
              label: '',
              hint: '',
            ),
            onKey: appui,
            onAnnuler: () {
              if (!okEnCours) Navigator.of(ctx).pop();
            },
          ),
        );
      },
    );
  } finally {
    ouverte = false;
    Douchette.instance.retirer(cible);
  }
}

class _FeuilleQuantite extends StatelessWidget {
  final Product product;
  final AppConfig config;
  final int? dejaCompte;
  final int? correction;
  final ValueNotifier<String> qte;
  final ValueNotifier<bool> estProposee;
  final ValueNotifier<String?> erreur;
  final Widget catcher;
  final void Function(String key, {bool? ajouter}) onKey;
  final VoidCallback onAnnuler;

  const _FeuilleQuantite({
    required this.product,
    required this.config,
    required this.dejaCompte,
    required this.correction,
    required this.qte,
    required this.estProposee,
    required this.erreur,
    required this.catcher,
    required this.onKey,
    required this.onAnnuler,
  });

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    final choixSurFeuille = config.isCumulEnabled && correction == null && dejaCompte != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Champ de scan invisible : garde le focus pendant la feuille (douchette en remplissage direct).
          SizedBox(width: 1, height: 1, child: Opacity(opacity: 0, child: catcher)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(product.produitName,
                  key: const ValueKey('nv-feuille-produit'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: nv.encre)),
              Text(
                [
                  'CIP ${product.produitCip}',
                  if (product.locationLabel != null && product.locationLabel!.isNotEmpty) 'rayon ${product.locationLabel}',
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: nv.gris, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 12, children: [
                Text('PA ${francs(product.produitPrixAchat)}', style: TextStyle(color: nv.gris, fontSize: 13.5)),
                Text('PV ${francs(product.produitPrixUni)}', style: TextStyle(color: nv.gris, fontSize: 13.5)),
                if (config.showTheoreticalStock)
                  Text('Stock théo. ${product.quantiteInitiale}',
                      style: TextStyle(color: product.quantiteInitiale < 0 ? nv.erreur.fg : nv.ok.fg, fontSize: 13.5, fontWeight: FontWeight.bold)),
              ]),
              if (correction != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('bandeau-correction'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: nv.info.bg, borderRadius: BorderRadius.circular(12)),
                  child: Text('Correction : saisie actuelle $correction (la nouvelle quantité la remplace)',
                      style: TextStyle(color: nv.info.fg, fontWeight: FontWeight.w600)),
                ),
              ] else if (dejaCompte != null) ...[
                const SizedBox(height: 10),
                ValueListenableBuilder<String>(
                  valueListenable: qte,
                  builder: (_, v, __) => Container(
                    key: const ValueKey('bandeau-deja-compte'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: nv.attente.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: nv.attente.fg.withValues(alpha: 0.3))),
                    child: Text(
                      config.isCumulEnabled
                          ? 'Déjà compté : $dejaCompte. Vous saisissez ${v.isEmpty ? '…' : v}.'
                          : 'Déjà compté : $dejaCompte — votre saisie le remplacera.',
                      style: TextStyle(color: nv.attente.fg, fontSize: 15),
                    ),
                  ),
                ),
              ],
              if (choixSurFeuille) ...[
                const SizedBox(height: 10),
                ValueListenableBuilder<String>(
                  valueListenable: qte,
                  builder: (_, v, __) {
                    final n = SaisieInput.parseQuantite(v);
                    return Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('nv-feuille-remplacer'),
                          onPressed: n == null ? null : () => onKey('OK', ajouter: false),
                          child: FittedBox(fit: BoxFit.scaleDown, child: TexteFleche('Remplacer', '${n ?? '…'}')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          key: const ValueKey('nv-feuille-ajouter'),
                          onPressed: n == null ? null : () => onKey('OK', ajouter: true),
                          child: FittedBox(fit: BoxFit.scaleDown, child: TexteFleche('Ajouter', n == null ? '…' : '${n + dejaCompte!}')),
                        ),
                      ),
                    ]);
                  },
                ),
              ],
              const SizedBox(height: 10),
              AnimatedBuilder(
                animation: Listenable.merge([qte, estProposee, erreur]),
                builder: (_, __) => AfficheQuantite(
                  label: 'Quantité',
                  valeur: qte.value,
                  proposee: estProposee.value,
                  erreur: erreur.value,
                  droite: Row(mainAxisSize: MainAxisSize.min, children: [
                    PetitBouton('−1', key: const ValueKey('qte-moins'), semantique: 'Moins un', onPressed: () => onKey('-1')),
                    PetitBouton('+1', key: const ValueKey('qte-plus'), semantique: 'Plus un', onPressed: () => onKey('+1')),
                  ]),
                ),
              ),
              Aide('Contrôles : 0 à ${SaisieInput.maxQuantite} ; au-delà de ${config.largeValueThreshold} : confirmation'
                  '${config.isCumulEnabled ? ' ; déjà compté : Remplacer ou Ajouter, jamais d\'écrasement silencieux' : ''}.'),
            ]),
          ),
          NvPave(onKey: (k) => onKey(k), hauteur: NvPave.hauteurPour(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextButton(key: const ValueKey('nv-feuille-annuler'), onPressed: onAnnuler, child: Text('Annuler', style: TextStyle(color: nv.erreur.fg))),
          ),
        ]),
      ),
    );
  }
}

/// Libère des objets quand la feuille quitte l'écran (après son animation de fermeture).
class _Liberer extends StatefulWidget {
  final List<ChangeNotifier> objets;
  final Widget child;
  const _Liberer({required this.objets, required this.child});

  @override
  State<_Liberer> createState() => _LibererState();
}

class _LibererState extends State<_Liberer> {
  @override
  void dispose() {
    for (final o in widget.objets) {
      o.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// « Remplacer → 4 » (flèche dessinée : la police du système n'a pas toujours le caractère →).
class TexteFleche extends StatelessWidget {
  final String action;
  final String valeur;
  const TexteFleche(this.action, this.valeur, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$action : $valeur',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(action),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 18)),
          Text(valeur),
        ]),
      );
}

/// Message d'échec d'un envoi direct (même texte que l'écran d'origine).
void messageEnvoiDirect(BuildContext context, String texte) => nvMessage(context, texte, ton: context.nv.erreur);
