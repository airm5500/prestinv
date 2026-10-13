// lib/utils/saisie_input.dart
// Contrôles de saisie communs (sur le modèle de VenteInput de prestige_vente_app) :
// rien d'absurde ne part au serveur, et un champ vide n'est jamais lu comme « 0 ».
import 'package:flutter/services.dart';

class SaisieInput {
  SaisieInput._();

  /// Quantité comptée : entier de 0 à 99 999.
  static const int maxQuantite = 99999;
  static const int maxChiffres = 5;

  /// Recherche / code scanné : longueur bornée, caractères de contrôle retirés.
  static const int maxRecherche = 60;

  static final RegExp _controle = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _chiffres = RegExp(r'^\d+$');

  /// Quantité valide (0 à 99 999), ou `null` si le champ est vide ou invalide.
  /// IMPORTANT : un champ vide donne `null` (jamais 0 implicite).
  static int? parseQuantite(String? texte) {
    final t = (texte ?? '').trim();
    if (t.isEmpty || t.length > maxChiffres || !_chiffres.hasMatch(t)) return null;
    final v = int.tryParse(t);
    if (v == null || v < 0 || v > maxQuantite) return null;
    return v;
  }

  /// Message d'erreur d'une quantité saisie (null si valide).
  static String? erreurQuantite(String? texte) {
    final t = (texte ?? '').trim();
    if (t.isEmpty) return 'Veuillez saisir une quantité.';
    return parseQuantite(t) == null ? 'Quantité invalide (0 à $maxQuantite).' : null;
  }

  /// Clavier numérique maison : ajoute [chiffre] à [actuel] sans dépasser 5 chiffres.
  static String ajouterChiffre(String actuel, String chiffre) {
    if (!_chiffres.hasMatch(chiffre)) return actuel;
    if (actuel.length >= maxChiffres) return actuel;
    return actuel + chiffre;
  }

  /// Texte de recherche / code scanné nettoyé (caractères parasites retirés, longueur limitée).
  static String nettoyerRecherche(String? texte) {
    final t = (texte ?? '').replaceAll(_controle, '').trim();
    return t.length > maxRecherche ? t.substring(0, maxRecherche) : t;
  }

  static List<TextInputFormatter> get rechercheFormatters =>
      [FilteringTextInputFormatter.deny(_controle), LengthLimitingTextInputFormatter(maxRecherche)];

  static List<TextInputFormatter> get quantiteFormatters =>
      [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxChiffres)];
}
