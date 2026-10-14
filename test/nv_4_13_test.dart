// Nouvelle interface 4.13 — écrans (widgets) : correctifs et nouveautés de la maquette validée.
//  - mini-clavier du champ de scan : le clavier du téléphone s'ouvre (guidée, scan continu, collecte,
//    écarts, restants) ;
//  - récapitulatif du rayon : Tous / Déjà comptés / Pas comptés, toucher une ligne → retour au produit ;
//  - « Masquer la quantité déjà comptée » : saisie et écarts ; stock théorique masqué : récapitulatif,
//    analyse ;
//  - inventaire choisi : Écarts grisé « Pas encore d'écart », Restant à faire grisé « Super ! tout a
//    été saisi » ;
//  - analyse « Tous les emplacements » : progression annulable, toucher une ligne → aperçu sans requête ;
//  - taille de l'écran : interface réduite, touchers et clavier justes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/widgets/pin_admin.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/ecrans/analyse_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/recap_screen.dart';
import 'package:prestinv/ui/ecrans/restants_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/taille_ecran.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

final _inv = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

Future<Banc> banc({Map<String, Object> prefs = const {}}) async {
  final b = await preparerBanc(serveur: serveurRealiste(), prefsEnPlus: prefs);
  b.auth.connecterPourTest(login: 'Awa K.');
  return b;
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
    AvancementCalcul.viderCache();
  });

  group('Mini-clavier du champ de scan : le clavier du téléphone s\'ouvre (le champ avait déjà le focus)', () {
    final ecrans = <String, Widget Function()>{
      'saisie guidée': () => NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S2B2'),
      'scan continu': () => NvScanContinuScreen(inventaire: _inv),
      'collecte': () => const NvCollecteScreen(),
      'écarts': () => NvEcartsScreen(inventaire: _inv),
      'restants': () => NvRestantsScreen(inventaire: _inv),
    };
    for (final e in ecrans.entries) {
      testWidgets(e.key, (tester) async {
        tailleEcran(tester, telephone360);
        final b = await banc();
        await tester.pumpWidget(monterNv(b, e.value()));
        await tester.pumpAndSettle();
        expect(champScanAFocus(tester), isTrue, reason: 'douchette prête (focus déjà pris)');
        tester.testTextInput.log.clear();
        await tester.tap(find.byTooltip('Clavier (chercher par nom)').first);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.log.map((c) => c.method), contains('TextInput.show'), reason: 'affichage du clavier demandé au système');
        final config = tester.testTextInput.log.lastWhere((c) => c.method == 'TextInput.setClient', orElse: () => const MethodCall('aucun'));
        if (config.arguments != null) {
          expect('${(config.arguments as List)[1]}', isNot(contains('TextInputType.none')));
        }
        expect(find.byTooltip('Masquer le clavier (scan)'), findsOneWidget);
        await demonter(tester);
      });
    }
  });

  group('Récapitulatif du rayon', () {
    testWidgets('Tous / Déjà comptés / Pas comptés (compteurs) ; saisie du téléphone comptée ; toucher → produit renvoyé', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      // CANNES : 5 produits, VOLTARENE et SMECTA comptés sur le serveur ; BÉTADINE saisi sur le téléphone.
      await b.queue.enregistrer(inventaireId: 'INV1', ligneId: 5, quantite: 30);
      Product? choisi;
      await tester.pumpWidget(monterNv(
          b,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async => choisi = await Navigator.of(context)
                      .push<Product>(MaterialPageRoute(builder: (_) => const NvRecapScreen(inventoryId: 'INV1', rayonId: 'S1A0T2', rayonName: 'CANNES', retourSaisie: true))),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          )));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Tous (5)'), findsOneWidget);
      expect(find.text('Déjà comptés (3)'), findsOneWidget);
      expect(find.text('Pas comptés (2)'), findsOneWidget);
      expect(find.text('Récapitulatif du rayon'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-recap-pas-comptes')));
      await tester.pumpAndSettle();
      expect(find.text('BILAN BIOLOGIQUE TOTAL'), findsOneWidget);
      expect(find.text('BÉTADINE DERMIQUE 10 %'), findsNothing, reason: 'saisi sur le téléphone : compté');
      await tester.tap(find.byKey(const ValueKey('nv-recap-comptes')));
      await tester.pumpAndSettle();
      expect(find.text('BÉTADINE DERMIQUE 10 %'), findsOneWidget);
      await tester.tap(find.text('VOLTARENE EMULGEL 1 %'));
      await tester.pumpAndSettle();
      expect(choisi?.id, 8, reason: 'retour à la saisie sur ce produit');
      await demonter(tester);
    });

    testWidgets('stock théorique masqué (réglage) : *** à l\'écran', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc(prefs: {'showTheoreticalStock': false});
      await tester.pumpWidget(monterNv(b, const NvRecapScreen(inventoryId: 'INV1', rayonId: 'S1A0T2', rayonName: 'CANNES')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Théo ***'), findsWidgets);
      expect(find.textContaining('Théo 30'), findsNothing);
      await demonter(tester);
    });
  });

  group('Masquer la quantité déjà comptée (réglage protégé, désactivé par défaut)', () {
    testWidgets('saisie guidée : « Déjà compté » masqué', (tester) async {
      tailleEcran(tester, telephone360);
      for (final masque in [false, true]) {
        final b = await banc(prefs: {'masquerDejaCompte': masque});
        expect(b.config.masquerDejaCompte, masque);
        await tester.pumpWidget(monterNv(b, NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S2B2')));
        await tester.pumpAndSettle();
        // Premier produit du rayon : AMOXICILLINE, déjà compté 6.
        expect(find.descendant(of: find.byKey(const ValueKey('nv-deja-compte')), matching: find.text(masque ? '•••' : '6')), findsOneWidget,
            reason: 'masqué : $masque');
        await demonter(tester);
      }
    });

    testWidgets('écarts : quantité comptée masquée, correction non pré-remplie', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc(prefs: {'masquerDejaCompte': true});
      await tester.pumpWidget(monterNv(b, NvEcartsScreen(inventaire: _inv)));
      await tester.pumpAndSettle();
      expect(find.textContaining('compté •••'), findsWidgets);
      expect(find.textContaining('compté 4'), findsNothing, reason: 'INSULINE comptée 4 : masqué');
      await tester.tap(find.textContaining('INSULINE LANTUS SOLOSTAR').first);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('nv-quantite')).last).data!.trim(), isEmpty, reason: 'pas de quantité pré-remplie');
      expect(find.text('Garder'), findsOneWidget);
      await demonter(tester);
    });
  });

  group('Inventaire choisi : tuiles Écarts / Restant à faire', () {
    testWidgets('aucun écart → « Pas encore d\'écart » (grisé) ; tout compté → « Super ! tout a été saisi » (grisé)', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      for (final p in b.serveur.produits) {
        p
          ..dtUpdated = '2026-10-13T10:00:00'
          ..saisi = p.theorique;
      }
      await tester.pumpWidget(monterNv(b, NvInventaireScreen(inventaire: _inv)));
      await tester.pumpAndSettle();
      expect(find.text('Voir les écarts'), findsOneWidget, reason: 'pas encore calculé');
      await tester.tap(find.byKey(const ValueKey('nv-actualiser-avancement')));
      await tester.pumpAndSettle();
      expect(find.text('Pas encore d\'écart'), findsOneWidget);
      expect(find.text('Super ! tout a été saisi'), findsOneWidget);
      expect(find.text('100 %'), findsOneWidget);
      expect(find.text('12 / 12'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-tuile-ecarts')));
      await tester.pumpAndSettle();
      expect(find.byType(NvEcartsScreen), findsNothing, reason: 'grisé : rien à ouvrir');
      await demonter(tester);
    });

    testWidgets('écarts et restants connus : compteurs affichés', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      await tester.pumpWidget(monterNv(b, NvInventaireScreen(inventaire: _inv)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nv-actualiser-avancement')));
      await tester.pumpAndSettle();
      // serveurRealiste : 7 produits comptés, tous en écart ; 5 restants.
      expect(find.text('7 produit(s) en écart'), findsOneWidget);
      expect(find.text('5 produit(s)'), findsOneWidget);
      await demonter(tester);
    });
  });

  group('Analyse', () {
    testWidgets('tous les emplacements : progression annulable, totaux, toucher une ligne → aperçu sans nouvelle requête', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc();
      b.serveur.delais['details'] = const Duration(milliseconds: 500);
      await tester.pumpWidget(monterNv(b, NvAnalyseScreen(inventaireInitial: _inv)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tous les emplacements'), findsWidgets, reason: 'proposé d\'office');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('nv-analyse-progression')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-analyse-annuler')));
      await tester.pump();
      expect(find.byKey(const ValueKey('nv-analyse-progression')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Terminer le calcul'), findsOneWidget, reason: 'les emplacements déjà lus restent ; reprise possible');
      await tester.tap(find.text('Terminer le calcul'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-analyse-ligne-S2B2')), findsOneWidget);
      // ANTIBIOTIQUES : 4 en écart (AMOX −4×1450, SPASFON 0, AUGMENTIN −8×7700, DAFALGAN −4×2460).
      expect(find.textContaining('produit(s) en écart'), findsWidgets);
      final avant = b.serveur.appels.where((a) => a == 'GET details').length;
      await tester.tap(find.byKey(const ValueKey('nv-analyse-ligne-S2B2')));
      await tester.pumpAndSettle();
      expect(find.text('Répartition des articles'.toUpperCase()), findsOneWidget, reason: 'aperçu actuel de l\'emplacement');
      expect(b.serveur.appels.where((a) => a == 'GET details').length, avant, reason: 'produits déjà lus : aucune requête');
      await tester.tap(find.byKey(const ValueKey('nv-analyse-retour-tous')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-analyse-ligne-S3')), findsOneWidget);
      await demonter(tester);
    });

    testWidgets('stock théorique masqué : « Valeur avant » masquée dans l\'aperçu', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await banc(prefs: {'showTheoreticalStock': false});
      await tester.pumpWidget(monterNv(b, NvAnalyseScreen(inventaireInitial: _inv)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nv-analyse-ligne-S3')));
      await tester.pumpAndSettle();
      expect(find.text('•••'), findsOneWidget);
      await demonter(tester);
    });
  });

  group('Taille de l\'écran (EchelleInterface)', () {
    for (final t in TailleEcran.values) {
      testWidgets('${t.libelle} : surface agrandie de 1/${t.facteur}, touchers justes, clavier ramené à l\'échelle', (tester) async {
        tailleEcran(tester, sunmiV2s);
        tester.view.viewInsets = const FakeViewPadding(bottom: 600); // 300 dp de clavier
        addTearDown(tester.view.resetViewInsets);
        var touches = 0;
        late MediaQueryData vu;
        await tester.pumpWidget(EchelleInterface(
          facteur: t.facteur,
          child: MaterialApp(
            home: Builder(builder: (context) {
              vu = MediaQuery.of(context);
              return Scaffold(
                body: Align(
                  alignment: Alignment.bottomRight,
                  child: ElevatedButton(key: const ValueKey('b'), onPressed: () => touches++, child: const Text('Toucher')),
                ),
              );
            }),
          ),
        ));
        expect(vu.size.width, closeTo(360 / t.facteur, 0.01));
        expect(vu.viewInsets.bottom, closeTo(300 / t.facteur, 0.01));
        final r = tester.getRect(find.byKey(const ValueKey('b')));
        expect(r.bottom, closeTo(640 - 300, 0.6), reason: 'posé juste au-dessus du clavier, sur l\'écran réel');
        await tester.tap(find.byKey(const ValueKey('b')));
        expect(touches, 1);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    testWidgets('réglage enregistré puis appliqué à la racine (RacineTailleEcran)', (tester) async {
      SharedPreferences.setMockInitialValues({TailleEcranReglage.cle: 'compact'});
      await TailleEcranReglage.charger();
      addTearDown(TailleEcranReglage.reinitialiser);
      tailleEcran(tester, sunmiV2s);
      late Size taille;
      await tester.pumpWidget(RacineTailleEcran(child: MaterialApp(home: Builder(builder: (c) {
        taille = MediaQuery.sizeOf(c);
        return const SizedBox();
      }))));
      expect(taille.width, closeTo(400, 0.01));
      TailleEcranReglage.enregistree = TailleEcran.automatique;
      TailleEcranReglage.appliquerMaintenant();
      await tester.pump();
      expect(taille.width, 360);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  group('Fenêtres partagées : nouveau style seulement avec la nouvelle interface', () {
    for (final nouvelle in [true, false]) {
      testWidgets('code administrateur et reconnexion — ${nouvelle ? 'nouvelle' : 'ancienne'} interface', (tester) async {
        tailleEcran(tester, telephone360);
        InterfaceVersion.useNew.value = nouvelle;
        addTearDown(() => InterfaceVersion.useNew.value = false);
        final b = await banc();
        await tester.pumpWidget(monter(
            b,
            Builder(
              builder: (context) => Scaffold(
                body: Column(children: [
                  ElevatedButton(onPressed: () => demanderPinAdmin(context), child: const Text('pin')),
                  ElevatedButton(onPressed: () => demanderReconnexion(context), child: const Text('reco')),
                ]),
              ),
            )));
        await tester.tap(find.text('pin'));
        await tester.pumpAndSettle();
        expect(find.text('Code administrateur'), findsOneWidget);
        expect(find.byType(NvCadreDialogue), nouvelle ? findsOneWidget : findsNothing);
        expect(find.byType(AlertDialog), nouvelle ? findsNothing : findsOneWidget, reason: 'ancienne interface : fenêtre d\'origine inchangée');
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('reco'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Reconnectez-vous pour continuer'), findsOneWidget);
        expect(find.byType(NvCadreDialogue), nouvelle ? findsOneWidget : findsNothing);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        await demonter(tester);
      });
    }
  });

  test('réglages protégés : enregistrés (masquer, création autres comptes)', () async {
    SharedPreferences.setMockInitialValues({});
    final c = AppConfig();
    await c.load();
    expect((c.masquerDejaCompte, c.creationAutresComptes), (false, false), reason: 'désactivés par défaut');
    await c.setReglagesProteges(masquerDejaCompte: true, creationAutresComptes: true);
    final relu = AppConfig();
    await relu.load();
    expect((relu.masquerDejaCompte, relu.creationAutresComptes), (true, true));
  });
}
