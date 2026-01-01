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
import 'package:prestinv/providers/license_provider.dart';

// --- IMPORTS ÉCRANS ---
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/screens/license_register_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  final appConfig = AppConfig();
  await appConfig.load();

  final authProvider = AuthProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appConfig),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => EntryProvider()),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
      ],
      child: const PrestinvApp(),
    ),
  );

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
      _checkLicense();
    });
  }

  /// Vérifie la licence via le Provider
  void _checkLicense() {
    // Sécurité : Vérifier si le widget est encore monté
    if (!mounted) return;

    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    final api = ApiService(baseUrl: config.currentApiUrl, sessionCookie: auth.sessionCookie);

    // Cette méthode mettra à jour le status du LicenseProvider.
    // Si la licence est expirée, le Consumer dans build() redirigera automatiquement vers l'écran d'enregistrement.
    context.read<LicenseProvider>().checkLicense(api);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetInactivityTimer(BuildContext context) {
    final appConfig = context.read<AppConfig>();
    final authProvider = context.read<AuthProvider>();

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

    // --- CORRECTION DU SCÉNARIO "DEMAIN" ---
    if (state == AppLifecycleState.resumed) {
      // 1. On relance le timer d'inactivité
      _resetInactivityTimer(context);

      // 2. On RE-VÉRIFIE la licence chaque fois que l'app revient au premier plan
      // Ainsi, si l'utilisateur ouvre l'app demain matin, la vérification se relance,
      // la date sera comparée à la nouvelle date du jour, et l'accès sera bloqué si expiré.
      _checkLicense();
    }

    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _attemptBackgroundSync();
    }
  }

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
    return GestureDetector(
      onTap: () => _resetInactivityTimer(context),
      onPanDown: (_) => _resetInactivityTimer(context),
      behavior: HitTestBehavior.translucent,

      child: Consumer2<AuthProvider, LicenseProvider>(
        builder: (context, auth, license, _) {

          WidgetsBinding.instance.addPostFrameCallback((_) => _resetInactivityTimer(context));

          Widget homeWidget;

          if (license.status == LicenseStatus.loading) {
            homeWidget = const Scaffold(
                body: Center(child: CircularProgressIndicator())
            );
          }
          // Si le statut passe à "expired" lors du _checkLicense() au "resume",
          // l'interface basculera immédiatement ici :
          else if (license.status == LicenseStatus.none || license.status == LicenseStatus.expired) {
            homeWidget = const LicenseRegisterScreen();
          }
          else if (auth.isLoggedIn) {
            homeWidget = const HomeScreen();
          }
          else {
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