// Création d'un inventaire depuis le terminal (POST /inventaire/creation) : contrôle du libellé,
// confirmation, anti double création (double appui, libellé déjà ouvert, réponse perdue), erreurs du
// serveur ; l'inventaire créé apparaît dans la liste et s'ouvre.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/faux_prestige_http.dart';

void main() {
  group('LibelleInventaire', () {
    test('obligatoire, 3 à 100 caractères', () {
      expect(LibelleInventaire.erreur(''), 'Libellé obligatoire.');
      expect(LibelleInventaire.erreur('   '), 'Libellé obligatoire.');
      expect(LibelleInventaire.erreur('ab'), contains('trop court'));
      expect(LibelleInventaire.erreur('abc'), isNull);
      expect(LibelleInventaire.erreur('a' * 100), isNull);
      expect(LibelleInventaire.erreur('a' * 101), contains('trop long'));
    });

    test('caractères sûrs seulement (accents et ponctuation simple acceptés)', () {
      expect(LibelleInventaire.erreur('Inventaire réserve n°2 – octobre'.replaceAll('–', '-')), isNull);
      expect(LibelleInventaire.erreur("Réserve (S3) / 13.10.2026 #1 & co + l'étage"), isNull);
      for (final mauvais in ['<script>', 'a"b"c', 'abc;DROP', r'a\b\c', 'abc`', 'a{b}c', 'a|bc', r'a$bc', 'a%bc']) {
        expect(LibelleInventaire.erreur(mauvais), contains('Caractères non autorisés'), reason: mauvais);
      }
      expect(LibelleInventaire.erreur('...'), contains('lettres ou des chiffres'));
    });

    test('normalisation : espaces en trop retirés ; comparaison sans casse', () {
      expect(LibelleInventaire.normaliser('  Inventaire   réserve  '), 'Inventaire réserve');
      expect(LibelleInventaire.cle(' INVENTAIRE  Réserve'), LibelleInventaire.cle('inventaire réserve'));
    });
  });

  group('CreationInventaire (service)', () {
    late FauxPrestige srv;
    late CreationInventaire service;
    setUp(() {
      srv = FauxPrestige(nombre: 5);
      service = CreationInventaire(ApiService(baseUrl: 'http://x/prestige', client: srv.client));
    });

    test('création : envoie libellé + type, retrouve l\'inventaire dans la liste', () async {
      final r = await service.creer('  Inventaire   réserve ', TypeInventaire.emplacement);
      expect(r.issue, IssueCreation.creee);
      expect(srv.creations.single, ('Inventaire réserve', 'Emplacement'));
      expect(r.inventaire!.id, 'NEW1');
      expect(r.inventaire!.libelle, 'Inventaire réserve');
      expect(r.lignes, 5, reason: 'pré-rempli avec tous les produits');
    });

    test('types acceptés par le serveur', () async {
      expect(TypeInventaire.values.map((t) => t.valeur), ['Emplacement', 'Famille', 'Grossiste']);
      await service.creer('Par famille', TypeInventaire.famille);
      expect(srv.creations.single.$2, 'Famille');
    });

    test('libellé invalide : rien n\'est envoyé', () async {
      final r = await service.creer('<x>', TypeInventaire.emplacement);
      expect(r.issue, IssueCreation.libelleInvalide);
      expect(srv.appels, isEmpty);
    });

    test('anti double : libellé déjà porté par un inventaire OUVERT (sans casse) → refusé, rien de créé', () async {
      final r = await service.creer('INVENTAIRE  test', TypeInventaire.emplacement);
      expect(r.issue, IssueCreation.doublon);
      expect(r.inventaire!.id, 'INV1');
      expect(srv.creations, isEmpty);
    });

    test('anti double : double appui (deux demandes simultanées) → UNE seule création', () async {
      srv.delai = const Duration(milliseconds: 50);
      final a = service.creer('Réserve', TypeInventaire.emplacement);
      final b = service.creer('Réserve', TypeInventaire.emplacement);
      final rb = await b;
      final ra = await a;
      expect(rb.issue, IssueCreation.dejaEnCours);
      expect(ra.issue, IssueCreation.creee);
      expect(srv.creations.length, 1);
      // Nouvel essai après coup : le libellé existe désormais → doublon, pas de 2ᵉ création.
      final rc = await service.creer('Réserve', TypeInventaire.emplacement);
      expect(rc.issue, IssueCreation.doublon);
      expect(srv.creations.length, 1);
    });

    test('réponse perdue après création : l\'inventaire est retrouvé, jamais créé deux fois', () async {
      srv.creationReponsePerdue = true;
      final r = await service.creer('Réserve', TypeInventaire.emplacement);
      expect(r.issue, IssueCreation.creee);
      expect(r.inventaire!.id, 'NEW1');
      srv.creationReponsePerdue = false;
      expect((await service.creer('Réserve', TypeInventaire.emplacement)).issue, IssueCreation.doublon);
      expect(srv.creations.length, 1);
    });

    test('refus du serveur (sélection vide, libellé) : message du serveur', () async {
      srv.reponseCreation = {'success': 0, 'message': "Aucun inventaire n'a ete cree. Cause : aucun produit ne correspond aux criteres retenus."};
      final r = await service.creer('Réserve', TypeInventaire.emplacement);
      expect(r.issue, IssueCreation.refus);
      expect(r.message, contains('Aucun inventaire'));
    });

    test('session expirée (401) ; erreur interne (500) ; serveur injoignable avant envoi', () async {
      srv.codes['creation'] = 401;
      expect((await service.creer('Réserve', TypeInventaire.emplacement)).issue, IssueCreation.session);
      srv.codes['creation'] = 500;
      final r500 = await service.creer('Réserve', TypeInventaire.emplacement);
      expect(r500.issue, IssueCreation.refus);
      expect(r500.message, contains('Erreur du serveur'));
      srv.codes.remove('creation');
      srv.injoignable = true;
      final r = await service.creer('Réserve', TypeInventaire.emplacement);
      expect(r.issue, IssueCreation.reseau);
      expect(srv.creations, isEmpty);
    });
  });

  testWidgets('écran : contrôles du libellé, confirmation, création, l\'inventaire apparaît dans la liste et s\'ouvre', (tester) async {
    ecranTerminal(tester);
    reinitialiserDouchette();
    installerFauxRetour();
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const InventoryListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Inventaire test'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nouvel-inventaire')));
    await tester.pumpAndSettle();
    expect(find.text('Nouvel inventaire'), findsOneWidget);

    // Libellé vide puis interdit : refusé sur place, rien n'est envoyé.
    await tester.tap(find.byKey(const ValueKey('bouton-creer')));
    await tester.pumpAndSettle();
    expect(find.text('Libellé obligatoire.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve <1>');
    await tester.tap(find.byKey(const ValueKey('bouton-creer')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Caractères non autorisés'), findsOneWidget);
    expect(b.serveur.creations, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve octobre');
    await tester.tap(find.byKey(const ValueKey('type-famille')));
    await tester.tap(find.byKey(const ValueKey('bouton-creer')));
    await tester.pumpAndSettle();
    expect(find.text('Créer l\'inventaire ?'), findsOneWidget);
    expect(find.textContaining('TOUS les produits actifs'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirmer-creation')));
    await tester.pumpAndSettle();
    expect(b.serveur.creations.single, ('Réserve octobre', 'Famille'));

    // Retour à la liste : le nouvel inventaire y est, marqué, et s'ouvre.
    expect(find.text('Réserve octobre'), findsOneWidget);
    expect(find.text('Nouveau — créé depuis ce terminal'), findsOneWidget);
    await tester.tap(find.text('Réserve octobre'));
    await tester.pumpAndSettle();
    expect(find.byType(InventoryEntryScreen), findsOneWidget);
    expect(tester.widget<InventoryEntryScreen>(find.byType(InventoryEntryScreen)).inventoryId, 'NEW1');
    await demonter(tester);
  });

  testWidgets('écran : libellé déjà ouvert → proposé à l\'utilisation, rien de créé ; erreur serveur affichée', (tester) async {
    ecranTerminal(tester);
    reinitialiserDouchette();
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const InventoryListScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nouvel-inventaire')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'inventaire TEST');
    await tester.tap(find.byKey(const ValueKey('bouton-creer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmer-creation')));
    await tester.pumpAndSettle();
    expect(find.text('Libellé déjà utilisé'), findsOneWidget);
    await tester.tap(find.text('Changer le libellé'));
    await tester.pumpAndSettle();
    expect(b.serveur.creations, isEmpty);

    b.serveur.codes['creation'] = 500;
    await tester.enterText(find.byKey(const ValueKey('libelle-inventaire')), 'Réserve');
    await tester.tap(find.byKey(const ValueKey('bouton-creer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmer-creation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('erreur-creation')), findsOneWidget);
    expect(find.textContaining('Erreur du serveur'), findsOneWidget);
    expect(find.text('Nouvel inventaire'), findsOneWidget, reason: 'on reste sur l\'écran');
    await demonter(tester);
  });
}
