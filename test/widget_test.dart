// Fichier : test/widget_test.dart
// Ce test par défaut a été mis à jour pour correspondre à l'architecture actuelle de l'application.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/main.dart'; // Importe PrestinvApp
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App starts and displays login screen by default', (WidgetTester tester) async {
    // ARRANGE : On prépare l'environnement et les providers, comme dans le test d'intégration.
    SharedPreferences.setMockInitialValues({});

    final appConfig = AppConfig();
    await appConfig.load();
    final authProvider = AuthProvider();

    // ACT : On construit l'application avec sa structure de providers correcte.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appConfig),
          ChangeNotifierProvider.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => InventoryProvider()),
          ChangeNotifierProvider(create: (_) => EntryProvider()),
        ],
        // CORRECTION : On utilise le nouveau widget racine PrestinvApp au lieu de MyApp
        child: const PrestinvApp(),
      ),
    );

    // On attend que l'UI se stabilise
    await tester.pumpAndSettle();

    // ASSERT : On vérifie que, par défaut, l'écran de connexion est bien affiché.
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
