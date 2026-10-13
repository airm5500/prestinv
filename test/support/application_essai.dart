// Montage de l'APPLICATION ENTIÈRE pour les tests de bout en bout : même racine que main()
// (racineApplication : providers + PrestinvApp, vérification de licence au lancement, aiguillage
// connexion / accueil, reprise automatique des saisies), branchée sur le faux serveur Prestige (en
// mémoire), une file des saisies sur « disque » en mémoire, un coffre sécurisé en mémoire.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/main.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:prestinv/services/pin_securise.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart';
import '../helpers/coffre_memoire.dart';
import '../helpers/douchette_essai.dart';
import 'donnees_fictives.dart';
import 'faux_serveur_prestige.dart';

/// Code administrateur fictif posé pour les tests (changer d'interface, déverrouiller la configuration).
const codeAdminFictif = '7391';

class AppEssai {
  final FauxServeurPrestige serveur;
  final DisqueMemoire disque;
  final SaisieQueue saisies;
  final AppConfig config;
  final AuthProvider auth;
  final CoffreMemoire coffre;
  AppEssai(this.serveur, this.disque, this.saisies, this.config, this.auth, this.coffre);
}

/// Lance l'application comme sur le terminal (préférences d'une installation déjà configurée).
/// [nouvelleInterface] : null = aucun choix enregistré (valeur par défaut de la 4.12 : nouvelle) ;
/// false = ancienne interface choisie dans les paramètres.
Future<AppEssai> lancerApplication(
  WidgetTester tester, {
  FauxServeurPrestige? serveur,
  bool? nouvelleInterface,
  SendMode mode = SendMode.collect,
  DisqueMemoire? disque,
  Map<String, Object> prefs = const {},
  bool attendre = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'localApiAddress': adresseServeurFictive,
    'localApiPort': '8080',
    'sendMode': mode.index,
    if (nouvelleInterface != null) InterfaceVersion.key: nouvelleInterface,
    ...prefs,
  });
  final srv = serveur ?? FauxServeurPrestige();
  ApiService.clientParDefaut = srv.client;
  ApiService.oublierRoutesAbsentes();
  AvancementCalcul.viderCache();
  reinitialiserDouchette();
  installerFauxRetour();
  final coffre = CoffreMemoire();
  IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: coffre);
  CodeAdmin.instance = CodeAdmin(coffre: coffre, iterations: 1000);
  await CodeAdmin.instance.definir(codeAdminFictif);

  final config = AppConfig();
  await config.load();
  await InterfaceVersion.load();
  final auth = AuthProvider();
  final d = disque ?? DisqueMemoire();
  final queue = SaisieQueue(store: d);
  SaisieQueue.instance = queue;
  await queue.load();

  await tester.pumpWidget(racineApplication(config: config, auth: auth, saisies: queue));
  if (attendre) await tester.pumpAndSettle();
  return AppEssai(srv, d, queue, config, auth, coffre);
}

/// Ferme l'application (minuteries arrêtées) et remet les réglages globaux des tests.
Future<void> fermerApplication(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.view.resetViewInsets();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
  ApiService.clientParDefaut = null;
  SaisieQueue.instance = null;
  IdentifiantsSecurises.instance = IdentifiantsSecurises();
  CodeAdmin.instance = CodeAdmin();
  InterfaceVersion.useNew.value = false;
}

/// Connexion par l'écran affiché (nouvelle ou ancienne interface).
Future<void> seConnecter(WidgetTester tester, {String login = CompteFictif.login, String motDePasse = CompteFictif.motDePasse}) async {
  if (InterfaceVersion.useNew.value) {
    await tester.enterText(find.byKey(const ValueKey('nv-identifiant')), login);
    await tester.enterText(find.byKey(const ValueKey('nv-mot-de-passe')), motDePasse);
    await tester.tap(find.byKey(const ValueKey('nv-connexion')));
  } else {
    await tester.enterText(find.widgetWithText(TextField, 'Identifiant'), login);
    await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), motDePasse);
    await tester.tap(find.text('CONNEXION'));
  }
  await tester.pumpAndSettle();
}

/// Revient à l'écran racine du navigateur de l'application.
Future<void> revenirAccueil(WidgetTester tester) async {
  navigateurApp.currentState!.popUntil((r) => r.isFirst);
  await tester.pumpAndSettle();
}
