// lib/scan/camera/scan_camera.dart
// SCAN PAR L'APPAREIL PHOTO (4.14) — pour les téléphones qui n'ont pas de douchette.
//
// Réglage protégé « Scan par l'appareil photo » (AppConfig.scanCamera), DÉSACTIVÉ par défaut : sans lui,
// aucun bouton, aucune demande d'autorisation, rien ne change (terminaux Sunmi, utilisateurs actuels).
//
// Principe : l'appareil photo n'est qu'un AUTRE LECTEUR. Chaque code lu est remis à la douchette
// ([Douchette.injecterLecture]) exactement comme une lecture de la douchette terminée par Entrée : même
// cible (l'écran au premier plan), même décodage, même file des scans, mêmes contrôles, même retour
// sonore / vibration. Aucune logique de saisie n'est dupliquée ici.
//
// L'aperçu plein écran est une page posée AU-DESSUS de l'écran de saisie : pour que la douchette
// considère toujours cet écran comme « au premier plan », les écrans utilisent [ScanCamera.auPremierPlan]
// au lieu de `ModalRoute.isCurrent` (identique tant que l'aperçu n'est pas ouvert depuis eux).
//
// Ce fichier ne dépend pas du module de l'appareil photo (mobile_scanner) : le moteur réel
// (moteur_mobile_scanner.dart) et l'accès au système sont remplaçables dans les tests ([moteur], [acces]).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:prestinv/scan/camera/moteur_mobile_scanner.dart';
import 'package:prestinv/scan/camera/page_camera.dart';
import 'package:prestinv/scan/douchette.dart';

/// Autorisation « Caméra » d'Android.
enum AutorisationCamera {
  /// Accordée.
  accordee,

  /// Pas encore demandée, ou refusée une fois (on peut la redemander).
  aDemander,

  /// Refusée définitivement (« Ne plus demander ») : seuls les paramètres d'Android peuvent la rendre.
  refuseeDefinitivement,
}

/// Accès au système : présence d'un appareil photo, autorisation Caméra.
abstract class AccesCamera {
  /// L'appareil a-t-il un appareil photo ? (sinon le bouton est masqué)
  Future<bool> presente();
  Future<AutorisationCamera> statut();

  /// Demande l'autorisation (fenêtre d'Android).
  Future<AutorisationCamera> demander();

  /// Ouvre la page de l'application dans les paramètres d'Android.
  Future<void> ouvrirParametres();
}

/// Accès réel : canal natif « prestinv/appareil » (MainActivity.kt) et permission_handler.
class AccesCameraSysteme implements AccesCamera {
  static const MethodChannel _canal = MethodChannel('prestinv/appareil');

  @override
  Future<bool> presente() async {
    try {
      return await _canal.invokeMethod<bool>('cameraPresente') ?? true;
    } catch (_) {
      // Canal absent (autre plateforme) : on suppose un appareil photo ; l'aperçu dira s'il manque.
      return true;
    }
  }

  static AutorisationCamera _depuis(PermissionStatus s) => s.isGranted || s.isLimited
      ? AutorisationCamera.accordee
      : (s.isPermanentlyDenied || s.isRestricted ? AutorisationCamera.refuseeDefinitivement : AutorisationCamera.aDemander);

  @override
  Future<AutorisationCamera> statut() async => _depuis(await Permission.camera.status);

  @override
  Future<AutorisationCamera> demander() async => _depuis(await Permission.camera.request());

  @override
  Future<void> ouvrirParametres() async {
    await openAppSettings();
  }
}

/// Moteur de lecture : aperçu de l'appareil photo qui signale chaque code lu (réel : mobile_scanner ;
/// tests : moteur simulé).
abstract class MoteurCamera {
  /// Aperçu plein cadre. [surCode] : chaque code lu (texte brut, séparateur GS conservé) ; peut être
  /// appelé plusieurs fois par seconde pour le même code (l'anti-doublon est fait par la page).
  /// [surErreur] : l'appareil photo ne peut pas démarrer (message à afficher).
  Widget apercu(BuildContext context, {required ValueChanged<String> surCode, required ValueChanged<String> surErreur});

  /// Lampe : null = indisponible ; sinon allumée ou éteinte.
  ValueListenable<bool?> get lampe;
  Future<void> basculerLampe();
  void liberer();
}

/// Anti-doublon : l'appareil photo lit le même code à chaque image. Le même code est ignoré tant qu'il
/// a été vu il y a moins de [delai] (vu à nouveau = délai repoussé) : il faut l'écarter du cadre ~1,5 s
/// pour le relire. Un AUTRE code passe tout de suite. (La douchette n'a pas besoin de cette règle :
/// chaque appui sur la gâchette donne une seule lecture.)
class AntiDoublon {
  final Duration delai;
  final DateTime Function() maintenant;
  AntiDoublon({this.delai = const Duration(milliseconds: 1500), DateTime Function()? horloge}) : maintenant = horloge ?? DateTime.now;

  String? _dernier;
  DateTime? _vuLe;

  /// Le code doit-il être pris ? (Note toujours la vue, même refusée.)
  bool accepter(String code) {
    final t = maintenant();
    final doublon = code == _dernier && _vuLe != null && t.difference(_vuLe!) < delai;
    _dernier = code;
    _vuLe = t;
    return !doublon;
  }

  /// Code vu à l'instant sans être pris (aperçu recouvert par la feuille de quantité…).
  void noter(String code) {
    _dernier = code;
    _vuLe = maintenant();
  }

  void oublier() {
    _dernier = null;
    _vuLe = null;
  }
}

class ScanCamera {
  ScanCamera._();

  /// Accès au système (remplaçable dans les tests).
  static AccesCamera acces = AccesCameraSysteme();

  /// Fabrique du moteur de lecture (remplaçable dans les tests).
  static MoteurCamera Function() moteur = MoteurMobileScanner.new;

  /// Horloge de l'anti-doublon (remplaçable dans les tests).
  static DateTime Function() horloge = DateTime.now;

  static Future<bool>? _presence;

  /// Présence d'un appareil photo (lue une fois).
  static Future<bool> cameraPresente() => _presence ??= acces.presente().catchError((_) => true);

  /// Tests : état initial (accès réel, moteur réel, présence relue).
  @visibleForTesting
  static void reinitialiser() {
    acces = AccesCameraSysteme();
    moteur = MoteurMobileScanner.new;
    horloge = DateTime.now;
    _presence = null;
    _routeCamera = null;
    _routeSous = null;
  }

  static Route<dynamic>? _routeCamera;
  static Route<dynamic>? _routeSous;

  /// Aperçu ouvert (tests).
  static bool get ouvert => _routeCamera != null;

  /// L'écran de [context] est-il au premier plan ? Vrai aussi quand il n'est recouvert QUE par l'aperçu
  /// de l'appareil photo ouvert depuis lui : la lecture lui revient alors, comme celle de la douchette.
  static bool auPremierPlan(BuildContext context) {
    final r = ModalRoute.of(context);
    if (r == null || r.isCurrent) return true;
    final cam = _routeCamera;
    return cam != null && identical(r, _routeSous) && cam.isCurrent;
  }

  /// Lecture remise à la douchette (même chemin qu'un code lu par la douchette).
  static void versDouchette(String code) => Douchette.instance.injecterLecture(code);

  /// Bouton appareil photo touché : autorisation (expliquée au premier usage), puis aperçu plein écran.
  /// [continu] : l'aperçu reste ouvert et enchaîne les lectures (scan continu, collecte) ; sinon il se
  /// ferme après une lecture (saisie guidée). [surLecture] : par défaut, vers la douchette.
  static Future<void> ouvrir(BuildContext context, {required bool continu, ValueChanged<String>? surLecture}) async {
    if (_routeCamera != null) return;
    if (!await autoriser(context) || !context.mounted) return;
    final sous = ModalRoute.of(context);
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PageCamera(continu: continu, surLecture: surLecture ?? versDouchette),
    );
    _routeCamera = route;
    _routeSous = sous;
    try {
      await Navigator.of(context).push(route);
    } finally {
      if (identical(_routeCamera, route)) {
        _routeCamera = null;
        _routeSous = null;
      }
    }
  }

  static const messageRefus = 'Appareil photo non autorisé : le scan par l\'appareil photo est indisponible. '
      'La saisie continue normalement (douchette, pavé, recherche au clavier).';

  /// Autorisation Caméra : accordée → vrai ; sinon explication, demande, et message clair en cas de refus
  /// (rien n'est bloqué : l'écran reste utilisable).
  static Future<bool> autoriser(BuildContext context) async {
    AutorisationCamera s;
    try {
      s = await acces.statut();
    } catch (_) {
      s = AutorisationCamera.aDemander;
    }
    if (s == AutorisationCamera.accordee) return true;
    if (!context.mounted) return false;
    if (s == AutorisationCamera.refuseeDefinitivement) {
      final parametres = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('camera-refusee-definitivement'),
          icon: const Icon(Icons.no_photography_outlined),
          title: const Text('Appareil photo refusé'),
          content: const Text('L\'autorisation « Caméra » a été refusée pour Prestige Inventaire. Pour scanner avec '
              'l\'appareil photo, autorisez-la dans les paramètres d\'Android. La saisie continue normalement sans elle.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Fermer')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Ouvrir les paramètres')),
          ],
        ),
      );
      if (parametres == true) {
        try {
          await acces.ouvrirParametres();
        } catch (_) {}
      }
      return false;
    }
    final continuer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('camera-explication'),
        icon: const Icon(Icons.photo_camera_outlined),
        title: const Text('Scanner avec l\'appareil photo'),
        content: const Text('Prestige Inventaire va demander l\'accès à l\'appareil photo. Il sert uniquement à lire '
            'les codes-barres et DataMatrix des boîtes : aucune photo n\'est prise ni enregistrée.'),
        actions: [
          TextButton(key: const ValueKey('camera-plus-tard'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Plus tard')),
          FilledButton(key: const ValueKey('camera-continuer'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuer')),
        ],
      ),
    );
    if (continuer != true) return false;
    try {
      s = await acces.demander();
    } catch (_) {
      s = AutorisationCamera.aDemander;
    }
    if (s == AutorisationCamera.accordee) return true;
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        key: ValueKey('camera-refusee'),
        duration: Duration(seconds: 5),
        content: Text(messageRefus),
      ));
    }
    return false;
  }
}
