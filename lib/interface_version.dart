// lib/interface_version.dart
// Interrupteur « Nouvelle interface » (même principe que prestige_vente_app) : permet de revenir aux
// écrans d'origine sans réinstaller l'application.
//
// ACTIVÉ par défaut depuis la 4.12.0 : nouvelles installations ET installations existantes qui n'ont
// jamais fait de choix (aucune valeur enregistrée sous [InterfaceVersion.key]). Un choix explicite
// est toujours respecté : qui a désactivé l'interrupteur garde les écrans d'origine.
// Le changer (Configuration d'origine ou Réglages de la nouvelle interface) demande le code
// administrateur.
// - Désactivé : écrans d'origine, STRICTEMENT inchangés (lib/screens/…).
// - Activé : nouveaux écrans (lib/ui/ecrans/…, maquettes A, B, C), mêmes données, même logique.
// Aiguillages : HomeScreen et LoginScreen (lib/screens/…) choisissent l'écran selon [useNew] ; le
// lancement, la licence et le serveur injoignable passent par les fonctions ci-dessous (main.dart).
// Retour arrière : Réglages / Configuration → « Nouvelle interface » → désactiver (code administrateur).
// Tests : test/flutter_test_config.dart remet les écrans d'origine avant chaque test (les tests
// d'origine visent ces écrans) ; les tests de la nouvelle interface l'activent eux-mêmes.
import 'package:flutter/material.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/license_register_screen.dart';
import 'package:prestinv/screens/serveur_injoignable_screen.dart';
import 'package:prestinv/ui/ecrans/lancement_screen.dart';
import 'package:prestinv/ui/ecrans/licence_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/widgets/pin_admin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InterfaceVersion {
  InterfaceVersion._();

  static const key = 'interface_nouvelle_version_v1';

  /// Valeur sans choix enregistré : la nouvelle interface.
  static const parDefaut = true;

  /// Version affichée (nouvelle par défaut ; [load] applique le choix enregistré).
  static final ValueNotifier<bool> useNew = ValueNotifier<bool>(parDefaut);

  /// Clair / sombre (nouvelle interface seulement).
  static ValueNotifier<Apparence> get apparence => NvApparence.valeur;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Aucune valeur = jamais choisi → nouvelle interface ; false = ancienne choisie → respectée.
      useNew.value = prefs.getBool(key) ?? parDefaut;
    } catch (_) {}
    await NvApparence.charger();
  }

  /// Choix explicite (mémorisé : il prime désormais sur la valeur par défaut).
  static Future<void> setNew(bool value) async {
    useNew.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  static Future<void> setApparence(Apparence a) => NvApparence.choisir(a);

  /// Écran d'accueil : aiguillage HomeScreen (nouvel accueil ou accueil d'origine).
  static Widget home() => const HomeScreen();

  /// Après une connexion réussie : accueil. 4.14.2 — quand l'écran de connexion est celui de la RACINE
  /// de l'application (premier lancement), la racine (main.dart) le remplace d'elle-même par l'accueil
  /// dès que la session est ouverte : on ne pousse pas un SECOND accueil par-dessus (avant : deux
  /// accueils construits, liste des inventaires lue deux fois). On attend donc la fin de l'image en
  /// cours : si l'écran de connexion a disparu, l'accueil est déjà là ; sinon (écran de connexion
  /// poussé après une déconnexion, ou monté seul) il est remplacé par l'accueil, comme avant.
  static Future<void> allerAccueilApresConnexion(BuildContext context) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => home()));
  }

  /// Attente de la vérification de la licence au lancement.
  static Widget lancement() =>
      useNew.value ? const NvTheme(child: NvLancementScreen()) : const Scaffold(body: Center(child: CircularProgressIndicator()));

  /// Licence absente ou expirée.
  static Widget licence() => useNew.value ? const NvTheme(child: NvLicenceScreen()) : const LicenseRegisterScreen();

  /// Serveur injoignable au premier lancement (≠ licence).
  static Widget serveurInjoignable(Future<void> Function() reessayer) => useNew.value
      ? NvTheme(child: NvServeurInjoignableScreen(reessayer: reessayer))
      : ServeurInjoignableScreen(reessayer: reessayer);
}

/// Réglage affiché dans la Configuration (ancienne et nouvelle) : le changer demande le code
/// administrateur ([verifierPin] remplaçable dans les tests).
class InterfaceVersionTile extends StatelessWidget {
  final Future<bool> Function(BuildContext context)? verifierPin;
  const InterfaceVersionTile({super.key, this.verifierPin});

  Future<void> _changer(BuildContext context, bool v) async {
    final ok = await (verifierPin ?? demanderPinAdmin)(context);
    if (!ok || !context.mounted) return;
    await InterfaceVersion.setNew(v);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(v
          ? 'Nouvelle interface activée : elle s\'affiche au retour à l\'accueil.'
          : 'Écrans d\'origine rétablis : ils s\'affichent au retour à l\'accueil.'),
    ));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: InterfaceVersion.useNew,
        builder: (context, isNew, _) => SwitchListTile(
          key: const ValueKey('interrupteur-nouvelle-interface'),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(isNew ? Icons.auto_awesome : Icons.new_releases_outlined),
          title: Text(isNew ? 'Nouvelle interface' : 'Nouvelle interface (désactivée)'),
          subtitle: Text(isNew
              ? 'Activée (présentation par défaut). Désactivez pour revenir aux écrans d\'origine : mêmes données, '
                  'mêmes réglages (code administrateur).'
              : 'Écrans d\'origine utilisés, à votre demande. Activez pour retrouver la nouvelle présentation : '
                  'mêmes données, mêmes réglages (code administrateur).'),
          value: isNew,
          onChanged: (v) => _changer(context, v),
        ),
      );
}
