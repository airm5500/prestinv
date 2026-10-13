// lib/scan/douchette.dart
// Douchette TOUJOURS PRÊTE (terminaux Sunmi V2s, V3H, V3, V3 Mix ; téléphones avec douchette Bluetooth).
//
// La douchette intégrée « tape » le code comme un clavier très rapide puis envoie Entrée. Ces touches
// sont lues ici, au niveau du clavier matériel (HardwareKeyboard), comme dans prestige_vente_app
// (accueil_screen.dart) : elles n'ont donc plus besoin d'arriver dans un champ de saisie précis.
// - Champ de scan (ChampDouchette) sans clavier à l'écran, champ en lecture seule (Quantité) ou aucun
//   champ : les touches sont lues ici et ne sont JAMAIS perdues.
// - Champ de saisie ordinaire (filtre, recherche avec clavier affiché, connexion…) : rien n'est
//   intercepté, le champ reçoit la saisie comme avant.
//
// Une suite de caractères + Entrée devient :
// - un CODE si elle fait 6 caractères ou plus, ou contient autre chose que des chiffres (une quantité a
//   5 chiffres au plus, un code produit 7 ou plus : CIP7, EAN-8, EAN-13, DataMatrix) ;
// - une QUANTITÉ (chiffres + validation) si elle fait 5 chiffres au plus et qu'une quantité est
//   attendue (clavier physique éventuel : chiffres, Retour arrière, Entrée/OK).
// Sans Entrée (douchette réglée sans suffixe), la suite est prise en compte après [delaiFin] sans touche.
//
// Touches latérales de scan Sunmi (gérées) : codes Android 520, 521, 522, 523 (gâchettes de scan des
// modèles récents), 285 à 288 (selon modèles / versions du système) et F1 à F4 (certains réglages
// « touche personnalisée »). Elles ne font que préparer la lecture : le tampon est vidé et le champ de
// scan reprend le focus ; le code lu arrive ensuite comme une saisie clavier.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prestinv/scan/code_scan.dart';

/// Touches latérales / gâchettes de scan des terminaux Sunmi.
class ToucheScan {
  ToucheScan._();

  /// Codes Android (KeyEvent.getKeyCode()) des touches de scan Sunmi.
  static const List<int> codesAndroid = [520, 521, 522, 523, 285, 286, 287, 288];

  static final Set<int> _ids = {
    for (final c in codesAndroid) LogicalKeyboardKey.androidPlane | c,
    LogicalKeyboardKey.f1.keyId,
    LogicalKeyboardKey.f2.keyId,
    LogicalKeyboardKey.f3.keyId,
    LogicalKeyboardKey.f4.keyId,
  };

  /// Touche logique Flutter d'un code Android non répertorié (comme le fait le moteur Android).
  static LogicalKeyboardKey depuisCodeAndroid(int code) => LogicalKeyboardKey(LogicalKeyboardKey.androidPlane | code);

  static bool est(LogicalKeyboardKey k) => _ids.contains(k.keyId);
}

enum TypeActionDouchette { code, chiffres, effacer, valider, toucheScan, echap }

class ActionDouchette {
  final TypeActionDouchette type;
  final String texte;
  const ActionDouchette(this.type, [this.texte = '']);

  @override
  String toString() => '${type.name}${texte.isEmpty ? '' : '($texte)'}';

  @override
  bool operator ==(Object other) => other is ActionDouchette && other.type == type && other.texte == texte;

  @override
  int get hashCode => Object.hash(type, texte);
}

/// Transforme une suite de touches en actions (sans Flutter : testable seul).
class DecodeurTouches {
  /// Quantité : 5 chiffres au plus (0 à 99 999).
  static const int maxChiffresQuantite = 5;

  String _tampon = '';
  String get tampon => _tampon;

  static final RegExp _chiffres = RegExp(r'^\d+$');

  bool _estQuantite(String t) => t.length <= maxChiffresQuantite && _chiffres.hasMatch(t);

  void caractere(String ch) {
    if (ch.isEmpty) return;
    if (ch == CodeScan.gs || ch.codeUnitAt(0) >= 0x20) _tampon += ch;
    if (_tampon.length > CodeScan.maxLongueur * 2) _tampon = _tampon.substring(_tampon.length - CodeScan.maxLongueur * 2);
  }

  /// Entrée (ou OK) : code, quantité validée, ou simple validation.
  List<ActionDouchette> entree({required bool quantiteAttendue}) {
    final t = _tampon.trim();
    _tampon = '';
    if (t.isEmpty) return quantiteAttendue ? const [ActionDouchette(TypeActionDouchette.valider)] : const [];
    if (quantiteAttendue && _estQuantite(t)) {
      return [ActionDouchette(TypeActionDouchette.chiffres, t), const ActionDouchette(TypeActionDouchette.valider)];
    }
    if (t.length >= 3) return [ActionDouchette(TypeActionDouchette.code, t)];
    return const [];
  }

  /// Plus aucune touche depuis un moment : chiffres tapés à la main → quantité ; code sans suffixe Entrée
  /// → code ; le reste (quelques lettres isolées) est ignoré.
  List<ActionDouchette> finDeSaisie({required bool quantiteAttendue}) {
    final t = _tampon.trim();
    _tampon = '';
    if (t.isEmpty) return const [];
    if (quantiteAttendue && _estQuantite(t)) return [ActionDouchette(TypeActionDouchette.chiffres, t)];
    if (t.length >= CodeScan.minLongueurCode) return [ActionDouchette(TypeActionDouchette.code, t)];
    return const [];
  }

  /// Retour arrière : corrige le tampon en cours, sinon efface un chiffre de la quantité.
  List<ActionDouchette> retourArriere() {
    if (_tampon.isNotEmpty) {
      _tampon = _tampon.substring(0, _tampon.length - 1);
      return const [];
    }
    return const [ActionDouchette(TypeActionDouchette.effacer)];
  }

  void vider() => _tampon = '';
}

/// Écran (ou fenêtre) qui reçoit les lectures de la douchette. La cible active la plus récente qui sait
/// traiter une action la reçoit (une fenêtre de quantité passe devant l'écran qui l'a ouverte).
class CibleDouchette {
  /// La cible peut-elle recevoir maintenant ? (écran au premier plan, fenêtre ouverte…)
  final bool Function() active;
  final void Function(String code)? onCode;
  final void Function(String chiffres)? onChiffres;
  final VoidCallback? onEffacer;
  final VoidCallback? onValider;
  final VoidCallback? onToucheScan;
  final VoidCallback? onEchap;

  CibleDouchette({
    required this.active,
    this.onCode,
    this.onChiffres,
    this.onEffacer,
    this.onValider,
    this.onToucheScan,
    this.onEchap,
  });
}

class Douchette {
  Douchette._();
  static final Douchette instance = Douchette._();

  /// Délai sans touche après lequel la suite tapée est prise en compte sans Entrée.
  static const Duration delaiFin = Duration(milliseconds: 300);

  final DecodeurTouches _decodeur = DecodeurTouches();
  final List<CibleDouchette> _cibles = [];
  final Set<FocusNode> _champsScan = {};
  bool _installe = false;
  Timer? _fin;

  /// Tests : actions distribuées.
  @visibleForTesting
  final List<ActionDouchette> historique = [];

  void _installer() {
    if (_installe) return;
    HardwareKeyboard.instance.addHandler(_surTouche);
    _installe = true;
  }

  void _desinstallerSiVide() {
    if (_cibles.isEmpty && _installe) {
      HardwareKeyboard.instance.removeHandler(_surTouche);
      _installe = false;
      _fin?.cancel();
      _decodeur.vider();
    }
  }

  void ajouter(CibleDouchette c) {
    _cibles.add(c);
    _installer();
  }

  void retirer(CibleDouchette c) {
    _cibles.remove(c);
    _desinstallerSiVide();
  }

  /// Champ de scan sans clavier à l'écran : ses touches sont lues ici (jamais par le champ).
  void enregistrerChampScan(FocusNode n) => _champsScan.add(n);
  void retirerChampScan(FocusNode n) => _champsScan.remove(n);

  /// Tests : remet l'état à zéro.
  @visibleForTesting
  void reinitialiser() {
    _cibles.clear();
    _champsScan.clear();
    _desinstallerSiVide();
    historique.clear();
  }

  CibleDouchette? _cible(bool Function(CibleDouchette) sait) {
    for (final c in _cibles.reversed) {
      if (sait(c) && c.active()) return c;
    }
    return null;
  }

  bool get _quantiteAttendue => _cible((c) => c.onChiffres != null) != null;

  /// Les touches doivent-elles être lues ici ? Non si un champ de saisie ordinaire a le focus.
  bool _doitCapturer() {
    if (_cible((c) => true) == null) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return true;
    if (_champsScan.contains(focus)) return true;
    final ctx = focus.context;
    if (ctx == null) return true;
    final w = ctx.widget;
    EditableText? champ = w is EditableText ? w : ctx.findAncestorWidgetOfExactType<EditableText>();
    if (champ == null) return true;
    // Champ en lecture seule (Quantité) : une saisie y serait perdue → lue ici.
    return champ.readOnly;
  }

  void _distribuer(List<ActionDouchette> actions) {
    for (final a in actions) {
      historique.add(a);
      switch (a.type) {
        case TypeActionDouchette.code:
          _cible((c) => c.onCode != null)?.onCode!(CodeScan.nettoyer(a.texte));
        case TypeActionDouchette.chiffres:
          _cible((c) => c.onChiffres != null)?.onChiffres!(a.texte);
        case TypeActionDouchette.effacer:
          _cible((c) => c.onEffacer != null)?.onEffacer!();
        case TypeActionDouchette.valider:
          _cible((c) => c.onValider != null)?.onValider!();
        case TypeActionDouchette.toucheScan:
          _cible((c) => c.onToucheScan != null)?.onToucheScan!();
        case TypeActionDouchette.echap:
          _cible((c) => c.onEchap != null)?.onEchap!();
      }
    }
  }

  void _programmerFin() {
    _fin?.cancel();
    _fin = Timer(delaiFin, () => _distribuer(_decodeur.finDeSaisie(quantiteAttendue: _quantiteAttendue)));
  }

  bool _surTouche(KeyEvent e) {
    final cle = e.logicalKey;
    if (ToucheScan.est(cle)) {
      if (_cible((c) => true) == null) return false;
      if (e is KeyDownEvent) {
        _fin?.cancel();
        _decodeur.vider();
        _distribuer(const [ActionDouchette(TypeActionDouchette.toucheScan)]);
      }
      return true;
    }
    if (e is KeyUpEvent) return false;
    if (!_doitCapturer()) {
      _decodeur.vider();
      return false;
    }
    if (e is KeyRepeatEvent) return true;
    if (cle == LogicalKeyboardKey.enter || cle == LogicalKeyboardKey.numpadEnter || cle == LogicalKeyboardKey.select) {
      _fin?.cancel();
      _distribuer(_decodeur.entree(quantiteAttendue: _quantiteAttendue));
      return true;
    }
    if (cle == LogicalKeyboardKey.backspace) {
      _fin?.cancel();
      _distribuer(_decodeur.retourArriere());
      if (_decodeur.tampon.isNotEmpty) _programmerFin();
      return true;
    }
    if (cle == LogicalKeyboardKey.escape) {
      _fin?.cancel();
      _decodeur.vider();
      _distribuer(const [ActionDouchette(TypeActionDouchette.echap)]);
      return true;
    }
    final ch = e.character;
    if (ch != null && ch.isNotEmpty && (ch == CodeScan.gs || ch.codeUnitAt(0) >= 0x20)) {
      _decodeur.caractere(ch);
      _programmerFin();
      return true;
    }
    // Autres touches (flèches, Tab, Maj…) : laissées à Flutter.
    return false;
  }
}

/// Branche une cible sur la douchette tant que le widget est monté.
mixin DouchetteCibleMixin<T extends StatefulWidget> on State<T> {
  CibleDouchette? _cibleDouchette;

  void brancherDouchette(CibleDouchette c) {
    debrancherDouchette();
    _cibleDouchette = c;
    Douchette.instance.ajouter(c);
  }

  void debrancherDouchette() {
    final c = _cibleDouchette;
    if (c != null) Douchette.instance.retirer(c);
    _cibleDouchette = null;
  }

  @override
  void dispose() {
    debrancherDouchette();
    super.dispose();
  }
}
