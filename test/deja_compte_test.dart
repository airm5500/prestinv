// « Déjà compté ? » (cumul) sur réseau lent ou coupé : un échec ne veut JAMAIS dire « jamais compté ».
// On redemande (Réessayer) ou on annule sans rien enregistrer. (Correction P2.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/faux_prestige_http.dart';

Future<void> scanner(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField).first, code);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  group('ApiService.verifierDejaCompte', () {
    late FauxPrestige srv;
    late ApiService api;
    setUp(() {
      srv = FauxPrestige(nombre: 4);
      api = ApiService(baseUrl: 'http://x/prestige', client: srv.client);
    });

    test('jamais compté : null', () async {
      expect(await api.verifierDejaCompte('INV1', srv.produits[0].cip, ligneId: srv.produits[0].id), isNull);
    });

    test('déjà compté : la quantité du serveur', () async {
      srv.produits[0]
        ..saisi = 7
        ..dtUpdated = '2026-10-13';
      expect(await api.verifierDejaCompte('INV1', srv.produits[0].cip, ligneId: srv.produits[0].id), 7);
    });

    test('serveur injoignable : exception (jamais « null »)', () async {
      srv.injoignable = true;
      await expectLater(api.verifierDejaCompte('INV1', srv.produits[0].cip), throwsA(isA<ApiLoadException>().having((e) => e.reseau, 'reseau', isTrue)));
    });

    test('session expirée (401) : exception typée session', () async {
      srv.codes['detailsAllTouched'] = 401;
      await expectLater(api.verifierDejaCompte('INV1', srv.produits[0].cip), throwsA(isA<ApiLoadException>().having((e) => e.sessionExpiree, 'session', isTrue)));
    });

    test('erreur serveur (500) ou réponse illisible : exception', () async {
      srv.codes['detailsAllTouched'] = 500;
      await expectLater(api.verifierDejaCompte('INV1', srv.produits[0].cip), throwsA(isA<ApiLoadException>()));
    });

    test('même produit dans deux emplacements : c\'est la ligne scannée qui compte', () async {
      final autre = FauxProduit(9999, srv.produits[0].cip, srv.produits[0].nom, 'R2', 1, saisi: 12)..dtUpdated = '2026-10-13';
      srv.produits.add(autre);
      expect(await api.verifierDejaCompte('INV1', srv.produits[0].cip, ligneId: srv.produits[0].id), isNull);
      expect(await api.verifierDejaCompte('INV1', srv.produits[0].cip, ligneId: 9999), 12);
    });
  });

  testWidgets('réseau lent (> 10 s) : « Vérification impossible », rien n\'est enregistré ni écrasé', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.direct, cumul: true);
    final p = b.serveur.produits[0]
      ..saisi = 7
      ..dtUpdated = '2026-10-13'; // un collègue a déjà compté 7
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await scanner(tester, p.cip);
    b.serveur.delais['detailsAllTouched'] = const Duration(seconds: 12);
    await taperQuantite(tester, '3');
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Vérification impossible'), findsOneWidget);
    expect(b.disque.saisies, isEmpty);

    await tester.tap(find.text('Annuler').last);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(b.disque.saisies, isEmpty);
    expect(b.serveur.puts, isEmpty);
    expect(p.saisi, 7); // le comptage du collègue n'est pas écrasé
    await demonter(tester);
  });

  testWidgets('serveur injoignable puis revenu : Réessayer → « Déjà compté » → Additionner (7 + 3 = 10)', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.direct, cumul: true);
    final p = b.serveur.produits[0]
      ..saisi = 7
      ..dtUpdated = '2026-10-13';
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await scanner(tester, p.cip);
    b.serveur.routesInjoignables.add('detailsAllTouched');
    await taperQuantite(tester, '3');
    await tester.pumpAndSettle();
    expect(find.text('Vérification impossible'), findsOneWidget);
    expect(b.disque.saisies, isEmpty);

    b.serveur.routesInjoignables.clear();
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('⚠️ Déjà compté'), findsOneWidget);
    await tester.tap(find.text('OUI (Additionner)'));
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.quantite, 10);
    expect(p.saisi, 10); // mode Direct : parti
    await demonter(tester);
  });

  testWidgets('une saisie encore en attente sur l\'appareil compte comme « déjà compté » (même hors réseau)', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect, cumul: true);
    final p = b.serveur.produits[1];
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await scanner(tester, p.cip);
    await taperQuantite(tester, '5');
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.quantite, 5);

    await scanner(tester, p.cip);
    b.serveur.routesInjoignables.add('detailsAllTouched');
    await taperQuantite(tester, '3');
    await tester.pumpAndSettle();
    expect(find.text('⚠️ Déjà compté'), findsOneWidget);
    await tester.tap(find.text('OUI (Additionner)'));
    await tester.pumpAndSettle();
    expect(b.disque.saisies.single.quantite, 8);
    await demonter(tester);
  });

  testWidgets('cumul désactivé (Remplacer, réglage par défaut) : aucune vérification, la saisie remplace', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc(mode: SendMode.collect, cumul: false);
    final p = b.serveur.produits[2]
      ..saisi = 7
      ..dtUpdated = '2026-10-13';
    await tester.pumpWidget(monter(b, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true)));
    await tester.pumpAndSettle();
    await scanner(tester, p.cip);
    await taperQuantite(tester, '4');
    await tester.pumpAndSettle();
    expect(b.serveur.appels.where((a) => a.endsWith('detailsAllTouched')), isEmpty);
    expect(b.disque.saisies.single.quantite, 4);
    await demonter(tester);
  });
}
