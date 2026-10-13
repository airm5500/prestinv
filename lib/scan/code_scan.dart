// lib/scan/code_scan.dart
// Lecture d'un code scanné : mêmes règles que prestige_vente_app (lib/ventes/core/product_lookup.dart,
// codeCandidates) pour que les deux applications reconnaissent les mêmes boîtes.
//
// - DataMatrix GS1 (avec ou sans séparateur GS, préfixe « ]d2 », GS rendu « ␝ ») → GTIN → EAN-13 → CIP7 ;
// - EAN-13 français 34009 + CIP7 + clé → CIP7 essayé aussi ;
// - GTIN-14 commençant par 0 → EAN-13 ;
// - UPC-A (12 chiffres, lu ainsi par certains lecteurs pour un EAN-13 commençant par 0) → EAN-13 ;
// - espaces et caractères parasites (retour chariot, tabulation, caractères de contrôle) retirés.
import 'package:prestinv/scan/datamatrix_parser.dart';

class CodeScan {
  CodeScan._();

  /// Longueur maximale gardée (un DataMatrix complet dépasse les 60 caractères d'une recherche).
  static const int maxLongueur = 120;

  /// Longueur minimale d'un code produit (CIP7 = 7 ; EAN-8 = 8). Une quantité a 5 chiffres au plus.
  static const int minLongueurCode = 6;

  static const String gs = '\u001d';
  static const String gsVisible = '␝';

  static final RegExp _chiffres = RegExp(r'^\d+$');
  static final RegExp _parasites = RegExp(r'[\x00-\x1C\x1E\x1F\x7F]');

  /// Code tel qu'il sera analysé : GS (FNC1) conservé, « ␝ » redevient GS, autres caractères de contrôle
  /// retirés, espaces de début et de fin retirés, longueur bornée.
  static String nettoyer(String? brut) {
    final v = (brut ?? '').replaceAll(gsVisible, gs).replaceAll(_parasites, '').trim();
    return v.length > maxLongueur ? v.substring(0, maxLongueur) : v;
  }

  /// Code à afficher (GS rendu visible).
  static String affichage(String code) => code.replaceAll(gs, gsVisible);

  /// La saisie ressemble-t-elle à un code scanné (et non à un nom) ?
  static bool ressembleACode(String brut) {
    final v = nettoyer(brut);
    if (v.isEmpty) return false;
    if (v.contains(gs) || v.startsWith(']d2') || (v.startsWith('01') && v.length > 16)) return true;
    final d = v.replaceAll(RegExp(r'\s'), '');
    return _chiffres.hasMatch(d) && d.length >= 7;
  }

  /// Codes à essayer, du plus précis au plus large (sans doublon).
  static List<String> candidats(String brut) {
    final v = nettoyer(brut);
    if (v.isEmpty) return const [];
    final out = <String>[];
    final dm = DataMatrixParser.parse(v);
    if (dm != null && dm.productSearchQueries.isNotEmpty) out.addAll(dm.productSearchQueries);
    final d = v.replaceAll(RegExp(r'\s'), '');
    if (_chiffres.hasMatch(d)) {
      out.add(d);
      // GTIN-14 commençant par 0 → EAN-13.
      final ean = d.length == 14 && d.startsWith('0') ? d.substring(1) : d;
      if (ean != d) out.add(ean);
      // EAN-13 / CIP13 français 34009 + CIP7 + clé.
      if (ean.length == 13 && ean.startsWith('34009')) out.add(ean.substring(5, 12));
      // UPC-A → EAN-13.
      if (d.length == 12) out.add('0$d');
    } else if (out.isEmpty) {
      out.add(d.replaceAll(gs, ''));
    }
    return out.where((c) => c.isNotEmpty).toSet().toList();
  }

  /// Message affiché quand aucun produit de l'inventaire ne correspond.
  static String messageIntrouvable(String code) => 'Code lu : ${affichage(code)} — introuvable dans cet inventaire';
}
