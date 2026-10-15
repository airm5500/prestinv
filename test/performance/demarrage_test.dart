// PERFORMANCE — DÉMARRAGE de l'application (même racine que main()) jusqu'à l'écran de connexion,
// contre le faux serveur Prestige (licence lue) : temps réel mesuré dans le test, nombre d'images
// rendues, nombre de requêtes. Mesuré À FROID (premier test du fichier : tous les widgets construits
// pour la première fois), nouvelle interface puis ancienne. Seuils : test/support/performance.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/banc_essai.dart' show ecranTerminal;
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';
import '../support/performance.dart';

/// Lance l'application et pompe image par image jusqu'à l'écran de connexion immobile.
Future<({double ms, int images, int requetes})> demarrer(WidgetTester tester, Finder connexion, {bool? nouvelleInterface}) async {
  final serveur = FauxServeurPrestige();
  final images0 = imagesRendues();
  final sw = Stopwatch()..start();
  await lancerApplication(tester, serveur: serveur, nouvelleInterface: nouvelleInterface, attendre: false);
  var n = 0;
  while ((connexion.evaluate().isEmpty || tester.binding.hasScheduledFrame) && n < 200) {
    await tester.pump(const Duration(milliseconds: 16));
    n++;
  }
  final ms = sw.elapsedMicroseconds / 1000;
  expect(connexion, findsOneWidget, reason: 'écran de connexion affiché');
  return (ms: ms, images: imagesRendues() - images0, requetes: serveur.requetes.length);
}

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('nouvelle interface : lancement → écran de connexion (temps, images, requêtes)', (tester) async {
    tailleEcran(tester, telephone360);
    final r = await demarrer(tester, find.byKey(const ValueKey('nv-connexion')));
    mesurer('Démarrage → connexion (nouvelle interface, à froid)', r.ms, seuil: Seuils.demarrageMs, unite: 'ms');
    mesurer('Démarrage → connexion (nouvelle interface) — images rendues', r.images, seuil: Seuils.demarrageImages, unite: 'images');
    mesurer('Démarrage → connexion (nouvelle interface) — requêtes', r.requetes, seuil: Seuils.demarrageRequetes, unite: 'requêtes');
    await fermerApplication(tester);
  });

  testWidgets('ancienne interface : lancement → écran de connexion d\'origine (temps, images, requêtes)', (tester) async {
    ecranTerminal(tester);
    final r = await demarrer(tester, find.text('CONNEXION'), nouvelleInterface: false);
    mesurer('Démarrage → connexion (ancienne interface)', r.ms, seuil: Seuils.demarrageMs, unite: 'ms');
    mesurer('Démarrage → connexion (ancienne interface) — images rendues', r.images, seuil: Seuils.demarrageImages, unite: 'images');
    mesurer('Démarrage → connexion (ancienne interface) — requêtes', r.requetes, seuil: Seuils.demarrageRequetes, unite: 'requêtes');
    await fermerApplication(tester);
  });
}
