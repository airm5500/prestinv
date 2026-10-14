// DE BOUT EN BOUT — 4.14 : scan par l'appareil photo (téléphones sans douchette), application entière
// (racineApplication) contre le faux serveur Prestige, appareil photo SIMULÉ :
//  - installation existante : réglage désactivé → aucun bouton ; Réglages → « Scan par l'appareil photo »
//    (code administrateur) → bouton ; scan continu : autorisation au premier usage, lectures enchaînées
//    dans l'aperçu, saisies envoyées au serveur ;
//  - saisie guidée : l'aperçu se ferme après la lecture, le produit lu s'ouvre ;
//  - ancienne interface : Configuration d'origine (code administrateur) → saisie rapide par l'appareil
//    photo → envoi direct.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/camera/scan_camera.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';

import '../helpers/banc_essai.dart';
import '../helpers/camera_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';

Future<void> toucherCle(WidgetTester tester, String cle) => toucher(tester, find.byKey(ValueKey(cle)));

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('nouvelle interface : réglage (code administrateur) → scan continu à l\'appareil photo → serveur à jour', (tester) async {
    tailleEcran(tester, telephone360);
    final horloge = HorlogeEssai();
    final acces = installerCameraSimulee(etat: AutorisationCamera.aDemander, horloge: horloge);
    final app = await lancerApplication(tester);
    await seConnecter(tester);

    // Désactivé par défaut : pas de bouton dans le scan continu.
    await choisirInventaire(tester, 'INV1');
    await toucherCle(tester, 'nv-scan-continu');
    await tester.pumpAndSettle();
    expect(find.byType(NvScanContinuScreen), findsOneWidget);
    expect(boutonCamera(), findsNothing);
    await revenirAccueil(tester);

    // Réglages → réglage protégé.
    await toucher(tester, find.text('Réglages'));
    await tester.pumpAndSettle();
    expect(find.byType(NvConfigScreen), findsOneWidget);
    final reglage = find.byKey(const ValueKey('nv-scan-camera'));
    await tester.scrollUntilVisible(reglage, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(reglage);
    await tester.pumpAndSettle();
    expect(find.text('Code administrateur'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, codeAdminFictif);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(app.config.scanCamera, isTrue);
    await revenirAccueil(tester);

    await choisirInventaire(tester, 'INV1');
    await toucherCle(tester, 'nv-scan-continu');
    await tester.pumpAndSettle();
    expect(boutonCamera(), findsOneWidget);
    await tester.tap(boutonCamera());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('camera-continuer')));
    await tester.pumpAndSettle();
    expect(acces.demandes, 1, reason: 'autorisation demandée au premier usage');
    expect(apercuOuvert(), isTrue);

    await lireCamera(tester, '3400930000001');
    await taperNv(tester, '24');
    await tester.pumpAndSettle();
    horloge.avancer(const Duration(seconds: 2));
    await lireCamera(tester, '3400937000003');
    await taperNv(tester, '5');
    await tester.pumpAndSettle();
    expect(apercuOuvert(), isTrue, reason: 'l\'aperçu enchaîne les lectures');
    await tester.tap(find.byKey(const ValueKey('camera-fermer')));
    await tester.pumpAndSettle();
    expect(app.saisies.ligne('INV1', 1)!.quantite, 24);
    expect(app.saisies.ligne('INV1', 4)!.quantite, 5);

    await tester.tap(find.byKey(const ValueKey('nv-envoyer-scan')));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(app.serveur.catalogue.produit(1).saisi, 24);
    expect(app.serveur.catalogue.produit(4).saisi, 5);
    expect(app.saisies.enAttente(), 0);
    await fermerApplication(tester);
  });

  testWidgets('nouvelle interface : saisie guidée → appareil photo → produit lu ouvert, aperçu fermé', (tester) async {
    tailleEcran(tester, telephone360);
    installerCameraSimulee();
    final app = await lancerApplication(tester, prefs: prefsCamera);
    await seConnecter(tester);
    await choisirInventaire(tester, 'INV1');
    await toucherCle(tester, 'nv-saisie-guidee');
    await tester.pumpAndSettle();
    await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
    await tester.pumpAndSettle();
    expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
    await ouvrirCamera(tester);
    await lireCamera(tester, '3400936311000'); // AUGMENTIN (S2B2)
    expect(apercuOuvert(), isFalse);
    expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget);
    await taperNv(tester, '3');
    await tester.pumpAndSettle();
    expect(app.saisies.ligne('INV1', 6)!.quantite, 3);
    await fermerApplication(tester);
  });

  testWidgets('ancienne interface : Configuration (code administrateur) → saisie rapide à l\'appareil photo → envoi direct', (tester) async {
    ecranTerminal(tester);
    installerCameraSimulee();
    final app = await lancerApplication(tester, nouvelleInterface: false, mode: SendMode.direct);
    await seConnecter(tester);
    await tester.tap(find.byTooltip('Configuration'));
    await tester.pumpAndSettle();
    final reglage = find.byKey(const ValueKey('reglage-scan-camera'));
    await tester.scrollUntilVisible(reglage, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(reglage);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, codeAdminFictif);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(app.config.scanCamera, isTrue);
    await revenirAccueil(tester);

    await tester.tap(find.text('SAISIE RAPIDE\n(Mode Scan)'));
    await tester.pumpAndSettle();
    expect(find.byType(InventoryListScreen), findsOneWidget);
    await tester.tap(find.text('Inventaire annuel 2026'));
    await tester.pumpAndSettle();
    await ouvrirCamera(tester);
    await lireCamera(tester, '3400937000003');
    expect(find.text('SPASFON LYOC 80 MG'), findsWidgets);
    await taperQuantite(tester, '5');
    await tester.pumpAndSettle();
    expect(app.serveur.catalogue.produit(4).saisi, 5);
    expect(app.saisies.ligne('INV1', 4)!.envoyee, isTrue);
    expect(apercuOuvert(), isTrue);
    await tester.tap(find.byKey(const ValueKey('camera-fermer')));
    await tester.pumpAndSettle();
    await fermerApplication(tester);
  });
}
