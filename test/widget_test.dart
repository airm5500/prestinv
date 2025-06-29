// test/widget_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/main.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// CORRECTION : Ajout de l'import manquant pour HomeScreen
import 'package:prestinv/screens/home_screen.dart';

void main() {
  testWidgets('App starts and displays login screen by default', (WidgetTester tester) async {
    // ARRANGE : On prépare l'environnement de test.

    // On crée une fausse version en mémoire de SharedPreferences pour éviter les erreurs.
    SharedPreferences.setMockInitialValues({});

    // On crée les instances des providers requis par le widget MyApp.
    final appConfig = AppConfig();
    await appConfig.load();

    final authProvider = AuthProvider();

    // ACT : On construit notre application en lui fournissant les providers.
    await tester.pumpWidget(MyApp(appConfig: appConfig, authProvider: authProvider));

    // ASSERT : On vérifie le résultat attendu.

    // Par défaut, l'utilisateur n'est pas connecté,
    // donc on s'attend à voir l'écran de connexion (LoginScreen).
    expect(find.byType(LoginScreen), findsOneWidget);

    // On peut aussi vérifier que l'écran d'accueil n'est PAS visible.
    expect(find.byType(HomeScreen), findsNothing);
  });
}