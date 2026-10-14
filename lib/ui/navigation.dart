// lib/ui/navigation.dart
// Navigation de la nouvelle interface : ouverture des écrans pour un inventaire, inventaire « en
// cours » mémorisé sur l'appareil, menu latéral bleu de la tablette (maquette C).
import 'package:flutter/material.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/ecrans/a_envoyer_screen.dart';
import 'package:prestinv/ui/ecrans/analyse_screen.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/restants_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Inventaire choisi sur l'accueil (mémorisé sur l'appareil, simple préférence d'affichage).
class InventaireCourant {
  InventaireCourant._();
  static const cle = 'nv_inventaire_courant_v1';

  static Future<String?> lire() async {
    try {
      return (await SharedPreferences.getInstance()).getString(cle);
    } catch (_) {
      return null;
    }
  }

  static Future<void> ecrire(String id) async {
    try {
      await (await SharedPreferences.getInstance()).setString(cle, id);
    } catch (_) {}
  }
}

enum Destination { accueil, guidee, scan, ecarts, restants, collecte, aEnvoyer, analyse, reglages }

class NvAller {
  NvAller._();

  static Future<T?> _push<T>(BuildContext context, Widget ecran) => Navigator.of(context).push<T>(nvRoute<T>(ecran));

  /// Saisie guidée : choix du rayon (ou directement le rayon [rayonId] : « Reprendre »).
  /// Inventaire choisi (maquette Hub) : passage obligé avant toute saisie.
  static Future<void> inventaire(BuildContext context, Inventory inv) {
    InventaireCourant.ecrire(inv.id);
    return _push(context, NvInventaireScreen(inventaire: inv));
  }

  static Future<void> guidee(BuildContext context, Inventory inv, {String? rayonId}) {
    context.read<EntryProvider>().reset();
    return rayonId == null
        ? _push(context, NvChoixRayonScreen(inventaire: inv))
        : _push(context, NvSaisieGuideeScreen(inventaire: inv, rayonId: rayonId));
  }

  static Future<void> scan(BuildContext context, Inventory inv) {
    context.read<EntryProvider>().reset();
    return _push(context, NvScanContinuScreen(inventaire: inv));
  }

  static Future<void> ecarts(BuildContext context, Inventory inv) => _push(context, NvEcartsScreen(inventaire: inv));
  static Future<void> restants(BuildContext context, Inventory inv) => _push(context, NvRestantsScreen(inventaire: inv));
  static Future<void> collecte(BuildContext context) => _push(context, const NvCollecteScreen());
  static Future<void> aEnvoyer(BuildContext context) => _push(context, const NvAEnvoyerScreen());
  static Future<void> analyse(BuildContext context, {Inventory? inventaire}) => _push(context, NvAnalyseScreen(inventaireInitial: inventaire));
  static Future<void> reglages(BuildContext context) => _push(context, const NvConfigScreen());

  /// Ouvre [d] (sans inventaire : les écrans qui en demandent un ne s'ouvrent pas).
  static Future<void> vers(BuildContext context, Destination d, Inventory? inv) async {
    switch (d) {
      case Destination.accueil:
        Navigator.of(context).popUntil((r) => r.isFirst);
      case Destination.guidee:
        if (inv != null) await guidee(context, inv);
      case Destination.scan:
        if (inv != null) await scan(context, inv);
      case Destination.ecarts:
        if (inv != null) await ecarts(context, inv);
      case Destination.restants:
        if (inv != null) await restants(context, inv);
      case Destination.collecte:
        await collecte(context);
      case Destination.aEnvoyer:
        await aEnvoyer(context);
      case Destination.analyse:
        await analyse(context, inventaire: inv);
      case Destination.reglages:
        await reglages(context);
    }
  }
}

/// Menu latéral bleu (tablette ≥ 900 dp, maquette C).
class NvMenuLateral extends StatelessWidget {
  final Destination actif;
  final Inventory? inventaire;
  final ValueChanged<Destination> onChoisir;
  const NvMenuLateral({super.key, required this.actif, required this.inventaire, required this.onChoisir});

  @override
  Widget build(BuildContext context) {
    SaisieQueue? q;
    try {
      q = context.watch<SaisieQueue>();
    } catch (_) {}
    final attente = q?.aTraiter() ?? 0;
    Widget entree(Destination d, IconData icon, String texte, {bool besoinInventaire = false}) {
      final on = d == actif;
      final actifOk = !besoinInventaire || inventaire != null;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Semantics(
          selected: on,
          button: true,
          child: Material(
            color: on ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('menu-${d.name}'),
              borderRadius: BorderRadius.circular(12),
              onTap: actifOk ? () => onChoisir(d) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(icon, color: actifOk ? Colors.white : Colors.white38, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(texte,
                          style: TextStyle(color: actifOk ? Colors.white : Colors.white38, fontSize: 16, fontWeight: on ? FontWeight.bold : FontWeight.w500)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: context.nv.entete,
      child: SafeArea(
        right: false,
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 16, 18),
            child: Text('Prestige\nInventaire', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.15)),
          ),
          if (inventaire != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 10),
              child: Text(inventaire!.libelle.toUpperCase(),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.headerMuted, fontSize: 12.5, letterSpacing: 0.8)),
            ),
          entree(Destination.accueil, Icons.home_outlined, 'Tableau de bord'),
          entree(Destination.guidee, Icons.format_list_bulleted, 'Saisie guidée', besoinInventaire: true),
          entree(Destination.scan, Icons.qr_code_scanner, 'Scan continu', besoinInventaire: true),
          entree(Destination.ecarts, Icons.compare_arrows, 'Écarts', besoinInventaire: true),
          entree(Destination.restants, Icons.hourglass_bottom, 'Restants', besoinInventaire: true),
          entree(Destination.collecte, Icons.download_for_offline_outlined, 'Collecte hors ligne'),
          entree(Destination.analyse, Icons.pie_chart_outline, 'Analyse'),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 16, 6),
            child: Text('ENVOI', style: TextStyle(color: Pal.headerMuted, fontSize: 12.5, letterSpacing: 0.8)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('menu-envoi'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChoisir(Destination.aEnvoyer),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(children: [
                    Icon(attente > 0 ? Icons.circle : Icons.check_circle, size: 14, color: attente > 0 ? Pal.amber : const Color(0xFF6EE7A0)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(attente > 0 ? '$attente en attente' : 'Tout est envoyé',
                          style: TextStyle(color: attente > 0 ? Pal.amber : Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          entree(Destination.reglages, Icons.settings_outlined, 'Réglages'),
        ]),
      ),
    );
  }
}
