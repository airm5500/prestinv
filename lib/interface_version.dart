// lib/interface_version.dart
// Interrupteur « Nouvelle interface » (même principe que prestige_vente_app) : permet de revenir aux
// écrans d'origine sans réinstaller l'application.
//
// DÉSACTIVÉ par défaut (installations existantes comme nouvelles) : il est PROPOSÉ dans la
// Configuration (ancienne et nouvelle), où le changer demande le code administrateur.
// - Désactivé : écrans d'origine, STRICTEMENT inchangés (lib/screens/…).
// - Activé : nouveaux écrans (lib/ui/ecrans/…, maquettes A, B, C), mêmes données, même logique.
// Aiguillages : HomeScreen et LoginScreen (lib/screens/…) choisissent l'écran selon [useNew] ; le
// lancement, la licence et le serveur injoignable passent par les fonctions ci-dessous (main.dart).
// Retour arrière : Configuration → « Nouvelle interface » → désactiver (code administrateur).
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

  /// Version choisie (ancienne par défaut).
  static final ValueNotifier<bool> useNew = ValueNotifier<bool>(false);

  /// Clair / sombre (nouvelle interface seulement).
  static ValueNotifier<Apparence> get apparence => NvApparence.valeur;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      useNew.value = prefs.getBool(key) ?? false;
    } catch (_) {}
    await NvApparence.charger();
  }

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
          title: Text(isNew ? 'Nouvelle interface' : 'Nouvelle interface (proposée)'),
          subtitle: Text(isNew
              ? 'Activée. Désactivez pour revenir aux écrans d\'origine (code administrateur).'
              : 'Écrans d\'origine utilisés. Activez pour essayer la nouvelle présentation : mêmes données, '
                  'mêmes réglages, retour possible à tout moment (code administrateur).'),
          value: isNew,
          onChanged: (v) => _changer(context, v),
        ),
      );
}
