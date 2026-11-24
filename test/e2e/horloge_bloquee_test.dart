// DE BOUT EN BOUT — 5.0.4 : HEURE DU SERVEUR FAUSSE (application entière, deux interfaces, mode Direct, données
// fictives). Le serveur refuse toute écriture (HTTP 423, horlogeBloquee) tant que son heure est fausse :
//  - la saisie continue ; les quantités restent sur l'appareil, « en attente » (jamais « refusées ») ;
//  - bandeau NON BLOQUANT « N saisies en attente d'envoi. » + message du serveur tel quel (jamais « serveur
//    injoignable ») ; aucune fenêtre bloquante, aucun contournement proposé ;
//  - relances espacées (pas de boucle) ; quand l'heure est remise, envoi seul, dans l'ordre, sans doublon ;
//  - écran de connexion : `GET horloge/public` BLOQUE → bandeau ; ancien serveur (route absente) / OK → rien.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';

import '../helpers/banc_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';

final _bandeau = find.byKey(const ValueKey('bandeau-attente-serveur'));
final _bandeauConnexion = find.byKey(const ValueKey('bandeau-horloge-serveur'));

const _msg = 'Opération refusée : l\'heure du serveur est fausse. Faites « Mettre à jour » ou appelez '
    'l\'administrateur pour remettre l\'heure dans Windows.';

ReponseScriptee _refus423() => ReponseScriptee.json({'success': false, 'horlogeBloquee': true, 'msg': _msg}, code: 423);

Future<void> _attendre(WidgetTester tester, Duration d) async {
  for (var t = Duration.zero; t < d; t += const Duration(seconds: 15)) {
    await tester.pump(const Duration(seconds: 15));
  }
  await tester.pumpAndSettle();
}

Future<void> _scenario(WidgetTester tester, AppEssai app, Future<void> Function(String quantite) saisir) async {
  app.serveur.scripter('details', _refus423(), methode: 'PUT');
  await saisir('7');
  await tester.pumpAndSettle();
  expect(app.saisies.enAttente(), 1, reason: 'gardée sur l\'appareil');
  expect(app.saisies.refusees(), 0, reason: 'jamais « refusée »');
  expect(_bandeau, findsOneWidget);
  expect(find.text('1 saisie en attente d\'envoi. $_msg'), findsOneWidget, reason: 'message du serveur tel quel');
  expect(find.textContaining('injoignable'), findsNothing);
  expect(find.byType(AlertDialog), findsNothing, reason: 'non bloquant');

  // Relances espacées pendant 10 minutes : quelques essais, jamais une boucle.
  final avant = app.serveur.recues('details', methode: 'PUT').length;
  await _attendre(tester, const Duration(minutes: 10));
  final essais = app.serveur.recues('details', methode: 'PUT').length - avant;
  expect(essais, inInclusiveRange(1, 8), reason: 'relances espacées ($essais en 10 minutes)');

  await saisir('4');
  await tester.pumpAndSettle();
  expect(app.saisies.enAttente(), 2);
  expect(find.text('2 saisies en attente d\'envoi. $_msg'), findsOneWidget);
  expect(app.serveur.catalogue.puts, isEmpty);

  // L'heure du serveur est remise : envoi seul, au plus 2 minutes plus tard, ordre, une pose chacune.
  app.serveur.oublierScripts();
  await _attendre(tester, const Duration(minutes: 2, seconds: 15));
  expect(app.saisies.enAttente(), 0);
  expect(app.saisies.refusees(), 0);
  expect(app.serveur.catalogue.puts.map((p) => p.$2).toList(), [7, 4], reason: 'ordre de saisie, sans doublon');
  expect(_bandeau, findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('nouvelle interface (saisie guidée) : 423 → gardées, bandeau avec le message, envoyées quand l\'heure est remise', (tester) async {
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

  for (final nouvelle in [true, false]) {
    final nom = nouvelle ? 'nouvelle interface' : 'ancienne interface';

    testWidgets('$nom — écran de connexion : horloge/public BLOQUE → bandeau ; la connexion reste possible', (tester) async {
      nouvelle ? tailleEcran(tester, telephone360) : ecranTerminal(tester);
      final serveur = FauxServeurPrestige()
        ..scripter('horloge/public', ReponseScriptee.json({'etat': 'BLOQUE', 'serveur': '24/11/2026 20:52'}), methode: 'GET');
      final app = await lancerApplication(tester, serveur: serveur, nouvelleInterface: nouvelle);
      await tester.pumpAndSettle();
      expect(_bandeauConnexion, findsOneWidget);
      expect(find.textContaining('L\'heure du serveur est fausse (heure du serveur : 24/11/2026 20:52)'), findsOneWidget);
      expect(app.serveur.recues('horloge/public'), hasLength(1), reason: 'une seule lecture');
      await tester.pump(const Duration(minutes: 1));
      expect(app.serveur.recues('horloge/public'), hasLength(1), reason: 'aucune relance');
      await seConnecter(tester);
      expect(app.serveur.recues('user/auth', methode: 'POST'), hasLength(1), reason: 'connexion permise');
      expect(tester.takeException(), isNull);
      await fermerApplication(tester);
    });

    testWidgets('$nom — écran de connexion : ancien serveur (route absente) puis OK / REGULARISATION → aucun bandeau', (tester) async {
      nouvelle ? tailleEcran(tester, telephone360) : ecranTerminal(tester);
      final app = await lancerApplication(tester, nouvelleInterface: nouvelle);
      await tester.pumpAndSettle();
      expect(app.serveur.recues('horloge/public'), hasLength(1), reason: 'une seule lecture');
      expect(_bandeauConnexion, findsNothing, reason: 'route absente (ancien serveur) : rien');
      expect(find.textContaining('heure du serveur'), findsNothing);
      await fermerApplication(tester);
      for (final etat in ['OK', 'REGULARISATION']) {
        final serveur = FauxServeurPrestige()
          ..scripter('horloge/public', ReponseScriptee.json({'etat': etat, 'serveur': '24/11/2026 20:52'}), methode: 'GET');
        await lancerApplication(tester, serveur: serveur, nouvelleInterface: nouvelle);
        await tester.pumpAndSettle();
        expect(_bandeauConnexion, findsNothing, reason: etat);
        await fermerApplication(tester);
      }
    });
  }
}
