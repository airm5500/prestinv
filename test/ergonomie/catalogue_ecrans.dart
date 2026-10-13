// Catalogue des ÉCRANS PRINCIPAUX vérifiés par les tests d'ergonomie (nouvelle et ancienne interface).
// Ajouter un écran = ajouter une entrée ici (voir test/README.md) : il est alors rendu sur tout le
// parc d'appareils, aux deux échelles de texte, et contrôlé (débordements, cibles tactiles, contraste).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/screens/a_envoyer_screen.dart';
import 'package:prestinv/screens/collection_screen.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/global_variance_screen.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/screens/license_register_screen.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/screens/serveur_injoignable_screen.dart';
import 'package:prestinv/screens/uncounted_screen.dart';
import 'package:prestinv/ui/ecrans/a_envoyer_screen.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/lancement_screen.dart';
import 'package:prestinv/ui/ecrans/licence_screen.dart';
import 'package:prestinv/ui/ecrans/restants_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';

import '../helpers/banc_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/ergonomie.dart';

final inventaireEssai = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

/// Écran à contrôler.
class EcranControle {
  final String nom;

  /// true : nouvelle interface (thème NvTheme) ; false : écran d'origine.
  final bool nouvelle;
  final Widget Function() construire;

  /// Préparation après l'affichage (ex. ouvrir un rayon) — facultative.
  final Future<void> Function(WidgetTester tester)? apres;

  /// Saisie de quantité : finder du champ qui doit rester visible au-dessus du clavier.
  final Finder Function()? champQuantite;

  /// Animation sans fin (indicateur de chargement) : on avance le temps au lieu d'attendre la fin.
  final bool anime;

  /// Règles d'accessibilité non exigées pour cet écran, avec la raison (anomalie connue documentée
  /// dans test/README.md). À n'utiliser que pour les écrans d'origine, gelés à l'identique.
  final Map<String, String> exemptions;

  const EcranControle(this.nom,
      {required this.nouvelle, required this.construire, this.apres, this.champQuantite, this.anime = false, this.exemptions = const {}});

  /// Monte l'écran avec les providers de l'application (session ouverte, faux serveur réaliste).
  Widget monterAvec(Banc b) {
    InterfaceVersion.useNew.value = nouvelle;
    return nouvelle ? monterNv(b, construire()) : monter(b, construire());
  }
}

Finder quantiteNv() => find.byKey(const ValueKey('nv-quantite'));
Finder quantiteOrigine() => find.ancestor(of: find.text('Quantité'), matching: find.byType(TextField));

Future<void> ouvrirEmplacementOrigine(WidgetTester tester) async {
  await tester.tap(find.text('Sélectionner un emplacement'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('ANTIBIOTIQUES').last);
  await tester.pumpAndSettle();
}

final ecransNouvelleInterface = <EcranControle>[
  EcranControle('Lancement', nouvelle: true, construire: () => const NvLancementScreen(), anime: true),
  EcranControle('Licence', nouvelle: true, construire: () => const NvLicenceScreen()),
  EcranControle('Serveur injoignable', nouvelle: true, construire: () => NvServeurInjoignableScreen(reessayer: () async {})),
  EcranControle('Connexion', nouvelle: true, construire: () => const NvConnexionScreen()),
  EcranControle('Accueil', nouvelle: true, construire: () => const NvAccueilScreen()),
  EcranControle('Choix du rayon', nouvelle: true, construire: () => NvChoixRayonScreen(inventaire: inventaireEssai)),
  EcranControle('Saisie guidée', nouvelle: true,
      construire: () => NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'), champQuantite: quantiteNv),
  EcranControle('Scan continu', nouvelle: true, construire: () => NvScanContinuScreen(inventaire: inventaireEssai)),
  EcranControle('Écarts', nouvelle: true, construire: () => NvEcartsScreen(inventaire: inventaireEssai)),
  EcranControle('Restants', nouvelle: true, construire: () => NvRestantsScreen(inventaire: inventaireEssai)),
  EcranControle('Collecte', nouvelle: true, construire: () => const NvCollecteScreen()),
  EcranControle('À envoyer', nouvelle: true, construire: () => const NvAEnvoyerScreen()),
  EcranControle('Création d\'inventaire', nouvelle: true, construire: () => const NvCreationInventaireScreen()),
  EcranControle('Réglages', nouvelle: true, construire: () => const NvConfigScreen()),
];

/// Anomalie connue A2 (test/README.md) : textes gris clair des écrans d'origine sous le seuil de
/// contraste WCAG. Les écrans d'origine restent STRICTEMENT inchangés (choix de l'officine) : la règle
/// de contraste n'y est pas exigée ; elle l'est pour toute la nouvelle interface.
const _contrasteOrigine = {contraste: 'A2 — écran d\'origine gelé : texte gris sous le seuil de contraste'};

final ecransAncienneInterface = <EcranControle>[
  EcranControle('Licence (origine)', nouvelle: false, construire: () => const LicenseRegisterScreen(), exemptions: _contrasteOrigine),
  EcranControle('Serveur injoignable (origine)', nouvelle: false, construire: () => ServeurInjoignableScreen(reessayer: () async {})),
  EcranControle('Connexion (origine)', nouvelle: false, construire: () => const AncienLoginScreen()),
  EcranControle('Accueil (origine)', nouvelle: false, construire: () => const AncienHomeScreen(), exemptions: _contrasteOrigine),
  EcranControle('Choix d\'inventaire (origine)', nouvelle: false, construire: () => const InventoryListScreen()),
  EcranControle('Saisie guidée (origine)', nouvelle: false,
      construire: () => InventoryEntryScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle),
      apres: ouvrirEmplacementOrigine,
      champQuantite: quantiteOrigine,
      exemptions: _contrasteOrigine),
  EcranControle('Saisie rapide / scan (origine)', nouvelle: false,
      construire: () => InventoryEntryScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle, isQuickMode: true),
      exemptions: _contrasteOrigine),
  EcranControle('Écarts (origine)', nouvelle: false,
      construire: () => GlobalVarianceScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle)),
  EcranControle('Restants (origine)', nouvelle: false, construire: () => UncountedScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle), exemptions: _contrasteOrigine),
  EcranControle('Collecte (origine)', nouvelle: false, construire: () => const CollectionScreen(), exemptions: _contrasteOrigine),
  EcranControle('À envoyer (origine)', nouvelle: false, construire: () => const AEnvoyerScreen()),
  EcranControle('Configuration (origine)', nouvelle: false, construire: () => const ConfigScreen(), exemptions: _contrasteOrigine),
];
