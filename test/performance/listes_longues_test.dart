// PERFORMANCE — rendu et défilement des LONGUES LISTES (nouvelle interface), contre le faux serveur :
//  - accueil : liste des inventaires déroulée (200 inventaires ouverts) ;
//  - saisie guidée sur un rayon de 2 000 produits (ouverture, « Suivant » ×100, recherche → 2 000 résultats) ;
//  - écarts : 2 000 produits en écart ;
//  - collecte : 1 000 lignes ;
//  - analyse « Tous les emplacements » : 50 emplacements.
// Pour chaque écran : temps d'ouverture (à froid), puis chaque image chronométrée pendant un défilement
// complet — 1er passage (à froid : code compilé à la volée, seuil large) puis 2e passage (aucune image
// au-dessus du budget [Seuils.imageDefilementMs]). Seuils : test/support/performance.dart et README.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/analyse_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/widgets_saisie.dart';

import '../helpers/banc_essai.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/faux_prestige_http.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/performance.dart';

final _inv = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

Future<Banc> banc(FauxPrestige s) async {
  final b = await preparerBanc(serveur: s);
  b.auth.connecterPourTest(login: 'Awa K.');
  return b;
}

/// Ouvre [ecran] dans une route (comme depuis l'accueil), chronomètre jusqu'à l'écran immobile.
Future<double> ouvrir(WidgetTester tester, Banc b, Widget ecran, {int pompes = 0}) async {
  await tester.pumpWidget(monterNv(
      b,
      Builder(
          builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran)), child: const Text('ouvrir')),
                ),
              ))));
  final sw = Stopwatch()..start();
  await tester.tap(find.text('ouvrir'));
  for (var i = 0; i < pompes; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
  return sw.elapsedMicroseconds / 1000;
}

/// Deux passages de défilement complets sur la plus grande liste : le 1er à froid, le 2e chronométré
/// image par image contre le budget.
Future<void> deuxPassages(WidgetTester tester, String nom, {int minPas = 5}) async {
  final liste = plusGrandeListe(tester);
  final froid = ChronoImages();
  final pas1 = await defilerJusquEnBas(tester, liste, froid);
  expect(pas1, greaterThanOrEqualTo(minPas), reason: '$nom : la liste doit être longue (pas de défilement : $pas1)');
  await remonter(tester, liste);
  final chaud = ChronoImages();
  await defilerJusquEnBas(tester, liste, chaud);
  mesurer('$nom — pire image, 1er défilement (à froid)', froid.max, seuil: Seuils.imageFroideMs, unite: 'ms', detail: froid.resume);
  mesurer('$nom — pire image, défilement', chaud.max, seuil: Seuils.imageDefilementMs, unite: 'ms', detail: chaud.resume);
  mesurer('$nom — image courante (p90), défilement', chaud.p90, seuil: Seuils.imageCouranteMs, unite: 'ms');
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  testWidgets('accueil : liste déroulée de 200 inventaires (avancement calculé), défilement fluide', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc(grandCatalogue(inventaires: 200, rayons: 2, parRayon: 10));
    final sw = Stopwatch()..start();
    await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();
    await deroulerInventaires(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    mesurer('Accueil, 200 inventaires — ouverture + déroulé', sw.elapsedMicroseconds / 1000, seuil: Seuils.ouvertureListeMs * 2, unite: 'ms');
    expect(find.byKey(const ValueKey('nv-ouvrir-INV1')), findsOneWidget);
    await deuxPassages(tester, 'Accueil, 200 inventaires');
    expect(find.byKey(const ValueKey('nv-ouvrir-INV200')), findsOneWidget, reason: 'dernier inventaire atteint');
    await demonter(tester);
  });

  testWidgets('saisie guidée sur un rayon de 2 000 produits : ouverture, « Suivant » ×100, recherche → 2 000 résultats', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc(grandCatalogue(rayons: 1, parRayon: 2000));
    final ouverture = await ouvrir(tester, b, NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'E1'));
    mesurer('Saisie guidée, rayon de 2 000 produits — ouverture', ouverture, seuil: Seuils.ouvertureListeMs, unite: 'ms');
    expect(find.text('1 / 2000'), findsOneWidget);

    final froid = ChronoImages(), chaud = ChronoImages();
    for (var i = 0; i < 100; i++) {
      await tester.tap(find.byKey(const ValueKey('nv-suivant')));
      await (i < 50 ? froid : chaud).pump(tester);
      await tester.pumpAndSettle();
    }
    expect(find.text('101 / 2000'), findsOneWidget);
    mesurer('Saisie guidée, 2 000 produits — pire image « Suivant » (à froid)', froid.max, seuil: Seuils.imageFroideMs, unite: 'ms', detail: froid.resume);
    mesurer('Saisie guidée, 2 000 produits — pire image « Suivant »', chaud.max, seuil: Seuils.imageEcranMs, unite: 'ms', detail: chaud.resume);
    mesurer('Saisie guidée, 2 000 produits — image courante (p90) « Suivant »', chaud.p90, seuil: Seuils.imageEcranCouranteMs, unite: 'ms');

    // Recherche par nom qui renvoie tout le rayon : liste de 2 000 résultats.
    await tester.enterText(find.byKey(const ValueKey('champ-scan')), 'PRODUIT');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(ListeResultats), findsOneWidget);
    await deuxPassages(tester, 'Saisie guidée, 2 000 résultats de recherche');
    await demonter(tester);
  });

  testWidgets('écarts : 2 000 produits en écart, défilement fluide', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc(grandCatalogue(rayons: 4, parRayon: 500, ecarts: true));
    final ouverture = await ouvrir(tester, b, NvEcartsScreen(inventaire: _inv));
    mesurer('Écarts, 2 000 produits — ouverture', ouverture, seuil: Seuils.ouvertureListeMs, unite: 'ms');
    await deuxPassages(tester, 'Écarts, 2 000 produits');
    await demonter(tester);
  });

  testWidgets('collecte : 1 000 lignes, défilement fluide', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc(grandCatalogue());
    final debut = DateTime(2026, 10, 13, 8);
    await CollecteStore.ecrire([
      for (var i = 0; i < 1000; i++)
        CollectedItem(code: '34009${(i + 1).toString().padLeft(8, '0')}', quantity: 1 + i % 9, dateScan: debut.add(Duration(seconds: i))),
    ]);
    final ouverture = await ouvrir(tester, b, const NvCollecteScreen());
    mesurer('Collecte, 1 000 lignes — ouverture', ouverture, seuil: Seuils.ouvertureListeMs, unite: 'ms');
    await deuxPassages(tester, 'Collecte, 1 000 lignes');
    await demonter(tester);
  });

  testWidgets('analyse « Tous les emplacements » : 50 emplacements calculés puis défilement fluide', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc(grandCatalogue(rayons: 50, parRayon: 20));
    final ouverture = await ouvrir(tester, b, NvAnalyseScreen(inventaireInitial: _inv), pompes: 20);
    mesurer('Analyse, 50 emplacements — calcul et affichage', ouverture, seuil: Seuils.ouvertureListeMs, unite: 'ms');
    expect(find.byKey(const ValueKey('nv-analyse-progression')), findsNothing, reason: 'calcul terminé');
    await deuxPassages(tester, 'Analyse, 50 emplacements', minPas: 3);
    expect(find.byKey(const ValueKey('nv-analyse-ligne-E50')), findsOneWidget, reason: 'dernier emplacement atteint');
    await demonter(tester);
  });
}
