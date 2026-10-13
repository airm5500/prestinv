// lib/ui/ecrans/reglages_scan_screen.dart
// Nouvelle interface — réglages du scan et des sons : son et vibration après un scan (essai des trois
// retours : trouvé, déjà compté, erreur), quantité proposée après un scan. Mêmes réglages et même
// enregistrement que la rubrique « Scan (douchette) » de ConfigScreen (AppConfig.setScanSettings).
import 'package:flutter/material.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/retour_scan.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:provider/provider.dart';

class NvReglagesScanScreen extends StatefulWidget {
  const NvReglagesScanScreen({super.key});

  @override
  State<NvReglagesScanScreen> createState() => _NvReglagesScanScreenState();
}

class _NvReglagesScanScreenState extends State<NvReglagesScanScreen> {
  late bool _son;
  late bool _vibration;
  final _quantite = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final c = context.read<AppConfig>();
    _son = c.sonScan;
    _vibration = c.vibrationScan;
    _quantite.text = c.quantiteScanDefaut?.toString() ?? '';
  }

  @override
  void dispose() {
    _quantite.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!(_formKey.currentState?.validate() ?? true)) {
      nvMessage(context, 'Réglages non enregistrés : corrigez le champ en rouge.', ton: context.nv.erreur);
      return;
    }
    final q = int.tryParse(_quantite.text.trim());
    await context.read<AppConfig>().setScanSettings(son: _son, vibration: _vibration, quantiteDefaut: q, aucuneQuantite: q == null);
    if (!mounted) return;
    nvMessage(context, 'Réglages du scan enregistrés.', ton: context.nv.ok);
    Navigator.of(context).maybePop();
  }

  Widget _essai(String libelle, TypeRetour t, IconData icon) => OutlinedButton.icon(
        onPressed: () => RetourScan.jouer(t, son: _son, vibration: _vibration),
        icon: Icon(icon, size: 18),
        label: Text(libelle),
      );

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    return NvScaffold(
      title: 'Scan et sons',
      subtitle: 'Douchette, bips et vibrations',
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          SoftCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchListTile(
                key: const ValueKey('reglage-son-scan'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Son après un scan'),
                subtitle: const Text('Bip court : trouvé · double : déjà compté · long : erreur'),
                value: _son,
                onChanged: (v) => setState(() => _son = v),
              ),
              SwitchListTile(
                key: const ValueKey('reglage-vibration-scan'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Vibration après un scan'),
                value: _vibration,
                onChanged: (v) => setState(() => _vibration = v),
              ),
              const SizedBox(height: 6),
              Text('Essayer', style: TextStyle(color: nv.gris)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _essai('Trouvé', TypeRetour.succes, Icons.check),
                _essai('Déjà compté', TypeRetour.dejaCompte, Icons.repeat),
                _essai('Erreur', TypeRetour.erreur, Icons.error_outline),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          SoftCard(
            padding: const EdgeInsets.all(16),
            child: TextFormField(
              key: const ValueKey('reglage-quantite-scan'),
              controller: _quantite,
              validator: (v) => (v ?? '').trim().isEmpty ? null : SaisieInput.erreurEntier(v, 1, SaisieInput.maxQuantite, 'Quantité proposée'),
              keyboardType: TextInputType.number,
              inputFormatters: SaisieInput.quantiteFormatters,
              decoration: const InputDecoration(
                labelText: 'Quantité proposée après un scan (vide = aucune)',
                helperText: 'Remplacée dès qu\'on tape un chiffre',
                helperMaxLines: 2,
                errorMaxLines: 3,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(key: const ValueKey('nv-enregistrer-scan'), onPressed: _enregistrer, child: const Text('Enregistrer')),
        ]),
      ),
    );
  }
}
