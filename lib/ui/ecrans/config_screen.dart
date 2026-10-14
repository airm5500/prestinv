// lib/ui/ecrans/config_screen.dart
// Nouvelle interface — configuration, par rubriques (connexion au serveur protégée par le code
// administrateur, inventaire, envoi, session, scan et sons, interface). Mêmes réglages, mêmes
// contrôles (SaisieInput) et même enregistrement que ConfigScreen (AppConfig.setApiConfig,
// setAppSettings, setSendMode) ; « Scan et sons » a sa propre page (NvReglagesScanScreen).
// L'interrupteur « Nouvelle interface » (code administrateur) permet de revenir aux écrans d'origine.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/ecrans/reglages_scan_screen.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/taille_ecran.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:prestinv/widgets/pin_admin.dart';
import 'package:provider/provider.dart';

class NvConfigScreen extends StatefulWidget {
  /// Tests : vérification du code administrateur (sinon demanderPinAdmin).
  final Future<bool> Function(BuildContext context)? verifierPin;
  const NvConfigScreen({super.key, this.verifierPin});

  @override
  State<NvConfigScreen> createState() => _NvConfigScreenState();
}

class _NvConfigScreenState extends State<NvConfigScreen> {
  final _localAdresse = TextEditingController();
  final _localPort = TextEditingController();
  final _distAdresse = TextEditingController();
  final _distPort = TextEditingController();
  final _contexte = TextEditingController();
  final _maxResult = TextEditingController();
  final _seuil = TextEditingController();
  final _deconnexion = TextEditingController();
  final _chemin = TextEditingController();
  final _rappel = TextEditingController();
  late bool _stock;
  late bool _cumul;
  bool _contexteModifiable = false;
  bool _test = false;
  bool _deverrouille = false;
  final _formKey = GlobalKey<FormState>();

  String? Function(String?) _siDeverrouille(String? Function(String?) c) => (v) => _deverrouille ? c(v) : null;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppConfig>();
    _localAdresse.text = c.localApiAddress;
    _localPort.text = c.localApiPort;
    _distAdresse.text = c.distantApiAddress;
    _distPort.text = c.distantApiPort;
    _contexte.text = c.appName;
    _maxResult.text = '${c.maxResult}';
    _seuil.text = '${c.largeValueThreshold}';
    _deconnexion.text = '${c.autoLogoutMinutes}';
    _chemin.text = c.networkExportPath;
    _rappel.text = '${c.sendReminderMinutes}';
    _stock = c.showTheoreticalStock;
    _cumul = c.isCumulEnabled;
  }

  @override
  void dispose() {
    for (final c in [_localAdresse, _localPort, _distAdresse, _distPort, _contexte, _maxResult, _seuil, _deconnexion, _chemin, _rappel]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _pin(String motif) => widget.verifierPin != null ? widget.verifierPin!(context) : demanderPinAdmin(context, motif: motif);

  /// Réglage protégé (4.13) : changé seulement après le code administrateur, enregistré tout de suite.
  Future<void> _reglageProtege({bool? masquer, bool? creation}) async {
    if (!await _pin('Ce réglage ne peut être modifié que par l\'administrateur.') || !mounted) return;
    await context.read<AppConfig>().setReglagesProteges(masquerDejaCompte: masquer, creationAutresComptes: creation);
  }

  /// Taille de l'écran : code administrateur, enregistrée pour le prochain lancement ; « Relancer
  /// maintenant » l'applique tout de suite (l'interface est reconstruite).
  Future<void> _changerTaille(TailleEcran t) async {
    if (t == TailleEcranReglage.enregistree) return;
    if (!await _pin('La taille de l\'écran ne peut être modifiée que par l\'administrateur.') || !mounted) return;
    await TailleEcranReglage.enregistrer(t);
    if (!mounted) return;
    setState(() {});
    final maintenant = await nvDialogue<bool>(
      context,
      key: const ValueKey('nv-taille-relancer'),
      icone: Icons.aspect_ratio,
      ton: context.nv.info,
      titre: 'Taille de l\'écran : ${t.libelle}',
      message: 'Appliquée au prochain lancement de l\'application. Vous pouvez aussi relancer l\'affichage maintenant '
          '(retour à l\'accueil ; la session et les saisies sont gardées).',
      boutons: const [
        NvBouton('Plus tard', false, genre: NvGenre.secondaire),
        NvBouton('Relancer maintenant', true, genre: NvGenre.principal, key: ValueKey('nv-relancer-maintenant')),
      ],
    );
    if (maintenant == true && mounted) {
      // Retour à l'accueil puis interface reconstruite à la nouvelle taille (le navigateur, à clé
      // globale, est conservé : session, saisies et accueil restent).
      Navigator.of(context).popUntil((r) => r.isFirst);
      TailleEcranReglage.appliquerMaintenant();
    }
  }

  Future<void> _deverrouiller() async {
    final ok = await (widget.verifierPin ?? demanderPinAdmin)(context);
    if (mounted && ok) setState(() => _deverrouille = true);
  }

  Future<void> _tester(String adresse, String port) async {
    if (adresse.isEmpty || _test) return;
    var hote = adresse.trim();
    final https = hote.toLowerCase().startsWith('https://');
    if (hote.toLowerCase().startsWith('http')) hote = Uri.parse(hote).host;
    var url = '${https ? 'https' : 'http'}://$hote';
    if (port.isNotEmpty) url += ':$port';
    setState(() => _test = true);
    nvMessage(context, 'Test de connexion vers $url…');
    try {
      await http.head(Uri.parse(url)).timeout(const Duration(seconds: 7));
      if (mounted) nvMessage(context, 'Succès : serveur accessible à l\'adresse $url !', ton: context.nv.ok);
    } catch (_) {
      if (mounted) {
        nvMessage(context, 'Échec : impossible de joindre le serveur. Vérifiez l\'adresse, le port et la connexion réseau.', ton: context.nv.erreur);
      }
    } finally {
      if (mounted) setState(() => _test = false);
    }
  }

  Future<void> _enregistrer() async {
    final c = context.read<AppConfig>();
    if (!(_formKey.currentState?.validate() ?? true)) {
      nvMessage(context, 'Configuration non enregistrée : corrigez les champs en rouge.', ton: context.nv.erreur);
      return;
    }
    await c.setApiConfig(
      localAddress: _localAdresse.text.trim(),
      localPort: _localPort.text.trim(),
      distantAddress: _distAdresse.text.trim(),
      distantPort: _distPort.text.trim(),
      appName: _contexte.text.trim(),
    );
    await c.setAppSettings(
      maxResult: int.tryParse(_maxResult.text) ?? 3,
      showStock: _stock,
      largeValue: int.tryParse(_seuil.text) ?? 1000,
      logoutMinutes: int.tryParse(_deconnexion.text) ?? 0,
      exportPath: _chemin.text.trim(),
      sendReminderMinutes: int.tryParse(_rappel.text) ?? 15,
      isCumulEnabled: _cumul,
    );
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InterfaceVersion.home()));
    }
  }

  Widget _rubrique(String titre, IconData icon, List<Widget> enfants) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SoftCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, color: context.nv.action),
              const SizedBox(width: 10),
              Expanded(child: Semantics(header: true, child: Text(titre, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: context.nv.encre)))),
            ]),
            const SizedBox(height: 10),
            ...enfants,
          ]),
        ),
      );

  Widget _adresse(String label, TextEditingController a, TextEditingController p, {required bool obligatoire}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: TextStyle(color: context.nv.encre, fontWeight: FontWeight.w600))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextFormField(
              controller: a,
              enabled: _deverrouille,
              validator: _siDeverrouille((v) => SaisieInput.erreurAdresse(v, obligatoire: obligatoire)),
              decoration: InputDecoration(labelText: 'IP ou domaine', semanticCounterText: label, errorMaxLines: 3),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: TextFormField(
              controller: p,
              enabled: _deverrouille,
              validator: _siDeverrouille(SaisieInput.erreurPort),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Port', errorMaxLines: 3),
            ),
          ),
          IconButton(
            tooltip: 'Tester la connexion',
            onPressed: _test ? null : () => _tester(a.text, p.text),
            icon: const Icon(Icons.network_ping),
          ),
          ]),
        ]),
      );

  Widget _nombre(TextEditingController c, String label, String? Function(String?) v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c,
          validator: v,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, errorMaxLines: 3),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final nv = context.nv;
    return NvScaffold(
      title: 'Réglages',
      subtitle: 'Configuration de l\'application',
      // Formulaire entièrement construit (SingleChildScrollView, pas de liste paresseuse) : chaque champ
      // est contrôlé à l'enregistrement, même hors de l'écran.
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _rubrique('Connexion au serveur', Icons.dns_outlined, [
            if (!_deverrouille)
              OutlinedButton.icon(
                key: const ValueKey('nv-deverrouiller'),
                onPressed: _deverrouiller,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Modifier la connexion (code administrateur)'),
              )
            else
              Row(children: [
                Icon(Icons.lock_open, color: nv.ok.fg),
                const SizedBox(width: 6),
                Expanded(child: Text('Connexion modifiable', style: TextStyle(color: nv.ok.fg, fontWeight: FontWeight.bold))),
                TextButton(onPressed: () => changerPinAdmin(context), child: const Text('Changer le code')),
              ]),
            const SizedBox(height: 12),
            _adresse('Adresse locale', _localAdresse, _localPort, obligatoire: true),
            _adresse('Adresse distante', _distAdresse, _distPort, obligatoire: false),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _contexte,
                  readOnly: !_contexteModifiable,
                  validator: _siDeverrouille(SaisieInput.erreurContexte),
                  decoration: const InputDecoration(labelText: 'Nom de l\'application (contexte URL)', errorMaxLines: 3),
                ),
              ),
              IconButton(
                tooltip: _contexteModifiable ? 'Terminer' : 'Modifier',
                onPressed: _deverrouille ? () => setState(() => _contexteModifiable = !_contexteModifiable) : null,
                icon: Icon(_contexteModifiable ? Icons.check : Icons.edit_outlined),
              ),
            ]),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mode de connexion'),
              subtitle: Text(config.apiMode == ApiMode.local ? 'Local' : 'Distant'),
              value: config.apiMode == ApiMode.local,
              onChanged: (v) => config.setApiMode(v ? ApiMode.local : ApiMode.distant),
            ),
          ]),
          _rubrique('Inventaire', Icons.inventory_2_outlined, [
            _nombre(_maxResult, 'Nombre d\'inventaires à afficher', (v) => SaisieInput.erreurEntier(v, 1, 100, 'Nombre d\'inventaires')),
            _nombre(_seuil, 'Seuil d\'alerte « grande quantité »', (v) => SaisieInput.erreurEntier(v, 1, SaisieInput.maxQuantite, 'Seuil')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Afficher le stock théorique'),
              subtitle: const Text('Saisie, écarts, récapitulatif et analyse, à l\'écran comme dans les PDF / CSV'),
              value: _stock,
              onChanged: (v) => setState(() => _stock = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cumul de quantité'),
              subtitle: const Text('Produit déjà compté : proposer Remplacer ou Ajouter'),
              value: _cumul,
              onChanged: (v) => setState(() => _cumul = v),
            ),
          ]),
          _rubrique('Réglages protégés', Icons.admin_panel_settings_outlined, [
            Text('Protégés par le code administrateur ; enregistrés dès le changement.', style: TextStyle(color: nv.gris, fontSize: 13)),
            SwitchListTile(
              key: const ValueKey('nv-masquer-deja-compte'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Masquer la quantité déjà comptée'),
              subtitle: const Text('Saisie et écarts ; masquée aussi dans les PDF / CSV des écarts'),
              value: config.masquerDejaCompte,
              onChanged: (v) => _reglageProtege(masquer: v),
            ),
            SwitchListTile(
              key: const ValueKey('nv-creation-autres'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Autoriser la création d\'inventaire aux autres comptes'),
              subtitle: const Text('Administrateur et pharmacien : toujours. Désactivé par défaut pour les autres comptes.'),
              value: config.creationAutresComptes,
              onChanged: (v) => _reglageProtege(creation: v),
            ),
            const SizedBox(height: 8),
            Text('Taille de l\'écran', style: TextStyle(color: nv.encre, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<TailleEcran>(
              key: const ValueKey('nv-taille-ecran'),
              segments: [
                for (final t in TailleEcran.values)
                  ButtonSegment(value: t, label: FittedBox(fit: BoxFit.scaleDown, child: Text(t.libelle, key: ValueKey('nv-taille-${t.name}')))),
              ],
              selected: {TailleEcranReglage.enregistree},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _changerTaille(s.first),
            ),
            const SizedBox(height: 6),
            Text(
              TailleEcranReglage.enAttente
                  ? 'Choix enregistré : appliqué au prochain lancement.'
                  : 'Pour les petits écrans (Sunmi V2s 5,45″) : Compact et Très compact réduisent toute l\'interface.',
              key: const ValueKey('nv-taille-aide'),
              style: TextStyle(color: TailleEcranReglage.enAttente ? nv.attente.fg : nv.gris, fontSize: 13),
            ),
          ]),
          _rubrique('Envoi au serveur', Icons.cloud_upload_outlined, [
            SwitchListTile(
              key: const ValueKey('nv-mode-envoi'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Mode d\'envoi'),
              subtitle: Text(config.sendMode == SendMode.direct ? 'Direct (après chaque saisie)' : 'Collecte (envoi manuel)'),
              value: config.sendMode == SendMode.direct,
              onChanged: (v) => config.setSendMode(v ? SendMode.direct : SendMode.collect),
            ),
            _nombre(_rappel, 'Rappel d\'envoi (minutes ; 0 = envoi automatique toutes les 15 min)', (v) => SaisieInput.erreurEntier(v, 0, 600, 'Rappel')),
            Text('Envoi manuel (Collecte) : bouton d\'envoi à droite du nuage en saisie ; après ce délai, message bloquant '
                '« Veuillez sauvegarder vos saisies » jusqu\'à l\'envoi.', style: TextStyle(color: nv.gris, fontSize: 13)),
          ]),
          _rubrique('Session et exports', Icons.timer_outlined, [
            _nombre(_deconnexion, 'Déconnexion automatique (minutes, 0 = désactivée)', (v) => SaisieInput.erreurEntier(v, 0, 600, 'Délai')),
            TextFormField(
              controller: _chemin,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Chemin réseau pour nom de fichier (facultatif)', hintText: 'ex : \\\\SERVEUR\\partage'),
            ),
          ]),
          _rubrique('Scan et sons', Icons.qr_code_scanner, [
            Text(
              '${config.sonScan ? 'Son' : 'Sans son'} · ${config.vibrationScan ? 'vibration' : 'sans vibration'} · '
              'quantité proposée : ${config.quantiteScanDefaut ?? 'aucune'}',
              style: TextStyle(color: nv.gris),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('nv-reglages-scan'),
              onPressed: () => Navigator.of(context).push(nvRoute(const NvReglagesScanScreen())),
              icon: const Icon(Icons.tune),
              label: const Text('Réglages du scan et des sons'),
            ),
          ]),
          _rubrique('Interface', Icons.palette_outlined, [
            InterfaceVersionTile(verifierPin: widget.verifierPin),
            const SizedBox(height: 8),
            Text('Apparence', style: TextStyle(color: nv.gris)),
            const SizedBox(height: 6),
            ValueListenableBuilder<Apparence>(
              valueListenable: InterfaceVersion.apparence,
              builder: (_, a, __) => SegmentedButton<Apparence>(
                key: const ValueKey('nv-apparence'),
                segments: [for (final x in Apparence.values) ButtonSegment(value: x, label: FittedBox(fit: BoxFit.scaleDown, child: Text(x.libelle)))],
                selected: {a},
                showSelectedIcon: false,
                onSelectionChanged: (s) => InterfaceVersion.setApparence(s.first),
              ),
            ),
          ]),
          FilledButton(key: const ValueKey('nv-valider-config'), onPressed: _enregistrer, child: const Text('Valider la configuration')),
        ]),
        ),
      ),
    );
  }
}
