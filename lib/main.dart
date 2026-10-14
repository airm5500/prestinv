// lib/main.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

// --- IMPORTS CONFIG & API ---
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/config/theme_origine.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/version_app.dart';
import 'package:prestinv/utils/app_utils.dart';
import 'package:prestinv/saisie/rappel_envoi.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/taille_ecran.dart';
import 'package:prestinv/widgets/rappel_sauvegarde_origine.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:prestinv/services/identifiants_securises.dart';

// --- IMPORTS PROVIDERS ---
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/providers/license_provider.dart';

// --- IMPORTS ÉCRANS ---
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/login_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  final appConfig = AppConfig();
  await appConfig.load();
  // Version du paquet installé (pubspec.yaml → Gradle), lue une fois pour l'affichage.
  await VersionApp.charger();
  await InterfaceVersion.load();
  // Taille de l'écran (Automatique / Compact / Très compact), appliquée dès ce lancement.
  await TailleEcranReglage.charger();

  // Mot de passe mémorisé : migration silencieuse de l'ancienne clé en clair vers le stockage sécurisé.
  await IdentifiantsSecurises.instance.migrer();

  final authProvider = AuthProvider();

  // File persistante des saisies (avant tout écran) + reprise des saisies non envoyées des versions
  // précédentes (anciennes clés par rayon), sans perte.
  final saisies = await ouvrirFileSaisies();

  runApp(racineApplication(config: appConfig, auth: authProvider, saisies: saisies));

  FlutterNativeSplash.remove();
}

/// Racine de l'application : providers + [PrestinvApp]. Utilisée telle quelle par [main] ; les tests de
/// bout en bout (test/e2e) montent exactement le même arbre, avec un faux serveur et une file en mémoire.
Widget racineApplication({required AppConfig config, required AuthProvider auth, required SaisieQueue saisies}) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: config),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: saisies),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => EntryProvider()),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
      ],
      child: const PrestinvApp(),
    );

/// Ouvre la file des saisies dans le dossier privé de l'application (survit aux redémarrages).
Future<SaisieQueue> ouvrirFileSaisies() async {
  Directory dossier;
  try {
    dossier = await getApplicationSupportDirectory();
  } catch (_) {
    dossier = await getApplicationDocumentsDirectory();
  }
  final queue = SaisieQueue(store: FichierSaisieStore(File('${dossier.path}/saisies_v1.jsonl')));
  SaisieQueue.instance = queue;
  await queue.load();
  try {
    await queue.migrerAnciennesCles();
  } catch (_) {
    // Les anciennes clés restent en place : nouvel essai au prochain lancement.
  }
  return queue;
}

class PrestinvApp extends StatefulWidget {
  const PrestinvApp({super.key});

  @override
  State<PrestinvApp> createState() => _PrestinvAppState();
}

/// Navigateur de l'application : la déconnexion automatique (minuterie) s'en sert pour afficher ses
/// fenêtres (le contexte de PrestinvApp est AU-DESSUS du navigateur : avant, plantage).
final GlobalKey<NavigatorState> navigateurApp = GlobalKey<NavigatorState>();

class _PrestinvAppState extends State<PrestinvApp> with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  SaisieQueue? _saisies;
  AuthProvider? _auth;
  bool _etaitConnecte = false;
  GardienEnvoi? _gardien;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _brancherFileSaisies();

    // VÉRIFICATION LICENCE AU DÉMARRAGE
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLicense();
    });
  }

  /// La file des saisies envoie avec l'adresse et la session COURANTES (lues à chaque envoi) ;
  /// rien ne part tant qu'on n'est pas connecté. Reprise automatique toutes les 15 s.
  void _brancherFileSaisies() {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    final queue = context.read<SaisieQueue>();
    _saisies = queue;
    _auth = auth;
    queue.serveurFactory = () {
      if (!auth.isLoggedIn || config.currentApiUrl.isEmpty) return null;
      return ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
    };
    queue.modeDirect = () => config.sendMode == SendMode.direct;
    queue.demarrerReprise();
    _etaitConnecte = auth.isLoggedIn;
    auth.addListener(_surChangementConnexion);

    // Envoi manuel (Collecte), DEUX interfaces (4.13.1) : rappel BLOQUANT après le délai réglé, ou
    // envoi automatique toutes les 15 min si le délai est à 0 (lib/saisie/rappel_envoi.dart). Dans
    // l'ancienne interface, il remplace le rappel d'origine de la saisie guidée (pas de doublon).
    _gardien = GardienEnvoi(
      queue: queue,
      envoiManuel: () => config.sendMode == SendMode.collect,
      delaiMinutes: () => config.sendReminderMinutes,
      actif: () => mounted && auth.isLoggedIn && navigateurApp.currentContext != null,
      afficherRappel: _afficherRappelEnvoi,
    )..demarrer();
  }

  /// Message bloquant puis envoi avec sa progression (nouvelle interface : l'envoi se poursuit si l'on
  /// ferme la fenêtre). Style de l'interface active : nouvelle (maquette) ou d'origine.
  Future<BilanEnvoi?> _afficherRappelEnvoi(int nombre, Duration depuis) async {
    final ctx = navigateurApp.currentContext;
    final queue = _saisies;
    if (ctx == null || queue == null) return null;
    final nouvelle = InterfaceVersion.useNew.value;
    if (nouvelle) {
      await nvRappelSauvegarde(ctx, nombre: nombre, depuis: depuis, themer: true);
    } else {
      await origineRappelSauvegarde(ctx, nombre: nombre, depuis: depuis);
    }
    final ctx2 = navigateurApp.currentContext;
    if (ctx2 == null || !ctx2.mounted) return null;
    final Future<BilanEnvoi> envoi = nouvelle
        ? nvEnvoiSaisies(ctx2,
            envoyer: (p) => queue.envoyer(onProgress: p), demandees: queue.enAttente(), sousTitre: 'Toutes les saisies non envoyées', themer: true)
        : origineEnvoiSaisies(ctx2, envoyer: (p) => queue.envoyer(onProgress: p), demandees: queue.enAttente());
    final bilan = await envoi;
    final ctx3 = navigateurApp.currentContext;
    if (bilan.sessionExpiree && ctx3 != null && ctx3.mounted) await demanderReconnexion(ctx3);
    return bilan;
  }

  /// Connexion (ou reconnexion après session expirée) : les saisies en attente repartent.
  void _surChangementConnexion() {
    final connecte = _auth?.isLoggedIn ?? false;
    if (connecte && !_etaitConnecte) _saisies?.signalerReconnexion();
    _etaitConnecte = connecte;
  }

  /// Vérifie la licence via le Provider ([silent] : retour au premier plan, sans sablier plein écran).
  Future<void> _checkLicense({bool silent = false}) async {
    // Sécurité : Vérifier si le widget est encore monté
    if (!mounted) return;

    final config = context.read<AppConfig>();
    final auth = context.read<AuthProvider>();
    final api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);

    // Cette méthode mettra à jour le status du LicenseProvider.
    // Si la licence est expirée, le Consumer dans build() redirigera automatiquement vers l'écran d'enregistrement.
    await context.read<LicenseProvider>().checkLicense(api, silent: silent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.removeListener(_surChangementConnexion);
    _saisies?.arreterReprise();
    _gardien?.arreter();
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
      final ctx = navigateurApp.currentContext;
      if (authProvider.isLoggedIn && mounted && ctx != null) {
        performLogout(ctx);
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

      // 2. On RE-VÉRIFIE la licence chaque fois que l'app revient au premier plan (sans sablier)
      _checkLicense(silent: true);

      // 3. Les saisies en attente repartent (mode Direct / corrections).
      _saisies?.relancer();
    }

    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _attemptBackgroundSync();
    }
  }

  /// Mise en arrière-plan : dernière tentative d'envoi des saisies en attente (mode Direct /
  /// corrections). Rien n'est perdu si le système arrête l'application : tout est sur disque.
  void _attemptBackgroundSync() {
    _saisies?.relancer();
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
            homeWidget = InterfaceVersion.lancement();
          }
          else if (license.status == LicenseStatus.unreachable) {
            // Serveur injoignable ≠ « Application non activée » : réessai automatique toutes les 10 s.
            homeWidget = InterfaceVersion.serveurInjoignable(() => _checkLicense());
          }
          else if (license.status == LicenseStatus.none || license.status == LicenseStatus.expired) {
            homeWidget = InterfaceVersion.licence();
          }
          else if (auth.isLoggedIn) {
            homeWidget = InterfaceVersion.home();
          }
          else {
            homeWidget = const LoginScreen();
          }

          // Taille de l'écran (réglage) : toute l'interface, fenêtres et calques compris, deux interfaces.
          return RacineTailleEcran(
            child: MaterialApp(
              navigatorKey: navigateurApp,
              title: 'Prestige Inventaire',
              debugShowCheckedModeBanner: false,
              theme: themeOrigine(),
              home: homeWidget,
            ),
          );
        },
      ),
    );
  }
}