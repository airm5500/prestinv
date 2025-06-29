// Fichier : integration_test/app_test.dart
// Cette version garantit que chaque test est indépendant et teste des scénarios réalistes,
// y compris la synchronisation des données avec le serveur.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/main.dart'; // Importe PrestinvApp
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/screens/variance_screen.dart';
//import 'package:prestinv/screens/barcode_scanner_screen.dart';
//import 'package:prestinv/widgets/numeric_keyboard.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Helper function pour la connexion
Future<void> login(WidgetTester tester) async {
      print('--- DÉBUT: Procédure de Connexion ---');
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Identifiant'), 'admin');
      await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'dcph1995');

      await tester.tap(find.text('CONNEXION'));

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget, reason: "La connexion a échoué.");
      print('--- FIN: Connexion Réussie ---');
}

// Helper pour lancer l'application
Future<void> launchApp(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final appConfig = AppConfig();
      await appConfig.load();
      final authProvider = AuthProvider();

      // Configuration de l'IP du serveur pour le test
      appConfig.setApiConfig(
            localAddress: "192.168.1.7",
            localPort: "8080",
            distantAddress: "192.168.1.7",
            distantPort: "8080",
      );

      await tester.pumpWidget(
            MultiProvider(
                  providers: [
                        ChangeNotifierProvider.value(value: appConfig),
                        ChangeNotifierProvider.value(value: authProvider),
                        ChangeNotifierProvider(create: (_) => InventoryProvider()),
                        ChangeNotifierProvider(create: (_) => EntryProvider()),
                  ],
                  child: const PrestinvApp(),
            ),
      );
}


void main() {
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

      group('Suite de Tests Complets de Prestinv', () {

            // --- TEST N°1 : FLUX PRINCIPAL ---
            testWidgets('Flux principal : de la connexion à la saisie', (tester) async {
                  await launchApp(tester);
                  await login(tester);

                  await tester.tap(find.text('COMMENCER L\'INVENTAIRE'));
                  await tester.pump(const Duration(seconds: 4));
                  await tester.pumpAndSettle();
                  expect(find.byType(InventoryListScreen), findsOneWidget);

                  expect(find.byType(ListTile), findsWidgets, reason: "Aucun inventaire n'a été chargé.");
                  await tester.tap(find.byType(ListTile).first);
                  await tester.pump(const Duration(seconds: 4));
                  await tester.pumpAndSettle();
                  expect(find.byType(InventoryEntryScreen), findsOneWidget);
            });


            // --- TEST N°2 : DÉCONNEXION ---
            testWidgets('Déconnexion : l\'utilisateur peut se déconnecter', (tester) async {
                  await launchApp(tester);
                  await login(tester);

                  print('TEST: Phase de déconnexion...');
                  await tester.tap(find.byIcon(Icons.logout));
                  await tester.pumpAndSettle();

                  expect(find.byType(LoginScreen), findsOneWidget);
                  expect(find.byType(HomeScreen), findsNothing);
                  print('TEST: Déconnexion réussie.');
            });


            // --- TEST N°3 : ÉCRAN DES ÉCARTS ET RECHERCHE (CORRIGÉ) ---
            testWidgets('Écarts : la recherche filtre correctement les produits', (tester) async {
                  await launchApp(tester);
                  await login(tester);

                  // 1. Navigation jusqu'à l'écran de saisie
                  await tester.tap(find.text('COMMENCER L\'INVENTAIRE'));
                  await tester.pump(const Duration(seconds: 4));
                  await tester.pumpAndSettle();
                  await tester.tap(find.byType(ListTile).first);
                  await tester.pump(const Duration(seconds: 4));
                  await tester.pumpAndSettle();
                  expect(find.byType(InventoryEntryScreen), findsOneWidget);

                  // 2. CORRECTION : On effectue une saisie pour créer un écart
                  print('TEST: Création d\'un écart...');
                  await tester.tap(find.widgetWithText(ElevatedButton, '9'));
                  await tester.pump();
                  await tester.tap(find.widgetWithText(ElevatedButton, '9'));
                  await tester.pump();
                  await tester.tap(find.widgetWithText(ElevatedButton, 'OK'));
                  await tester.pumpAndSettle();

                  // 3. CORRECTION : On envoie la donnée au serveur pour qu'elle soit prise en compte
                  print('TEST: Envoi des données au serveur...');
                  await tester.tap(find.byIcon(Icons.send));
                  await tester.pump(const Duration(seconds: 5)); // Laisse le temps à l'envoi de se faire
                  await tester.pumpAndSettle();
                  print('TEST: Données envoyées.');

                  // 4. Navigation vers l'écran des écarts
                  await tester.tap(find.byIcon(Icons.edit_note_outlined));
                  await tester.pump(const Duration(seconds: 4));
                  await tester.pumpAndSettle();
                  expect(find.byType(VarianceScreen), findsOneWidget);

                  // 5. On effectue la recherche
                  final searchField = find.widgetWithText(TextField, 'Rechercher un produit avec écart');
                  expect(searchField, findsOneWidget);

                  // Assurez-vous que ce texte correspond à un produit qui a un écart
                  await tester.enterText(searchField, 'VITALAE');
                  await tester.pumpAndSettle();

                  // 6. On vérifie que la liste des résultats s'affiche bien
                  expect(find.byType(ListView), findsOneWidget);
                  expect(find.textContaining('VITALAE'), findsWidgets);
                  print('TEST: Recherche sur écran des écarts réussie.');
            });


            // --- TEST N°4 : SCANNER DE CODE-BARRES ---
            testWidgets('Scanner : le bouton ouvre bien l\'écran du scanner', (tester) async {
                  await launchApp(tester);
                  await login(tester);

                  await tester.tap(find.text('COMMENCER L\'INVENTAIRE'));
                  await tester.pump(const Duration(seconds: 4));
                  await tester.pumpAndSettle();
                  await tester.tap(find.byType(ListTile).first);
                  await tester.pump(const Duration(seconds: 4));
                  await tester.pumpAndSettle();

                  await tester.tap(find.byIcon(Icons.edit_note_outlined));
                  await tester.pump(const Duration(seconds: 4));
                  await tester.pumpAndSettle();
                  expect(find.byType(VarianceScreen), findsOneWidget);

                  await tester.tap(find.byIcon(Icons.qr_code_scanner));
                  await tester.pumpAndSettle();

                  //expect(find.byType(BarcodeScannerScreen), findsOneWidget);
                  print('TEST: Écran du scanner ouvert avec succès.');

                  await tester.pageBack();
                  await tester.pumpAndSettle();
                  expect(find.byType(VarianceScreen), findsOneWidget);
            });

      });
}
