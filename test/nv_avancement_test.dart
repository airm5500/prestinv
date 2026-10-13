// Nouvelle interface — accueil : « Actualiser l'avancement » calcule l'état des rayons À LA DEMANDE
// (mêmes requêtes que « Choisir un rayon »), jamais automatiquement ; progression « Rayon i/n »,
// annulation, anti double appui, motif d'échec affiché, résultat gardé avec son heure.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/faux_prestige_http.dart';
import 'helpers/nouvelle_interface.dart';

/// Requêtes d'état des rayons (celles que le calcul envoie).
int requetesEtat(FauxPrestige s) => s.appels.where((a) => a.endsWith('TouchedRayon') || a.endsWith('UntouchedRayon') || a == 'GET rayons').length;

Future<Banc> banc() async {
  final b = await preparerBanc(serveur: serveurRealiste());
  b.auth.connecterPourTest(login: 'Awa K.');
  // RÉSERVE (S3) entièrement comptée → terminé ; CANNES et ANTIBIOTIQUES commencés.
  for (final p in b.serveur.produits.where((p) => p.rayon == 'S3')) {
    p.dtUpdated ??= '2026-10-13T10:00:00';
  }
  return b;
}

/// Laisse finir le calcul (les délais du faux serveur sont des minuteries : pumpAndSettle seul ne les
/// attend pas).
Future<void> finir(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pumpAndSettle();
}

Finder get bouton => find.byKey(const ValueKey('nv-actualiser-avancement'));

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
    AvancementCalcul.viderCache();
  });

  testWidgets('aucun calcul automatique à l\'affichage ; sur demande : progression, résultat, heure gardée', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    b.serveur.delais['detailsTouchedRayon'] = const Duration(milliseconds: 300);
    await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();
    expect(requetesEtat(b.serveur), 0, reason: 'pas de calcul à l\'affichage de l\'accueil');
    expect(find.text('Actualiser l\'avancement'), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-avancement-pct')), findsNothing);

    await tester.tap(bouton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Rayon 1/3'), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-annuler-avancement')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Rayon 2/3'), findsOneWidget);
    await finir(tester);

    expect(find.byKey(const ValueKey('nv-avancement-progression')), findsNothing);
    expect(find.textContaining('1 rayon(s) terminé(s) sur 3'), findsOneWidget);
    expect(find.textContaining('2 commencé(s)'), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget, reason: '(1 + 2 × ½) / 3');
    final heure = tester.widget<Text>(find.byKey(const ValueKey('nv-avancement-heure'))).data!;
    expect(heure, matches(RegExp(r'^Avancement à \d\d:\d\d$')));
    // 1 liste des rayons + 3 « comptés » + 3 « restants » (les trois rayons sont entamés).
    expect(requetesEtat(b.serveur), 7);
    final garde = (await SharedPreferences.getInstance()).getString(AvancementCalcul.cle('INV1'));
    expect(garde, isNotNull, reason: 'résultat gardé sur l\'appareil');

    // Retour sur l'accueil (nouvel affichage, cache mémoire vidé = redémarrage) : avancement relu, sans requête.
    AvancementCalcul.viderCache();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();
    expect(find.text(heure), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget);
    expect(requetesEtat(b.serveur), 7, reason: 'aucune nouvelle requête');
    await demonter(tester);
  });

  testWidgets('anti double appui : deux touches rapprochées = un seul calcul', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    b.serveur.delais['rayons'] = const Duration(milliseconds: 200);
    await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.tap(bouton, warnIfMissed: false); // même endroit : n'annule pas, ne relance pas
    await tester.pump();
    await tester.tap(find.text('Lecture des rayons…'), warnIfMissed: false);
    await finir(tester);
    expect(b.serveur.appels.where((a) => a == 'GET rayons').length, 1);
    expect(requetesEtat(b.serveur), 7);
    expect(find.text('67 %'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('annulation : arrêt immédiat, réponse en vol ignorée, ancien résultat gardé', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    final heure = tester.widget<Text>(find.byKey(const ValueKey('nv-avancement-heure'))).data!;
    final avant = requetesEtat(b.serveur);

    // Un collègue termine les CANNES ; on relance puis on annule pendant la lecture du 1er rayon.
    for (final p in b.serveur.produits.where((p) => p.rayon == 'S1A0T2')) {
      p.dtUpdated ??= '2026-10-13T11:00:00';
    }
    b.serveur.delais['detailsTouchedRayon'] = const Duration(seconds: 2);
    await tester.tap(bouton);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Rayon 1/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nv-annuler-avancement')));
    await tester.pump();
    expect(find.byKey(const ValueKey('nv-avancement-progression')), findsNothing);
    expect(find.text('Actualisation de l\'avancement annulée.'), findsOneWidget);
    await finir(tester);
    // Seule la requête déjà partie (liste + 1er rayon) a été envoyée ; rien d'autre ensuite.
    expect(requetesEtat(b.serveur), avant + 2);
    expect(find.text(heure), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget, reason: 'le résultat annulé n\'est pas pris en compte');
    expect(find.byKey(const ValueKey('nv-avancement-erreur')), findsNothing);
    await demonter(tester);
  });

  testWidgets('erreur réseau : motif affiché, arrêt rapide, dernier avancement gardé ; Réessayer = Actualiser', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();

    // Liste des rayons injoignable.
    b.serveur.routesInjoignables.add('rayons');
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nv-avancement-erreur')), findsOneWidget);
    expect(find.textContaining('Avancement non actualisé : Serveur injoignable (emplacements non chargés)'), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-avancement-pct')), findsNothing, reason: 'pas d\'avancement inventé');

    // Rétabli : calcul réussi, le message disparaît.
    b.serveur.routesInjoignables.clear();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nv-avancement-erreur')), findsNothing);
    expect(find.text('67 %'), findsOneWidget);

    // Le serveur tombe pendant le calcul : arrêt après deux rayons illisibles (pas 3 délais).
    b.serveur.routesInjoignables.add('detailsTouchedRayon');
    final avant = b.serveur.appels.where((a) => a.endsWith('detailsTouchedRayon')).length;
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    expect(b.serveur.appels.where((a) => a.endsWith('detailsTouchedRayon')).length - avant, AvancementCalcul.echecsReseauMax);
    expect(find.textContaining('Serveur injoignable (produits comptés non chargés)'), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget, reason: 'le dernier avancement connu reste affiché');
    await demonter(tester);
  });

  testWidgets('session expirée : motif et « Se reconnecter »', (tester) async {
    tailleEcran(tester, telephone360);
    final b = await banc();
    b.serveur.codes['detailsTouchedRayon'] = 401;
    await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Session expirée'), findsOneWidget);
    expect(find.byKey(const ValueKey('nv-avancement-reconnecter')), findsOneWidget);
    expect(b.serveur.appels.where((a) => a.endsWith('detailsTouchedRayon')).length, 1, reason: 'arrêt dès la 1re réponse 401');
    await demonter(tester);
  });

  testWidgets('rendu sans débordement pendant et après le calcul (Sunmi V2s, tablette)', (tester) async {
    for (final taille in [sunmiV2s, tablette]) {
      tailleEcran(tester, taille);
      final b = await banc();
      b.serveur.delais['detailsTouchedRayon'] = const Duration(milliseconds: 300);
      await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
      await tester.pumpAndSettle();
      await tester.tap(bouton);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await finir(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('67 %'), findsOneWidget);
      AvancementCalcul.viderCache();
      await demonter(tester);
    }
  });
}
