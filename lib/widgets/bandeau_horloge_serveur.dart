// lib/widgets/bandeau_horloge_serveur.dart
// 5.0.4 — Bandeau de l'écran de connexion (deux interfaces) : « heure du serveur fausse ».
//
// Le serveur Prestige à jour (plan du 24/11) refuse toute écriture tant que son heure est fausse (HTTP 423). Il expose,
// SANS session, `GET /api/v1/horloge/public` → {"etat": "OK" | "BLOQUE" | "REGULARISATION", "serveur": "24/11/2026 20:52"}.
// Une seule lecture à l'affichage de l'écran (et au changement d'adresse) ; jamais de relance.
//  - BLOQUE : bandeau d'information (les saisies seront gardées sur l'appareil, rien n'est perdu) ;
//  - OK, REGULARISATION (écritures permises) : rien ;
//  - serveur ancien (404), autre réponse, injoignable, délai : rien (jamais un message d'erreur ici).
// Aucun contournement n'est proposé : seuls l'administrateur ou la tâche Windows du serveur remettent l'heure.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

/// État de l'horloge du serveur lu par `GET /horloge/public`.
class HorlogePublique {
  /// « OK », « BLOQUE » ou « REGULARISATION ».
  final String etat;

  /// Heure du serveur telle qu'il l'affiche (« 24/11/2026 20:52 »), vide si absente.
  final String serveur;
  const HorlogePublique(this.etat, this.serveur);

  bool get bloque => etat == 'BLOQUE';

  /// Texte du bandeau (null : rien à afficher).
  String? get message {
    if (!bloque) return null;
    final heure = serveur.isEmpty ? '' : ' (heure du serveur : $serveur)';
    return 'L\'heure du serveur est fausse$heure : le serveur refuse les enregistrements tant qu\'elle n\'est pas remise. '
        'Les saisies restent gardées sur l\'appareil.';
  }

  static const _etats = {'OK', 'BLOQUE', 'REGULARISATION'};

  /// Lit l'état de l'horloge du serveur [baseUrl]. null pour TOUT autre cas que la réponse attendue (serveur ancien :
  /// 404 ; page HTML ; JSON inattendu ; injoignable ; délai dépassé). Ne lève jamais.
  static Future<HorlogePublique?> lire(String baseUrl, {http.Client? client, Duration delai = const Duration(seconds: 5)}) async {
    if (baseUrl.isEmpty) return null;
    try {
      final url = Uri.parse('$baseUrl/api/v1/horloge/public');
      final c = client ?? ApiService.clientParDefaut;
      final r = await (c != null ? c.get(url) : http.get(url)).timeout(delai);
      if (r.statusCode != 200) return null;
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (d is! Map) return null;
      final etat = d['etat'];
      if (etat is! String || !_etats.contains(etat)) return null;
      final serveur = d['serveur'];
      return HorlogePublique(etat, serveur is String ? serveur.trim() : '');
    } catch (_) {
      return null;
    }
  }
}

class BandeauHorlogeServeur extends StatefulWidget {
  /// Adresse du serveur (par défaut : celle de la configuration, fournie par Provider).
  final String? baseUrl;
  const BandeauHorlogeServeur({super.key, this.baseUrl});

  @override
  State<BandeauHorlogeServeur> createState() => _BandeauHorlogeServeurState();
}

class _BandeauHorlogeServeurState extends State<BandeauHorlogeServeur> {
  String? _lue;
  HorlogePublique? _etat;

  String? _adresse() {
    if (widget.baseUrl != null) return widget.baseUrl;
    try {
      return Provider.of<AppConfig>(context).currentApiUrl;
    } catch (_) {
      return null; // écran monté sans configuration (tests, aperçus) : rien à afficher
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _verifier();
  }

  @override
  void didUpdateWidget(covariant BandeauHorlogeServeur oldWidget) {
    super.didUpdateWidget(oldWidget);
    _verifier();
  }

  /// Une lecture par adresse (affichage de l'écran, changement Local / Distant ou d'adresse).
  void _verifier() {
    final adresse = _adresse();
    if (adresse == null || adresse == _lue) return;
    _lue = adresse;
    _etat = null;
    unawaited(HorlogePublique.lire(adresse).then((e) {
      if (!mounted || _lue != adresse) return;
      setState(() => _etat = e);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final texte = _etat?.message;
    if (texte == null) return const SizedBox.shrink();
    final ton = context.nv.attente;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        container: true,
        label: texte,
        child: ExcludeSemantics(
          child: Container(
            key: const ValueKey('bandeau-horloge-serveur'),
            width: double.infinity,
            decoration: BoxDecoration(color: ton.bg, borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.schedule, size: 20, color: ton.fg),
              const SizedBox(width: 8),
              Expanded(child: Text(texte, style: TextStyle(color: ton.fg, fontSize: 13.5, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ),
    );
  }
}
