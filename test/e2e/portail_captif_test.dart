// DE BOUT EN BOUT — 5.0.3 : une RÉPONSE QUI N'EST PAS CELLE DE PRESTIGE (application entière, deux interfaces, mode
// Direct, données fictives). Un portail captif / un relais / une box répond à la place du serveur Prestige : d'abord
// une page HTML en 200, puis une redirection 302 vers sa page de connexion.
//  - avant 5.0.3 : le 200 comptait comme un envoi réussi, la saisie sortait de la file sans être arrivée (perte) ;
//  - désormais : les saisies restent sur l'appareil, « en attente » (jamais « envoyées » ni « refusées »), bandeau NON
//    BLOQUANT « N saisies en attente d'envoi (serveur injoignable) », la saisie continue ;
//  - au retour du vrai serveur, l'envoi reprend SEUL (au plus 2 min après), dans l'ordre, sans doublon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';

import '../helpers/banc_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';

final _bandeau = find.byKey(const ValueKey('bandeau-attente-serveur'));

const _page = '<!DOCTYPE html><html><body><h1>Wi-Fi invités</h1><form action="/connexion"></form></body></html>';

Future<void> _attendre(WidgetTester tester, Duration d) async {
  for (var t = Duration.zero; t < d; t += const Duration(seconds: 15)) {
    await tester.pump(const Duration(seconds: 15));
  }
  await tester.pumpAndSettle();
}

Future<void> _scenario(WidgetTester tester, AppEssai app, Future<void> Function(String quantite) saisir) async {
  // 1. Portail captif : 200 avec SA page HTML à la place de la réponse de Prestige.
  app.serveur.scripter('details', ReponseScriptee(code: 200, corps: _page, entetes: {'content-type': 'text/html'}), methode: 'PUT');
  await saisir('7');
  await tester.pumpAndSettle();
  expect(app.saisies.enAttente(), 1, reason: 'jamais « envoyée » sur une page HTML');
  expect(_bandeau, findsOneWidget);
  expect(find.text('1 saisie en attente d\'envoi (serveur injoignable)'), findsOneWidget);
  expect(find.byType(AlertDialog), findsNothing, reason: 'non bloquant');
  await _attendre(tester, const Duration(minutes: 2));
  expect(app.serveur.recues('details', methode: 'PUT').length, greaterThan(1), reason: 'relancée seule');
  expect(app.saisies.enAttente(), 1);
  expect(app.saisies.refusees(), 0);

  // 2. Le portail redirige vers sa page de connexion (302) : la saisie continue, rien n'est perdu.
  app.serveur.scripter('details', ReponseScriptee(code: 302, corps: '', entetes: {'location': 'http://portail.invalid/connexion'}), methode: 'PUT');
  await saisir('4');
  await tester.pumpAndSettle();
  expect(app.saisies.enAttente(), 2);
  expect(find.text('2 saisies en attente d\'envoi (serveur injoignable)'), findsOneWidget);
  await _attendre(tester, const Duration(minutes: 2));
  expect(app.disque.saisies.where((s) => s.enAttente), hasLength(2), reason: 'écrites sur l\'appareil');
  expect(app.serveur.catalogue.puts, isEmpty, reason: 'rien n\'est arrivé à Prestige');

  // 3. Le vrai serveur répond de nouveau : envoi automatique, ordre, une pose chacune, bandeau retiré.
  app.serveur.oublierScripts();
  await _attendre(tester, const Duration(minutes: 2, seconds: 15));
  expect(app.saisies.enAttente(), 0, reason: 'envoyées seules au retour du serveur');
  expect(app.saisies.refusees(), 0);
  expect(app.serveur.catalogue.puts.map((p) => p.$2).toList(), [7, 4], reason: 'ordre de saisie, sans doublon');
  expect(_bandeau, findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('nouvelle interface (saisie guidée) : page HTML puis 302 → gardées, bandeau, envoyées au retour', (tester) async {
    tailleEcran(tester, telephone360);
    final app = await lancerApplication(tester, mode: SendMode.direct);
    await seConnecter(tester);
    await choisirInventaire(tester, 'INV1');
    await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
    await tester.pumpAndSettle();
    await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
    await tester.pumpAndSettle();
    await _scenario(tester, app, (q) => taperNv(tester, q));
    await fermerApplication(tester);
  });

  testWidgets('ancienne interface (saisie guidée d\'origine) : idem', (tester) async {
    ecranTerminal(tester);
    final app = await lancerApplication(tester, nouvelleInterface: false, mode: SendMode.direct);
    await seConnecter(tester);
    await tester.tap(find.text('SAISIE GUIDEE\n(Mode Guidé)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventaire annuel 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sélectionner un emplacement'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('ANTIBIOTIQUES').last);
    await tester.pumpAndSettle();
    await _scenario(tester, app, (q) => taperQuantite(tester, q));
    await fermerApplication(tester);
  });
}
