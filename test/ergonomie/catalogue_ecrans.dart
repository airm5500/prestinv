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
import 'package:prestinv/models/product_filter.dart';
import 'package:prestinv/ui/ecrans/a_envoyer_screen.dart';
import 'package:prestinv/ui/ecrans/analyse_screen.dart';
import 'package:prestinv/ui/ecrans/feuille_scanner.dart';
import 'package:prestinv/ui/ecrans/inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/recap_screen.dart';
import 'package:prestinv/ui/filtre_rayon.dart';
import 'package:prestinv/ui/taille_ecran.dart';
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
import '../helpers/camera_essai.dart';
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

  /// Préférences en plus (ex. 4.14 : réglage « Scan par l'appareil photo » actif, [prefsCamera]).
  final Map<String, Object> prefs;

  const EcranControle(this.nom,
      {required this.nouvelle,
      required this.construire,
      this.apres,
      this.champQuantite,
      this.anime = false,
      this.exemptions = const {},
      this.prefs = const {}});

  /// Monte l'écran avec les providers de l'application (session ouverte, faux serveur réaliste), à la
  /// taille d'écran [taille] (réglage 4.13, comme main()).
  Widget monterAvec(Banc b, {TailleEcran taille = TailleEcran.automatique}) {
    InterfaceVersion.useNew.value = nouvelle;
    return aLaTaille(taille, nouvelle ? monterNv(b, construire()) : monter(b, construire()));
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
  // 4.14.1 : depuis la collecte, emplacement des produits collectés présélectionné (deux emplacements trouvés).
  EcranControle('Création d\'inventaire depuis la collecte', nouvelle: true,
      construire: () => const NvCreationInventaireScreen(libelleInitial: 'Collecte du 15-10-2026 09.30', codesCollectes: ['3400935959001', '3400937000003', '3400930000001'])),
  EcranControle('Réglages', nouvelle: true, construire: () => const NvConfigScreen()),
  // 4.13 (maquette validée) :
  EcranControle('Inventaire choisi', nouvelle: true, construire: () => NvInventaireScreen(inventaire: inventaireEssai), apres: actualiserAvancement),
  EcranControle('Accueil, liste déroulée', nouvelle: true, construire: () => const NvAccueilScreen(), apres: deroulerInventaires),
  EcranControle('Feuille Scanner pour…', nouvelle: true, construire: () => Scaffold(body: Align(alignment: Alignment.bottomCenter, child: Material(child: FeuilleScanner(inventaires: [inventaireEssai, inventaireEssai2], courantId: 'INV1'))))),
  EcranControle('Saisie guidée, filtre appliqué', nouvelle: true,
      construire: () => NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'), apres: appliquerFiltre, champQuantite: quantiteNv),
  EcranControle('Filtre du rayon', nouvelle: true,
      construire: () => Scaffold(
          body: Center(child: FenetreFiltre(actuel: ProductFilter(type: FilterType.numeric, from: '2', to: '3'), total: 4, rayon: 'S2B2 – ANTIBIOTIQUES', oublis: 1)))),
  EcranControle('Récapitulatif du rayon', nouvelle: true,
      construire: () => const NvRecapScreen(inventoryId: 'INV1', rayonId: 'S1A0T2', rayonName: 'S1A0T2 – CANNES', retourSaisie: true)),
  EcranControle('Analyse, tous les emplacements', nouvelle: true, construire: () => NvAnalyseScreen(inventaireInitial: inventaireEssai)),
];

final inventaireEssai2 = Inventory(id: 'INV2', libelle: 'Réserve S3 — octobre');

/// 4.14 — écrans avec le bouton appareil photo (réglage actif, appareil photo simulé) et aperçu plein écran.
final ecransAppareilPhoto = <EcranControle>[
  EcranControle('Saisie guidée, bouton appareil photo', nouvelle: true,
      construire: () => NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'), champQuantite: quantiteNv, prefs: prefsCamera),
  EcranControle('Scan continu, bouton appareil photo', nouvelle: true, construire: () => NvScanContinuScreen(inventaire: inventaireEssai), prefs: prefsCamera),
  EcranControle('Collecte, bouton appareil photo', nouvelle: true, construire: () => const NvCollecteScreen(), prefs: prefsCamera),
  EcranControle('Aperçu appareil photo (scan continu, après une lecture)', nouvelle: true,
      construire: () => NvScanContinuScreen(inventaire: inventaireEssai), apres: lectureAppareilPhoto, prefs: prefsCamera),
  EcranControle('Aperçu appareil photo (saisie guidée)', nouvelle: true,
      construire: () => NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'), apres: ouvrirCamera, prefs: prefsCamera),
  EcranControle('Saisie guidée (origine), bouton appareil photo', nouvelle: false,
      construire: () => InventoryEntryScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle),
      apres: ouvrirEmplacementOrigine,
      exemptions: _contrasteOrigine,
      prefs: prefsCamera),
  EcranControle('Saisie rapide / scan (origine), bouton appareil photo', nouvelle: false,
      construire: () => InventoryEntryScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle, isQuickMode: true),
      exemptions: _contrasteOrigine,
      prefs: prefsCamera),
  EcranControle('Collecte (origine), bouton appareil photo', nouvelle: false,
      construire: () => const CollectionScreen(), exemptions: _contrasteOrigine, prefs: prefsCamera),
  EcranControle('Aperçu appareil photo (origine, saisie rapide)', nouvelle: false,
      construire: () => InventoryEntryScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle, isQuickMode: true),
      apres: ouvrirCamera,
      prefs: prefsCamera),
];

/// Aperçu ouvert, un code inconnu lu (ligne « Lu (1) : … », cadre de visée, lampe, Fermer).
Future<void> lectureAppareilPhoto(WidgetTester tester) async {
  await ouvrirCamera(tester);
  await lireCamera(tester, '1234567890128');
  await tester.pump(const Duration(seconds: 4)); // fin du message d'erreur
  await tester.pumpAndSettle();
}

Future<void> actualiserAvancement(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nv-actualiser-avancement')));
  await tester.pumpAndSettle();
}

/// Filtre n° 2 à 3 appliqué par la fenêtre du filtre (ligne réservée remplie, bouton bleu plein).
Future<void> appliquerFiltre(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nv-filtre')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('nv-filtre-num-de')), '2');
  await tester.enterText(find.byKey(const ValueKey('nv-filtre-num-a')), '3');
  await tester.tap(find.byKey(const ValueKey('nv-appliquer-filtre')));
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

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
