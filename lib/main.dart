// lib/main.dart
import 'package:flutter/material.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appConfig = AppConfig();
  await appConfig.load();

  // On passe authProvider à MyApp pour qu'il soit disponible dès le début
  runApp(MyApp(appConfig: appConfig));
}

class MyApp extends StatelessWidget {
  final AppConfig appConfig;

  const MyApp({super.key, required this.appConfig});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appConfig),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => EntryProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'Prestinv',
            theme: ThemeData(
              primarySwatch: Colors.deepOrange,
              visualDensity: VisualDensity.adaptivePlatformDensity,
            ),
            debugShowCheckedModeBanner: false,
            // Si l'utilisateur est connecté, on va à l'accueil, sinon à la page de connexion
            home: auth.isLoggedIn ? const HomeScreen() : const LoginScreen(),
          );
        },
      ),
    );
  }
}