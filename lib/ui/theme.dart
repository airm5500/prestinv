// lib/ui/theme.dart
// Charte commune aux trois applications Prestige (même palette que prestige_vente_app,
// lib/widgets/presentation_style.dart → Pal) : bleu nuit #003366, ambre #F59E0B pour l'action
// principale. Nouvelle interface seulement (InterfaceVersion) : les écrans d'origine gardent leur thème.
//
// Thème clair et sombre : les couleurs qui changent avec le mode sont dans [NvCouleurs] (extension du
// thème, lue par `context.nv`) ; [Pal] garde les couleurs fixes de la charte.
// Polices : Roboto (police du système Android, utilisée par Flutter par défaut) — aucune police
// embarquée, comme prestige_vente_app.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apparence de la nouvelle interface.
enum Apparence { systeme, clair, sombre }

extension ApparenceLibelle on Apparence {
  String get libelle => switch (this) {
        Apparence.systeme => 'Comme le téléphone',
        Apparence.clair => 'Clair',
        Apparence.sombre => 'Sombre',
      };
}

/// Choix clair / sombre mémorisé sur l'appareil (nouvelle interface seulement).
class NvApparence {
  NvApparence._();
  static const cle = 'interface_apparence_v1';
  static final ValueNotifier<Apparence> valeur = ValueNotifier<Apparence>(Apparence.systeme);

  static Future<void> charger() async {
    try {
      valeur.value = Apparence.values.asNameMap()[(await SharedPreferences.getInstance()).getString(cle)] ?? Apparence.systeme;
    } catch (_) {}
  }

  static Future<void> choisir(Apparence a) async {
    valeur.value = a;
    try {
      await (await SharedPreferences.getInstance()).setString(cle, a.name);
    } catch (_) {}
  }
}

/// Couleurs fixes de la charte (identiques dans prestige_vente_app).
class Pal {
  Pal._();
  static const navy = Color(0xFF003366);
  static const navyFonce = Color(0xFF0B2A4A);
  static const amber = Color(0xFFF59E0B);
  static const onAmber = Color(0xFF1F1300);
  static const page = Color(0xFFF2F4F8);
  static const ink = Color(0xFF14213D);
  static const muted = Color(0xFF5B6B82);
  static const line = Color(0xFFE3E8EF);
  static const headerMuted = Color(0xFFC9D6E8);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const blue = Color(0xFF2563EB);
}

/// Couleur d'un état (texte + fond), toujours accompagnée d'un libellé (jamais la couleur seule).
class TonEtat {
  final Color fg;
  final Color bg;
  const TonEtat(this.fg, this.bg);
}

/// Couleurs qui dépendent du mode clair / sombre.
@immutable
class NvCouleurs extends ThemeExtension<NvCouleurs> {
  final Color page;
  final Color carte;
  final Color encre;
  final Color gris;
  final Color ligne;
  final Color champ;
  final Color entete;

  /// Texte / contour d'action sur fond de page (bleu nuit en clair, bleu clair en sombre).
  final Color action;
  final Color touche;
  final Color toucheSpeciale;
  final TonEtat ok;
  final TonEtat attente;
  final TonEtat erreur;
  final TonEtat info;
  final TonEtat neutre;

  /// Bandeau « scanner prêt » (vert).
  final TonEtat scan;
  final Color manquant;
  final Color surplus;

  const NvCouleurs({
    required this.page,
    required this.carte,
    required this.encre,
    required this.gris,
    required this.ligne,
    required this.champ,
    required this.entete,
    required this.action,
    required this.touche,
    required this.toucheSpeciale,
    required this.ok,
    required this.attente,
    required this.erreur,
    required this.info,
    required this.neutre,
    required this.scan,
    required this.manquant,
    required this.surplus,
  });

  static const clair = NvCouleurs(
    page: Pal.page,
    carte: Colors.white,
    encre: Pal.ink,
    gris: Pal.muted,
    ligne: Pal.line,
    champ: Colors.white,
    entete: Pal.navy,
    action: Pal.navy,
    touche: Colors.white,
    toucheSpeciale: Color(0xFFDDE3EA),
    ok: TonEtat(Color(0xFF0B6B45), Color(0xFFDCF5E7)),
    attente: TonEtat(Color(0xFF8A4B00), Color(0xFFFFF1D6)),
    erreur: TonEtat(Color(0xFF9B1C1C), Color(0xFFFDE7E7)),
    info: TonEtat(Color(0xFF1F4F8F), Color(0xFFE3ECF7)),
    neutre: TonEtat(Color(0xFF3D4B60), Color(0xFFE6EBF2)),
    scan: TonEtat(Color(0xFF0B6B45), Color(0xFFF0FBF4)),
    manquant: Color(0xFFB91C1C),
    surplus: Color(0xFF15803D),
  );

  static const sombre = NvCouleurs(
    page: Color(0xFF0E1622),
    carte: Color(0xFF182231),
    encre: Color(0xFFE7EDF5),
    gris: Color(0xFFA9B6C8),
    ligne: Color(0xFF2A3647),
    champ: Color(0xFF101A27),
    entete: Pal.navyFonce,
    action: Color(0xFF9CC3FF),
    touche: Color(0xFF223047),
    toucheSpeciale: Color(0xFF2E3B52),
    ok: TonEtat(Color(0xFF86E5AE), Color(0xFF12321F)),
    attente: TonEtat(Color(0xFFFBC96B), Color(0xFF3A2A0C)),
    erreur: TonEtat(Color(0xFFFFA3A3), Color(0xFF3B1515)),
    info: TonEtat(Color(0xFFA9CBFF), Color(0xFF13284A)),
    neutre: TonEtat(Color(0xFFC7D0DD), Color(0xFF253042)),
    scan: TonEtat(Color(0xFF86E5AE), Color(0xFF0F2A1B)),
    manquant: Color(0xFFFF8A8A),
    surplus: Color(0xFF6EE7A0),
  );

  @override
  NvCouleurs copyWith() => this;

  @override
  NvCouleurs lerp(ThemeExtension<NvCouleurs>? other, double t) => t < 0.5 || other is! NvCouleurs ? this : other;
}

extension NvContexte on BuildContext {
  /// Couleurs de la nouvelle interface (clair par défaut si le thème n'est pas posé).
  NvCouleurs get nv => Theme.of(this).extension<NvCouleurs>() ?? NvCouleurs.clair;
  bool get nvSombre => Theme.of(this).brightness == Brightness.dark;
}

/// Thème complet de la nouvelle interface.
ThemeData themeNouveau(Brightness b) {
  final c = b == Brightness.dark ? NvCouleurs.sombre : NvCouleurs.clair;
  final sombre = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: sombre ? c.action : Pal.navy,
    onPrimary: sombre ? Pal.navyFonce : Colors.white,
    secondary: Pal.amber,
    onSecondary: Pal.onAmber,
    error: c.erreur.fg,
    onError: sombre ? Colors.black : Colors.white,
    surface: c.carte,
    onSurface: c.encre,
    surfaceContainerHighest: c.page,
    outline: c.ligne,
  );
  final rond = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.page,
    canvasColor: c.carte,
    dividerColor: c.ligne,
    extensions: [c],
    appBarTheme: AppBarTheme(backgroundColor: c.entete, foregroundColor: Colors.white, elevation: 0),
    cardTheme: CardThemeData(color: c.carte, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    dialogTheme: DialogThemeData(backgroundColor: c.carte, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.carte,
      modalBackgroundColor: c.carte,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, actionTextColor: c.action),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Pal.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: rond,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.amber,
        foregroundColor: Pal.onAmber,
        minimumSize: const Size(48, 48),
        shape: rond,
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.action,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: c.action, width: 1.5),
        shape: rond,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.action, minimumSize: const Size(48, 48), textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.champ,
      labelStyle: TextStyle(color: c.gris),
      hintStyle: TextStyle(color: c.gris),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ligne)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ligne)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.action, width: 2)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (sombre ? const Color(0xFF3B82F6) : Pal.navy) : null),
    ),
    listTileTheme: ListTileThemeData(textColor: c.encre, iconColor: c.gris, minVerticalPadding: 10),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Pal.amber),
  );
}

/// Pose le thème de la nouvelle interface (clair / sombre selon le réglage « Apparence » et le
/// système) sur [child]. Les fenêtres ouvertes depuis [child] en héritent (showDialog et
/// showModalBottomSheet reprennent le thème du contexte).
class NvTheme extends StatelessWidget {
  final Widget child;
  const NvTheme({super.key, required this.child});

  static Brightness luminosite(BuildContext context, Apparence a) => switch (a) {
        Apparence.clair => Brightness.light,
        Apparence.sombre => Brightness.dark,
        Apparence.systeme => MediaQuery.platformBrightnessOf(context),
      };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Apparence>(
        valueListenable: NvApparence.valeur,
        builder: (context, a, _) {
          final b = luminosite(context, a);
          return Theme(
            data: themeNouveau(b),
            child: DefaultTextStyle.merge(style: TextStyle(color: (b == Brightness.dark ? NvCouleurs.sombre : NvCouleurs.clair).encre), child: child),
          );
        },
      );
}

/// Route d'un écran de la nouvelle interface (thème posé).
Route<T> nvRoute<T>(Widget ecran) => MaterialPageRoute<T>(builder: (_) => NvTheme(child: ecran));
