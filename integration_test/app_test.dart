// Fichier : integration_test/app_test.dart
// Test d'intégration SUR APPAREIL contre un VRAI serveur Prestige (terminal Sunmi ou émulateur).
// Les parcours sont dans parcours_origine.dart ; ils sont aussi joués à chaque `flutter test` contre le
// faux serveur (test/e2e/integration_test_coherence_test.dart), ce qui les garde à jour.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'parcours_origine.dart';

// Identifiants et serveur de test : JAMAIS dans le code. À fournir au lancement, par exemple :
//   flutter test integration_test --dart-define=PRESTINV_TEST_LOGIN=... \
//     --dart-define=PRESTINV_TEST_PASSWORD=... --dart-define=PRESTINV_TEST_HOST=192.168.1.7 \
//     --dart-define=PRESTINV_TEST_RECHERCHE=<produit avec écart>
// (ou variables d'environnement du même nom sur la machine qui lance les tests).
String _param(String nom, String defaut) {
  const fromDefine = {
    'PRESTINV_TEST_LOGIN': String.fromEnvironment('PRESTINV_TEST_LOGIN'),
    'PRESTINV_TEST_PASSWORD': String.fromEnvironment('PRESTINV_TEST_PASSWORD'),
    'PRESTINV_TEST_HOST': String.fromEnvironment('PRESTINV_TEST_HOST'),
    'PRESTINV_TEST_PORT': String.fromEnvironment('PRESTINV_TEST_PORT'),
    'PRESTINV_TEST_RECHERCHE': String.fromEnvironment('PRESTINV_TEST_RECHERCHE'),
  };
  final v = fromDefine[nom] ?? '';
  if (v.isNotEmpty) return v;
  return Platform.environment[nom] ?? defaut;
}

final _parametres = ParametresEssai(
  login: _param('PRESTINV_TEST_LOGIN', ''),
  motDePasse: _param('PRESTINV_TEST_PASSWORD', ''),
  hote: _param('PRESTINV_TEST_HOST', ''),
  port: _param('PRESTINV_TEST_PORT', '8080'),
  recherche: _param('PRESTINV_TEST_RECHERCHE', ''),
  attente: const Duration(seconds: 4),
);
final bool _sansServeur = _parametres.login.isEmpty || _parametres.motDePasse.isEmpty || _parametres.hote.isEmpty;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Suite de tests complets de Prestinv (serveur réel)',
      skip: _sansServeur ? 'PRESTINV_TEST_LOGIN / PRESTINV_TEST_PASSWORD / PRESTINV_TEST_HOST non fournis' : null, () {
    testWidgets('Flux principal : de la connexion à la saisie envoyée', (tester) async {
      await lancerOrigine(tester, _parametres);
      await connecterOrigine(tester, _parametres);
      await parcoursSaisieOrigine(tester, _parametres);
    });

    testWidgets('Déconnexion : l\'utilisateur peut se déconnecter', (tester) async {
      await lancerOrigine(tester, _parametres);
      await connecterOrigine(tester, _parametres);
      await parcoursDeconnexionOrigine(tester, _parametres);
    });

    testWidgets('Écarts : écran des écarts de l\'emplacement et recherche', (tester) async {
      await lancerOrigine(tester, _parametres);
      await connecterOrigine(tester, _parametres);
      await parcoursSaisieOrigine(tester, _parametres);
      await parcoursEcartsOrigine(tester, _parametres);
    });
  });
}
