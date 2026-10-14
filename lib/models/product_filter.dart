// lib/models/product_filter.dart

import 'dart:convert';

// Énumération pour les types de filtres.
// [oublis] (4.13, nouvelle interface) : produits pas encore comptés — un VRAI filtre, distinct du
// filtre par numéro (avant : filtre « numérique » détourné avec « Rattrapage / Oublis », gardé pour les
// écrans d'origine). Ajouté en fin d'énumération : les index enregistrés ne changent pas.
enum FilterType { none, numeric, alphabetic, oublis }

class ProductFilter {
  final FilterType type;
  final String from;
  final String to;

  ProductFilter({
    this.type = FilterType.none,
    this.from = '',
    this.to = '',
  });

  /// Indique si un filtre est actuellement appliqué.
  bool get isActive => type != FilterType.none;

  /// Filtre « oublis » (produits pas encore comptés) : nouveau type, ou ancienne forme des écrans
  /// d'origine (numérique « Rattrapage » / « Oublis »).
  bool get estOublis => type == FilterType.oublis || from == 'Rattrapage';

  /// Crée une copie de l'objet (utile pour la mise à jour de l'état).
  ProductFilter copyWith({
    FilterType? type,
    String? from,
    String? to,
  }) {
    return ProductFilter(
      type: type ?? this.type,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }

  // --- Logique de persistance (pour SharedPreferences) ---

  /// Convertit l'objet filtre en une Map pour le JSON.
  Map<String, dynamic> toJson() {
    return {
      'type': type.index, // Stocke l'index de l'énumération
      'from': from,
      'to': to,
    };
  }

  /// Crée un objet filtre à partir d'une Map (JSON décodé).
  factory ProductFilter.fromJson(Map<String, dynamic> json) {
    return ProductFilter(
      type: FilterType.values[json['type'] ?? 0], // Récupère l'énumération par son index (index inconnu : erreur → aucun filtre)
      from: json['from'] ?? '',
      to: json['to'] ?? '',
    );
  }

  /// Crée un filtre à partir d'une chaîne JSON (depuis SharedPreferences).
  factory ProductFilter.fromRawJson(String rawJson) {
    if (rawJson.isEmpty) {
      return ProductFilter(); // Retourne un filtre vide si pas de sauvegarde
    }
    try {
      return ProductFilter.fromJson(json.decode(rawJson));
    } catch (e) {
      return ProductFilter(); // En cas d'erreur de décodage
    }
  }

  /// Convertit l'objet filtre en une chaîne JSON (pour SharedPreferences).
  String toRawJson() {
    return json.encode(toJson());
  }
}