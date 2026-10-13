// lib/scan/file_scans.dart
// File des codes scannés : les scans arrivés pendant le traitement du précédent (recherche serveur,
// fenêtre de quantité ouverte…) attendent leur tour, dans l'ordre. Aucun n'est perdu, même en rafale.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

class FileScans extends ChangeNotifier {
  /// Traite UN code (recherche, fenêtre de quantité…) ; le suivant attend la fin.
  final Future<void> Function(String code) traiter;

  /// L'écran peut-il traiter maintenant ? (sinon nouvel essai un peu plus tard)
  final bool Function() pret;

  /// Délai entre deux essais quand l'écran n'est pas prêt (fenêtre ouverte par ailleurs…).
  final Duration attente;

  FileScans({required this.traiter, required this.pret, this.attente = const Duration(milliseconds: 300)});

  final Queue<String> _attente = Queue<String>();
  bool _enCours = false;
  bool _ferme = false;
  Timer? _relance;
  String? _courant;

  /// Codes en attente (sans celui en cours).
  int get enAttente => _attente.length;
  List<String> get codesEnAttente => List.unmodifiable(_attente);

  /// Code en cours de traitement.
  String? get courant => _courant;
  bool get occupe => _enCours;

  void ajouter(String code) {
    if (_ferme || code.isEmpty) return;
    _attente.add(code);
    notifyListeners();
    _pomper();
  }

  /// À appeler quand l'écran redevient disponible (fenêtre fermée…).
  void relancer() => _pomper();

  Future<void> _pomper() async {
    if (_enCours || _ferme) return;
    _enCours = true;
    try {
      while (_attente.isNotEmpty && !_ferme) {
        if (!pret()) {
          _relance?.cancel();
          _relance = Timer(attente, _pomper);
          return;
        }
        final code = _attente.removeFirst();
        _courant = code;
        notifyListeners();
        try {
          await traiter(code);
        } catch (e) {
          if (kDebugMode) debugPrint('Scan non traité : $e');
        }
        _courant = null;
      }
    } finally {
      _enCours = false;
      if (!_ferme) notifyListeners();
    }
  }

  void fermer() {
    _ferme = true;
    _relance?.cancel();
    _attente.clear();
  }

  @override
  void dispose() {
    fermer();
    super.dispose();
  }
}
