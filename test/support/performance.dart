// Outils des tests de PERFORMANCE (test/performance/) et des tests RÉSEAU (test/reseau/).
//
// Principe : chaque mesure est comparée à un SEUIL écrit ici (table [Seuils]) ; au-delà, le test
// échoue (en local comme sur la CI). Chaque mesure est aussi imprimée sur une ligne
// « PRESTINV_MESURE {json} », que tool/rapport_tests.dart relève dans la sortie `flutter test --machine`
// pour l'écrire dans le rapport de tests de livraison (résumé du job GitHub + artefact `rapport-tests`).
//
// Temps des images : les tests de widgets tournent en temps SIMULÉ, mais le travail de chaque image
// (construction, mise en page, peinture) est réellement exécuté par le processeur : on chronomètre donc
// chaque `tester.pump()` avec une horloge réelle (Stopwatch, non simulée), image par image
// ([ChronoImages]). C'est le même travail que `binding.framePolicy` / `traceAction` observent sur un
// appareil, en mode test (JIT, assertions actives : plus lent qu'une version « release »). Les seuils
// sont donc des seuils de NON-RÉGRESSION en mode test sur la CI Linux, pas des temps d'appareil.
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/faux_prestige_http.dart';

/// Seuils de performance et de nombre de requêtes. Calibrés sur la CI GitHub (ubuntu-latest, run
/// 38675865785, `flutter test -j 1`) avec une marge d'environ ×3 sur la mesure la plus lente (temps) et
/// une marge nulle sur les requêtes (plafond = nombre attendu par le fonctionnement voulu). Sur un PC
/// chargé (autres tests en parallèle), lancer `flutter test -j 1 test/performance`.
/// Valeurs mesurées et marge : test/README.md (« Seuils de performance »). Un seuil ne se relève
/// qu'avec une justification écrite dans le README (jamais pour faire passer un test).
class Seuils {
  Seuils._();

  // --- Démarrage ---
  /// Lancement de l'application (montage de la racine, licence lue sur le faux serveur) jusqu'à
  /// l'écran de connexion affiché et immobile, à froid (première construction de tous les widgets).
  static const demarrageMs = 2500;

  /// Images rendues pendant ce démarrage (animations d'entrée comprises).
  static const demarrageImages = 10;

  /// Requêtes au démarrage (avant connexion) : la licence seulement.
  static const demarrageRequetes = 1;

  // --- Longues listes : temps de construction d'UNE image (ms, mode test) ---
  /// PIRE image pendant le défilement d'une longue liste, après un premier passage (code déjà compilé) :
  /// aucune image au-dessus.
  static const imageDefilementMs = 64;

  /// 90 % des images de défilement en dessous (image « courante »).
  static const imageCouranteMs = 16;

  /// Pire image d'un changement de produit (« Suivant » : tout l'écran de saisie reconstruit).
  static const imageEcranMs = 50;

  /// 90 % des changements de produit en dessous.
  static const imageEcranCouranteMs = 40;

  /// Pire image (première apparition d'un écran, à froid, ou défilement d'une très longue liste).
  static const imageFroideMs = 200;

  /// Ouverture d'un écran sur une longue liste (lecture du faux serveur, tri, première image), à froid.
  static const ouvertureListeMs = 1500;

  /// Accueil : 200 inventaires déroulés, avancement de chacun calculé (1 400 réponses du faux serveur lues).
  static const accueil200Ms = 6000;

  // --- Traitement local ---
  /// File d'envoi de 5 000 saisies sur un VRAI fichier : chaque saisie est écrite sur le disque (et
  /// forcée sur le support, `flush`) avant d'être confirmée — durée par saisie enregistrée.
  static const enregistrementParSaisieMs = 5;

  /// Relecture des 5 000 saisies au redémarrage de l'application.
  static const relecture5000Ms = 500;

  /// Envoi des 5 000 saisies à un serveur instantané (une écriture disque par confirmation) — par saisie.
  static const envoiParSaisieMs = 5;

  /// Normaliser 10 000 codes scannés (appareil photo + recherche : EAN-13, UPC-A/E, Code 39, Codabar, DataMatrix).
  static const normalisation10000Ms = 500;
}

/// Mesure enregistrée (pour le rapport) et comparée à son seuil.
void mesurer(String nom, num valeur, {required num seuil, required String unite, String? detail}) {
  // ignore: avoid_print
  print('PRESTINV_MESURE ${json.encode({
        'nom': nom,
        'valeur': valeur is double ? double.parse(valeur.toStringAsFixed(1)) : valeur,
        'seuil': seuil,
        'unite': unite,
        if (detail != null) 'detail': detail,
      })}');
  expect(valeur, lessThanOrEqualTo(seuil), reason: '$nom : $valeur $unite > seuil $seuil $unite${detail == null ? '' : ' ($detail)'}');
}

/// Chronomètre chaque image (chaque `pump`) en temps réel.
class ChronoImages {
  final List<double> ms = [];

  Future<void> pump(WidgetTester tester, [Duration? duree]) async {
    final sw = Stopwatch()..start();
    await tester.pump(duree);
    ms.add(sw.elapsedMicroseconds / 1000);
  }

  int get nombre => ms.length;
  double get max => ms.isEmpty ? 0 : ms.reduce((a, b) => a > b ? a : b);
  double get moyenne => ms.isEmpty ? 0 : ms.reduce((a, b) => a + b) / ms.length;

  /// 90e centile.
  double get p90 {
    if (ms.isEmpty) return 0;
    final t = [...ms]..sort();
    return t[((t.length - 1) * 0.9).round()];
  }

  String get resume => '${ms.length} images, moyenne ${moyenne.toStringAsFixed(1)} ms, p90 ${p90.toStringAsFixed(1)} ms, max ${max.toStringAsFixed(1)} ms';
}

int _images = 0;
bool _compteurBranche = false;

/// Nombre d'images rendues depuis le début du fichier de tests (compteur branché au premier appel).
int imagesRendues() {
  if (!_compteurBranche) {
    SchedulerBinding.instance.addPersistentFrameCallback((_) => _images++);
    _compteurBranche = true;
  }
  return _images;
}

/// Plus grande zone défilante affichée (la liste principale de l'écran).
Finder plusGrandeListe(WidgetTester tester) {
  final tous = find.byType(Scrollable).evaluate().toList();
  tous.sort((a, b) => (b.size?.height ?? 0).compareTo(a.size?.height ?? 0));
  final cible = tous.first;
  return find.byElementPredicate((e) => identical(e, cible));
}

/// Fait défiler [scrollable] (un [Scrollable]) par pas de [pas] dp jusqu'en bas (ou [maxPas] pas), une
/// image chronométrée par pas. Renvoie le nombre de pas effectués.
Future<int> defilerJusquEnBas(WidgetTester tester, Finder scrollable, ChronoImages chrono, {double pas = 120, int maxPas = 2000}) async {
  final etat = tester.state<ScrollableState>(scrollable);
  var n = 0;
  while (n < maxPas && etat.position.pixels < etat.position.maxScrollExtent) {
    etat.position.jumpTo((etat.position.pixels + pas).clamp(0, etat.position.maxScrollExtent));
    await chrono.pump(tester);
    n++;
  }
  return n;
}

/// Remonte en haut de [scrollable] (une image).
Future<void> remonter(WidgetTester tester, Finder scrollable) async {
  final etat = tester.state<ScrollableState>(scrollable);
  etat.position.jumpTo(0);
  await tester.pump();
}

/// Catalogue de [rayons] emplacements × [parRayon] produits. [ecarts] : produits déjà comptés avec écart.
FauxPrestige grandCatalogue({int rayons = 3, int parRayon = 100, bool ecarts = false, int inventaires = 2}) {
  final s = FauxPrestige(nombre: 0);
  s.inventaires = {
    'INV1': 'Inventaire annuel 2026',
    for (var i = 2; i <= inventaires; i++) 'INV$i': 'Inventaire n° $i — réserve ${i % 7}',
  };
  s.rayons
    ..clear()
    ..addAll({for (var r = 1; r <= rayons; r++) 'E$r': 'EMPLACEMENT ${r.toString().padLeft(2, '0')}'});
  var id = 1;
  for (var r = 1; r <= rayons; r++) {
    for (var i = 0; i < parRayon; i++, id++) {
      final p = FauxProduit(id, '34009${id.toString().padLeft(8, '0')}', 'PRODUIT ${id.toString().padLeft(5, '0')} CPR B/${10 + id % 20}', 'E$r', 5 + id % 40);
      if (ecarts || id % 3 == 0) {
        p
          ..saisi = p.theorique + (id.isEven ? 2 : -3)
          ..dtUpdated = '2026-10-13T09:00:00';
      }
      s.produits.add(p);
    }
  }
  return s;
}

