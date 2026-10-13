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
// - Le serveur ne renvoie pas l'identifiant du nouvel inventaire : il est retrouvé dans la liste des
//   inventaires ouverts (le plus récent portant ce libellé).
import 'package:prestinv/api/api_service.dart';
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
}

class ResultatCreation {
  final IssueCreation issue;
  final Inventory? inventaire;
  final int? lignes;
  final String message;
  const ResultatCreation(this.issue, {this.inventaire, this.lignes, this.message = ''});

  bool get ok => issue == IssueCreation.creee;
}

class CreationInventaire {
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

  Future<ResultatCreation> creer(String libelleSaisi, TypeInventaire type) async {
    final erreur = LibelleInventaire.erreur(libelleSaisi);
    if (erreur != null) return ResultatCreation(IssueCreation.libelleInvalide, message: erreur);
    if (_enCours) return const ResultatCreation(IssueCreation.dejaEnCours, message: 'Création déjà en cours : patientez.');
    _enCours = true;
    final libelle = LibelleInventaire.normaliser(libelleSaisi);
    try {
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
      final r = await api.creerInventaire(libelle, type.valeur);
      if (r.session) return ResultatCreation(IssueCreation.session, message: r.message);
      if (!r.succes && !r.incertain) return ResultatCreation(IssueCreation.refus, message: r.message);

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
    } finally {
      _enCours = false;
    }
  }
}
