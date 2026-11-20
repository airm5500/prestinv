// DE BOUT EN BOUT — 5.0.2 (demande du pharmacien) : le SERVEUR S'ÉTEINT PENDANT L'INVENTAIRE (application entière,
// deux interfaces, mode Direct, données fictives). Le serveur répond d'abord 500 (Payara qui s'arrête), puis plus
// du tout (PC éteint) :
//  - les saisies restent sur l'appareil, « en attente » (jamais « refusées »), au-delà de 3 essais ;
//  - bandeau NON BLOQUANT « N saisies en attente d'envoi (serveur injoignable) », aucune fenêtre : la saisie continue ;
//  - au retour du serveur, l'envoi reprend SEUL (au plus 2 min après), sans doublon, et le bandeau disparaît.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';

import '../helpers/banc_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';

final _bandeau = find.byKey(const ValueKey('bandeau-attente-serveur'));

/// Laisse tourner la reprise automatique (toutes les 15 s, espacée pendant la panne).
Future<void> _attendre(WidgetTester tester, Duration d) async {
  for (var t = Duration.zero; t < d; t += const Duration(seconds: 15)) {
    await tester.pump(const Duration(seconds: 15));
  }
  await tester.pumpAndSettle();
}

/// Panne (500 puis serveur coupé), deux saisies, retour du serveur : vérifications communes.
Future<void> _scenario(WidgetTester tester, AppEssai app, Future<void> Function(String quantite) saisir) async {
  // 1. Payara s'arrête : 500 sur l'envoi des quantités.
  app.serveur.scripter('details', ReponseScriptee.code(500), methode: 'PUT');
  await saisir('7');
  await tester.pumpAndSettle();
  expect(app.saisies.enAttente(), 1);
  expect(_bandeau, findsOneWidget);
  expect(find.text('1 saisie en attente d\'envoi (serveur injoignable)'), findsOneWidget);
  expect(find.byType(AlertDialog), findsNothing, reason: 'non bloquant');

  // Plus de 3 essais (avant 5.0.2 : « refusée » au 3e, la relance s'arrêtait).
  await _attendre(tester, const Duration(minutes: 2));
  expect(app.serveur.recues('details', methode: 'PUT').length, greaterThan(3));
  expect(app.saisies.refusees(), 0, reason: 'jamais « refusée » par une erreur du serveur');
  expect(app.saisies.enAttente(), 1);

  // 2. Le PC serveur s'éteint : la saisie continue (produit suivant), rien n'est bloqué.
  app.serveur.couper();
  await saisir('4');
  await tester.pumpAndSettle();
  expect(app.saisies.enAttente(), 2);
  expect(find.text('2 saisies en attente d\'envoi (serveur injoignable)'), findsOneWidget);
  expect(find.byType(AlertDialog), findsNothing);
  await _attendre(tester, const Duration(minutes: 3));
  expect(app.saisies.enAttente(), 2);
  expect(app.disque.saisies.where((s) => s.enAttente), hasLength(2), reason: 'écrites sur l\'appareil');
  expect(app.serveur.catalogue.puts, isEmpty);

  // 3. Retour du serveur : envoi automatique, au plus 2 min après (espacement plafonné), sans doublon.
  app.serveur
    ..retablir()
    ..oublierScripts();
  await _attendre(tester, const Duration(minutes: 2, seconds: 15));
  expect(app.saisies.enAttente(), 0, reason: 'envoyées seules au retour du serveur');
  expect(app.saisies.refusees(), 0);
  final puts = app.serveur.catalogue.puts;
  expect(puts.map((p) => p.$2).toList(), [7, 4], reason: 'ordre de saisie, une pose chacune : $puts');
  expect(_bandeau, findsNothing, reason: 'bandeau retiré');
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('nouvelle interface (saisie guidée) : 500 puis serveur éteint → gardées, bandeau, envoyées au retour', (tester) async {
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
