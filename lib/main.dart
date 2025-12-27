// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

// --- IMPORTS CONFIG & API ---
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/utils/app_utils.dart';

// --- IMPORTS PROVIDERS ---
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/license_provider.dart'; // NOUVEAU

// --- IMPORTS ÉCRANS ---
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/screens/license_register_screen.dart'; // NOUVEAU

void main() async {
  // On s'assure que tout est prêt et on préserve le splash screen natif
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // On charge les configurations essentielles avant de lancer l'app
  final appConfig = AppConfig();
  await appConfig.load();

  final authProvider = AuthProvider();

  runApp(
    // Le MultiProvider est à la racine pour être accessible partout
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appConfig),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => EntryProvider()),
        // AJOUT DU PROVIDER LICENCE
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
      ],
      child: const PrestinvApp(),
    ),
  );

  // Une fois l'application prête, on retire le splash screen
  FlutterNativeSplash.remove();
}

class PrestinvApp extends StatefulWidget {
  const PrestinvApp({super.key});

  @override
  State<PrestinvApp> createState() => _PrestinvAppState();
}

class _PrestinvAppState extends State<PrestinvApp> with WidgetsBindingObserver {
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // VÉRIFICATION LICENCE AU DÉMARRAGE
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLicenseAtStartup();
    });
  }

  /// Lance la vérification de la licence via le Provider dédié
  void _checkLicenseAtStartup() {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    // On construit une instance API temporaire avec la config actuelle
    final api = ApiService(baseUrl: config.currentApiUrl, sessionCookie: auth.sessionCookie);

    // On lance la vérification (API ou Cache)
    context.read<LicenseProvider>().checkLicense(api);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  /// Réinitialise le minuteur de déconnexion automatique
  void _resetInactivityTimer(BuildContext context) {
    final appConfig = context.read<AppConfig>();
    final authProvider = context.read<AuthProvider>();

    // Le timer ne s'active que si l'utilisateur est connecté ET que le délai est configuré.
    if (!authProvider.isLoggedIn) {
      _inactivityTimer?.cancel();
      return;
    }

    final delay = appConfig.autoLogoutMinutes;
    if (delay <= 0) {
      _inactivityTimer?.cancel();
      return;
    }

    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(Duration(minutes: delay), () {
      if (authProvider.isLoggedIn && mounted) {
        performLogout(context);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _resetInactivityTimer(context);
      // Optionnel : On pourrait revérifier la licence ici au retour de l'app
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _attemptBackgroundSync();
    }
  }

  /// Tente d'envoyer les données en attente quand l'app passe en arrière-plan
  void _attemptBackgroundSync() {
    final entryProvider = context.read<EntryProvider>();
    if (entryProvider.hasUnsyncedData) {
      final authProvider = context.read<AuthProvider>();
      final appConfig = context.read<AppConfig>();

      final apiService = ApiService(
          baseUrl: appConfig.currentApiUrl,
          sessionCookie: authProvider.sessionCookie
      );

      entryProvider.sendDataToServer(apiService);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Le GestureDetector global intercepte les clics pour reset le timer d'inactivité
    return GestureDetector(
      onTap: () => _resetInactivityTimer(context),
      onPanDown: (_) => _resetInactivityTimer(context),
      behavior: HitTestBehavior.translucent,

      // On écoute AuthProvider ET LicenseProvider pour décider quel écran afficher
      child: Consumer2<AuthProvider, LicenseProvider>(
        builder: (context, auth, license, _) {

          // On s'assure que le timer est géré à chaque reconstruction si nécessaire
          WidgetsBinding.instance.addPostFrameCallback((_) => _resetInactivityTimer(context));

          // --- LOGIQUE DE ROUTAGE ---
          Widget homeWidget;

          if (license.status == LicenseStatus.loading) {
            // 1. Chargement de la licence en cours
            homeWidget = const Scaffold(
                body: Center(child: CircularProgressIndicator())
            );
          }
          else if (license.status == LicenseStatus.none || license.status == LicenseStatus.expired) {
            // 2. Pas de licence ou expirée => Écran d'enregistrement BLOQUANT
            homeWidget = const LicenseRegisterScreen();
          }
          else if (auth.isLoggedIn) {
            // 3. Licence OK et Connecté => Accueil
            homeWidget = const HomeScreen();
          }
          else {
            // 4. Licence OK mais pas connecté => Login
            homeWidget = const LoginScreen();
          }

          return MaterialApp(
            title: 'Prestige Inventaire',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                primaryColor: AppColors.primary,
                scaffoldBackgroundColor: AppColors.background,
                colorScheme: const ColorScheme.light(
                  primary: AppColors.primary,
                  secondary: AppColors.accent,
                  onPrimary: AppColors.white,
                  onSecondary: AppColors.white,
                ),
                appBarTheme: const AppBarTheme(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  elevation: 2,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                floatingActionButtonTheme: const FloatingActionButtonThemeData(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.white,
                ),
                inputDecorationTheme: InputDecorationTheme(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.accent, width: 2),
                  ),
                  labelStyle: TextStyle(color: Colors.grey.shade600),
                  filled: true,
                  fillColor: Colors.white,
                ),
                cardTheme: CardThemeData(
                  elevation: 1,
                  shadowColor: Colors.grey.withOpacity(0.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                )
            ),
            home: homeWidget,
          );
        },
      ),
    );
  }
}