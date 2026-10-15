// lib/ui/ecrans/serveur_injoignable_screen.dart
// Nouvelle interface — serveur injoignable au lancement (maquette A, à droite) : ce n'est PAS un
// problème de licence. Même logique que ServeurInjoignableScreen : réessai automatique toutes les
// 10 s, « Réessayer », Configuration ; en plus, passage Local ⇄ Distant (réglage existant) si
// l'autre adresse est renseignée, saisies en attente rappelées, collecte hors ligne accessible.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/lancement_screen.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

class NvServeurInjoignableScreen extends StatefulWidget {
  final Future<void> Function() reessayer;
  final Duration intervalle;
  const NvServeurInjoignableScreen({super.key, required this.reessayer, this.intervalle = const Duration(seconds: 10)});

  @override
  State<NvServeurInjoignableScreen> createState() => _NvServeurInjoignableScreenState();
}

class _NvServeurInjoignableScreenState extends State<NvServeurInjoignableScreen> {
  Timer? _minuterie;
  late int _reste = widget.intervalle.inSeconds;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _minuterie = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _enCours) return;
      setState(() => _reste--);
      if (_reste <= 0) _essayer();
    });
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _essayer() async {
    if (_enCours) return;
    setState(() => _enCours = true);
    await widget.reessayer();
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _reste = widget.intervalle.inSeconds;
    });
  }

  Future<void> _basculer(AppConfig config) async {
    await config.setApiMode(config.apiMode == ApiMode.local ? ApiMode.distant : ApiMode.local);
    if (mounted) _essayer();
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final licence = context.watch<LicenseProvider>();
    SaisieQueue? q;
    try {
      q = context.watch<SaisieQueue>();
    } catch (_) {}
    final enAttente = q?.aTraiter() ?? 0;
    final nv = context.nv;
    final adresse = config.currentApiUrl.isEmpty ? 'non configurée' : config.currentApiUrl;
    final autre = config.apiMode == ApiMode.local ? config.distantApiAddress : config.localApiAddress;
    final certificat = licence.error == ApiService.messageCertificat;
    return CadreEntree(
      titre: 'Inventaire',
      sousTitre: config.apiMode == ApiMode.local ? 'Connexion locale' : 'Connexion distante',
      actions: [
        ActionEntete(
          icon: Icons.settings_outlined,
          tooltip: 'Configuration',
          onPressed: () async {
            await Navigator.of(context).push(nvRoute(const NvConfigScreen()));
            if (mounted) _essayer();
          },
        ),
      ],
      enfants: [
        SoftCard(
          fond: nv.erreur.bg,
          bordure: nv.erreur.fg.withValues(alpha: 0.35),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 4.14.2 : certificat HTTPS refusé ≠ serveur injoignable (le serveur a répondu).
            Text(certificat ? 'Certificat du serveur refusé' : 'Serveur injoignable',
                key: const ValueKey('nv-titre-injoignable'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: nv.erreur.fg)),
            const SizedBox(height: 6),
            Text(
                certificat
                    ? 'Le serveur Prestige ($adresse) a répondu, mais son certificat de sécurité (HTTPS) n\'est pas reconnu par le '
                        'téléphone. Votre licence n\'est pas en cause : vérifiez l\'adresse dans la Configuration ou faites '
                        'installer un certificat valide sur le serveur.'
                    : 'Le téléphone ne joint pas le serveur Prestige ($adresse). Votre licence n\'est pas en cause : '
                        'vérifiez le Wi-Fi, que le serveur est allumé et l\'adresse dans la Configuration.',
                style: TextStyle(color: nv.erreur.fg, fontSize: 14.5)),
            if (licence.error != null && !certificat) ...[
              const SizedBox(height: 6),
              Text(licence.error!, style: TextStyle(color: nv.erreur.fg, fontSize: 12.5)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: ElevatedButton(
              key: const ValueKey('nv-reessayer-serveur'),
              onPressed: _enCours ? null : _essayer,
              child: Text(_enCours ? 'Connexion…' : 'Réessayer', textAlign: TextAlign.center),
            ),
          ),
          if (autre.trim().isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('nv-basculer-mode'),
                onPressed: _enCours ? null : () => _basculer(config),
                child: Text(config.apiMode == ApiMode.local ? 'Passer en Distant' : 'Passer en Local', textAlign: TextAlign.center),
              ),
            ),
          ],
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_enCours ? 'Connexion en cours…' : 'Nouvel essai automatique dans $_reste s',
              textAlign: TextAlign.center, style: TextStyle(color: nv.gris, fontWeight: FontWeight.w600)),
        ),
        if (enAttente > 0) ...[
          const SizedBox(height: 12),
          Bandeau(ton: nv.erreur, texte: '$enAttente saisie(s) en attente · envoi automatique au retour du réseau'),
        ],
        const SectionTitre('Ce qui marche sans réseau'),
        SoftCard(
          onTap: () => Navigator.of(context).push(nvRoute(const NvCollecteScreen())),
          semantique: 'Collecte hors ligne',
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: nv.scan.bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.download_for_offline_outlined, color: nv.scan.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Continuer sans réseau', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: nv.encre)),
                Text('Collecte hors ligne : scanner et compter, verser plus tard', style: TextStyle(color: nv.gris)),
              ]),
            ),
            Icon(Icons.chevron_right, color: nv.gris),
          ]),
        ),
      ],
    );
  }
}
