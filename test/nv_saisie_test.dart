// Nouvelle interface — saisie guidée (maquette A) et scan continu (maquette B) : même logique que
// l'écran d'origine (file des saisies AVANT envoi, cumul sûr, Remplacer / Ajouter explicite, seuils),
// douchette toujours prête (focus du champ de scan après OK, après la feuille, après une erreur ;
// rafale sans perte ; chiffres + Entrée de la douchette), journal avec l'état d'envoi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/nouvelle_interface.dart';

final _inv = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

String qte(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('nv-quantite')).last).data!.trim();

Future<Banc> scanContinu(WidgetTester tester, {SendMode mode = SendMode.collect, bool cumul = false, Map<String, Object> prefs = const {}}) async {
  tailleEcran(tester, telephone360);
  final b = await preparerBanc(serveur: serveurRealiste(), mode: mode, cumul: cumul, prefsEnPlus: prefs);
  await tester.pumpWidget(monterNv(b, NvScanContinuScreen(inventaire: _inv)));
  await tester.pumpAndSettle();
  return b;
}

Future<Banc> guidee(WidgetTester tester, {String rayon = 'S2B2', SendMode mode = SendMode.collect, bool cumul = false}) async {
  tailleEcran(tester, telephone360);
  final b = await preparerBanc(serveur: serveurRealiste(), mode: mode, cumul: cumul);
  await tester.pumpWidget(monterNv(b, NvSaisieGuideeScreen(inventaire: _inv, rayonId: rayon)));
  await tester.pumpAndSettle();
  return b;
}

String produitCourant(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('nv-produit-courant'))).data!;

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  group('Scan continu (maquette B)', () {
    testWidgets('focus du champ de scan à l\'ouverture, après OK, après Annuler, après une erreur réseau', (tester) async {
      final b = await scanContinu(tester);
      expect(champScanAFocus(tester), isTrue, reason: 'à l\'ouverture');

      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      expect(find.text('DOLIPRANE 1000 MG CPR B/8'), findsWidgets);
      expect(qte(tester), '1', reason: 'quantité proposée 1 (réglage par défaut)');
      await taperNv(tester, '24');
      await tester.pumpAndSettle();
      final s = b.disque.saisies.single;
      expect((s.ligneId, s.quantite, s.origine), (1, 24, OrigineSaisie.rapide));
      expect(champScanAFocus(tester), isTrue, reason: 'après OK');

      await douchette(tester, '3400937000003');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nv-feuille-annuler')));
      await tester.pumpAndSettle();
      expect(champScanAFocus(tester), isTrue, reason: 'après Annuler');
      expect(b.disque.saisies, hasLength(1));

      b.serveur.injoignable = true;
      await douchette(tester, '3400938000004');
      await tester.pumpAndSettle();
      expect(find.textContaining('Serveur injoignable'), findsWidgets);
      expect(champScanAFocus(tester), isTrue, reason: 'après une erreur réseau');
      expect(find.textContaining('toucher pour relancer'), findsOneWidget);
      b.serveur.injoignable = false;
      await tester.tap(find.textContaining('toucher pour relancer'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget, reason: 'relance de la recherche');
      await tester.tap(find.byKey(const ValueKey('nv-feuille-annuler')));
      await tester.pumpAndSettle();
      await demonter(tester);
    });

    testWidgets('rafale de la douchette : chiffres + Entrée dans la feuille, aucun scan perdu', (tester) async {
      final b = await scanContinu(tester, prefs: {'scanQuantiteDefaut': -1});
      // Trois codes d'affilée : ils attendent leur tour pendant que la feuille est ouverte.
      await douchette(tester, '3400930000001');
      await douchette(tester, '3400937000003');
      await douchette(tester, '3400938000004');
      await tester.pumpAndSettle();
      for (final q in ['5', '6', '7']) {
        expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget);
        await douchette(tester, q); // pavé physique / douchette : chiffres puis Entrée = OK
        await tester.pumpAndSettle();
      }
      expect({for (final s in b.disque.saisies) s.ligneId: s.quantite}, {1: 5, 4: 6, 5: 7});
      expect(champScanAFocus(tester), isTrue);
      await demonter(tester);
    });

    testWidgets('touche latérale de scan Sunmi : le champ de scan reprend le focus', (tester) async {
      await scanContinu(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(champScanAFocus(tester), isFalse);
      expect(await toucheSunmi(tester, 521), isTrue);
      await tester.pump();
      expect(champScanAFocus(tester), isTrue);
      await demonter(tester);
    });

    testWidgets('code inconnu : « à vérifier » au journal, bip d\'erreur, focus gardé', (tester) async {
      await scanContinu(tester);
      final retour = installerFauxRetour();
      await douchette(tester, '3401597413');
      await tester.pumpAndSettle();
      expect(find.textContaining('introuvable dans cet inventaire'), findsOneWidget);
      expect(find.text('à vérifier'), findsOneWidget);
      expect(retour.bips, ['erreur']);
      expect(champScanAFocus(tester), isTrue);
      await demonter(tester);
    });

    testWidgets('déjà compté (Cumul) : boutons Ajouter → total, Remplacer → saisie ; cumul noté', (tester) async {
      final b = await scanContinu(tester, cumul: true, prefs: {'scanQuantiteDefaut': -1});
      // AMOXICILLINE déjà comptée 6 par un collègue (serveur).
      await douchette(tester, '3400935959001');
      await tester.pumpAndSettle();
      expect(find.textContaining('Déjà compté : 6'), findsOneWidget);
      await taperNv(tester, '4', ok: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nv-feuille-ajouter')));
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 10);
      expect(b.entry.cumulLogs.single['newQty'], 10);

      // Remplacer (même produit : la saisie en attente, 10, fait foi).
      await douchette(tester, '3400935959001');
      await tester.pumpAndSettle();
      expect(find.textContaining('Déjà compté : 10'), findsOneWidget);
      await taperNv(tester, '3', ok: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nv-feuille-remplacer')));
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 3);
      await demonter(tester);
    });

    testWidgets('déjà compté, OK sans choisir : la question Remplacer / Ajouter est posée ; Annuler n\'enregistre rien', (tester) async {
      final b = await scanContinu(tester, cumul: true, prefs: {'scanQuantiteDefaut': -1});
      await douchette(tester, '3400935959001');
      await tester.pumpAndSettle();
      await taperNv(tester, '4');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-choix-deja-compte')), findsOneWidget);
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(b.disque.saisies, isEmpty, reason: 'jamais d\'écrasement silencieux');
      await taperNv(tester, '', ok: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nv-remplacer')));
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 4);
      await demonter(tester);
    });

    testWidgets('vérification « déjà compté » impossible (réseau) : rien n\'est enregistré', (tester) async {
      final b = await scanContinu(tester, cumul: true);
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      b.serveur.routesInjoignables.add('detailsAllTouched');
      await taperNv(tester, '');
      await tester.pumpAndSettle();
      expect(find.text('Vérification impossible'), findsOneWidget);
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(b.disque.saisies, isEmpty);
      await demonter(tester);
    });

    testWidgets('mode Direct : envoyé tout de suite, journal « envoyé » ; mode Collecte : « en attente » puis Envoyer', (tester) async {
      var b = await scanContinu(tester, mode: SendMode.direct);
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      await taperNv(tester, '');
      await tester.pumpAndSettle();
      expect(b.serveur.puts, [(1, 1)]);
      expect(find.text('envoyé'), findsOneWidget);
      await demonter(tester);

      reinitialiserDouchette();
      b = await scanContinu(tester, mode: SendMode.collect);
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      await taperNv(tester, '');
      await tester.pumpAndSettle();
      expect(b.serveur.puts, isEmpty);
      expect(find.text('en attente'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-envoyer-scan')));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(b.serveur.puts, [(1, 1)]);
      expect(find.text('envoyé'), findsOneWidget);
      await demonter(tester);
    });

    testWidgets('corriger depuis le journal : la nouvelle quantité remplace la précédente', (tester) async {
      final b = await scanContinu(tester, prefs: {'scanQuantiteDefaut': -1});
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      await taperNv(tester, '12');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('journal-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bandeau-correction')), findsOneWidget);
      await taperNv(tester, '5');
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 15 - 10, reason: 'remplacée (5), pas ajoutée');
      expect(champScanAFocus(tester), isTrue);
      await demonter(tester);
    });

    testWidgets('quantité : −1 / +1, bornes, champ vide refusé, seuil « grande quantité »', (tester) async {
      final b = await scanContinu(tester, prefs: {'largeValueThreshold': 50});
      await douchette(tester, '3400930000001');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qte-moins')));
      await tester.tap(find.byKey(const ValueKey('qte-moins')));
      await tester.pump();
      expect(qte(tester), '0', reason: 'jamais négatif');
      await tester.tap(find.byKey(const ValueKey('touche-DEL')));
      await tester.pump();
      await taperNv(tester, '');
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);
      await taperNv(tester, '60');
      await tester.pumpAndSettle();
      expect(find.text('Grande quantité'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-confirmer-grande')));
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 60);
      await demonter(tester);
    });
  });

  group('Saisie guidée (maquette A)', () {
    testWidgets('produit par produit : OK enregistre (file des saisies), passe au suivant, focus au champ de scan', (tester) async {
      final b = await guidee(tester);
      final premier = produitCourant(tester);
      expect(champScanAFocus(tester), isTrue);
      await taperNv(tester, '7');
      await tester.pumpAndSettle();
      final s = b.disque.saisies.single;
      expect((s.quantite, s.origine, s.rayonId), (7, OrigineSaisie.guidee, 'S2B2'));
      expect(produitCourant(tester), isNot(premier));
      expect(champScanAFocus(tester), isTrue, reason: 'après OK');
      expect(find.text('précédent en attente'), findsOneWidget);
      await demonter(tester);
    });

    testWidgets('OK sur champ vide refusé ; chiffres + Entrée de la douchette (clavier physique)', (tester) async {
      final b = await guidee(tester);
      await taperNv(tester, '');
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une quantité.'), findsOneWidget);
      expect(b.disque.saisies, isEmpty);
      expect(champScanAFocus(tester), isTrue, reason: 'après OK refusé');
      await douchette(tester, '12');
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 12);
      await demonter(tester);
    });

    testWidgets('scan pendant la saisie guidée : produit du rayon → feuille ; autre rayon → message, focus gardé', (tester) async {
      final b = await guidee(tester);
      await douchette(tester, '3400936311000'); // AUGMENTIN (S2B2)
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-feuille-produit')), findsOneWidget);
      await taperNv(tester, '3');
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.ligneId, 6);
      expect(champScanAFocus(tester), isTrue, reason: 'après la feuille');

      await douchette(tester, '3400930000001'); // DOLIPRANE (S3)
      await tester.pumpAndSettle();
      expect(find.textContaining('introuvable dans cet emplacement'), findsOneWidget);
      expect(champScanAFocus(tester), isTrue, reason: 'après une erreur');
      await demonter(tester);
    });

    testWidgets('Cumul : produit déjà compté → Remplacer / Ajouter explicite', (tester) async {
      final b = await guidee(tester, cumul: true);
      // AMOXICILLINE (déjà comptée 6) est le premier produit du rayon S2B2 par ordre alphabétique.
      expect(produitCourant(tester), 'AMOXICILLINE 500 GÉL B/12');
      await taperNv(tester, '4');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nv-ajouter')));
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 10);
      await demonter(tester);
    });

    testWidgets('sortie avec des saisies non envoyées (Collecte) : « Envoyer et quitter » envoie puis quitte', (tester) async {
      tailleEcran(tester, telephone360);
      final b = await preparerBanc(serveur: serveurRealiste());
      await tester.pumpWidget(monterNv(
          b,
          Builder(
              builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S2B2'))),
                        child: const Text('ouvrir'),
                      ),
                    ),
                  ))));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await taperNv(tester, '7');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nv-quitter')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nv-envoyer-quitter')));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(b.serveur.puts, hasLength(1));
      expect(find.text('ouvrir'), findsOneWidget, reason: 'écran quitté après envoi complet');
      await demonter(tester);
    });

    testWidgets('tablette : pavé à droite, sans débordement, même logique', (tester) async {
      tailleEcran(tester, tablette, densite: 1.5);
      final b = await preparerBanc(serveur: serveurRealiste());
      await tester.pumpWidget(monterNv(b, NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S2B2')));
      await tester.pumpAndSettle();
      await taperNv(tester, '2');
      await tester.pumpAndSettle();
      expect(b.disque.saisies.single.quantite, 2);
      expect(tester.takeException(), isNull);
      await touche(tester, LogicalKeyboardKey.escape);
      await demonter(tester);
    });
  });
}
