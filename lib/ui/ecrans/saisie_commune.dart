// lib/ui/ecrans/saisie_commune.dart
// Nouvelle interface — logique commune à la saisie guidée et au scan continu. C'est la logique de
// l'écran d'origine InventoryEntryScreen (inchangé), reprise telle quelle pour les nouveaux écrans :
// douchette toujours prête (Douchette + ChampDouchette + FileScans : aucun scan perdu, même en rafale),
// recherche du code (variantes CodeScan.candidats, produit exact, choix parmi plusieurs), retour
// sonore, journal des codes sans saisie, enregistrement dans la file des saisies AVANT tout envoi,
// envoi direct / groupé, rappel d'envoi, sécurité de sortie.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/scan/file_scans.dart';
import 'package:prestinv/scan/journal_scans.dart';
import 'package:prestinv/scan/retour_scan.dart';
import 'package:prestinv/ui/ecrans/feuille_quantite.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:provider/provider.dart';

mixin SaisieCommune<T extends StatefulWidget> on State<T>, DouchetteCibleMixin<T> {
  Inventory get inventaire;

  /// Scan continu (sans rayon) ; faux : saisie guidée par rayon.
  bool get modeScan;

  late final ApiService api;
  late final FileScans fileScans;
  final champScanCtrl = TextEditingController();
  final champScanFocus = FocusNode();

  /// Feuille de quantité ouverte (les scans continuent d'arriver dans la file).
  bool feuilleOuverte = false;

  /// OK de la saisie guidée en cours de traitement.
  bool validationEnCours = false;

  /// Clavier à l'écran affiché dans le champ de scan (recherche par nom).
  bool clavierTexte = false;

  /// Résultats d'une recherche au clavier.
  List<Product> resultats = [];
  bool afficherResultats = false;

  final List<ScanSansSaisie> sansSaisie = [];
  final Map<int, Product> produitsVus = {};
  Timer? _rappel;
  Timer? _frappe;

  String get inventoryId => inventaire.id;
  EntryProvider get entry => context.read<EntryProvider>();
  AppConfig get config => context.read<AppConfig>();
  SaisieQueue? get queue => entry.queue;
  bool get routeCourante => ModalRoute.of(context)?.isCurrent ?? true;

  /// Douchette : chiffres / effacer / valider de la saisie guidée (null en scan continu).
  void Function(String key)? get toucheGuidee => null;

  void initSaisie() {
    final auth = context.read<AuthProvider>();
    api = ApiService(baseUrl: context.read<AppConfig>().currentApiUrl, cookie: () => auth.sessionCookie);
    fileScans = FileScans(traiter: traiterCode, pret: pretPourScan);
    final g = toucheGuidee;
    brancherDouchette(CibleDouchette(
      active: () => mounted && (routeCourante || feuilleOuverte),
      onCode: recevoirCode,
      onChiffres: g == null ? null : (t) => t.split('').forEach(g),
      onEffacer: g == null ? null : () => g('DEL'),
      onValider: g == null ? null : () => g('OK'),
      onToucheScan: reprendreFocusScan,
    ));
  }

  void disposeSaisie() {
    fileScans.dispose();
    champScanCtrl.dispose();
    champScanFocus.dispose();
    _rappel?.cancel();
    _frappe?.cancel();
  }

  void reprendreFocusScan() {
    if (!mounted) return;
    if (champScanFocus.canRequestFocus) champScanFocus.requestFocus();
  }

  bool pretPourScan() => mounted && routeCourante && !validationEnCours && !feuilleOuverte;

  void recevoirCode(String code) {
    final c = CodeScan.nettoyer(code);
    if (c.isEmpty) return;
    fileScans.ajouter(c);
  }

  /// Champ de scan validé : texte tapé au clavier → recherche ; code → file des scans.
  void surCodeChamp(String texte) {
    if (clavierTexte && !CodeScan.ressembleACode(texte)) {
      rechercher(texte, auFil: false);
    } else {
      recevoirCode(texte);
    }
  }

  void surClavier(bool v) => setState(() {
        clavierTexte = v;
        if (!v) {
          afficherResultats = false;
          resultats = [];
        }
      });

  void retour(TypeRetour type) => RetourScan.jouer(type, son: config.sonScan, vibration: config.vibrationScan);

  void noterSansSaisie(String code, String raison, {bool aRelancer = false}) {
    setState(() {
      sansSaisie.add(ScanSansSaisie(code, DateTime.now(), raison, aRelancer: aRelancer));
      if (sansSaisie.length > 50) sansSaisie.removeAt(0);
    });
  }

  /// Traite UN code scanné : recherche (variantes du code) puis feuille de quantité.
  Future<void> traiterCode(String code) async {
    final provider = entry;
    if (!modeScan && provider.selectedRayon == null) {
      retour(TypeRetour.erreur);
      nvMessage(context, 'Code lu : choisissez d\'abord un emplacement.', ton: context.nv.erreur);
      return;
    }
    final candidats = CodeScan.candidats(code);
    if (candidats.isEmpty) return;
    Product? exact;
    final possibles = <int, Product>{};
    try {
      for (final c in candidats) {
        final r = await provider.searchProductOnline(api, inventoryId, c);
        if (!mounted) return;
        final memeCode = r.where((p) => p.produitCip.trim() == c).toList();
        if (memeCode.length == 1) {
          exact = memeCode.first;
          break;
        }
        if (r.length == 1) {
          exact = r.first;
          break;
        }
        for (final p in r) {
          possibles[p.id] = p;
        }
      }
    } catch (e) {
      if (!mounted) return;
      retour(TypeRetour.erreur);
      noterSansSaisie(code, 'recherche impossible (${estSessionExpiree(e) ? 'session expirée' : 'réseau'}) — toucher pour relancer', aRelancer: true);
      nvMessage(context, 'Code lu : ${CodeScan.affichage(code)} — ${messageErreur(e)}',
          ton: context.nv.erreur,
          action: estSessionExpiree(e) ? SnackBarAction(label: 'Se reconnecter', onPressed: () => demanderReconnexion(context)) : null);
      reprendreFocusScan();
      return;
    }
    if (!mounted) return;
    if (exact == null && possibles.isNotEmpty) {
      retour(TypeRetour.dejaCompte);
      exact = await choisirParmi(context, code, possibles.values.toList());
      if (!mounted) return;
      if (exact == null) {
        reprendreFocusScan();
        return;
      }
    }
    if (exact == null) {
      retour(TypeRetour.erreur);
      final message =
          modeScan ? CodeScan.messageIntrouvable(code) : 'Code lu : ${CodeScan.affichage(code)} — introuvable dans cet emplacement';
      noterSansSaisie(code, modeScan ? 'pas dans cet inventaire' : 'pas dans cet emplacement');
      nvMessage(context, message, ton: context.nv.erreur, key: const ValueKey('code-introuvable'));
      reprendreFocusScan();
      return;
    }
    await ouvrirProduitScanne(exact);
  }

  int? dejaCompteConnu(Product p) {
    final locale = queue?.ligne(inventoryId, p.id);
    if (locale != null) return locale.quantite;
    if (p.dtUpdated != null) return p.quantiteSaisie;
    return null;
  }

  Future<void> ouvrirProduitScanne(Product p) async {
    produitsVus[p.id] = p;
    final deja = dejaCompteConnu(p);
    retour(deja != null ? TypeRetour.dejaCompte : TypeRetour.succes);
    champScanCtrl.clear();
    if (afficherResultats) {
      setState(() {
        afficherResultats = false;
        resultats = [];
      });
    }
    await ouvrirFeuille(p, dejaCompte: deja);
  }

  /// Correction d'une saisie du journal (la nouvelle quantité remplace la précédente).
  Future<void> corrigerSaisie(SaisieLigne s) async {
    if (fileScans.occupe || feuilleOuverte) {
      nvMessage(context, 'Patientez : un scan est en cours de traitement.');
      return;
    }
    final p = produitsVus[s.ligneId] ??
        Product(
          id: s.ligneId,
          produitCip: s.cip,
          produitName: s.nom,
          produitPrixAchat: 0,
          produitPrixUni: 0,
          quantiteInitiale: 0,
          quantiteSaisie: s.quantite,
          locationLabel: s.rayonLibelle,
        );
    await ouvrirFeuille(p, correction: s.quantite);
    fileScans.relancer();
  }

  Future<void> ouvrirFeuille(Product p, {int? dejaCompte, int? correction}) async {
    setState(() => feuilleOuverte = true);
    try {
      await ouvrirFeuilleQuantite(
        context,
        ContexteFeuille(
          inventoryId: inventoryId,
          api: api,
          config: config,
          provider: entry,
          retour: retour,
          recevoirCode: recevoirCode,
          enregistrer: enregistrerScan,
        ),
        p,
        dejaCompte: dejaCompte,
        correction: correction,
      );
    } finally {
      if (mounted) {
        setState(() {
          feuilleOuverte = false;
          afficherResultats = false;
          resultats = [];
        });
        champScanCtrl.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          reprendreFocusScan();
          fileScans.relancer();
        });
      }
    }
  }

  /// Quantité d'un produit scanné : écrite dans la file persistante avant tout envoi.
  Future<bool> enregistrerScan(Product product, int quantite) async {
    product.quantiteSaisie = quantite;
    try {
      await entry.updateSpecificProduct(product, inventoryId);
    } catch (e) {
      if (mounted) nvMessage(context, 'Enregistrement impossible sur l\'appareil : $e', ton: context.nv.erreur);
      return false;
    }
    if (mounted) nvMessage(context, 'Saisie enregistrée : ${product.produitName}', ton: context.nv.ok, duree: const Duration(seconds: 2));
    if (config.sendMode == SendMode.direct) envoyerDirect(product);
    return true;
  }

  /// Mode Direct : envoi immédiat de la ligne (déjà enregistrée sur l'appareil).
  void envoyerDirect(Product product) {
    final q = queue;
    if (q == null) return;
    q.envoyerLigne(inventoryId, product.id).then((r) {
      if (!r.estOk && mounted) {
        if (r.type == ResultatEnvoi.session) return proposerReconnexion();
        messageEnvoiDirect(
            context, r.type == ResultatEnvoi.refus ? r.message : 'Non envoyé (réseau) : gardé sur l\'appareil, nouvel essai automatique.');
      }
    });
  }

  /// Envoie les saisies en attente de l'inventaire (tous rayons). Renvoie vrai si tout est confirmé.
  Future<bool> envoyerInventaire() async {
    if (!mounted) return false;
    final provider = entry;
    final enAttente = provider.pendingCountInventory;
    if (config.sendMode == SendMode.direct && enAttente == 0) {
      nvMessage(context, 'Mode Direct : tout est déjà synchronisé.', ton: context.nv.info);
      return true;
    }
    if (enAttente == 0) {
      nvMessage(context, 'Aucune donnée en attente d\'envoi.', ton: context.nv.attente);
      return true;
    }
    final progression = ValueNotifier<String>('Connexion au serveur…');
    final fini = ValueNotifier<bool>(false);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LibererApres(
        objets: [progression, fini],
        child: AlertDialog(
        content: AnimatedBuilder(
          animation: Listenable.merge([progression, fini]),
          builder: (_, __) => Row(children: [
            if (fini.value) Icon(Icons.info_outline, color: ctx.nv.action, size: 28) else const CircularProgressIndicator(),
            const SizedBox(width: 18),
            Expanded(child: Text(progression.value)),
          ]),
        ),
      ),
      ),
    );
    final bilan = await provider.envoyerInventaire(inventoryId, (a, b) => progression.value = 'Envoi… ($a/$b)');
    if (bilan.complet && bilan.refusees == 0) {
      progression.value = '${bilan.envoyees} article(s) traité(s) avec succès.';
    } else if (bilan.sessionExpiree) {
      progression.value = SaisieQueue.messageSessionExpiree;
    } else if (bilan.envoyees > 0) {
      progression.value = 'Réseau instable : ${bilan.envoyees}/$enAttente envoyé(s). Le reste est gardé sur l\'appareil (« À envoyer »).';
    } else if (bilan.refusees > 0 && bilan.interruption == null) {
      progression.value = '${bilan.refusees} saisie(s) refusée(s) par le serveur (voir « À envoyer »).';
    } else {
      progression.value = 'Échec : ${bilan.interruption ?? 'Vérifiez votre connexion au serveur.'} Les saisies restent sur l\'appareil.';
    }
    fini.value = true;
    _rappel?.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (mounted) Navigator.of(context).pop();
    if (bilan.sessionExpiree && mounted) proposerReconnexion();
    return bilan.complet;
  }

  /// Session expirée (401 / 403) : message et action « Se reconnecter » ; après la reconnexion, la
  /// file reprend l'envoi interrompu (saisies gardées sur l'appareil).
  void proposerReconnexion() {
    nvMessage(context, 'Session expirée — reconnectez-vous',
        key: const ValueKey('nv-session-expiree'),
        ton: context.nv.erreur,
        duree: const Duration(seconds: 10),
        action: SnackBarAction(label: 'Se reconnecter', onPressed: () => demanderReconnexion(context)));
  }

  /// Rappel d'envoi (mode Collecte), comme l'écran d'origine.
  void relancerRappel() {
    _rappel?.cancel();
    if (config.sendMode == SendMode.collect && config.sendReminderMinutes > 0) {
      final provider = entry;
      _rappel = Timer(Duration(minutes: config.sendReminderMinutes), () {
        if (provider.hasUnsyncedData && mounted) {
          nvMessage(context, 'Rappel : vous avez des données non envoyées !', ton: context.nv.info, duree: const Duration(seconds: 5));
        }
      });
    }
  }

  void arreterRappel() => _rappel?.cancel();

  /// Sécurité de sortie (même règles que l'écran d'origine). Renvoie vrai si l'on peut quitter.
  Future<bool> securiteSortie() async {
    _rappel?.cancel();
    final provider = entry;
    final reste = provider.uncountedProductsCount;
    final nonEnvoye = provider.hasUnsyncedData;
    if (reste == 0 && !nonEnvoye) return true;
    if (config.sendMode == SendMode.direct && reste == 0) return true;
    final r = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final nv = ctx.nv;
        final direct = config.sendMode == SendMode.direct;
        return AlertDialog(
          key: const ValueKey('nv-quitter'),
          title: const Text('Quitter ?'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (nonEnvoye && !direct)
              Text('Des saisies ne sont pas encore envoyées au serveur (elles restent sur l\'appareil).',
                  style: TextStyle(fontWeight: FontWeight.bold, color: nv.erreur.fg)),
            if (reste > 0) ...[
              const SizedBox(height: 8),
              Text('Il reste encore $reste produit(s) jamais touchés dans ce rayon.'),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop('rester'), child: const Text('Rester')),
            if (reste > 0) OutlinedButton(onPressed: () => Navigator.of(ctx).pop('oublis'), child: const Text('Voir les oublis')),
            TextButton(
                key: const ValueKey('nv-quitter-ignorer'),
                onPressed: () => Navigator.of(ctx).pop('quitter'),
                child: Text('Ignorer et quitter', style: TextStyle(color: nv.erreur.fg))),
            if (nonEnvoye && !direct)
              FilledButton(key: const ValueKey('nv-envoyer-quitter'), onPressed: () => Navigator.of(ctx).pop('envoyer'), child: const Text('Envoyer et quitter')),
          ],
        );
      },
    );
    switch (r) {
      case 'quitter':
        return true;
      case 'oublis':
        provider.filterToUncounted();
        return false;
      case 'envoyer':
        final tout = await envoyerInventaire();
        if (!tout && mounted) {
          nvMessage(context, 'Envoi incomplet : les saisies restent sur l\'appareil (« À envoyer »).', ton: context.nv.attente);
        }
        return tout;
      default:
        return false;
    }
  }

  /// Recherche au clavier (au fil de la frappe : liste ; validée : ouvre le produit s'il est seul).
  void surFrappe(String texte) {
    _frappe?.cancel();
    if (texte.isEmpty) {
      setState(() {
        afficherResultats = false;
        resultats = [];
      });
      return;
    }
    _frappe = Timer(const Duration(milliseconds: 500), () => rechercher(texte, auFil: true));
  }

  Future<void> rechercher(String texte, {required bool auFil}) async {
    final q = SaisieInput.nettoyerRecherche(texte);
    if (q.isEmpty) return;
    _frappe?.cancel();
    try {
      final r = await entry.searchProductOnline(api, inventoryId, q);
      if (!mounted) return;
      if (r.isEmpty) {
        if (!auFil) nvMessage(context, 'Produit introuvable.', ton: context.nv.erreur);
        return;
      }
      setState(() {
        resultats = r;
        afficherResultats = true;
      });
      if (!auFil && r.length == 1) {
        champScanCtrl.clear();
        await ouvrirProduitScanne(r.first);
      }
    } catch (e) {
      if (mounted && !auFil) {
        nvMessage(context, messageErreur(e),
            ton: context.nv.erreur,
            action: estSessionExpiree(e) ? SnackBarAction(label: 'Se reconnecter', onPressed: () => demanderReconnexion(context)) : null);
      }
    }
  }

  void choisirResultat(Product p) {
    produitsVus[p.id] = p;
    ouvrirFeuille(p, dejaCompte: dejaCompteConnu(p));
  }
}
