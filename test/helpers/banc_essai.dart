// Montage d'un écran avec tous les providers de l'application, un faux serveur HTTP Prestige et une
// file des saisies sur un « disque » en mémoire (les tests de widgets tournent en temps simulé :
// les vraies entrées/sorties fichier n'y avancent pas — la file sur fichier est testée à part).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/license.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'faux_prestige_http.dart';

/// « Disque » en mémoire : chaque écriture est sérialisée en JSON (comme sur disque) ; une nouvelle
/// file ouverte sur le même disque relit exactement ce qui a été écrit (= redémarrage).
class DisqueMemoire implements SaisieStore {
  final Map<String, String> donnees = {};
  int ecritures = 0;

  @override
  Future<List<SaisieLigne>> lire() async =>
      donnees.values.map((j) => SaisieLigne.fromJson(json.decode(j) as Map<String, dynamic>)).toList();

  @override
  Future<void> ecrire(SaisieLigne s) async {
    ecritures++;
    donnees[s.cle] = json.encode(s.toJson());
  }

  @override
  Future<void> supprimer(String cle) async => donnees.remove(cle);

  @override
  Future<void> remplacerTout(List<SaisieLigne> saisies) async {
    donnees
      ..clear()
      ..addEntries(saisies.map((s) => MapEntry(s.cle, json.encode(s.toJson()))));
  }

  /// Saisies « sur disque » (relues comme après un redémarrage).
  List<SaisieLigne> get saisies => donnees.values.map((j) => SaisieLigne.fromJson(json.decode(j) as Map<String, dynamic>)).toList();
}

class Banc {
  final FauxPrestige serveur;
  final DisqueMemoire disque;
  final SaisieQueue queue;
  final AppConfig config;
  final AuthProvider auth;
  final EntryProvider entry;
  Banc(this.serveur, this.disque, this.queue, this.config, this.auth, this.entry);
}

/// Prépare préférences, faux serveur, file et providers (sans rien afficher).
Future<Banc> preparerBanc({
  FauxPrestige? serveur,
  DisqueMemoire? disque,
  SendMode mode = SendMode.collect,
  bool cumul = false,
  Map<String, Object> prefsEnPlus = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'sendMode': mode.index,
    'isCumulEnabled': cumul,
    'localApiAddress': 'serveur-test',
    'localApiPort': '8080',
    ...prefsEnPlus,
  });
  final srv = serveur ?? FauxPrestige();
  ApiService.clientParDefaut = srv.client;
  final d = disque ?? DisqueMemoire();
  final config = AppConfig();
  await config.load();
  final auth = AuthProvider()..connecterPourTest();
  final queue = SaisieQueue(store: d);
  SaisieQueue.instance = queue;
  queue.serveurFactory = () => auth.isLoggedIn ? ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie) : null;
  queue.modeDirect = () => config.sendMode == SendMode.direct;
  await queue.load();
  final entry = EntryProvider(queue: queue);
  return Banc(srv, d, queue, config, auth, entry);
}

Widget monter(Banc b, Widget ecran) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: b.config),
        ChangeNotifierProvider.value(value: b.auth),
        ChangeNotifierProvider.value(value: b.queue),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider.value(value: b.entry),
        // Licence valide (pas d'alerte d'expiration sur l'accueil).
        ChangeNotifierProvider(
          create: (_) => LicenseProvider()
            ..setLicenseForTest(License(id: 'L', dateStart: DateTime(2026), dateEnd: DateTime.now().add(const Duration(days: 400)), typeLicence: 'TEST')),
        ),
      ],
      child: MaterialApp(home: ecran),
    );

/// Écran de test de 600 × 1000 dp. (La police des tests, où chaque lettre est un carré plein, est bien
/// plus large que Roboto : à 360 dp elle fait déborder des libellés qui tiennent sur le terminal.)
void ecranTerminal(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 2.0;
}

/// Démonte l'écran (annule les minuteries) et remet la vue par défaut.
Future<void> demonter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  ApiService.clientParDefaut = null;
  SaisieQueue.instance = null;
}

/// Tape une quantité sur le clavier numérique maison visible puis OK.
Future<void> taperQuantite(WidgetTester tester, String chiffres, {bool ok = true}) async {
  for (final c in chiffres.split('')) {
    await tester.tap(find.widgetWithText(ElevatedButton, c).last);
    await tester.pump();
  }
  if (ok) {
    await tester.tap(find.widgetWithText(ElevatedButton, 'OK').last);
    await tester.pump();
  }
}
