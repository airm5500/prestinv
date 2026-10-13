// Lancement : serveur injoignable ≠ « Application non activée » ; réessai automatique toutes les 10 s ;
// licence revérifiée au retour sans sablier ; dates de licence contrôlées.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/main.dart';
import 'package:prestinv/models/license.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/screens/license_register_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/screens/serveur_injoignable_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/banc_essai.dart';
import 'helpers/faux_prestige_http.dart';

void main() {
  group('LicenseProvider', () {
    late FauxPrestige srv;
    late ApiService api;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      srv = FauxPrestige(nombre: 1);
      api = ApiService(baseUrl: 'http://x/prestige', client: srv.client);
    });

    test('serveur injoignable, aucune licence en cache : « injoignable », PAS « non activée »', () async {
      srv.injoignable = true;
      final l = LicenseProvider();
      await l.checkLicense(api);
      expect(l.status, LicenseStatus.unreachable);
    });

    test('serveur injoignable avec une licence en cache : on continue avec le cache (inchangé)', () async {
      final l = LicenseProvider();
      await l.checkLicense(api);
      expect(l.status, LicenseStatus.valid);
      srv.injoignable = true;
      final l2 = LicenseProvider();
      await l2.checkLicense(api);
      expect(l2.status, LicenseStatus.valid);
    });

    test('le serveur répond sans licence (corps vide, comme le serveur de test) : « non activée »', () async {
      srv.codes['find'] = 200;
      final l = LicenseProvider();
      await l.checkLicense(api);
      expect(l.status, LicenseStatus.none);
    });

    test('erreur du serveur (500) sur la licence : « injoignable / erreur serveur », PAS « non activée »', () async {
      srv.codes['find'] = 500;
      final l = LicenseProvider();
      await l.checkLicense(api);
      expect(l.status, LicenseStatus.unreachable);
      expect(l.error, contains('code 500'));
    });

    test('vérification au retour au premier plan : aucun passage par « chargement »', () async {
      final l = LicenseProvider();
      await l.checkLicense(api);
      final etats = <LicenseStatus>[];
      l.addListener(() => etats.add(l.status));
      srv.injoignable = true;
      await l.checkLicense(api, silent: true);
      expect(etats, isNot(contains(LicenseStatus.loading)));
      expect(l.status, LicenseStatus.valid);
    });

    test('dates de licence contrôlées (ISO, horodatage, illisible)', () {
      expect(License.lireDate('2027-12-31T00:00:00Z[UTC]'), DateTime(2027, 12, 31));
      expect(License.lireDate('2027-02-28'), DateTime(2027, 2, 28));
      expect(License.lireDate(DateTime(2027, 1, 2).millisecondsSinceEpoch), DateTime(2027, 1, 2));
      expect(() => License.lireDate('31/12/2027'), throwsFormatException);
      expect(() => License.lireDate('2027-02-31'), throwsFormatException);
      expect(() => License.lireDate(null), throwsFormatException);
    });
  });

  testWidgets('premier lancement serveur éteint : écran « Serveur injoignable », réessai auto 10 s, puis connexion',
      (tester) async {
    SharedPreferences.setMockInitialValues({'localApiAddress': 'serveur-test'});
    final srv = FauxPrestige(nombre: 1)..injoignable = true;
    ApiService.clientParDefaut = srv.client;
    final config = AppConfig();
    await config.load();
    final saisies = SaisieQueue(store: DisqueMemoire());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: config),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: saisies),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => EntryProvider(queue: saisies)),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
      ],
      child: const PrestinvApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ServeurInjoignableScreen), findsOneWidget);
    expect(find.byType(LicenseRegisterScreen), findsNothing);
    expect(find.text('Application non activée'), findsNothing);

    // Le serveur revient : sans rien toucher, l'essai suivant (10 s) mène à la connexion.
    srv.injoignable = false;
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    saisies.arreterReprise();
    ApiService.clientParDefaut = null;
  });
}
