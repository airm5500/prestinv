// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart'; // Importez AppConfig

import 'package:prestinv/main.dart';

void main() {
  // Le test a été renommé pour être plus pertinent
  testWidgets('App starts and displays home screen', (WidgetTester tester) async {
    // Créez une instance de configuration pour le test
    final appConfig = AppConfig();

    // Dans un environnement de test, SharedPreferences a besoin d'être initialisé
    // avec des valeurs "mock" (factices). Nous le laissons vide ici.
    // Vous devrez peut-être ajouter le package `shared_preferences_platform_interface`
    // dans vos dev_dependencies si ce n'est pas déjà fait.
    // Mais en général, `flutter test` le gère bien.

    // Comme `load()` est asynchrone, nous l'attendons.
    await appConfig.load();

    // Construisez notre application en fournissant le paramètre requis
    await tester.pumpWidget(MyApp(appConfig: appConfig));

    // Vérifiez que le titre de l'écran d'accueil est bien présent.
    // C'est un bon "smoke test" pour s'assurer que l'app a démarré correctement.
    expect(find.text('Prestinv - Accueil'), findsOneWidget);

    // Le test par défaut cherchait des '0' et des '1', ce qui n'est plus le cas.
    // Nous vérifions aussi qu'un bouton est présent.
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
}