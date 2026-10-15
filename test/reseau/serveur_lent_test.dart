// RÉSEAU — serveur LENT MAIS QUI RÉPOND (2 s, 5 s, 8 s), application entière (nouvelle interface et
// ancienne pour la connexion), faux serveur Prestige en temps simulé. Sur chaque écran principal :
//  - un indicateur de chargement est visible pendant toute l'attente ;
//  - aucun message d'erreur (« injoignable », « trop de temps »…) n'apparaît AVANT le délai de
//    l'application (20 s pour les listes et la connexion, 15 s pour l'envoi d'une quantité) ;
//  - l'écran reste utilisable (bouton retour, aucun blocage) et une seconde action pendant l'attente
//    n'envoie RIEN en double ;
//  - la réponse, une fois arrivée, est affichée / prise en compte.
// Délais de l'application (lib/api/api_service.dart) : connexion et listes 20 s, envoi 15 s,
// avancement d'un emplacement 8 s (d'où des délais d'essai ≤ 8 s).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';

import '../helpers/banc_essai.dart' show ecranTerminal;
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

const delais = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 8)];

final indicateur = find.byWidgetPredicate((w) => w is ProgressIndicator);

/// Textes d'erreur qui ne doivent pas apparaître tant que le serveur répond dans les délais.
Finder erreurs() => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final t = (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase();
      return t.contains('injoignable') || t.contains('trop de temps') || t.contains('erreur') || t.contains('impossible') || t.contains('réessayer');
    });

/// Attend la réponse du serveur lent ([delai]) par pas de 250 ms : indicateur visible et aucun message
/// d'erreur à chaque pas ; [pendant] est appelé une fois, à mi-attente (seconde action de l'utilisateur).
Future<void> attendreServeurLent(WidgetTester tester, Duration delai, String ecran, {Future<void> Function()? pendant}) async {
  final fin = delai - const Duration(milliseconds: 250);
  var t = Duration.zero;
  var milieu = false;
  while (t < fin) {
    await tester.pump(const Duration(milliseconds: 250));
    t += const Duration(milliseconds: 250);
    expect(indicateur, findsWidgets, reason: '$ecran : indicateur de chargement visible à ${t.inMilliseconds} ms');
    expect(erreurs(), findsNothing, reason: '$ecran : aucun message d\'erreur à ${t.inMilliseconds} ms (serveur lent, pas en panne)');
    if (!milieu && t >= delai ~/ 2 && pendant != null) {
      milieu = true;
      await pendant();
    }
  }
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  expect(erreurs(), findsNothing, reason: '$ecran : réponse arrivée, aucun message d\'erreur');
}

void main() {
  setUpAll(chargerPolicesReelles);

  for (final d in delais) {
    final s = '${d.inSeconds} s';
    group('serveur lent ($s)', () {
      testWidgets('connexion (nouvelle interface) : bouton occupé, aucun double envoi, puis accueil', (tester) async {
        tailleEcran(tester, telephone360);
        final app = await lancerApplication(tester);
        app.serveur.scripter('user/auth', ReponseScriptee.lente(d));
        await seConnecterSansAttendre(tester);
        await attendreServeurLent(tester, d, 'Connexion', pendant: () async {
          await tester.tap(find.byKey(const ValueKey('nv-connexion')), warnIfMissed: false);
        });
        expect(app.serveur.recues('user/auth'), hasLength(1), reason: 'second toucher ignoré pendant l\'attente');
        expect(find.byType(NvAccueilScreen), findsOneWidget);
        await fermerApplication(tester);
      });

      testWidgets('connexion (ancienne interface) : aucun double envoi, puis accueil d\'origine', (tester) async {
        ecranTerminal(tester);
        final app = await lancerApplication(tester, nouvelleInterface: false);
        app.serveur.scripter('user/auth', ReponseScriptee.lente(d));
        await seConnecterSansAttendre(tester);
        await attendreServeurLent(tester, d, 'Connexion d\'origine', pendant: () async {
          final bouton = find.text('CONNEXION');
          if (bouton.evaluate().isNotEmpty) await tester.tap(bouton, warnIfMissed: false);
        });
        expect(app.serveur.recues('user/auth'), hasLength(1));
        expect(find.text('CONNEXION'), findsNothing, reason: 'accueil d\'origine affiché');
        await fermerApplication(tester);
      });

      testWidgets('accueil : liste des inventaires lente, chargement visible, puis liste', (tester) async {
        tailleEcran(tester, telephone360);
        final app = await lancerApplication(tester);
        app.serveur.scripter('inventaires', ReponseScriptee.lente(d), methode: 'GET');
        await seConnecterSansAttendre(tester);
        await tester.pump(const Duration(milliseconds: 100));
        // La liste est repliée à l'ouverture : on la déroule pendant le chargement.
        await tester.tap(find.byKey(const ValueKey('nv-voir-inventaires')));
        await tester.pump();
        await attendreServeurLent(tester, d - const Duration(milliseconds: 100), 'Accueil (liste déroulée)');
        expect(app.serveur.recues('ws/inventaires', methode: 'GET'), hasLength(1), reason: 'une seule lecture de la liste');
        await deroulerInventaires(tester);
        expect(find.byKey(const ValueKey('nv-ouvrir-INV1')), findsOneWidget);
        await fermerApplication(tester);
      });

      testWidgets('choix de l\'emplacement : chargement visible, retour possible pendant l\'attente', (tester) async {
        tailleEcran(tester, telephone360);
        final app = await lancerApplication(tester);
        await seConnecter(tester);
        await choisirInventaire(tester, 'INV1');
        app.serveur.scripter('rayons', ReponseScriptee.lente(d));
        final avant = app.serveur.recues('rayons').length;
        await tester.tap(find.byKey(const ValueKey('nv-saisie-guidee')));
        await tester.pump();
        await attendreServeurLent(tester, d, 'Choix de l\'emplacement');
        expect(find.text('S2B2 – ANTIBIOTIQUES'), findsOneWidget);
        expect(app.serveur.recues('rayons').length - avant, 1);

        // Écran utilisable : un second chargement lent peut être quitté par le bouton retour.
        await retour(tester);
        await tester.pumpAndSettle();
        expect(find.byType(NvInventaireScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('nv-saisie-guidee')));
        await tester.pump(const Duration(milliseconds: 300));
        await retour(tester);
        await tester.pump(d);
        await tester.pumpAndSettle();
        expect(find.byType(NvInventaireScreen), findsOneWidget, reason: 'retour pendant l\'attente, sans erreur');
        expect(erreurs(), findsNothing);
        await fermerApplication(tester);
      });

      testWidgets('saisie guidée : rayon lent, chargement visible, puis premier produit', (tester) async {
        tailleEcran(tester, telephone360);
        final app = await lancerApplication(tester);
        await seConnecter(tester);
        await choisirInventaire(tester, 'INV1');
        await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
        await tester.pumpAndSettle();
        expect(find.byType(NvChoixRayonScreen), findsOneWidget);
        app.serveur.scripter('details', ReponseScriptee.lente(d), methode: 'GET');
        await tester.tap(find.text('S2B2 – ANTIBIOTIQUES'));
        await tester.pump();
        await attendreServeurLent(tester, d, 'Saisie guidée');
        expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('nv-produit-courant')), findsOneWidget);
        expect(app.serveur.recues('details', methode: 'GET'), hasLength(1));
        await fermerApplication(tester);
      });

      testWidgets('envoi des saisies : progression visible, second toucher sans double envoi', (tester) async {
        tailleEcran(tester, telephone360);
        final app = await lancerApplication(tester);
        await seConnecter(tester);
        await choisirInventaire(tester, 'INV1');
        await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
        await tester.pumpAndSettle();
        await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
        await tester.pumpAndSettle();
        for (final q in ['3', '2', '7']) {
          await taperNv(tester, q);
          await tester.pumpAndSettle();
        }
        expect(app.saisies.enAttente(), 3);
        app.serveur.scripter('details', ReponseScriptee.lente(d), methode: 'PUT');
        await tester.tap(find.byKey(const ValueKey('nv-envoyer-badge')));
        await tester.pump();
        // 3 quantités, chacune lente : attente totale 3 × d.
        await attendreServeurLent(tester, d * 3, 'Envoi des saisies', pendant: () async {
          await tester.tap(find.byKey(const ValueKey('nv-envoyer-badge')), warnIfMissed: false);
          unawaited(app.saisies.envoyer()); // envoi automatique déclenché en même temps
        });
        expect(app.saisies.enAttente(), 0);
        expect(app.serveur.recues('details', methode: 'PUT'), hasLength(3), reason: 'aucun double envoi');
        await tester.pump(const Duration(seconds: 5)); // fenêtre d'envoi refermée seule
        await tester.pumpAndSettle();
        await fermerApplication(tester);
      });
    });
  }
}

/// Touche « Connexion » sans attendre la réponse du serveur.
Future<void> seConnecterSansAttendre(WidgetTester tester) async {
  final nouvelle = find.byKey(const ValueKey('nv-identifiant')).evaluate().isNotEmpty;
  if (nouvelle) {
    await tester.enterText(find.byKey(const ValueKey('nv-identifiant')), CompteFictif.login);
    await tester.enterText(find.byKey(const ValueKey('nv-mot-de-passe')), CompteFictif.motDePasse);
    await tester.tap(find.byKey(const ValueKey('nv-connexion')));
  } else {
    await tester.enterText(find.widgetWithText(TextField, 'Identifiant'), CompteFictif.login);
    await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), CompteFictif.motDePasse);
    await tester.tap(find.text('CONNEXION'));
  }
  await tester.pump();
}

/// Touche « retour » du téléphone.
Future<void> retour(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}
