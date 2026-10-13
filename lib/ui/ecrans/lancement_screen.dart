// lib/ui/ecrans/lancement_screen.dart
// Nouvelle interface — lancement (vérification de la licence) et cadre commun des écrans d'entrée
// (connexion, licence, serveur injoignable) : bandeau bleu nuit avec le logo, contenu sur carte.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';

/// Logo de l'application sur pastille blanche.
class LogoApp extends StatelessWidget {
  final double taille;
  const LogoApp({super.key, this.taille = 64});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Prestige Inventaire',
        image: true,
        child: Container(
          width: taille,
          height: taille,
          padding: EdgeInsets.all(taille * 0.14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(taille * 0.26)),
          child: Image.asset('assets/images/icon.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.inventory_2, color: Pal.navy, size: taille * 0.6)),
        ),
      );
}

/// Cadre des écrans d'entrée : bandeau bleu (logo, titre, sous-titre) puis contenu centré.
class CadreEntree extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final List<Widget> enfants;
  final List<Widget> actions;
  final Widget? bas;
  const CadreEntree({super.key, required this.titre, this.sousTitre, required this.enfants, this.actions = const [], this.bas});

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: nv.page,
        body: Column(children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(color: nv.entete, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28))),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20 + Responsive.sideInset(context), 8, 8 + Responsive.sideInset(context), 22),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(children: [
                        const LogoApp(taille: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Semantics(
                              header: true,
                              child: Text(titre, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            ),
                            if (sousTitre != null) Text(sousTitre!, style: const TextStyle(color: Pal.headerMuted, fontSize: 13.5)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  ...actions,
                ]),
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: enfants),
                  ),
                ),
              ),
            ),
          ),
          if (bas != null) SafeArea(top: false, child: bas!),
        ]),
      ),
    );
  }
}

class NvLancementScreen extends StatelessWidget {
  const NvLancementScreen({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: context.nv.entete,
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const LogoApp(taille: 96),
              const SizedBox(height: 20),
              const Text('Prestige Inventaire', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Vérification de la licence…', style: TextStyle(color: Pal.headerMuted, fontSize: 15)),
              const SizedBox(height: 24),
              Semantics(label: 'Chargement', child: const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Pal.amber, strokeWidth: 3))),
            ]),
          ),
        ),
      );
}
