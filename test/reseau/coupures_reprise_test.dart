// RÉSEAU — ALTERNANCE coupure → retour, plusieurs fois, et reprise de la file des saisies :
//  - service (vrai serveur HTTP local) : coupures avant l'envoi, PENDANT un envoi (connexion fermée
//    au milieu d'une requête), retours successifs : à la fin, chaque quantité est sur le serveur avec sa
//    DERNIÈRE valeur, aucune saisie perdue, aucune confirmée deux fois ;
//  - application entière (mode Direct) : coupure → saisies gardées → retour → envoi automatique (reprise
//    toutes les 15 s), trois cycles de suite, sans message bloquant ni double envoi.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/saisie/saisie_queue.dart';

import '../helpers/banc_essai.dart' show DisqueMemoire;
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';

void main() {
  group('File des saisies contre le vrai serveur HTTP local', () {
    late FauxServeurPrestige serveur;
    late String base;

    setUpAll(() => HttpOverrides.global = null);
    setUp(() async {
      ApiService.clientParDefaut = null;
      serveur = FauxServeurPrestige(exigerSession: false);
      base = await serveur.demarrer();
    });
    tearDown(() => serveur.arreter());

    test('coupure → retour ×4 (dont coupures en pleine requête) : tout arrive, dernière valeur, sans doublon', () async {
      final file = SaisieQueue(store: DisqueMemoire())..serveurFactory = () => ApiService(baseUrl: base);
      await file.load();
      final ids = [for (final p in serveur.catalogue.produits) p.id];
      final attendu = <int, int>{};

      for (var cycle = 0; cycle < 4; cycle++) {
        // Saisies pendant que le serveur répond, puis coupure.
        for (final id in ids.skip(cycle * 3).take(3)) {
          attendu[id] = 10 + cycle;
          await file.enregistrer(inventaireId: 'INV1', ligneId: id, quantite: 10 + cycle);
        }
        serveur.couper();
        final coupe = await file.envoyer();
        expect(coupe.envoyees, 0, reason: 'cycle $cycle : serveur coupé, rien de confirmé');
        expect(coupe.interruption, contains('injoignable'));
        // Correction d'une saisie déjà faite pendant la coupure (dernière valeur gagnante).
        attendu[ids[0]] = 100 + cycle;
        await file.enregistrer(inventaireId: 'INV1', ligneId: ids[0], quantite: 100 + cycle);

        serveur.retablir();
        // La première quantité envoyée est coupée en pleine requête (connexion fermée sans réponse).
        serveur.scripter('details', ReponseScriptee.coupee(fois: 1), methode: 'PUT');
        await file.envoyer();
        // Puis le serveur répond normalement : la file repart d'elle-même.
        await file.envoyer();
        expect(file.enAttente(), 0, reason: 'cycle $cycle : tout est parti au retour');
      }
      for (final e in attendu.entries) {
        expect(serveur.catalogue.produit(e.key).saisi, e.value, reason: 'ligne ${e.key} : dernière valeur saisie');
      }
      // Chaque ligne n'est confirmée (posée sur le serveur) qu'une fois par valeur envoyée.
      final poses = serveur.catalogue.puts;
      expect(poses.toSet().length, poses.length, reason: 'aucune valeur posée deux fois : $poses');
    });
  });

  group('Application entière (mode Direct)', () {
    setUpAll(chargerPolicesReelles);

    testWidgets('coupure → saisie gardée → retour → envoi automatique, trois cycles', (tester) async {
      tailleEcran(tester, telephone360);
      final app = await lancerApplication(tester, mode: SendMode.direct);
      await seConnecter(tester);
      await choisirInventaire(tester, 'INV1');
      await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
      await tester.pumpAndSettle();
      await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
      await tester.pumpAndSettle();

      for (var cycle = 1; cycle <= 3; cycle++) {
        app.serveur.couper();
        await taperNv(tester, '$cycle');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(app.saisies.enAttente(), 1, reason: 'cycle $cycle : saisie gardée pendant la coupure');
        expect(find.text('Veuillez sauvegarder vos saisies'), findsNothing);

        app.serveur.retablir();
        await tester.pump(const Duration(seconds: 16)); // reprise automatique toutes les 15 s
        await tester.pumpAndSettle();
        expect(app.saisies.enAttente(), 0, reason: 'cycle $cycle : envoyée seule au retour du serveur');
      }
      final puts = app.serveur.catalogue.puts;
      expect(puts, hasLength(3), reason: 'une requête aboutie par saisie, aucun double envoi : $puts');
      await fermerApplication(tester);
    });
  });
}
