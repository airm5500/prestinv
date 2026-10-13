// lib/interface_version.dart
// Interrupteur « Nouvelle interface » (même principe que prestige_vente_app) : permet de revenir aux
// écrans d'origine sans réinstaller l'application.
//
// ÉTEINT par défaut. Tant qu'aucun nouvel écran n'existe (refonte prévue à l'étape 4), les deux
// positions ouvrent exactement les mêmes écrans d'origine : l'interrupteur n'est donc pas encore
// affiché dans la Configuration (InterfaceVersionTile est prêt pour l'étape 4).
import 'package:flutter/material.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InterfaceVersion {
  InterfaceVersion._();

  static const key = 'interface_nouvelle_version_v1';

  /// Version choisie (ancienne par défaut).
  static final ValueNotifier<bool> useNew = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      useNew.value = prefs.getBool(key) ?? false;
    } catch (_) {}
  }

  static Future<void> setNew(bool value) async {
    useNew.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  /// Écran d'accueil. Étape 0 : l'accueil d'origine dans les deux cas.
  static Widget home() => const HomeScreen();
}

/// Réglage à afficher dans la Configuration quand la nouvelle interface existera (étape 4).
class InterfaceVersionTile extends StatelessWidget {
  const InterfaceVersionTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: InterfaceVersion.useNew,
        builder: (context, isNew, _) => SwitchListTile(
          title: const Text('Nouvelle interface'),
          subtitle: Text(isNew
              ? 'Désactivez pour revenir aux écrans d\'origine (effet au prochain retour à l\'accueil).'
              : 'Écrans d\'origine utilisés.'),
          value: isNew,
          onChanged: (v) => InterfaceVersion.setNew(v),
        ),
      );
}
