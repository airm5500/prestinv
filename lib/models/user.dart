// lib/models/user.dart

class AppUser {
  final String id;
  final String login;
  final String firstName;
  final String lastName;
  final String officine;

  AppUser({
    required this.id,
    required this.login,
    required this.firstName,
    required this.lastName,
    required this.officine,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['str_USER_ID'] ?? '',
      login: json['str_LOGIN'] ?? '',
      firstName: json['str_FIRST_NAME'] ?? '',
      lastName: json['str_LAST_NAME'] ?? '',
      officine: json['OFFICINE'] ?? '',
    );
  }
}