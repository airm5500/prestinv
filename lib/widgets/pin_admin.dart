// lib/widgets/pin_admin.dart
// Demande du code administrateur avant de modifier la connexion au serveur (adresse, port, contexte).
// Code par défaut « 1234 » au premier usage : il n'ouvre que le changement obligatoire du code.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/services/pin_securise.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/theme.dart';

/// Message par défaut de la demande de code (connexion au serveur).
const motifConnexion = 'La connexion au serveur ne peut être modifiée que par l\'administrateur.';

/// Renvoie `true` si le code administrateur a été vérifié (ou défini au premier usage).
/// [motif] : pourquoi le code est demandé (par défaut : modification de la connexion au serveur).
/// Nouvelle interface active : fenêtre au nouveau style ; sinon fenêtre d'origine (inchangée).
Future<bool> demanderPinAdmin(BuildContext context, {CodeAdmin? code, String motif = motifConnexion}) async {
  final c = code ?? CodeAdmin.instance;
  final r = await showDialog<VerificationPin>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SaisiePinDialog(code: c, motif: motif),
  );
  if (r == VerificationPin.accepte) return true;
  if (r == VerificationPin.changementObligatoire && context.mounted) {
    return await changerPinAdmin(context, code: c, obligatoire: true);
  }
  return false;
}

/// Définition d'un nouveau code (deux saisies identiques, règles de [ReglesPin]).
Future<bool> changerPinAdmin(BuildContext context, {CodeAdmin? code, bool obligatoire = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NouveauPinDialog(code: code ?? CodeAdmin.instance, obligatoire: obligatoire),
  );
  return ok == true;
}

List<TextInputFormatter> get _pinFormatters =>
    [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(ReglesPin.longueurMax)];

class _SaisiePinDialog extends StatefulWidget {
  final CodeAdmin code;
  final String motif;
  const _SaisiePinDialog({required this.code, required this.motif});

  @override
  State<_SaisiePinDialog> createState() => _SaisiePinDialogState();
}

class _SaisiePinDialogState extends State<_SaisiePinDialog> {
  final _pin = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours || _pin.text.isEmpty) return;
    setState(() => _enCours = true);
    final r = await widget.code.verifier(_pin.text);
    if (!mounted) return;
    switch (r) {
      case VerificationPin.accepte:
      case VerificationPin.changementObligatoire:
        Navigator.of(context).pop(r);
        return;
      case VerificationPin.refuse:
        _erreur = 'Code incorrect.';
      case VerificationPin.bloque:
        final reste = await widget.code.attenteRestante();
        _erreur = 'Trop d\'erreurs : réessayez dans ${reste == null ? 'un instant' : CodeAdmin.formaterAttente(reste)}.';
      case VerificationPin.indisponible:
        _erreur = 'Stockage sécurisé indisponible : impossible de vérifier le code.';
    }
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _pin.clear();
    });
  }

  Widget _champ() => TextField(
        controller: _pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: _pinFormatters,
        decoration: InputDecoration(labelText: 'Code', errorText: _erreur, errorMaxLines: 3),
        onSubmitted: (_) => _valider(),
      );

  @override
  Widget build(BuildContext context) => InterfaceVersion.useNew.value ? NvTheme(child: Builder(builder: _nouveau)) : _ancien();

  Widget _nouveau(BuildContext context) {
    {
      return NvCadreDialogue(
        icone: Icons.lock_outline,
        ton: context.nv.info,
        titre: 'Code administrateur',
        message: widget.motif,
        contenu: _champ(),
        boutons: nvRangeeBoutons(context, [
          nvBoutonFenetre(context,
              libelle: 'Annuler', genre: NvGenre.secondaire, onPressed: _enCours ? null : () => Navigator.of(context).pop(VerificationPin.refuse)),
          nvBoutonFenetre(context, libelle: 'Valider', genre: NvGenre.principal, onPressed: _enCours ? null : _valider),
        ], const []),
      );
    }
  }

  Widget _ancien() => AlertDialog(
        title: const Text('Code administrateur'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.motif),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: _pinFormatters,
            decoration: InputDecoration(labelText: 'Code', errorText: _erreur, errorMaxLines: 3),
            onSubmitted: (_) => _valider(),
          ),
        ]),
        actions: [
          TextButton(onPressed: _enCours ? null : () => Navigator.of(context).pop(VerificationPin.refuse), child: const Text('Annuler')),
          ElevatedButton(onPressed: _enCours ? null : _valider, child: const Text('Valider')),
        ],
      );
}

class _NouveauPinDialog extends StatefulWidget {
  final CodeAdmin code;
  final bool obligatoire;
  const _NouveauPinDialog({required this.code, required this.obligatoire});

  @override
  State<_NouveauPinDialog> createState() => _NouveauPinDialogState();
}

class _NouveauPinDialogState extends State<_NouveauPinDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    if (_a.text != _b.text) {
      setState(() => _erreur = 'Les deux codes sont différents.');
      return;
    }
    setState(() => _enCours = true);
    final motif = await widget.code.definir(_a.text);
    if (!mounted) return;
    if (motif == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _enCours = false;
      _erreur = motif;
    });
  }

  @override
  Widget build(BuildContext context) => InterfaceVersion.useNew.value ? NvTheme(child: Builder(builder: _nouveau)) : _ancien();

  Widget _nouveau(BuildContext context) {
    return NvCadreDialogue(
      icone: Icons.password,
      ton: context.nv.info,
      titre: widget.obligatoire ? 'Choisir le code administrateur' : 'Nouveau code administrateur',
      message: widget.obligatoire ? 'Le code par défaut doit être remplacé avant de continuer (4 à 8 chiffres, pas de suite ni de répétition).' : null,
      contenu: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _a,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: _pinFormatters,
          decoration: const InputDecoration(labelText: 'Nouveau code'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _b,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: _pinFormatters,
          decoration: InputDecoration(labelText: 'Confirmer le code', errorText: _erreur, errorMaxLines: 3),
          onSubmitted: (_) => _valider(),
        ),
      ]),
      boutons: nvRangeeBoutons(context, [
        nvBoutonFenetre(context, libelle: 'Annuler', genre: NvGenre.secondaire, onPressed: _enCours ? null : () => Navigator.of(context).pop(false)),
        nvBoutonFenetre(context, libelle: 'Enregistrer', genre: NvGenre.principal, onPressed: _enCours ? null : _valider),
      ], const []),
    );
  }

  Widget _ancien() => AlertDialog(
        title: Text(widget.obligatoire ? 'Choisir le code administrateur' : 'Nouveau code administrateur'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.obligatoire)
              const Text('Le code par défaut doit être remplacé avant de continuer (4 à 8 chiffres, pas de suite ni de répétition).'),
            const SizedBox(height: 8),
            TextField(
              controller: _a,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: _pinFormatters,
              decoration: const InputDecoration(labelText: 'Nouveau code'),
            ),
            TextField(
              controller: _b,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: _pinFormatters,
              decoration: InputDecoration(labelText: 'Confirmer le code', errorText: _erreur, errorMaxLines: 3),
              onSubmitted: (_) => _valider(),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: _enCours ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: _enCours ? null : _valider, child: const Text('Enregistrer')),
        ],
      );
}
