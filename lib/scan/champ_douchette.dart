// lib/scan/champ_douchette.dart
// Champ de scan qui GARDE le focus, sans clavier à l'écran par défaut (le clavier Android ne cache plus
// le pavé numérique ni le journal). Deux façons de recevoir un code, selon le réglage de la douchette :
// - « Saisie clavier » (émulation de clavier, réglage habituel) : les touches sont lues par [Douchette]
//   avant d'atteindre le champ (rien ne se perd, même pendant le traitement du code précédent) ;
// - « Remplissage direct » (Sunmi) : le texte est posé dans le champ ; il est pris comme un code à la
//   validation (Entrée) ou, sans suffixe, dès que le texte ne bouge plus.
// L'icône clavier affiche le clavier pour chercher un produit par son nom (le champ redevient alors un
// champ de recherche ordinaire).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/scan/douchette.dart';

/// Séparateur GS (FNC1) d'un DataMatrix rendu visible (« ␝ ») au lieu d'être supprimé.
class _GsVisible extends TextInputFormatter {
  const _GsVisible();
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.text.contains(CodeScan.gs) ? newValue.copyWith(text: newValue.text.replaceAll(CodeScan.gs, CodeScan.gsVisible)) : newValue;
}

class ChampDouchette extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Code lu (scan) ou texte validé (recherche au clavier).
  final ValueChanged<String> onCode;

  /// Texte tapé au clavier à l'écran (recherche au fil de la frappe), seulement clavier affiché.
  final ValueChanged<String>? onTexte;

  /// Le clavier à l'écran est affiché / masqué.
  final ValueChanged<bool>? onClavier;

  final bool autofocus;
  final String label;
  final String hint;

  const ChampDouchette({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCode,
    this.onTexte,
    this.onClavier,
    this.autofocus = true,
    this.label = 'Rechercher / Scanner',
    this.hint = 'Scannez ou touchez ⌨ pour chercher',
  });

  @override
  State<ChampDouchette> createState() => ChampDouchetteState();
}

class ChampDouchetteState extends State<ChampDouchette> {
  bool _clavier = false;
  Timer? _remplissage;

  /// Délai sans changement après lequel un texte posé par la douchette (remplissage direct, sans
  /// suffixe Entrée) est pris comme un code.
  static const Duration delaiRemplissage = Duration(milliseconds: 250);

  bool get clavierAffiche => _clavier;

  @override
  void initState() {
    super.initState();
    Douchette.instance.enregistrerChampScan(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant ChampDouchette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      Douchette.instance.retirerChampScan(oldWidget.focusNode);
      if (!_clavier) Douchette.instance.enregistrerChampScan(widget.focusNode);
    }
  }

  @override
  void dispose() {
    _remplissage?.cancel();
    Douchette.instance.retirerChampScan(widget.focusNode);
    super.dispose();
  }

  /// Affiche / masque le clavier à l'écran (recherche par nom).
  void basculerClavier([bool? afficher]) {
    final v = afficher ?? !_clavier;
    if (v == _clavier) return;
    setState(() => _clavier = v);
    if (v) {
      Douchette.instance.retirerChampScan(widget.focusNode);
    } else {
      Douchette.instance.enregistrerChampScan(widget.focusNode);
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    }
    widget.onClavier?.call(v);
    widget.focusNode.requestFocus();
  }

  void _soumettre(String texte) {
    _remplissage?.cancel();
    final t = CodeScan.nettoyer(texte);
    widget.controller.clear();
    if (t.isNotEmpty) widget.onCode(t);
    // Le champ garde le focus (Entrée le lui retire sinon).
    widget.focusNode.requestFocus();
  }

  void _change(String texte) {
    if (_clavier) {
      setState(() {}); // bouton « Effacer »
      widget.onTexte?.call(texte);
      return;
    }
    // Remplissage direct sans suffixe : le texte posé par la douchette devient un code quand il ne bouge plus.
    _remplissage?.cancel();
    if (texte.trim().isEmpty) return;
    _remplissage = Timer(delaiRemplissage, () {
      if (mounted && widget.controller.text.isNotEmpty) _soumettre(widget.controller.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      keyboardType: _clavier ? TextInputType.text : TextInputType.none,
      textInputAction: TextInputAction.search,
      inputFormatters: [const _GsVisible(), LengthLimitingTextInputFormatter(CodeScan.maxLongueur)],
      onSubmitted: _soumettre,
      onChanged: _change,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.qr_code_scanner, size: 20),
        isDense: true,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              tooltip: 'Effacer',
              onPressed: () {
                widget.controller.clear();
                widget.onTexte?.call('');
                widget.focusNode.requestFocus();
              },
            ),
          IconButton(
            icon: Icon(_clavier ? Icons.keyboard_hide : Icons.keyboard, size: 20),
            tooltip: _clavier ? 'Masquer le clavier (scan)' : 'Clavier (chercher par nom)',
            onPressed: () => basculerClavier(),
          ),
        ]),
      ),
    );
  }
}
