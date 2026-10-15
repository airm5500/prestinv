// RÉSEAU — réponses TRONQUÉES et JSON PARTIEL :
//  - au niveau HTTP (vrai serveur local) : longueur annoncée non atteinte, connexion fermée au milieu
//    du corps → panne RÉSEAU (« injoignable », réessai), jamais une liste vide ni « aucune licence » ;
//  - réponse complète mais JSON partiel (serveur qui coupe sa propre réponse) → « réponse illisible »
//    (données), jamais une liste vide ; envoi d'une quantité → saisie gardée, pas marquée envoyée ;
//  - à l'écran (application entière) : message et « Réessayer », puis la liste au retour d'une réponse
//    correcte.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart' show DisqueMemoire;
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';

const listePartielle = '[{"id":"INV1","libelle":"Inventaire annuel 2026"},{"id":"INV2","libel';
const lignesPartielles = '[{"id":2,"produitCip":"3400935959001","produitName":"AMOXI';

void main() {
  group('Service contre le vrai serveur HTTP local', () {
    late FauxServeurPrestige serveur;
    late String base;

    setUpAll(() => HttpOverrides.global = null);
    setUp(() async {
      ApiService.clientParDefaut = null;
      serveur = FauxServeurPrestige(exigerSession: false);
      base = await serveur.demarrer();
    });
    tearDown(() => serveur.arreter());

    Matcher erreur(TypeErreurChargement type, String texte) =>
        throwsA(isA<ApiLoadException>().having((e) => e.type, 'type', type).having((e) => e.message, 'message', contains(texte)));

    test('liste coupée en cours de transfert (longueur annoncée non atteinte) → panne réseau, pas liste vide', () async {
      serveur.scripter('inventaires', ReponseScriptee.tronquee(listePartielle));
      await expectLater(ApiService(baseUrl: base).fetchTousInventairesOuverts(), erreur(TypeErreurChargement.reseau, 'injoignable'));
    });

    test('JSON partiel dans une réponse complète → « réponse illisible », pas liste vide', () async {
      serveur.scripter('inventaires', ReponseScriptee.json(listePartielle));
      await expectLater(ApiService(baseUrl: base).fetchTousInventairesOuverts(), erreur(TypeErreurChargement.donnees, 'illisible'));
      serveur.scripter('details', ReponseScriptee.json(lignesPartielles));
      await expectLater(ApiService(baseUrl: base).fetchProducts('INV1', 'S2B2'), erreur(TypeErreurChargement.donnees, 'illisible'));
    });

    test('« déjà compté » sur une réponse partielle → erreur, jamais « jamais compté »', () async {
      serveur.scripter('detailsAllTouched', ReponseScriptee.json(lignesPartielles));
      await expectLater(ApiService(baseUrl: base).verifierDejaCompte('INV1', '3400935959001'), throwsA(isA<ApiLoadException>()));
      serveur.scripter('detailsAllTouched', ReponseScriptee.tronquee(lignesPartielles));
      await expectLater(ApiService(baseUrl: base).verifierDejaCompte('INV1', '3400935959001'), throwsA(isA<ApiLoadException>()));
    });

    test('licence coupée en cours de transfert → « serveur injoignable », PAS « aucune licence »', () async {
      serveur.scripter('licence/find', ReponseScriptee.tronquee('{"id":"LIC-ESSAI-0001","dateStart":"2026-01-01","dateE'));
      SharedPreferences.setMockInitialValues({});
      final l = LicenseProvider();
      await l.checkLicense(ApiService(baseUrl: base));
      expect(l.status, LicenseStatus.unreachable);
    });

    test('envoi d\'une quantité : réponse tronquée → saisie gardée (réseau), renvoyée ensuite', () async {
      final api = ApiService(baseUrl: base);
      serveur.scripter('inventaire/ligne/quantite', ReponseScriptee.tronquee('{"success":1,"int_NUMB'), methode: 'POST');
      final r = await api.poserQuantiteSession(2, 5);
      expect(r.type, ResultatEnvoi.reseau, reason: 'pas de confirmation lisible : la saisie reste à envoyer');
      serveur.scripter('inventaire/ligne/quantite', ReponseScriptee.json('{"success":1,"int_NUMB'), methode: 'POST');
      expect((await api.poserQuantiteSession(2, 5)).type, isNot(ResultatEnvoi.ok), reason: 'JSON partiel : jamais « envoyée »');
      serveur.oublierScripts();
      expect((await api.poserQuantiteSession(2, 5)).type, ResultatEnvoi.ok);
    });

    test('file des saisies : liste des inventaires tronquée → rien n\'est marqué envoyé, tout part au retour', () async {
      final file = SaisieQueue(store: DisqueMemoire())..serveurFactory = () => ApiService(baseUrl: base);
      await file.load();
      for (final id in [2, 3, 4]) {
        await file.enregistrer(inventaireId: 'INV1', ligneId: id, quantite: id * 2);
      }
      serveur.scripter('ws/inventaires', ReponseScriptee.tronquee(listePartielle), methode: 'GET');
      final b = await file.envoyer();
      expect(b.envoyees, 0);
      expect(file.enAttente(), 3);
      expect(serveur.recues('details', methode: 'PUT'), isEmpty);
      serveur.oublierScripts();
      expect((await file.envoyer()).envoyees, 3);
      expect(serveur.catalogue.produit(4).saisi, 8);
    });
  });

  group('Écrans (application entière)', () {
    setUpAll(chargerPolicesReelles);

    for (final (cas, reponse) in [
      ('coupée en cours de transfert', ReponseScriptee.tronquee(listePartielle, fois: 1)),
      ('JSON partiel', ReponseScriptee.json(listePartielle, fois: 1)),
    ]) {
      testWidgets('accueil, liste des inventaires $cas : message + « Réessayer », jamais une liste vide trompeuse', (tester) async {
        tailleEcran(tester, telephone360);
        final app = await lancerApplication(tester);
        app.serveur.scripter('inventaires', reponse, methode: 'GET');
        await seConnecter(tester);
        await deroulerInventaires(tester);
        expect(find.textContaining('Aucun inventaire'), findsNothing);
        expect(find.byKey(const ValueKey('nv-ouvrir-INV1')), findsNothing);
        expect(find.textContaining('Réessayer'), findsWidgets);
        await tester.tap(find.textContaining('Réessayer').first);
        await tester.pumpAndSettle();
        await deroulerInventaires(tester);
        expect(find.byKey(const ValueKey('nv-ouvrir-INV1')), findsOneWidget, reason: 'réponse correcte au nouvel essai');
        await fermerApplication(tester);
      });
    }

    testWidgets('saisie guidée : rayon en JSON partiel → message + « Réessayer », puis produits', (tester) async {
      tailleEcran(tester, telephone360);
      final app = await lancerApplication(tester);
      await seConnecter(tester);
      await choisirInventaire(tester, 'INV1');
      await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
      await tester.pumpAndSettle();
      app.serveur.scripter('details', ReponseScriptee.json(lignesPartielles, fois: 1), methode: 'GET');
      await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
      await tester.pumpAndSettle();
      expect(find.textContaining('illisible'), findsWidgets);
      expect(find.byKey(const ValueKey('nv-produit-courant')), findsNothing);
      await tester.tap(find.textContaining('Réessayer').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-produit-courant')), findsOneWidget);
      await fermerApplication(tester);
    });
  });
}
