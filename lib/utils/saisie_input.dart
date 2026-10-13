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

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  static final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
  static final RegExp _domaine = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$');
  static final RegExp _contexte = RegExp(r'^[A-Za-z0-9_.-]{1,40}$');

  /// Adresse du serveur : IP ou nom de domaine, avec « http:// » ou « https:// » facultatif
  /// (HTTPS accepté, non imposé). Le port va dans le champ Port. [obligatoire] : vide refusé.
  static String? erreurAdresse(String? texte, {bool obligatoire = true}) {
    var t = (texte ?? '').trim();
    if (t.isEmpty) return obligatoire ? 'Adresse requise.' : null;
    if (t.length > 253) return 'Adresse trop longue.';
    final schema = RegExp(r'^https?://', caseSensitive: false).firstMatch(t);
    if (schema != null) t = t.substring(schema.end);
    if (t.endsWith('/')) t = t.substring(0, t.length - 1);
    if (t.contains(':')) return 'Mettez le port dans le champ « Port ».';
    if (t.contains('/') || t.contains(' ')) return 'Adresse invalide (ni chemin ni espace).';
    final ip = _ipv4.firstMatch(t);
    if (ip != null) {
      for (var i = 1; i <= 4; i++) {
        if (int.parse(ip.group(i)!) > 255) return 'Adresse IP invalide.';
      }
      return null;
    }
    if (RegExp(r'^[\d.]+$').hasMatch(t)) return 'Adresse IP invalide.';
    return _domaine.hasMatch(t) ? null : 'Adresse invalide.';
  }

  /// Port : vide (port par défaut) ou 1 à 65 535.
  static String? erreurPort(String? texte) {
    final t = (texte ?? '').trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    return (v == null || v < 1 || v > 65535) ? 'Port : 1 à 65535.' : null;
  }

  /// Contexte de l'application dans l'URL (« prestige ») : lettres, chiffres, « _ », « - », « . ».
  static String? erreurContexte(String? texte) {
    final t = (texte ?? '').trim();
    if (t.isEmpty) return null;
    return _contexte.hasMatch(t) ? null : 'Nom invalide (lettres, chiffres, _ - . ; 40 au plus).';
  }

  /// Entier de [min] à [max] (réglages : nombre d'inventaires, seuils, minutes).
  static String? erreurEntier(String? texte, int min, int max, String libelle) {
    final v = int.tryParse((texte ?? '').trim());
    return (v == null || v < min || v > max) ? '$libelle : $min à $max.' : null;
  }

  /// Clé de licence : caractères de contrôle retirés, 200 caractères au plus.
  static String nettoyerCleLicence(String? texte) {
    final t = (texte ?? '').replaceAll(_controle, '').trim();
    return t.length > 200 ? t.substring(0, 200) : t;
  }

  static List<TextInputFormatter> get rechercheFormatters =>
      [FilteringTextInputFormatter.deny(_controle), LengthLimitingTextInputFormatter(maxRecherche)];

  static List<TextInputFormatter> get quantiteFormatters =>
      [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxChiffres)];
}
