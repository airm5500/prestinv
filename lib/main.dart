// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Créer une instance d'AppConfig.
  final appConfig = AppConfig();

  // 2. Appeler la méthode d'instance load() pour charger les données.
  await appConfig.load();

  // 3. Lancer l'application en lui passant l'instance configurée.
  runApp(MyApp(appConfig: appConfig));
}

class MyApp extends StatelessWidget {
  // Recevoir l'instance pré-chargée.
  final AppConfig appConfig;
  const MyApp({super.key, required this.appConfig});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Fournir l'instance déjà créée en utilisant ChangeNotifierProvider.value
        ChangeNotifierProvider.value(value: appConfig),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => EntryProvider()),
      ],
      child: MaterialApp(
        title: 'Prestinv',
        theme: ThemeData(
          primarySwatch: Colors.deepOrange,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        debugShowCheckedModeBanner: false,
        // MODIFICATION: On utilise les nouvelles variables pour la logique de démarrage.
        home: appConfig.localApiAddress.isEmpty || appConfig.distantApiAddress.isEmpty
            ? const ConfigScreen()
            : const HomeScreen(),
      ),
    );
  }
}