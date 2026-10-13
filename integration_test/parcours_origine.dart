// Parcours du test d'intégration sur appareil (integration_test/app_test.dart), écrits UNE fois :
//  - app_test.dart les joue sur un terminal réel contre un VRAI serveur Prestige (identifiants fournis
//    au lancement, jamais dans le code) ;
//  - test/e2e/integration_test_coherence_test.dart les joue à chaque `flutter test` contre le faux
//    serveur : si un écran change, ces parcours cassent tout de suite (et non le jour d'une recette).
// Ils visent les ÉCRANS D'ORIGINE (ancienne interface choisie explicitement dans les paramètres).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/main.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/screens/variance_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParametresEssai {
  final String login;
  final String motDePasse;
  final String hote;
  final String port;

  /// Texte d'un produit présentant un écart sur ce serveur (vide : recherche non vérifiée).
  final String recherche;

  /// Attente après une action réseau (serveur réel : quelques secondes ; faux serveur : immédiat).
  final Duration attente;
  const ParametresEssai(
      {required this.login, required this.motDePasse, required this.hote, this.port = '8080', this.recherche = '', this.attente = Duration.zero});
}

Future<void> _attendre(WidgetTester tester, ParametresEssai p) async {
  if (p.attente > Duration.zero) await tester.pump(p.attente);
  await tester.pumpAndSettle();
}

/// Lance l'application (même racine que main()), ancienne interface choisie, serveur [p].
/// [store] : stockage de la file des saisies (par défaut un fichier temporaire, jamais celui de l'appareil).
Future<void> lancerOrigine(WidgetTester tester, ParametresEssai p, {SaisieStore? store, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({InterfaceVersion.key: false, ...prefs});
  final appConfig = AppConfig();
  await appConfig.load();
  await InterfaceVersion.load();
  await appConfig.setApiConfig(localAddress: p.hote, localPort: p.port, distantAddress: p.hote, distantPort: p.port);
  final saisies = SaisieQueue(
      store: store ?? FichierSaisieStore(File('${(await Directory.systemTemp.createTemp('prestinv_integration_')).path}/saisies_v1.jsonl')));
  SaisieQueue.instance = saisies;
  await saisies.load();
  await tester.pumpWidget(racineApplication(config: appConfig, auth: AuthProvider(), saisies: saisies));
  await _attendre(tester, p);
}

Future<void> connecterOrigine(WidgetTester tester, ParametresEssai p) async {
  expect(find.byType(LoginScreen), findsOneWidget);
  await tester.enterText(find.widgetWithText(TextField, 'Identifiant'), p.login);
  await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), p.motDePasse);
  await tester.tap(find.text('CONNEXION'));
  await _attendre(tester, p);
  expect(find.byType(HomeScreen), findsOneWidget, reason: 'La connexion a échoué.');
}

/// Saisie guidée : premier inventaire, premier emplacement, quantité 99, envoi.
Future<void> parcoursSaisieOrigine(WidgetTester tester, ParametresEssai p) async {
  await tester.tap(find.text('SAISIE GUIDEE\n(Mode Guidé)'));
  await _attendre(tester, p);
  expect(find.byType(InventoryListScreen), findsOneWidget);
  expect(find.byType(ListTile), findsWidgets, reason: 'Aucun inventaire n\'a été chargé.');
  await tester.tap(find.byType(ListTile).first);
  await _attendre(tester, p);
  expect(find.byType(InventoryEntryScreen), findsOneWidget);

  await tester.tap(find.text('Sélectionner un emplacement'));
  await _attendre(tester, p);
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(ListTile)).first);
  await _attendre(tester, p);

  for (final t in ['9', '9', 'OK']) {
    await tester.tap(find.widgetWithText(ElevatedButton, t).last);
    await tester.pump();
  }
  await _attendre(tester, p);
  await tester.tap(find.byTooltip('Envoyer les données'));
  await _attendre(tester, p);
}

/// Écarts de l'emplacement (depuis la saisie) et recherche.
Future<void> parcoursEcartsOrigine(WidgetTester tester, ParametresEssai p) async {
  await tester.tap(find.byTooltip('Correction écarts'));
  await _attendre(tester, p);
  expect(find.byType(VarianceScreen), findsOneWidget);
  final recherche = find.widgetWithText(TextField, 'Rechercher / Scanner un produit avec écart');
  expect(recherche, findsOneWidget);
  if (p.recherche.isNotEmpty) {
    await tester.enterText(recherche, p.recherche);
    await _attendre(tester, p);
    expect(find.textContaining(p.recherche), findsWidgets);
  }
}

Future<void> parcoursDeconnexionOrigine(WidgetTester tester, ParametresEssai p) async {
  await tester.tap(find.byIcon(Icons.logout));
  await _attendre(tester, p);
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(find.byType(HomeScreen), findsNothing);
}
