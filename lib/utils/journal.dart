// lib/utils/journal.dart
// Journal de mise au point : écrit SEULEMENT dans une version de développement (jamais dans l'APK
// release, lisible par câble USB / logcat), et sans secret (mot de passe, cookie de session, clé de
// licence et paramètres d'URL masqués).
import 'package:flutter/foundation.dart';

final RegExp _secrets = RegExp(
  r'(JSESSIONID=)[^;\s]+|("?(?:password|motDePasse|mot_de_passe|pin|cookie)"?\s*[:=]\s*"?)[^",\s}]+|(licence/save/)[^\s?/]+|(\?)[^\s]+',
  caseSensitive: false,
);

/// Masque les secrets d'un message.
String masquerSecrets(String message) => message.replaceAllMapped(_secrets, (m) {
      final prefixe = m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      return '$prefixe***';
    });

void journal(String message) {
  if (kDebugMode) debugPrint(masquerSecrets(message));
}
