// lib/collecte/versement.dart
// VERSEMENT de la collecte hors ligne dans un inventaire OUVERT.
//
// 1. Correspondance : toutes les lignes de l'inventaire sont lues en UNE requête (detailsAll sans
//    filtre) ; un code collecté égal à un CIP de l'inventaire est trouvé sans autre appel. Sinon, chaque
//    variante du code (CodeScan : EAN-13 34009 → CIP7, GTIN, DataMatrix, UPC-A) est cherchée par le
//    serveur (detailsAll?query=, qui reconnaît aussi l'EAN-13, l'EAN fabricant et le code article
//    grossiste) ; une correspondance seulement partielle (début de CIP) est refusée.
//    Deux codes du même produit (CIP et EAN) sont regroupés : leurs quantités s'additionnent.
// 2. Quantité TOTALE envoyée (jamais « + X ») : si la ligne est déjà comptée (sur le serveur ou dans une
//    saisie encore sur l'appareil), selon le choix fait au début : Remplacer (quantité collectée) ou
//    Ajouter (déjà compté + collecté). Cette quantité est calculée UNE fois et gardée avant l'envoi :
//    une reprise après coupure renvoie la même valeur (aucun doublon, même en « Ajouter »).
// 3. Envoi par la file persistante des saisies (écrite sur disque avant l'envoi, envoi idempotent,
//    reprise automatique), par la route qui enregistre l'auteur (POST /inventaire/ligne/quantite).
// 4. Rapport : versés, déjà comptés (remplacés / ajoutés), codes non reconnus (code, quantité, raison),
//    erreurs. Une ligne de la collecte n'est marquée « versée » qu'une fois confirmée par le serveur ;
//    les lignes en erreur restent à reverser. Annulation sûre : ce qui est envoyé reste envoyé, le reste
//    reprend plus tard (« Reprendre le versement »).
import 'dart:convert';

import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ligne déjà comptée dans l'inventaire : que faire de la quantité collectée ?
enum ModeDejaCompte {
  remplacer('Remplacer', 'la quantité collectée remplace la quantité déjà comptée'),
  ajouter('Ajouter', 'la quantité collectée s\'ajoute à la quantité déjà comptée');

  final String libelle;
  final String aide;
  const ModeDejaCompte(this.libelle, this.aide);
}

enum EtatLigneVersement {
  /// Pas encore traitée (ou à reprendre).
  aVerser,

  /// Confirmée par le serveur.
  versee,

  /// Aucun produit de l'inventaire ne correspond (ou plusieurs) : rien n'est envoyé.
  nonReconnue,

  /// Envoi refusé ou impossible : à reverser.
  erreur,

  /// Regroupée avec une autre ligne du même produit (sa quantité y est ajoutée).
  regroupee,
}

enum StatutVersement { enCours, interrompu, termine }

class LigneVersement {
  /// Code collecté (tel que scanné).
  final String code;

  /// Quantité collectée (somme des scans de ce code).
  int quantiteCollectee;

  /// Codes collectés regroupés dans cette ligne (même produit), y compris [code].
  final List<String> codes;

  EtatLigneVersement etat;
  int? ligneId;
  String cip;
  String nom;

  /// Quantité déjà comptée au moment du versement (null : jamais comptée).
  int? quantiteExistante;

  /// Quantité TOTALE à poser, calculée une seule fois (reprise sans doublon).
  int? quantiteCible;

  /// Raison (non reconnue / erreur).
  String? raison;
  DateTime? verseeLe;

  LigneVersement({
    required this.code,
    required this.quantiteCollectee,
    List<String>? codes,
    this.etat = EtatLigneVersement.aVerser,
    this.ligneId,
    this.cip = '',
    this.nom = '',
    this.quantiteExistante,
    this.quantiteCible,
    this.raison,
    this.verseeLe,
  }) : codes = codes ?? [code];

  bool get dejaComptee => quantiteExistante != null;

  Map<String, dynamic> toJson() => {
        'code': code,
        'q': quantiteCollectee,
        'codes': codes,
        'etat': etat.name,
        'ligne': ligneId,
        'cip': cip,
        'nom': nom,
        'qExist': quantiteExistante,
        'qCible': quantiteCible,
        'raison': raison,
        'verseeLe': verseeLe?.toIso8601String(),
      };

  factory LigneVersement.fromJson(Map<String, dynamic> j) => LigneVersement(
        code: '${j['code']}',
        quantiteCollectee: (j['q'] as num).toInt(),
        codes: (j['codes'] as List?)?.map((e) => '$e').toList(),
        etat: EtatLigneVersement.values.where((e) => e.name == j['etat']).firstOrNull ?? EtatLigneVersement.aVerser,
        ligneId: (j['ligne'] as num?)?.toInt(),
        cip: '${j['cip'] ?? ''}',
        nom: '${j['nom'] ?? ''}',
        quantiteExistante: (j['qExist'] as num?)?.toInt(),
        quantiteCible: (j['qCible'] as num?)?.toInt(),
        raison: j['raison'] as String?,
        verseeLe: j['verseeLe'] == null ? null : DateTime.tryParse('${j['verseeLe']}'),
      );
}

/// Un versement (et son rapport).
class Versement {
  final String id;
  final String inventaireId;
  final String inventaireLibelle;
  final ModeDejaCompte mode;
  final DateTime debut;
  DateTime? fin;
  StatutVersement statut;
  String? interruption;
  final List<LigneVersement> lignes;

  Versement({
    required this.id,
    required this.inventaireId,
    required this.inventaireLibelle,
    required this.mode,
    required this.debut,
    this.fin,
    this.statut = StatutVersement.enCours,
    this.interruption,
    required this.lignes,
  });

  Iterable<LigneVersement> _en(EtatLigneVersement e) => lignes.where((l) => l.etat == e);

  List<LigneVersement> get versees => _en(EtatLigneVersement.versee).toList();
  List<LigneVersement> get nouvelles => versees.where((l) => !l.dejaComptee).toList();
  List<LigneVersement> get remplacees => mode == ModeDejaCompte.remplacer ? versees.where((l) => l.dejaComptee).toList() : const [];
  List<LigneVersement> get ajoutees => mode == ModeDejaCompte.ajouter ? versees.where((l) => l.dejaComptee).toList() : const [];
  List<LigneVersement> get nonReconnues => _en(EtatLigneVersement.nonReconnue).toList();
  List<LigneVersement> get erreurs => _en(EtatLigneVersement.erreur).toList();
  List<LigneVersement> get aVerser => _en(EtatLigneVersement.aVerser).toList();

  /// Lignes à (re)traiter : pas encore versées, en erreur.
  List<LigneVersement> get aReprendre => lignes.where((l) => l.etat == EtatLigneVersement.aVerser || l.etat == EtatLigneVersement.erreur).toList();

  /// Tout ce qui pouvait être versé l'a été (aucune ligne à verser ni en erreur).
  bool get complet => aReprendre.isEmpty;

  int get total => lignes.where((l) => l.etat != EtatLigneVersement.regroupee).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'inv': inventaireId,
        'invLib': inventaireLibelle,
        'mode': mode.name,
        'debut': debut.toIso8601String(),
        'fin': fin?.toIso8601String(),
        'statut': statut.name,
        'interruption': interruption,
        'lignes': lignes.map((l) => l.toJson()).toList(),
      };

  factory Versement.fromJson(Map<String, dynamic> j) => Versement(
        id: '${j['id']}',
        inventaireId: '${j['inv']}',
        inventaireLibelle: '${j['invLib'] ?? ''}',
        mode: ModeDejaCompte.values.where((m) => m.name == j['mode']).firstOrNull ?? ModeDejaCompte.remplacer,
        debut: DateTime.tryParse('${j['debut']}') ?? DateTime.now(),
        fin: j['fin'] == null ? null : DateTime.tryParse('${j['fin']}'),
        statut: StatutVersement.values.where((s) => s.name == j['statut']).firstOrNull ?? StatutVersement.interrompu,
        interruption: j['interruption'] as String?,
        lignes: [for (final l in (j['lignes'] as List? ?? const [])) LigneVersement.fromJson(Map<String, dynamic>.from(l as Map))],
      );

  /// Prépare un versement des lignes NON versées de la collecte (regroupées par code).
  factory Versement.depuisCollecte(List<CollectedItem> collecte,
      {required String inventaireId, required String inventaireLibelle, required ModeDejaCompte mode, DateTime? maintenant}) {
    final parCode = <String, LigneVersement>{};
    for (final i in collecte.where((i) => !i.versee)) {
      final code = CodeScan.nettoyer(i.code);
      if (code.isEmpty) continue;
      final l = parCode.putIfAbsent(code, () => LigneVersement(code: code, quantiteCollectee: 0));
      l.quantiteCollectee += i.quantity;
    }
    final t = maintenant ?? DateTime.now();
    return Versement(
      id: 'V${t.microsecondsSinceEpoch}',
      inventaireId: inventaireId,
      inventaireLibelle: inventaireLibelle,
      mode: mode,
      debut: t,
      lignes: parCode.values.toList(),
    );
  }
}

/// Versements gardés sur l'appareil (rapports consultables, reprise après coupure).
class StockageVersements {
  StockageVersements._();

  static const String cle = 'versements_v1';

  /// Rapports gardés (les plus anciens au-delà sont oubliés ; jamais un versement inachevé).
  static const int maxGardes = 30;

  static Future<List<Versement>> lire() async {
    final prefs = await SharedPreferences.getInstance();
    final brut = prefs.getString(cle);
    if (brut == null) return [];
    final out = <Versement>[];
    try {
      for (final v in json.decode(brut) as List<dynamic>) {
        try {
          out.add(Versement.fromJson(Map<String, dynamic>.from(v as Map)));
        } catch (_) {}
      }
    } catch (_) {}
    out.sort((a, b) => b.debut.compareTo(a.debut));
    return out;
  }

  /// Enregistre (ajoute ou remplace) un versement.
  static Future<void> ecrire(Versement v) async {
    final tous = await lire();
    tous.removeWhere((x) => x.id == v.id);
    tous.insert(0, v);
    var gardes = tous;
    if (tous.length > maxGardes) {
      final inacheves = tous.where((x) => !x.complet).toList();
      final acheves = tous.where((x) => x.complet).take((maxGardes - inacheves.length).clamp(0, maxGardes)).toList();
      gardes = [...inacheves, ...acheves]..sort((a, b) => b.debut.compareTo(a.debut));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cle, json.encode(gardes.map((x) => x.toJson()).toList()));
  }

  /// Dernier versement inachevé (à reprendre), s'il y en a un.
  static Future<Versement?> aReprendre() async => (await lire()).where((v) => !v.complet).firstOrNull;
}

/// Avancement d'un versement.
class AvancementVersement {
  final int fait;
  final int total;
  final String etape;
  const AvancementVersement(this.fait, this.total, this.etape);
  double get fraction => total == 0 ? 0 : fait / total;
}

class MoteurVersement {
  final ApiService api;
  final SaisieQueue queue;
  final String auteur;

  /// Ligne versée (confirmée) : la collecte la marque « versée ».
  final Future<void> Function(LigneVersement l, Versement v)? surLigneVersee;

  /// Enregistre l'état du versement (après chaque ligne) — par défaut [StockageVersements.ecrire].
  final Future<void> Function(Versement v) enregistrer;

  final DateTime Function() _horloge;

  MoteurVersement({
    required this.api,
    required this.queue,
    this.auteur = '',
    this.surLigneVersee,
    Future<void> Function(Versement v)? enregistrer,
    DateTime Function()? horloge,
  })  : enregistrer = enregistrer ?? StockageVersements.ecrire,
        _horloge = horloge ?? DateTime.now;

  bool _annule = false;

  /// Annulation sûre : la ligne en cours se termine, le reste attend une reprise.
  void annuler() => _annule = true;

  /// Correspondance d'un code dans les lignes de l'inventaire. Renvoie (produit, raison si non reconnu).
  Future<(Product?, String?)> _correspondance(String code, String inventaireId, Map<String, List<Product>> parCip) async {
    final candidats = CodeScan.candidats(code);
    if (candidats.isEmpty) return (null, 'code vide');
    for (final c in candidats) {
      final memes = parCip[c];
      if (memes != null && memes.length == 1) return (memes.first, null);
      if (memes != null && memes.length > 1) return (null, 'plusieurs lignes pour le CIP $c');
    }
    // Pas de CIP identique : recherche serveur (EAN-13, EAN fabricant, code article…).
    final possibles = <int, Product>{};
    for (final c in candidats) {
      final r = await api.fetchProducts(inventaireId, null, query: c); // ApiLoadException : remontée
      final exacts = r.where((p) => p.produitCip.trim() == c).toList();
      if (exacts.length == 1) return (exacts.first, null);
      // Un seul produit, trouvé par un autre code que le début de son CIP (EAN côté serveur) : c'est lui.
      if (r.length == 1 && !r.first.produitCip.startsWith(c)) return (r.first, null);
      for (final p in r) {
        possibles[p.id] = p;
      }
    }
    if (possibles.length > 1) {
      return (null, 'plusieurs produits possibles (${possibles.values.take(3).map((p) => p.produitCip).join(', ')}${possibles.length > 3 ? '…' : ''})');
    }
    if (possibles.length == 1) return (null, 'correspondance partielle seulement (${possibles.values.first.produitCip})');
    return (null, 'introuvable dans cet inventaire');
  }

  /// Exécute (ou reprend) le versement [v]. Ne lève pas : une panne interrompt le versement
  /// ([Versement.interruption]), ce qui reste reprendra plus tard.
  Future<Versement> executer(Versement v, {void Function(AvancementVersement a)? onAvancement}) async {
    _annule = false;
    v
      ..statut = StatutVersement.enCours
      ..interruption = null;
    await enregistrer(v);
    final aTraiter = v.aReprendre;
    final total = aTraiter.length;
    var fait = 0;
    void avancer(String etape) => onAvancement?.call(AvancementVersement(fait, total, etape));

    // 1. Lignes de l'inventaire (une seule requête).
    avancer('Lecture des lignes de l\'inventaire…');
    final Map<String, List<Product>> parCip = {};
    final Map<int, Product> parId = {};
    try {
      for (final p in await api.fetchProducts(v.inventaireId, null)) {
        parCip.putIfAbsent(p.produitCip.trim(), () => []).add(p);
        parId[p.id] = p;
      }
    } on ApiLoadException catch (e) {
      return _interrompre(v, 'Lignes de l\'inventaire non lues : ${e.message}');
    }

    // 2. Correspondance de chaque code (sans rien envoyer).
    for (final l in aTraiter) {
      if (_annule) return _interrompre(v, 'Versement annulé : le reste est à reprendre.');
      if (l.ligneId != null) continue; // déjà trouvée (reprise)
      avancer('Recherche du code ${CodeScan.affichage(l.code)}…');
      try {
        final (p, raison) = await _correspondance(l.code, v.inventaireId, parCip);
        if (p == null) {
          l
            ..etat = EtatLigneVersement.nonReconnue
            ..raison = raison;
        } else {
          l
            ..ligneId = p.id
            ..cip = p.produitCip
            ..nom = p.produitName
            ..raison = null;
          parId[p.id] = p;
        }
      } on ApiLoadException catch (e) {
        await enregistrer(v);
        return _interrompre(v, 'Recherche impossible : ${e.message}');
      }
      await enregistrer(v);
    }

    // Regroupement : plusieurs codes pour le même produit → une seule ligne (quantités additionnées).
    final parLigne = <int, LigneVersement>{};
    for (final l in v.lignes) {
      if (l.ligneId == null || l.etat == EtatLigneVersement.regroupee || l.etat == EtatLigneVersement.nonReconnue) continue;
      final premiere = parLigne[l.ligneId!];
      if (premiere == null) {
        parLigne[l.ligneId!] = l;
      } else if (premiere.quantiteCible == null && l.quantiteCible == null && premiere.etat != EtatLigneVersement.versee && l.etat != EtatLigneVersement.versee) {
        premiere
          ..quantiteCollectee += l.quantiteCollectee
          ..codes.addAll(l.codes.where((c) => !premiere.codes.contains(c)));
        l
          ..etat = EtatLigneVersement.regroupee
          ..raison = 'regroupée avec ${CodeScan.affichage(premiere.code)} (même produit)';
      }
    }
    await enregistrer(v);

    // 3. Envoi (quantité TOTALE, par la file persistante).
    final aEnvoyer = v.aReprendre.where((l) => l.ligneId != null).toList();
    fait = total - aEnvoyer.length;
    for (final l in aEnvoyer) {
      if (_annule) return _interrompre(v, 'Versement annulé : ce qui est envoyé reste envoyé, le reste est à reprendre.');
      avancer(l.nom.isEmpty ? l.cip : l.nom);
      final ligneId = l.ligneId!;
      final locale = queue.ligne(v.inventaireId, ligneId);

      // Quantité TOTALE calculée une seule fois (une reprise renvoie la même valeur).
      if (l.quantiteCible == null) {
        final p = parId[ligneId];
        int? existante;
        if (locale != null && locale.enAttente) {
          existante = locale.quantite; // saisie encore sur l'appareil : plus récente que le serveur
        } else if (p != null && p.dtUpdated != null) {
          existante = p.quantiteSaisie;
        } else if (locale != null && locale.envoyee) {
          existante = locale.quantite;
        }
        final cible = v.mode == ModeDejaCompte.ajouter ? (existante ?? 0) + l.quantiteCollectee : l.quantiteCollectee;
        l
          ..quantiteExistante = existante
          ..quantiteCible = cible;
        await enregistrer(v);
      }
      final cible = l.quantiteCible!;
      if (cible > SaisieInput.maxQuantite) {
        l
          ..etat = EtatLigneVersement.erreur
          ..raison = 'total $cible au-delà de ${SaisieInput.maxQuantite}';
        await enregistrer(v);
        fait++;
        continue;
      }

      // Déjà confirmée par le serveur (coupure juste après l'envoi) : rien n'est renvoyé.
      ReponseEnvoi r;
      if (locale != null && locale.envoyee && locale.quantiteEnvoyee == cible && locale.origine == OrigineSaisie.versement) {
        r = ReponseEnvoi.ok;
      } else {
        if (!(locale != null && locale.enAttente && locale.quantite == cible)) {
          await queue.enregistrer(
            inventaireId: v.inventaireId,
            ligneId: ligneId,
            quantite: cible,
            inventaireLibelle: v.inventaireLibelle,
            cip: l.cip,
            nom: l.nom,
            origine: OrigineSaisie.versement,
            envoiAuto: true, // si l'envoi échoue, la file le reprend seule
            auteur: auteur,
          );
        }
        r = await queue.envoyerLigne(v.inventaireId, ligneId);
      }
      fait++;
      switch (r.type) {
        case ResultatEnvoi.ok:
          l
            ..etat = EtatLigneVersement.versee
            ..raison = null
            ..verseeLe = _horloge();
          await enregistrer(v);
          await surLigneVersee?.call(l, v);
        case ResultatEnvoi.refus:
        case ResultatEnvoi.erreurServeur:
          l
            ..etat = EtatLigneVersement.erreur
            ..raison = r.message;
          await enregistrer(v);
        case ResultatEnvoi.reseau:
        case ResultatEnvoi.session:
          l
            ..etat = EtatLigneVersement.erreur
            ..raison = '${r.message} — gardée sur l\'appareil, envoi automatique au retour du réseau';
          await enregistrer(v);
          return _interrompre(v, r.type == ResultatEnvoi.session ? 'Session expirée : reconnectez-vous puis reprenez le versement.' : r.message);
      }
    }
    avancer('Terminé');
    v
      ..statut = v.complet ? StatutVersement.termine : StatutVersement.interrompu
      ..fin = _horloge();
    await enregistrer(v);
    return v;
  }

  Future<Versement> _interrompre(Versement v, String raison) async {
    v
      ..statut = StatutVersement.interrompu
      ..interruption = raison
      ..fin = _horloge();
    await enregistrer(v);
    return v;
  }
}
