// 4.14 — SCAN PAR L'APPAREIL PHOTO (téléphones sans douchette), réglage protégé désactivé par défaut.
// Appareil photo SIMULÉ (helpers/camera_essai.dart) : aucun module natif.
//  - réglage désactivé (défaut) : aucun bouton, nulle part (deux interfaces) ;
//  - réglage actif sans appareil photo : aucun bouton ;
//  - réglage actif : bouton à côté du champ de scan ; un code lu par l'appareil photo donne EXACTEMENT
//    le même résultat qu'une lecture de la douchette (saisies, messages, bips) en saisie guidée (aperçu
//    fermé après la lecture), scan continu et collecte (aperçu gardé ouvert, anti-doublon ~1,5 s) ;
//  - autorisation : explication au premier usage, refus → message clair, rien n'est bloqué ; refus
//    définitif → paramètres d'Android ;
//  - ancienne interface : saisie guidée, saisie rapide et collecte d'origine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/scan/camera/scan_camera.dart';
import 'package:prestinv/screens/collection_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/camera_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

final _inv = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

enum Lecteur { douchette, camera }

Future<Banc> _monterNv(WidgetTester tester, Widget ecran, {bool camera = true, Map<String, Object> prefs = const {}}) async {
  tailleEcran(tester, telephone360);
  final b = await preparerBanc(serveur: serveurRealiste(), prefsEnPlus: {if (camera) ...prefsCamera, ...prefs});
  await tester.pumpWidget(monterNv(b, ecran));
  await tester.pumpAndSettle();
  return b;
}

Future<Banc> _monterOrigine(WidgetTester tester, Widget ecran, {bool camera = true}) async {
  ecranTerminal(tester);
  final b = await preparerBanc(mode: SendMode.collect, prefsEnPlus: {if (camera) ...prefsCamera});
  await tester.pumpWidget(monter(b, ecran));
  await tester.pumpAndSettle();
  return b;
}

Future<void> _ouvrirRayonOrigine(WidgetTester tester, String libelle) async {
  await tester.tap(find.text('Sélectionner un emplacement'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(libelle));
  await tester.pumpAndSettle();
}

/// Lit [code] avec la douchette ou avec l'appareil photo (ouvert au besoin).
Future<void> _lire(WidgetTester tester, Lecteur l, String code) async {
  if (l == Lecteur.douchette) {
    await douchette(tester, code);
    await tester.pumpAndSettle();
    return;
  }
  if (!apercuOuvert()) await ouvrirCamera(tester);
  await lireCamera(tester, code);
}

Future<void> _fermerCamera(WidgetTester tester) async {
  if (!apercuOuvert()) return;
  await tester.tap(find.byKey(const ValueKey('camera-fermer')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  group('Réglage désactivé (défaut) : aucun bouton appareil photo', () {
    testWidgets('nouvelle interface : saisie guidée, scan continu, collecte', (tester) async {
      installerCameraSimulee();
      final b = await _monterNv(tester, NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S2B2'), camera: false);
      expect(b.config.scanCamera, isFalse, reason: 'désactivé par défaut');
      expect(find.byKey(const ValueKey('champ-scan')), findsOneWidget);
      expect(boutonCamera(), findsNothing);
      await demonter(tester);
      await _monterNv(tester, NvScanContinuScreen(inventaire: _inv), camera: false);
      expect(boutonCamera(), findsNothing);
      await demonter(tester);
      await _monterNv(tester, const NvCollecteScreen(), camera: false);
      expect(boutonCamera(), findsNothing);
      await demonter(tester);
    });

    testWidgets('ancienne interface : saisie guidée, saisie rapide, collecte', (tester) async {
      installerCameraSimulee();
      await _monterOrigine(tester, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test'), camera: false);
      await _ouvrirRayonOrigine(tester, 'RAYON UN');
      expect(find.byKey(const ValueKey('champ-scan')), findsOneWidget);
      expect(boutonCamera(), findsNothing);
      await demonter(tester);
      await _monterOrigine(tester, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true), camera: false);
      expect(boutonCamera(), findsNothing);
      await demonter(tester);
      await _monterOrigine(tester, const CollectionScreen(), camera: false);
      expect(boutonCamera(), findsNothing);
      await demonter(tester);
    });

    testWidgets('réglage actif mais téléphone sans appareil photo : bouton masqué', (tester) async {
      installerCameraSimulee(presente: false);
      await _monterNv(tester, NvScanContinuScreen(inventaire: _inv));
      expect(boutonCamera(), findsNothing);
      await demonter(tester);
    });
  });

  group('Réglage actif : même résultat que la douchette', () {
    for (final l in Lecteur.values) {
      testWidgets('saisie guidée (${l.name}) : produit du rayon → feuille ; autre rayon → message', (tester) async {
        installerCameraSimulee();
        final b = await _monterNv(tester, NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S2B2'));
        final retour = installerFauxRetour();
        expect(boutonCamera(), findsOneWidget);
        await _lire(tester, l, '3400936311000'); // AUGMENTIN (S2B2)
        expect(apercuOuvert(), isFalse, reason: 'saisie guidée : l\'aperçu se ferme après une lecture');
        expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget);
        await taperNv(tester, '3');
        await tester.pumpAndSettle();
        expect(b.disque.saisies.single.ligneId, 6);
        expect(b.disque.saisies.single.quantite, 3);

        await _lire(tester, l, '3400930000001'); // DOLIPRANE (S3)
        expect(find.textContaining('introuvable dans cet emplacement'), findsOneWidget);
        expect(retour.bips, ['dejaCompte', 'erreur'], reason: 'mêmes bips que la douchette (AUGMENTIN déjà compté)');
        expect(retour.vibrations, ['dejaCompte', 'erreur']);
        expect(champScanAFocus(tester), isTrue, reason: 'champ de scan prêt pour la douchette');
        await demonter(tester);
      });

      testWidgets('scan continu (${l.name}) : saisie, déjà compté, code inconnu', (tester) async {
        final horloge = HorlogeEssai();
        installerCameraSimulee(horloge: horloge);
        final b = await _monterNv(tester, NvScanContinuScreen(inventaire: _inv));
        final retour = installerFauxRetour();
        await _lire(tester, l, '3400930000001');
        expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget);
        await taperNv(tester, '24');
        await tester.pumpAndSettle();
        final s = b.disque.saisies.single;
        expect((s.ligneId, s.quantite, s.origine), (1, 24, OrigineSaisie.rapide));
        if (l == Lecteur.camera) expect(apercuOuvert(), isTrue, reason: 'scan continu : l\'aperçu reste ouvert');

        horloge.avancer(const Duration(seconds: 3));
        await _lire(tester, l, '3401597413'); // inconnu
        horloge.avancer(const Duration(seconds: 3));
        await _lire(tester, l, '3400937000003');
        expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget);
        await taperNv(tester, '5');
        await tester.pumpAndSettle();
        expect({for (final s in b.disque.saisies) s.ligneId: s.quantite}, {1: 24, 4: 5});
        expect(retour.bips, ['succes', 'erreur', 'succes']);
        await _fermerCamera(tester);
        expect(find.text('à vérifier'), findsOneWidget, reason: 'code inconnu noté au journal');
        expect(find.textContaining('introuvable dans cet inventaire'), findsNothing, reason: 'message passé');
        await demonter(tester);
      });

      testWidgets('collecte (${l.name}) : code → quantité → liste locale', (tester) async {
        final horloge = HorlogeEssai();
        installerCameraSimulee(horloge: horloge);
        await _monterNv(tester, const NvCollecteScreen());
        await _lire(tester, l, '3400938000004');
        expect(find.byKey(const ValueKey('nv-collecte-code')), findsOneWidget);
        await taperNv(tester, '30');
        await tester.pumpAndSettle();
        horloge.avancer(const Duration(seconds: 2));
        await _lire(tester, l, '9999999999999');
        await taperNv(tester, '2');
        await tester.pumpAndSettle();
        if (l == Lecteur.camera) expect(apercuOuvert(), isTrue, reason: 'collecte : l\'aperçu reste ouvert');
        expect((await CollecteStore.lire()).map((i) => (i.code, i.quantity)), [('9999999999999', 2), ('3400938000004', 30)]);
        await _fermerCamera(tester);
        await demonter(tester);
      });
    }

    testWidgets('anti-doublon : le même code relu aussitôt est ignoré, relu après 1,5 s il est pris', (tester) async {
      final horloge = HorlogeEssai();
      installerCameraSimulee(horloge: horloge);
      final b = await _monterNv(tester, NvScanContinuScreen(inventaire: _inv));
      await ouvrirCamera(tester);
      await lireCamera(tester, '3400930000001');
      await taperNv(tester, '2');
      await tester.pumpAndSettle();
      // La boîte est restée devant l'objectif : relue aussitôt, puis encore 1 s plus tard → ignorée.
      await lireCamera(tester, '3400930000001');
      horloge.avancer(const Duration(seconds: 1));
      await lireCamera(tester, '3400930000001');
      expect(find.byKey(const ValueKey('nv-feuille-produit')), findsNothing);
      // Un autre code passe tout de suite.
      await lireCamera(tester, '3400937000003');
      expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget);
      await taperNv(tester, '1');
      await tester.pumpAndSettle();
      // Le premier code, revu après plus de 1,5 s : pris.
      horloge.avancer(const Duration(seconds: 2));
      await lireCamera(tester, '3400930000001');
      expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-feuille-annuler')));
      await tester.pumpAndSettle();
      expect(b.disque.saisies, hasLength(2));
      expect(find.byKey(const ValueKey('camera-dernier')), findsOneWidget);
      await _fermerCamera(tester);
      await demonter(tester);
    });

    testWidgets('lecture pendant que la feuille de quantité couvre l\'aperçu : ignorée', (tester) async {
      final horloge = HorlogeEssai();
      installerCameraSimulee(horloge: horloge);
      final b = await _monterNv(tester, NvScanContinuScreen(inventaire: _inv));
      await ouvrirCamera(tester);
      await lireCamera(tester, '3400930000001');
      horloge.avancer(const Duration(seconds: 5));
      await lireCamera(tester, '3400937000003'); // feuille ouverte au-dessus : ignoré
      await taperNv(tester, '4');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-feuille-produit')), findsNothing, reason: 'aucun scan en file');
      expect(b.disque.saisies.single.ligneId, 1);
      await _fermerCamera(tester);
      await demonter(tester);
    });

    testWidgets('aperçu : lampe (allumer / éteindre) et Fermer, cibles ≥ 48 dp avec libellé', (tester) async {
      installerCameraSimulee();
      await _monterNv(tester, NvScanContinuScreen(inventaire: _inv));
      final h = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      expect(find.bySemanticsLabel('Scanner avec l\'appareil photo'), findsOneWidget);
      await ouvrirCamera(tester);
      expect(find.byKey(const ValueKey('camera-cadre')), findsOneWidget, reason: 'cadre de visée');
      expect(find.bySemanticsLabel('Allumer la lampe'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('camera-lampe')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Éteindre la lampe'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      expect(find.bySemanticsLabel('Fermer l\'appareil photo'), findsOneWidget);
      final moteur = MoteurCameraSimule.actif!;
      await _fermerCamera(tester);
      expect(apercuOuvert(), isFalse);
      expect(moteur.libere, isTrue, reason: 'appareil photo libéré à la fermeture');
      expect(champScanAFocus(tester), isTrue, reason: 'douchette prête au retour');
      h.dispose();
      await demonter(tester);
    });
  });

  group('Autorisation Caméra', () {
    testWidgets('premier usage : explication, refus → message clair, rien n\'est bloqué (douchette, pavé)', (tester) async {
      final acces = installerCameraSimulee(etat: AutorisationCamera.aDemander, reponse: AutorisationCamera.aDemander);
      final b = await _monterNv(tester, NvScanContinuScreen(inventaire: _inv));
      await tester.tap(boutonCamera());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-explication')), findsOneWidget);
      expect(acces.demandes, 0, reason: 'explication AVANT la demande d\'Android');
      await tester.tap(find.byKey(const ValueKey('camera-continuer')));
      await tester.pumpAndSettle();
      expect(acces.demandes, 1);
      expect(find.text(ScanCamera.messageRefus), findsOneWidget);
      expect(apercuOuvert(), isFalse);
      // Rien n'est bloqué : la douchette fonctionne.
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      await taperNv(tester, '7');
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 7);
      await demonter(tester);
    });

    testWidgets('« Plus tard » : aucune demande ; accord ensuite → aperçu ouvert', (tester) async {
      final acces = installerCameraSimulee(etat: AutorisationCamera.aDemander, reponse: AutorisationCamera.accordee);
      await _monterNv(tester, NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S2B2'));
      await tester.tap(boutonCamera());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('camera-plus-tard')));
      await tester.pumpAndSettle();
      expect(acces.demandes, 0);
      expect(apercuOuvert(), isFalse);
      await tester.tap(boutonCamera());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('camera-continuer')));
      await tester.pumpAndSettle();
      expect(apercuOuvert(), isTrue);
      // Autorisation accordée : plus d'explication la fois suivante.
      await _fermerCamera(tester);
      await tester.tap(boutonCamera());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-explication')), findsNothing);
      expect(apercuOuvert(), isTrue);
      await _fermerCamera(tester);
      await demonter(tester);
    });

    testWidgets('refus définitif : message et accès aux paramètres d\'Android', (tester) async {
      final acces = installerCameraSimulee(etat: AutorisationCamera.refuseeDefinitivement);
      await _monterNv(tester, const NvCollecteScreen());
      await tester.tap(boutonCamera());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-refusee-definitivement')), findsOneWidget);
      await tester.tap(find.text('Ouvrir les paramètres'));
      await tester.pumpAndSettle();
      expect(acces.parametresOuverts, 1);
      expect(acces.demandes, 0);
      expect(apercuOuvert(), isFalse);
      await demonter(tester);
    });

    testWidgets('appareil photo qui ne démarre pas : message dans l\'aperçu, Fermer ramène à l\'écran', (tester) async {
      installerCameraSimulee();
      await _monterNv(tester, NvScanContinuScreen(inventaire: _inv));
      await ouvrirCamera(tester);
      MoteurCameraSimule.actif!.erreur('L\'appareil photo ne démarre pas.');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-erreur')), findsOneWidget);
      await _fermerCamera(tester);
      expect(find.byType(NvScanContinuScreen), findsOneWidget);
      await demonter(tester);
    });
  });

  group('Réglages (code administrateur)', () {
    testWidgets('nouvelle interface : réglage protégé, code refusé → inchangé ; accepté → activé', (tester) async {
      var codeOk = false;
      tailleEcran(tester, telephone360);
      final b = await preparerBanc(serveur: serveurRealiste());
      await tester.pumpWidget(monterNv(b, NvConfigScreen(verifierPin: (_) async => codeOk)));
      await tester.pumpAndSettle();
      final reglage = find.byKey(const ValueKey('nv-scan-camera'));
      await tester.scrollUntilVisible(reglage, 300, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<SwitchListTile>(reglage).value, isFalse, reason: 'désactivé par défaut');
      await tester.tap(reglage);
      await tester.pumpAndSettle();
      expect(b.config.scanCamera, isFalse, reason: 'sans le code administrateur');
      codeOk = true;
      await tester.tap(reglage);
      await tester.pumpAndSettle();
      expect(b.config.scanCamera, isTrue);
      expect(tester.widget<SwitchListTile>(reglage).value, isTrue);
      await demonter(tester);
    });
  });

  group('Ancienne interface (réglage actif)', () {
    for (final l in Lecteur.values) {
      testWidgets('saisie guidée d\'origine (${l.name}) : produit du rayon → fenêtre « Saisie Rapide »', (tester) async {
        installerCameraSimulee();
        final b = await _monterOrigine(tester, const InventoryEntryScreen(inventoryId: 'INV1', inventoryName: 'Inventaire test'));
        await _ouvrirRayonOrigine(tester, 'RAYON UN');
        expect(boutonCamera(), findsOneWidget);
        final p = b.serveur.produits.firstWhere((p) => p.rayon == 'R1');
        await _lire(tester, l, p.cip);
        expect(apercuOuvert(), isFalse);
        expect(find.text('Saisie Rapide'), findsOneWidget);
        await taperQuantite(tester, '3');
        await tester.pumpAndSettle();
        expect(b.disque.saisies.single.ligneId, p.id);
        expect(b.disque.saisies.single.quantite, 3);
        await demonter(tester);
      });

      testWidgets('saisie rapide d\'origine (${l.name}) : deux codes à la suite', (tester) async {
        final horloge = HorlogeEssai();
        installerCameraSimulee(horloge: horloge);
        final b = await _monterOrigine(tester, const InventoryEntryScreen(inventoryId: 'INV1', isQuickMode: true));
        for (final (i, p) in b.serveur.produits.take(2).indexed) {
          horloge.avancer(const Duration(seconds: 2));
          await _lire(tester, l, p.cip);
          expect(find.text('Saisie Rapide'), findsOneWidget);
          await taperQuantite(tester, '${i + 4}');
          await tester.pumpAndSettle();
        }
        if (l == Lecteur.camera) expect(apercuOuvert(), isTrue);
        expect({for (final s in b.disque.saisies) s.ligneId: s.quantite}, {b.serveur.produits[0].id: 4, b.serveur.produits[1].id: 5});
        await _fermerCamera(tester);
        await demonter(tester);
      });

      testWidgets('collecte d\'origine (${l.name}) : code → « Ajout Collecte » → liste', (tester) async {
        installerCameraSimulee();
        await _monterOrigine(tester, const CollectionScreen());
        if (l == Lecteur.douchette) {
          // Collecte d'origine : la douchette tape dans le champ de scan (validation = Entrée).
          await tester.enterText(find.byType(TextField).first, '3400938000004');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
        } else {
          await _lire(tester, l, '3400938000004');
        }
        expect(find.text('Ajout Collecte'), findsOneWidget);
        expect(find.text('Code : 3400938000004'), findsOneWidget);
        await taperQuantite(tester, '6');
        await tester.pumpAndSettle();
        expect((await CollecteStore.lire()).map((i) => (i.code, i.quantity)), [('3400938000004', 6)]);
        await _fermerCamera(tester);
        await demonter(tester);
      });
    }
  });
}
