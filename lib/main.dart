// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/utils/app_utils.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

void main() async {
  // On s'assure que tout est prêt et on préserve le splash screen
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // On charge les configurations essentielles avant de lancer l'app
  final appConfig = AppConfig();
  await appConfig.load();

  final authProvider = AuthProvider();
  await authProvider.loadUserFromStorage();

  runApp(MyApp(appConfig: appConfig, authProvider: authProvider));

  // Une fois l'application prête et la première frame dessinée, on retire le splash screen
  FlutterNativeSplash.remove();
}

class MyApp extends StatefulWidget {
  final AppConfig appConfig;
  final AuthProvider authProvider;

  const MyApp({super.key, required this.appConfig, required this.authProvider});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  /// Réinitialise le minuteur de déconnexion. Nécessite un context valide.
  void _resetInactivityTimer(BuildContext context) {
    final appConfig = context.read<AppConfig>();
    final authProvider = context.read<AuthProvider>();

    // Le timer ne s'active que si l'utilisateur est connecté ET que le délai est configuré
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _attemptBackgroundSync();
    }
  }

  void _attemptBackgroundSync() {
    // context.read<T>() est sûr à utiliser ici car _MyAppState est toujours dans l'arbre
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.appConfig),
        ChangeNotifierProvider.value(value: widget.authProvider),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => EntryProvider()),
      ],
      // On utilise un Builder pour obtenir un context qui est "en dessous" du MultiProvider
      // Cela résout l'erreur "Provider not found" pour le minuteur.
      child: Builder(
        builder: (context) {
          // On peut maintenant initialiser le timer en toute sécurité.
          _resetInactivityTimer(context);

          return GestureDetector(
            onTap: () => _resetInactivityTimer(context),
            onPanDown: (_) => _resetInactivityTimer(context),
            behavior: HitTestBehavior.translucent,
            child: Consumer<AuthProvider>(
              builder: (context, auth, _) {
                return MaterialApp(
                  title: 'Prestinv',
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
                        elevation: 4,
                      ),
                      elevatedButtonTheme: ElevatedButtonThemeData(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                        ),
                      ),
                      floatingActionButtonTheme: const FloatingActionButtonThemeData(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.white,
                      ),
                      inputDecorationTheme: const InputDecorationTheme(
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent, width: 2)),
                      ),
                      cardTheme: CardThemeData(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      )
                  ),
                  home: auth.isLoggedIn ? const HomeScreen() : const LoginScreen(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}