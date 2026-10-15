// lib/inventaire/creation_inventaire.dart
// Création d'un inventaire DEPUIS LE TERMINAL, par la route existante du serveur
// (POST /inventaire/creation, voir ApiService.creerInventaire).
//
// - Libellé contrôlé : obligatoire, 3 à 100 caractères, caractères sûrs (lettres, chiffres, espace et
//   ponctuation simple) ; espaces en trop retirés.
// - Anti double création : une seule création à la fois ; un libellé déjà porté par un inventaire OUVERT
//   est refusé (proposé à l'ouverture) ; si la réponse du serveur se perd (réseau, délai), la liste des
//   inventaires ouverts est relue avant toute nouvelle tentative : l'inventaire n'est jamais créé deux fois
//   par un double appui ou une nouvelle tentative.
// - Identifiant du nouvel inventaire : `lgInventaireId` de la réponse (serveurs récents, demande 20) ;
//   sinon il est retrouvé dans la liste des inventaires ouverts (le plus récent portant ce libellé).
// - 4.15, DEPUIS LA COLLECTE ([CreationInventaire.creerDepuisCollecte]) : l'inventaire ne contient que les
//   produits collectés, sur leurs emplacements (voir lib/inventaire/produits_collecte.dart).
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/inventaire/produits_collecte.dart';
import 'package:prestinv/models/inventory.dart';

/// Types acceptés par le serveur (str_TYPE_TRANSACTION). Sans valeurs choisies, les trois donnent le
/// même contenu (tous les produits actifs) : le type ne sert qu'au classement dans Prestige.
enum TypeInventaire {
  emplacement('Emplacement', 'Par emplacement (rayon)'),
  famille('Famille', 'Par famille de produits'),
  grossiste('Grossiste', 'Par grossiste');

  /// Valeur envoyée au serveur.
  final String valeur;
  final String libelle;
  const TypeInventaire(this.valeur, this.libelle);
}

class LibelleInventaire {
  LibelleInventaire._();

  static const int min = 3;
  static const int max = 100;

  /// Lettres (accents compris), chiffres, espace et ponctuation simple. Refusés : < > " ; \ ` { } | $ % …
  static final RegExp _sur = RegExp(r"^[\p{L}\p{N} .,'’()/_#&+°:-]+$", unicode: true);

  /// Espaces de début / fin retirés, espaces multiples réduits.
  static String normaliser(String? texte) => (texte ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Clé de comparaison (doublons) : sans casse ni espaces en trop.
  static String cle(String texte) => normaliser(texte).toLowerCase();

  static String? erreur(String? texte) {
    final t = normaliser(texte);
    if (t.isEmpty) return 'Libellé obligatoire.';
    if (t.length < min) return 'Libellé trop court ($min caractères au moins).';
    if (t.length > max) return 'Libellé trop long ($max caractères au plus).';
    if (!_sur.hasMatch(t)) return 'Caractères non autorisés : lettres, chiffres, espace et . , \' ( ) / _ # & + ° : - seulement.';
    if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(t)) return 'Le libellé doit contenir des lettres ou des chiffres.';
    return null;
  }
}

enum IssueCreation {
  /// Inventaire créé (et retrouvé dans la liste).
  creee,

  /// Un inventaire ouvert porte déjà ce libellé : rien n'est créé.
  doublon,

  /// Libellé invalide : rien n'est envoyé.
  libelleInvalide,

  /// Une création est déjà en cours (double appui).
  dejaEnCours,

  /// Refus du serveur (message du serveur).
  refus,

  /// Session expirée.
  session,

  /// Serveur injoignable avant l'envoi : rien n'a été créé.
  reseau,

  /// Pas de réponse après l'envoi, et l'inventaire n'apparaît pas (encore) : à vérifier avant de réessayer.
  incertaine,

  /// 4.15 — Depuis la collecte : inventaire créé, mais les produits collectés n'y sont pas encore retenus
  /// (réseau, session) : [CreationInventaire.retenir] à refaire (sans rien recréer).
  produitsNonAjoutes,
}

class ResultatCreation {
  final IssueCreation issue;
  final Inventory? inventaire;
  final int? lignes;
  final String message;

  /// 4.15 — Depuis la collecte : lignes retenues (produits collectés mis dans l'inventaire) ; null :
  /// serveur qui ne sait pas retenir (l'inventaire contient tous les produits de ces emplacements).
  final int? retenus;
  const ResultatCreation(this.issue, {this.inventaire, this.lignes, this.message = '', this.retenus});

  bool get ok => issue == IssueCreation.creee;
}

class CreationInventaire {
  /// 4.15.1 (décision du pharmacien) : serveur sans `POST /inventaire/lignes/retenue` → création depuis la
  /// collecte REFUSÉE (plus jamais un inventaire avec tous les produits des emplacements).
  static const messageServeurAncien = 'Ce serveur Prestige ne permet pas encore de créer un inventaire limité aux '
      'produits scannés. Mettez le serveur à jour ou versez la collecte dans un inventaire existant.';

  final ApiService api;
  CreationInventaire(this.api);

  bool _enCours = false;
  bool get enCours => _enCours;

  static Inventory? _trouver(List<Inventory> ouverts, String libelle) {
    final c = LibelleInventaire.cle(libelle);
    for (final i in ouverts) {
      if (LibelleInventaire.cle(i.libelle) == c) return i; // liste triée du plus récent au plus ancien
    }
    return null;
  }

  /// [valeurs] : identifiants choisis sur l'axe du type (pour « Emplacement » : les rayons). Absent :
  /// tous les produits actifs. [nonRetenues] : lignes créées non retenues (voir [creerDepuisCollecte]).
  Future<ResultatCreation> creer(String libelleSaisi, TypeInventaire type, {List<String>? valeurs, bool nonRetenues = false}) async {
    final erreur = LibelleInventaire.erreur(libelleSaisi);
    if (erreur != null) return ResultatCreation(IssueCreation.libelleInvalide, message: erreur);
    if (_enCours) return const ResultatCreation(IssueCreation.dejaEnCours, message: 'Création déjà en cours : patientez.');
    _enCours = true;
    try {
      return await _creer(LibelleInventaire.normaliser(libelleSaisi), type, valeurs: valeurs, nonRetenues: nonRetenues);
    } finally {
      _enCours = false;
    }
  }

  Future<ResultatCreation> _creer(String libelle, TypeInventaire type, {List<String>? valeurs, bool nonRetenues = false}) async {
    // 1. Doublon parmi les inventaires ouverts (et serveur joignable avant d'envoyer quoi que ce soit).
    final List<Inventory> avant;
    try {
      avant = await api.fetchTousInventairesOuverts();
    } on ApiLoadException catch (e) {
      return ResultatCreation(e.sessionExpiree ? IssueCreation.session : IssueCreation.reseau, message: e.message);
    }
    final existant = _trouver(avant, libelle);
    if (existant != null) {
      return ResultatCreation(IssueCreation.doublon,
          inventaire: existant, message: 'Un inventaire ouvert s\'appelle déjà « ${existant.libelle} ».');
    }

    // 2. Création.
    final r = await api.creerInventaire(libelle, type.valeur, valeurs: valeurs, nonRetenues: nonRetenues);
    if (r.session) return ResultatCreation(IssueCreation.session, message: r.message);
    if (!r.succes && !r.incertain) return ResultatCreation(IssueCreation.refus, message: r.message);
    // Identifiant donné par le serveur (demande 20) : pas besoin de relire la liste.
    if (r.succes && r.inventaireId != null) {
      return ResultatCreation(IssueCreation.creee, inventaire: Inventory(id: r.inventaireId!, libelle: libelle), lignes: r.lignes);
    }

    // 3. Identifiant : relu dans la liste (aussi quand la réponse s'est perdue).
    List<Inventory> apres;
    try {
      apres = await api.fetchTousInventairesOuverts();
    } on ApiLoadException catch (e) {
      return ResultatCreation(r.succes ? IssueCreation.creee : IssueCreation.incertaine,
          lignes: r.lignes,
          message: r.succes
              ? 'Inventaire créé ; liste non relue (${e.message}).'
              : 'Pas de réponse du serveur (${r.message}). Vérifiez la liste des inventaires avant de réessayer.');
    }
    final cree = _trouver(apres, libelle);
    if (cree != null) return ResultatCreation(IssueCreation.creee, inventaire: cree, lignes: r.lignes);
    if (r.succes) {
      return ResultatCreation(IssueCreation.creee, lignes: r.lignes, message: 'Inventaire créé mais absent de la liste des inventaires ouverts.');
    }
    return ResultatCreation(IssueCreation.incertaine,
        message: 'Pas de réponse du serveur (${r.message}) et l\'inventaire n\'apparaît pas. Vérifiez la liste avant de réessayer.');
  }

  /// 4.15 — Inventaire des PRODUITS COLLECTÉS ([analyse]), comme Prestige le fait (inventaire « unitaire »
  /// puis « Ajouter des articles ») :
  ///  1. le serveur sait-il retenir des lignes (`POST /inventaire/lignes/retenue`) ? (essai sans effet ;
  ///     inutile sur un serveur reconnu récent) ;
  ///  2. création sur les EMPLACEMENTS des produits collectés (type Emplacement, `valeurs` = ces
  ///     emplacements), lignes NON retenues (`bool_INVENTAIRE = 0`) : à l'ouverture, l'inventaire ne
  ///     propose que ces emplacements ;
  ///  3. seules les lignes des produits collectés sont retenues ([retenir]) : la saisie, les écarts et la
  ///     clôture ne voient qu'elles.
  /// Serveur qui ne sait pas retenir (404 / 405) : création REFUSÉE ([messageServeurAncien]), rien n'est
  /// envoyé (4.15.1, décision du pharmacien).
  Future<ResultatCreation> creerDepuisCollecte(String libelleSaisi, AnalyseCollecte analyse) async {
    final erreur = LibelleInventaire.erreur(libelleSaisi);
    if (erreur != null) return ResultatCreation(IssueCreation.libelleInvalide, message: erreur);
    if (!analyse.creationPossible) {
      return const ResultatCreation(IssueCreation.refus, message: 'Aucun produit de la collecte n\'a été retrouvé sur le serveur : rien à créer.');
    }
    if (_enCours) return const ResultatCreation(IssueCreation.dejaEnCours, message: 'Création déjà en cours : patientez.');
    _enCours = true;
    try {
      final bool retenue;
      try {
        retenue = await api.routeRetenueDisponible();
      } on ApiLoadException catch (e) {
        return ResultatCreation(e.sessionExpiree ? IssueCreation.session : IssueCreation.reseau, message: e.message);
      }
      if (!retenue) return const ResultatCreation(IssueCreation.refus, message: messageServeurAncien);
      final r = await _creer(LibelleInventaire.normaliser(libelleSaisi), TypeInventaire.emplacement,
          valeurs: [for (final e in analyse.emplacements) e.rayon.id], nonRetenues: true);
      if (!r.ok) return r;
      final inv = r.inventaire;
      if (inv == null || inv.id.isEmpty) {
        return ResultatCreation(IssueCreation.produitsNonAjoutes,
            lignes: r.lignes,
            message: 'Inventaire créé mais introuvable dans la liste : les produits collectés n\'ont pas pu y être ajoutés.');
      }
      return _retenir(inv, analyse, lignes: r.lignes);
    } finally {
      _enCours = false;
    }
  }

  /// Retient (à nouveau) les produits de [analyse] dans [inventaire] : sans rien recréer, idempotent.
  /// Sert après [IssueCreation.produitsNonAjoutes] (« Réessayer ») et quand un inventaire existant du
  /// même libellé est choisi depuis la collecte. Serveur qui ne sait pas retenir : refus.
  Future<ResultatCreation> retenir(Inventory inventaire, AnalyseCollecte analyse) async {
    if (_enCours) return const ResultatCreation(IssueCreation.dejaEnCours, message: 'Création déjà en cours : patientez.');
    _enCours = true;
    try {
      final bool retenue;
      try {
        retenue = await api.routeRetenueDisponible();
      } on ApiLoadException catch (e) {
        return ResultatCreation(IssueCreation.produitsNonAjoutes, inventaire: inventaire, message: e.message);
      }
      if (!retenue) return const ResultatCreation(IssueCreation.refus, message: messageServeurAncien);
      return _retenir(inventaire, analyse);
    } finally {
      _enCours = false;
    }
  }

  Future<ResultatCreation> _retenir(Inventory inv, AnalyseCollecte analyse, {int? lignes}) async {
    try {
      final n = await api.retenirProduits(inv.id, [for (final p in analyse.inclus) p.id]);
      return ResultatCreation(IssueCreation.creee, inventaire: inv, lignes: lignes, retenus: n);
    } on ApiLoadException catch (e) {
      return ResultatCreation(IssueCreation.produitsNonAjoutes,
          inventaire: inv,
          lignes: lignes,
          message: '${e.message}\nL\'inventaire « ${inv.libelle} » est créé mais les produits collectés n\'y sont pas encore : '
              'touchez « Réessayer » (rien n\'est recréé).');
    }
  }
}
