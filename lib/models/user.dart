// lib/models/user.dart

class AppUser {
  final String id;
  final String login;
  final String firstName;
  final String lastName;
  final String officine;

  /// Écran d'accueil que le serveur Prestige attribue au profil (« xtypeuser » de la réponse de
  /// POST /user/auth) : « dashboard » pour l'utilisateur système, le pharmacien, l'administrateur et le
  /// super administrateur (AccountResource.auth) ; « mainmenumanager » pour les autres profils.
  /// null : serveur qui ne l'envoie pas (profil inconnu).
  final String? typeAccueil;

  AppUser({
    required this.id,
    required this.login,
    required this.firstName,
    required this.lastName,
    required this.officine,
    this.typeAccueil,
  });

  /// Administrateur ou pharmacien ? null : le serveur ne l'a pas dit (voir [typeAccueil]).
  bool? get adminOuPharmacien {
    final t = typeAccueil?.trim().toLowerCase();
    if (t == null || t.isEmpty) return null;
    return t == 'dashboard';
  }

  /// Nom affiché (« Prénom Nom »), l'identifiant à défaut.
  String get nomComplet {
    final n = [firstName.trim(), lastName.trim()].where((e) => e.isNotEmpty).join(' ');
    return n.isEmpty ? login : n;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['str_USER_ID'] ?? '',
      login: json['str_LOGIN'] ?? '',
      firstName: json['str_FIRST_NAME'] ?? '',
      lastName: json['str_LAST_NAME'] ?? '',
      officine: json['OFFICINE'] ?? '',
      typeAccueil: json['xtypeuser'] is String ? json['xtypeuser'] as String : null,
    );
  }
}