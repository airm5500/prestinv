// lib/saisie/saisie_queue.dart
// File PERSISTANTE des quantités comptées (toutes les saisies : guidée, rapide/scan, écarts, restants).
//
// Règles :
// 1. Toute quantité saisie est écrite sur l'appareil ([enregistrer]) AVANT tout envoi et avant de
//    passer au produit suivant. Une ligne d'inventaire = une saisie : la dernière valeur remplace la
//    précédente (quantité TOTALE, jamais un ajout).
// 2. Envoi idempotent : le serveur reçoit la quantité totale (« quantite = X ») ; renvoyer la même
//    valeur ne crée aucun doublon. Une seule requête en vol par ligne ; une correction faite pendant
//    l'envoi est renvoyée ensuite (numéro de version) — la ligne n'est « envoyée » que si le serveur a
//    confirmé la DERNIÈRE valeur.
// 3. Panne réseau / session expirée : rien n'est perdu, la saisie reste « en attente ». Reprise
//    automatique ([demarrerReprise]) toutes les 15 s en mode Direct (et pour les corrections Écarts /
//    Restants, qui partent toujours tout de suite), au retour au premier plan et après reconnexion.
// 4. Inventaire clôturé : avant d'envoyer, la liste des inventaires ouverts est lue ; une saisie d'un
//    inventaire absent de cette liste n'est PAS envoyée, elle passe en « refusée » (visible dans
//    « À envoyer »).
// 5. Les anciennes saisies non envoyées (clés `inv_<inventaire>_ray_<rayon>_unsynced` des versions
//    précédentes) sont reprises dans la file au premier lancement, sans perte ([migrerAnciennesCles]).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bilan d'un envoi groupé.
class BilanEnvoi {
  final int envoyees;
  final int refusees;
  final int restantes;

  /// Envoi interrompu (serveur injoignable, session expirée…) : message à afficher.
  final String? interruption;
  final bool sessionExpiree;

  const BilanEnvoi({this.envoyees = 0, this.refusees = 0, this.restantes = 0, this.interruption, this.sessionExpiree = false});

  bool get complet => restantes == 0 && interruption == null;
}

class SaisieQueue extends ChangeNotifier {
  final SaisieStore store;
  final DateTime Function() _clock;

  /// Instance de l'application (posée au démarrage ; remplaçable dans les tests).
  static SaisieQueue? instance;

  /// Serveur courant (null : pas connecté ou pas configuré → rien n'est envoyé).
  SaisieServeur? Function()? serveurFactory;

  /// Mode d'envoi Direct (toutes les saisies partent automatiquement) ; sinon seules les saisies
  /// [SaisieLigne.envoiAuto] partent automatiquement.
  bool Function() modeDirect = () => false;

  /// Erreurs serveur (5xx) tolérées avant de passer une saisie en « refusée ».
  static const maxTentatives = 3;

  /// Les saisies envoyées sont gardées 7 jours (historique « À envoyer », export), puis purgées.
  static const conservationEnvoyees = Duration(days: 7);

  /// Durée de validité de la liste des inventaires ouverts lue sur le serveur.
  static const validiteListeOuverts = Duration(seconds: 60);

  static const motifCloture = 'Inventaire clôturé ou supprimé sur le serveur : quantité non envoyée.';

  SaisieQueue({required this.store, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Map<String, SaisieLigne> _lignes = {};
  final Map<String, Future<ReponseEnvoi>> _enVol = {};
  bool _charge = false;
  Future<void>? _chargement;
  Future<BilanEnvoi>? _envoiGroupe;
  String? _derniereErreur;
  bool _sessionExpiree = false;
  InventairesOuverts? _ouverts;
  DateTime? _ouvertsLe;
  Timer? _reprise;
  String? _erreurLecture;

  // ---------------------------------------------------------------------------
  // Lecture de l'état
  // ---------------------------------------------------------------------------

  bool get charge => _charge;

  /// Dernière interruption d'envoi (réseau, session…), null si le dernier envoi est complet.
  String? get derniereErreur => _derniereErreur;

  /// Un envoi a reçu 401/403 : reconnexion nécessaire (la file est conservée).
  bool get sessionExpiree => _sessionExpiree;

  /// Stockage illisible au chargement (le fichier n'est pas effacé).
  String? get erreurLecture => _erreurLecture;

  bool get envoiEnCours => _envoiGroupe != null || _enVol.isNotEmpty;

  List<SaisieLigne> lignes({String? inventaireId}) =>
      _lignes.values.where((s) => inventaireId == null || s.inventaireId == inventaireId).toList()
        ..sort((a, b) => a.modifieLe.compareTo(b.modifieLe));

  SaisieLigne? ligne(String inventaireId, int ligneId) => _lignes[SaisieLigne.cleDe(inventaireId, ligneId)];

  int enAttente({String? inventaireId, String? rayonId}) => _lignes.values
      .where((s) => s.enAttente && (inventaireId == null || s.inventaireId == inventaireId) && (rayonId == null || s.rayonId == rayonId))
      .length;

  int refusees({String? inventaireId}) =>
      _lignes.values.where((s) => s.refusee && (inventaireId == null || s.inventaireId == inventaireId)).length;

  /// Saisies en attente + refusées (tout ce qui n'est pas confirmé par le serveur).
  int aTraiter({String? inventaireId}) => enAttente(inventaireId: inventaireId) + refusees(inventaireId: inventaireId);

  bool estEnAttente(String inventaireId, int ligneId) => ligne(inventaireId, ligneId)?.enAttente ?? false;

  bool estEnVol(String inventaireId, int ligneId) => _enVol.containsKey(SaisieLigne.cleDe(inventaireId, ligneId));

  /// Tout est réellement confirmé par le serveur pour cet inventaire (rien en attente, rien en vol).
  bool estAJour(String inventaireId) =>
      enAttente(inventaireId: inventaireId) == 0 && !_enVol.keys.any((k) => k.startsWith('$inventaireId#'));

  // ---------------------------------------------------------------------------
  // Chargement
  // ---------------------------------------------------------------------------

  Future<void> load({bool force = false}) {
    if (_charge && !force) return Future.value();
    return _chargement ??= _load().whenComplete(() => _chargement = null);
  }

  Future<void> _load() async {
    try {
      final lues = await store.lire();
      _lignes
        ..clear()
        ..addEntries(lues.map((s) => MapEntry(s.cle, s)));
      _erreurLecture = null;
      // Purge des saisies confirmées depuis plus de 7 jours (jamais des saisies en attente / refusées).
      final limite = _clock().subtract(conservationEnvoyees);
      final perimees = _lignes.values.where((s) => s.envoyee && (s.envoyeeLe ?? s.modifieLe).isBefore(limite)).map((s) => s.cle).toList();
      if (perimees.isNotEmpty) {
        perimees.forEach(_lignes.remove);
        await store.remplacerTout(_lignes.values.toList());
      }
    } catch (e) {
      _erreurLecture = 'Saisies enregistrées illisibles : $e';
    }
    _charge = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Saisie
  // ---------------------------------------------------------------------------

  /// Enregistre sur l'appareil la quantité TOTALE [quantite] de la ligne [ligneId]. Le Future se termine
  /// quand la saisie est écrite sur disque. Ne contacte jamais le serveur.
  Future<SaisieLigne> enregistrer({
    required String inventaireId,
    required int ligneId,
    required int quantite,
    String inventaireLibelle = '',
    String cip = '',
    String nom = '',
    String? rayonId,
    String? rayonLibelle,
    OrigineSaisie origine = OrigineSaisie.guidee,
    bool envoiAuto = false,
    String auteur = '',
  }) async {
    if (quantite < 0) throw ArgumentError('quantité négative');
    await load();
    final now = _clock();
    final cle = SaisieLigne.cleDe(inventaireId, ligneId);
    var s = _lignes[cle];
    if (s == null) {
      s = SaisieLigne(
        inventaireId: inventaireId,
        ligneId: ligneId,
        inventaireLibelle: inventaireLibelle,
        cip: cip,
        nom: nom,
        rayonId: rayonId,
        rayonLibelle: rayonLibelle,
        quantite: quantite,
        origine: origine,
        envoiAuto: envoiAuto,
        auteur: auteur,
        creeLe: now,
        modifieLe: now,
      );
      _lignes[cle] = s;
    } else {
      s
        ..quantite = quantite
        ..version = s.version + 1
        ..etat = EtatSaisie.enAttente
        ..motif = null
        ..tentatives = 0
        ..origine = origine
        ..envoiAuto = envoiAuto
        ..modifieLe = now;
      if (inventaireLibelle.isNotEmpty) s.inventaireLibelle = inventaireLibelle;
      if (cip.isNotEmpty) s.cip = cip;
      if (nom.isNotEmpty) s.nom = nom;
      if (rayonId != null) s.rayonId = rayonId;
      if (rayonLibelle != null) s.rayonLibelle = rayonLibelle;
      if (auteur.isNotEmpty) s.auteur = auteur;
    }
    await store.ecrire(s);
    notifyListeners();
    return s;
  }

  /// Saisie refusée remise en attente (action de l'utilisateur dans « À envoyer »).
  Future<void> renvoyer(String cle) async {
    final s = _lignes[cle];
    if (s == null || !s.refusee) return;
    s
      ..etat = EtatSaisie.enAttente
      ..tentatives = 0
      ..motif = null
      ..modifieLe = _clock();
    await store.ecrire(s);
    notifyListeners();
  }

  /// Saisie non confirmée abandonnée (action de l'utilisateur, après confirmation).
  Future<void> abandonner(String cle) async {
    final s = _lignes[cle];
    if (s == null || _enVol.containsKey(cle)) return;
    _lignes.remove(cle);
    await store.supprimer(cle);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Envoi
  // ---------------------------------------------------------------------------

  SaisieServeur? _serveur() {
    try {
      return serveurFactory?.call();
    } catch (_) {
      return null;
    }
  }

  /// Liste des inventaires ouverts (cache de 60 s ; [frais] impose une nouvelle lecture).
  Future<InventairesOuverts?> _lireOuverts(SaisieServeur serveur, {bool frais = false}) async {
    final age = _ouvertsLe == null ? null : _clock().difference(_ouvertsLe!);
    if (!frais && _ouverts != null && age != null && age < validiteListeOuverts) return _ouverts;
    final lus = await serveur.inventairesOuverts();
    if (lus != null) {
      _ouverts = lus;
      _ouvertsLe = _clock();
    }
    return lus;
  }

  /// `true` : ouvert ; `false` : clôturé (certain) ; `null` : impossible à savoir maintenant.
  Future<bool?> _inventaireOuvert(SaisieServeur serveur, String inventaireId) async {
    var ouverts = await _lireOuverts(serveur);
    if (ouverts == null) return null;
    if (ouverts.ids.contains(inventaireId)) return true;
    // Absent d'une liste ancienne : on relit avant de conclure.
    ouverts = await _lireOuverts(serveur, frais: true);
    if (ouverts == null) return null;
    if (ouverts.ids.contains(inventaireId)) return true;
    // Liste vide : le serveur renvoie aussi une liste vide quand sa requête échoue → on ne conclut pas.
    if (ouverts.ids.isEmpty) return null;
    return false;
  }

  Future<void> _marquerCloture(String inventaireId) async {
    for (final s in _lignes.values.where((s) => s.inventaireId == inventaireId && s.enAttente).toList()) {
      s
        ..etat = EtatSaisie.refusee
        ..motif = motifCloture;
      await store.ecrire(s);
    }
    notifyListeners();
  }

  /// Envoie la ligne [cle] jusqu'à ce que le serveur ait confirmé sa DERNIÈRE version.
  /// Une seule requête en vol par ligne : un second appel attend la fin du premier.
  Future<ReponseEnvoi> _envoyerAJour(String cle, SaisieServeur serveur) async {
    for (var tour = 0; tour < 20; tour++) {
      final enVol = _enVol[cle];
      if (enVol != null) {
        await enVol;
        continue;
      }
      final s = _lignes[cle];
      if (s == null) return ReponseEnvoi.ok;
      if (s.envoyee) return ReponseEnvoi.ok;
      if (s.refusee) return ReponseEnvoi(ResultatEnvoi.refus, s.motif ?? 'Refusée');
      final version = s.version;
      final quantite = s.quantite;
      final requete = _poser(serveur, s.ligneId, quantite, auteurServeur: s.origine == OrigineSaisie.versement);
      _enVol[cle] = requete;
      notifyListeners();
      ReponseEnvoi r;
      try {
        r = await requete;
      } finally {
        _enVol.remove(cle);
      }
      final apres = _lignes[cle];
      if (apres == null) return r; // abandonnée entre-temps
      switch (r.type) {
        case ResultatEnvoi.ok:
          apres
            ..quantiteEnvoyee = quantite
            ..tentatives = 0
            ..motif = null;
          if (apres.version == version) {
            apres
              ..etat = EtatSaisie.envoyee
              ..envoyeeLe = _clock();
            await store.ecrire(apres);
            notifyListeners();
            return r;
          }
          // Corrigée pendant l'envoi : on renvoie la nouvelle valeur.
          await store.ecrire(apres);
          continue;
        case ResultatEnvoi.refus:
          if (apres.version == version) {
            apres
              ..etat = EtatSaisie.refusee
              ..motif = r.message;
            await store.ecrire(apres);
            notifyListeners();
            return r;
          }
          continue;
        case ResultatEnvoi.erreurServeur:
          apres.tentatives++;
          apres.motif = r.message;
          if (apres.tentatives >= maxTentatives && apres.version == version) {
            apres.etat = EtatSaisie.refusee;
          }
          await store.ecrire(apres);
          notifyListeners();
          return r;
        case ResultatEnvoi.reseau:
        case ResultatEnvoi.session:
          notifyListeners();
          return r;
      }
    }
    return const ReponseEnvoi(ResultatEnvoi.reseau, 'Trop de corrections successives : nouvel essai plus tard.');
  }

  Future<ReponseEnvoi> _poser(SaisieServeur serveur, int ligneId, int quantite, {bool auteurServeur = false}) async {
    try {
      // Versement de la collecte : route qui enregistre l'auteur (session exigée).
      if (auteurServeur) return await serveur.poserQuantiteSession(ligneId, quantite);
      return await serveur.poserQuantite(ligneId, quantite);
    } catch (e) {
      return ReponseEnvoi(ResultatEnvoi.reseau, 'Erreur réseau : $e');
    }
  }

  /// Envoie tout de suite UNE saisie (corrections Écarts / Restants, mode Direct).
  /// Résultat `ok` seulement si le serveur a confirmé la dernière valeur saisie.
  Future<ReponseEnvoi> envoyerLigne(String inventaireId, int ligneId) async {
    await load();
    final cle = SaisieLigne.cleDe(inventaireId, ligneId);
    final s = _lignes[cle];
    if (s == null) return ReponseEnvoi.ok;
    if (s.envoyee) return ReponseEnvoi.ok;
    final serveur = _serveur();
    if (serveur == null) return const ReponseEnvoi(ResultatEnvoi.session, 'Non connecté au serveur.');
    final ouvert = await _inventaireOuvert(serveur, inventaireId);
    if (ouvert == null) {
      return const ReponseEnvoi(ResultatEnvoi.reseau, 'Serveur injoignable : impossible de vérifier l\'inventaire.');
    }
    if (!ouvert) {
      await _marquerCloture(inventaireId);
      return const ReponseEnvoi(ResultatEnvoi.refus, motifCloture);
    }
    final r = await _envoyerAJour(cle, serveur);
    _noterResultat(r);
    return r;
  }

  void _noterResultat(ReponseEnvoi r) {
    if (r.type == ResultatEnvoi.session) _sessionExpiree = true;
    if (r.type == ResultatEnvoi.ok) _sessionExpiree = false;
    if (r.type == ResultatEnvoi.reseau || r.type == ResultatEnvoi.session) _derniereErreur = r.message;
    notifyListeners();
  }

  /// Envoie les saisies en attente (d'un inventaire, ou toutes), dans l'ordre de saisie.
  /// Un seul envoi groupé à la fois : un second appel attend le premier puis repart.
  Future<BilanEnvoi> envoyer({String? inventaireId, bool seulementAuto = false, void Function(int fait, int total)? onProgress}) async {
    while (_envoiGroupe != null) {
      await _envoiGroupe;
    }
    final f = _envoyer(inventaireId: inventaireId, seulementAuto: seulementAuto, onProgress: onProgress);
    _envoiGroupe = f;
    notifyListeners();
    try {
      return await f;
    } finally {
      _envoiGroupe = null;
      notifyListeners();
    }
  }

  Future<BilanEnvoi> _envoyer({String? inventaireId, required bool seulementAuto, void Function(int, int)? onProgress}) async {
    await load();
    List<SaisieLigne> aEnvoyer() => lignes(inventaireId: inventaireId).where((s) => s.enAttente && (!seulementAuto || s.envoiAuto)).toList();
    var candidates = aEnvoyer();
    if (candidates.isEmpty) return const BilanEnvoi();
    final serveur = _serveur();
    if (serveur == null) {
      return BilanEnvoi(restantes: candidates.length, interruption: 'Non connecté au serveur : saisies gardées sur l\'appareil.');
    }

    // Inventaires clôturés : rien n'est envoyé, les saisies passent en « refusées ».
    var refusees = 0;
    for (final inv in candidates.map((s) => s.inventaireId).toSet()) {
      final ouvert = await _inventaireOuvert(serveur, inv);
      if (ouvert == null) {
        const msg = 'Serveur injoignable : saisies gardées sur l\'appareil, nouvel essai automatique.';
        _derniereErreur = msg;
        notifyListeners();
        return BilanEnvoi(restantes: candidates.length, interruption: msg);
      }
      if (!ouvert) {
        refusees += candidates.where((s) => s.inventaireId == inv).length;
        await _marquerCloture(inv);
      }
    }
    candidates = aEnvoyer();
    final total = candidates.length;
    var envoyees = 0;
    String? interruption;
    var session = false;
    for (final s in candidates) {
      if (!s.enAttente) continue;
      final r = await _envoyerAJour(s.cle, serveur);
      switch (r.type) {
        case ResultatEnvoi.ok:
          envoyees++;
          onProgress?.call(envoyees, total);
        case ResultatEnvoi.refus:
          refusees++;
        case ResultatEnvoi.erreurServeur:
          if (_lignes[s.cle]?.refusee ?? false) refusees++;
        case ResultatEnvoi.reseau:
          interruption = r.message.isEmpty ? 'Serveur injoignable.' : r.message;
        case ResultatEnvoi.session:
          interruption = 'Session expirée : reconnectez-vous (les saisies sont gardées sur l\'appareil).';
          session = true;
      }
      if (interruption != null) break;
    }
    _derniereErreur = interruption;
    if (session) {
      _sessionExpiree = true;
    } else if (interruption == null) {
      _sessionExpiree = false;
    }
    final restantes = aEnvoyer().length;
    notifyListeners();
    return BilanEnvoi(envoyees: envoyees, refusees: refusees, restantes: restantes, interruption: interruption, sessionExpiree: session);
  }

  /// Envoi automatique (mode Direct : tout ; sinon : corrections Écarts / Restants seulement).
  /// Ne fait rien si un envoi groupé est déjà en cours ou si rien n'est à envoyer.
  Future<void> relancer() async {
    if (_envoiGroupe != null) return;
    await load();
    final direct = modeDirect();
    final aEnvoyer = _lignes.values.any((s) => s.enAttente && (direct || s.envoiAuto));
    if (!aEnvoyer || _serveur() == null) return;
    await envoyer(seulementAuto: !direct);
  }

  /// Reprise automatique périodique (au retour du réseau, la file repart d'elle-même).
  void demarrerReprise({Duration intervalle = const Duration(seconds: 15)}) {
    _reprise?.cancel();
    _reprise = Timer.periodic(intervalle, (_) => relancer());
  }

  void arreterReprise() {
    _reprise?.cancel();
    _reprise = null;
  }

  /// Après une reconnexion réussie : la file repart.
  void signalerReconnexion() {
    _sessionExpiree = false;
    _derniereErreur = null;
    notifyListeners();
    unawaited(relancer());
  }

  @override
  void dispose() {
    arreterReprise();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Reprise des saisies des versions précédentes
  // ---------------------------------------------------------------------------

  static final RegExp _ancienneCle = RegExp(r'^inv_(.+?)_ray_(.+)_unsynced$');

  /// Reprend dans la file les saisies non envoyées gardées par les versions précédentes
  /// (`inv_<inventaire>_ray_<rayon>_unsynced`, une liste JSON de produits par rayon).
  /// Les anciennes clés ne sont supprimées qu'APRÈS relecture et vérification de la file.
  /// Renvoie le nombre de saisies reprises.
  Future<int> migrerAnciennesCles({SharedPreferences? prefs}) async {
    await load();
    final SharedPreferences p;
    try {
      p = prefs ?? await SharedPreferences.getInstance();
    } catch (_) {
      return 0;
    }
    var reprises = 0;
    final aVerifier = <String, Map<String, int>>{}; // clé ancienne -> {clé saisie: quantité}
    for (final cle in p.getKeys().toList()) {
      final m = _ancienneCle.firstMatch(cle);
      if (m == null) continue;
      final inv = m.group(1)!;
      final rayon = m.group(2)!;
      final brut = p.getString(cle);
      if (brut == null) {
        await p.remove(cle);
        continue;
      }
      final List<dynamic> liste;
      try {
        liste = json.decode(brut) as List<dynamic>;
      } catch (e) {
        if (kDebugMode) debugPrint('Saisies : ancienne clé illisible gardée ($cle)');
        continue;
      }
      final attendues = <String, int>{};
      for (final brutP in liste) {
        if (brutP is! Map) continue;
        final id = brutP['id'];
        final q = brutP['quantiteSaisie'];
        if (id is! num || q is! num) continue;
        if (brutP['isSynced'] == true) continue;
        final cleSaisie = SaisieLigne.cleDe(inv, id.toInt());
        final existante = _lignes[cleSaisie];
        if (existante != null) {
          attendues[cleSaisie] = existante.quantite;
          continue;
        }
        final now = _clock();
        final s = SaisieLigne(
          inventaireId: inv,
          ligneId: id.toInt(),
          cip: '${brutP['produitCip'] ?? ''}',
          nom: '${brutP['produitName'] ?? ''}',
          rayonId: rayon,
          rayonLibelle: brutP['locationLabel'] as String?,
          quantite: q.toInt() < 0 ? 0 : q.toInt(),
          origine: OrigineSaisie.migration,
          creeLe: now,
          modifieLe: now,
        );
        _lignes[cleSaisie] = s;
        await store.ecrire(s);
        attendues[cleSaisie] = s.quantite;
        reprises++;
      }
      aVerifier[cle] = attendues;
    }
    if (aVerifier.isEmpty) return 0;
    // Relecture du stockage : on ne supprime une ancienne clé que si toutes ses saisies y sont.
    List<SaisieLigne> relues;
    try {
      relues = await store.lire();
    } catch (_) {
      return reprises;
    }
    final parCle = {for (final s in relues) s.cle: s};
    for (final e in aVerifier.entries) {
      final ok = e.value.entries.every((a) => parCle[a.key]?.quantite == a.value);
      if (ok) await p.remove(e.key);
    }
    notifyListeners();
    return reprises;
  }
}
