// Fichier : test/widget_test.dart
// Démarrage de l'application : avec une licence valide et sans session, l'écran de connexion s'affiche.
// (Réparé : le test d'origine ne fournissait pas LicenseProvider → ProviderNotFoundException.)

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/main.dart';
import 'package:prestinv/models/license.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Licence valide, sans aucun appel au serveur (les tests n'ont pas de réseau).
class _LicenceValide extends LicenseProvider {
  @override
  Future<void> checkLicense(ApiService api, {bool silent = false}) async {
    final now = DateTime.now();
    setLicenseForTest(License(
      id: 'test',
      dateStart: now.subtract(const Duration(days: 1)),
      dateEnd: now.add(const Duration(days: 365)),
      typeLicence: 'TEST',
    ));
  }
}

void main() {
  testWidgets('App starts and displays login screen by default', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    final appConfig = AppConfig();
    await appConfig.load();
    final authProvider = AuthProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appConfig),
          ChangeNotifierProvider.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => InventoryProvider()),
          ChangeNotifierProvider(create: (_) => EntryProvider()),
          ChangeNotifierProvider<LicenseProvider>(create: (_) => _LicenceValide()),
        ],
        child: const PrestinvApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
