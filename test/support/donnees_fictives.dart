// Données FICTIVES des tests : compte, licence, officine, catalogue. Aucun vrai identifiant, aucun vrai
// mot de passe, aucune vraie adresse de serveur ne doit apparaître dans le dépôt (un garde-fou le
// vérifie : test/non_regression/secrets_test.dart).
import '../helpers/faux_prestige_http.dart';
import '../helpers/nouvelle_interface.dart';

/// Compte d'essai accepté par le faux serveur.
class CompteFictif {
  CompteFictif._();
  static const login = 'inventoriste.essai';
  static const motDePasse = 'mdp-fictif-0000';
  static const prenom = 'Awa';
  static const nom = 'Essai';
  static const officine = 'Pharmacie Fictive du Plateau';
}

/// Adresse donnée à la configuration de l'application pendant les tests (jamais résolue : le faux
/// serveur répond en mémoire).
const adresseServeurFictive = 'serveur-essai.invalid';

/// Réponse de /user/auth pour [login] (même forme que AccountResource.auth : « xtypeuser » vaut
/// « dashboard » pour l'administrateur / le pharmacien, « mainmenumanager » pour les autres profils).
/// [typeAccueil] null : serveur plus ancien qui n'envoie pas « xtypeuser » (profil inconnu).
///
/// [droitCreation] (4.15, serveur à jour) : ajoute `role` et `droits.creerInventaire` (demande 10) ;
/// null : serveur plus ancien (champs absents).
Map<String, dynamic> utilisateurFictif(String login, {String? typeAccueil = 'dashboard', bool? droitCreation}) => {
      'success': true,
      if (typeAccueil != null) 'xtypeuser': typeAccueil,
      if (droitCreation != null) 'role': {'code': droitCreation ? 'PHARMACIEN' : 'VENDEUR', 'libelle': droitCreation ? 'Pharmacien' : 'Vendeur'},
      if (droitCreation != null) 'droits': {'creerInventaire': droitCreation},
      'str_USER_ID': 'U-ESSAI-1',
      'str_LOGIN': login,
      'str_FIRST_NAME': CompteFictif.prenom,
      'str_LAST_NAME': CompteFictif.nom,
      'OFFICINE': CompteFictif.officine,
    };

/// Licence valide (fin dans [joursRestants] jours, relative à aujourd'hui : jamais périmée).
Map<String, dynamic> licenceFictive({int joursRestants = 400}) {
  String jour(DateTime d) => d.toIso8601String().substring(0, 10);
  final maintenant = DateTime.now();
  return {
    'id': 'LIC-ESSAI-0001',
    'dateStart': jour(maintenant.subtract(const Duration(days: 30))),
    'dateEnd': jour(maintenant.add(Duration(days: joursRestants))),
    'typeLicence': 'ANNUELLE',
  };
}

/// Catalogue d'officine fictif : 2 inventaires ouverts, 3 rayons, 12 produits (noms usuels, CIP de
/// forme réaliste mais inventés), certains déjà comptés avec écart.
FauxPrestige catalogueFictif() => serveurRealiste();
