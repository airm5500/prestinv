// Erreurs réseau ≠ liste vide : un échec de chargement affiche un message clair et « Réessayer »,
// jamais « Aucun inventaire » / « Aucun écart » / « Tout est inventorié » / « Produit introuvable ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/screens/global_variance_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/uncounted_screen.dart';
import 'package:prestinv/screens/variance_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/faux_prestige_http.dart';

void main() {
  group('ApiService : chaque échec a sa nature', () {
    late FauxPrestige srv;
    late ApiService api;
    setUp(() {
      srv = FauxPrestige(nombre: 3);
      api = ApiService(baseUrl: 'http://x/prestige', client: srv.client);
    });

    test('liste vide légitime : []', () async {
      srv.inventaires = {};
      expect(await api.fetchInventories(), isEmpty);
    });

    test('serveur injoignable : ApiLoadException réseau', () async {
      srv.injoignable = true;
      await expectLater(api.fetchInventories(), throwsA(isA<ApiLoadException>().having((e) => e.reseau, 'réseau', isTrue)));
      await expectLater(api.fetchRayons('INV1'), throwsA(isA<ApiLoadException>()));
      await expectLater(api.fetchUntouchedProducts('INV1'), throwsA(isA<ApiLoadException>()));
      await expectLater(api.fetchGlobalVariances('INV1'), throwsA(isA<ApiLoadException>()));
      await expectLater(api.fetchTouchedProductsByRayon('INV1', 'R1'), throwsA(isA<ApiLoadException>()));
    });

    test('401 : session expirée', () async {
      srv.codes['detailsAll'] = 401;
      await expectLater(api.fetchProducts('INV1', null, query: 'x'),
          throwsA(isA<ApiLoadException>().having((e) => e.sessionExpiree, 'session', isTrue)));
    });

    test('500 : refus ; réponse illisible : données', () async {
      srv.codes['rayons'] = 500;
      await expectLater(api.fetchRayons('INV1'), throwsA(isA<ApiLoadException>().having((e) => e.type, 'type', TypeErreurChargement.refus)));
    });

    test('état d\'un rayon en erreur : inconnu (null), plus « pas commencé » / « reste à faire »', () async {
      srv.injoignable = true;
      expect(await api.hasTouchedProductsInRayon('INV1', 'R1'), isNull);
      expect(await api.hasUntouchedProductsInRayon('INV1', 'R1'), isNull);
    });
  });

  testWidgets('liste des inventaires : serveur injoignable → message + Réessayer, puis la liste', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    b.serveur.injoignable = true;
    await tester.pumpWidget(monter(b, const InventoryListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Chargement impossible'), findsOneWidget);
    expect(find.textContaining('Serveur injoignable'), findsOneWidget);
    expect(find.text('Aucun inventaire trouvé.'), findsNothing);

    b.serveur.injoignable = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Inventaire test'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('liste des inventaires vide (vraiment) : « Aucun inventaire trouvé. »', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    b.serveur.inventaires = {};
    await tester.pumpWidget(monter(b, const InventoryListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Aucun inventaire trouvé.'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('restants : échec ≠ « Tout est inventorié ! »', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    b.serveur.routesInjoignables.addAll(['detailsAllUntouched', 'rayons']);
    await tester.pumpWidget(monter(b, const UncountedScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test')));
    await tester.pumpAndSettle();
    expect(find.text('Tout est inventorié !'), findsNothing);
    expect(find.text('Chargement impossible'), findsOneWidget);
    expect(find.textContaining('emplacements non chargés'), findsOneWidget); // bandeau du filtre
    b.serveur.routesInjoignables.clear();
    await tester.tap(find.widgetWithText(TextButton, 'Réessayer')); // bandeau des emplacements
    await tester.pumpAndSettle();
    expect(find.text(b.serveur.produits[0].nom), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('écarts : échec ≠ « Aucun écart trouvé ! »', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    b.serveur.injoignable = true;
    await tester.pumpWidget(monter(b, const GlobalVarianceScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test')));
    await tester.pumpAndSettle();
    expect(find.text('Aucun écart trouvé !'), findsNothing);
    expect(find.text('Chargement impossible'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('écarts d\'un emplacement : échec ≠ « Aucun produit avec un écart »', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    b.serveur.injoignable = true;
    await tester.pumpWidget(monter(b, const VarianceScreen(inventoryId: 'INV1', rayonId: 'R1', rayonName: 'RAYON UN')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun produit avec un écart'), findsNothing);
    expect(find.text('Chargement impossible'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('saisie guidée : emplacements non chargés → Réessayer (plus de texte rouge sans issue)', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    b.serveur.injoignable = true;
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1')));
    await tester.pumpAndSettle();
    expect(find.text('Chargement impossible'), findsOneWidget);
    b.serveur.injoignable = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Sélectionner un emplacement'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('scan en panne réseau : message réseau, jamais « Produit introuvable »', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    b.serveur.injoignable = true;
    await tester.enterText(find.byType(TextField).first, b.serveur.produits[0].cip);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Produit introuvable.'), findsNothing);
    expect(find.textContaining('Serveur injoignable'), findsOneWidget);
    expect(find.text('Mode Saisie Rapide Activé'), findsNothing); // l'écran n'est pas remplacé par l'erreur
    expect(find.byType(TextField), findsWidgets);
    await demonter(tester);
  });
}
