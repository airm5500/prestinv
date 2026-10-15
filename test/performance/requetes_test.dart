// PERFORMANCE — NOMBRE DE REQUÊTES envoyées au faux serveur Prestige pour les parcours clés
// (application entière, nouvelle interface). Chaque parcours a un PLAFOND explicite : une requête de
// trop (boucle, double chargement, recherche sans anti-rebond, envoi ligne à ligne en double…) fait
// échouer le test. Plafonds = fonctionnement voulu, sans marge (voir test/README.md).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/ui/ecrans/inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';

import '../helpers/banc_essai.dart' show ecranTerminal;
import '../helpers/faux_prestige_http.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/faux_serveur_prestige.dart';
import '../support/performance.dart';

/// Catalogue d'officine fictif + 60 produits de plus dans ANTIBIOTIQUES (saisie de 50 quantités).
FauxServeurPrestige serveurRempli() {
  final c = serveurRealiste();
  for (var i = 1; i <= 60; i++) {
    c.produits.add(FauxProduit(5000 + i, '34009${(5000 + i).toString().padLeft(8, '0')}', 'ZINC ${i.toString().padLeft(3, '0')} GÉL', 'S2B2', 10 + i % 5));
  }
  return FauxServeurPrestige(catalogue: c);
}

/// Requêtes reçues pendant [action], par route (pour le message d'échec).
Future<List<RequeteRecue>> compter(FauxServeurPrestige s, Future<void> Function() action) async {
  final avant = s.requetes.length;
  await action();
  return s.requetes.sublist(avant);
}

String detail(List<RequeteRecue> rs) {
  final par = <String, int>{};
  for (final r in rs) {
    final k = '${r.methode} ${r.route.split('/').last}';
    par[k] = (par[k] ?? 0) + 1;
  }
  return par.entries.map((e) => '${e.key} ×${e.value}').join(', ');
}

Future<void> ouvrirSaisieAntibiotiques(WidgetTester tester) async {
  await choisirInventaire(tester, 'INV1');
  await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
  await tester.pumpAndSettle();
  await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
  await tester.pumpAndSettle();
  expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
}

void main() {
  setUpAll(chargerPolicesReelles);

  testWidgets('ancienne interface : connexion + accueil d\'origine, liste lue une seule fois', (tester) async {
    ecranTerminal(tester);
    final serveur = serveurRempli();
    await lancerApplication(tester, serveur: serveur, nouvelleInterface: false);
    final accueil = await compter(serveur, () => seConnecter(tester));
    mesurer('Requêtes — connexion + accueil d\'origine', accueil.length, seuil: 1, unite: 'requêtes', detail: detail(accueil));
    await fermerApplication(tester);
  });

  testWidgets('démarrage, connexion + accueil, déroulé de la liste, ouverture d\'un inventaire : plafonds', (tester) async {
    tailleEcran(tester, telephone360);
    final serveur = serveurRempli();
    final demarrage = await compter(serveur, () async {
      await lancerApplication(tester, serveur: serveur);
    });
    mesurer('Requêtes — démarrage (jusqu\'à l\'écran de connexion)', demarrage.length, seuil: Seuils.demarrageRequetes, unite: 'requêtes', detail: detail(demarrage));

    final accueil = await compter(serveur, () => seConnecter(tester));
    // Connexion (1) + liste des inventaires (1). Avant la 4.14.2 : liste lue DEUX fois (accueil construit
    // deux fois : par la racine de l'application et par l'écran de connexion).
    mesurer('Requêtes — connexion + ouverture de l\'accueil', accueil.length, seuil: 2, unite: 'requêtes', detail: detail(accueil));

    // Déroulé : avancement de chaque inventaire : ses emplacements (1) puis, par
    // emplacement, comptés (1) et restants (1). Catalogue : 2 inventaires × 3 emplacements.
    final deroule = await compter(serveur, () => deroulerInventaires(tester));
    final nbInv = serveur.catalogue.inventaires.length, nbRayons = serveur.catalogue.rayons.length;
    mesurer('Requêtes — déroulé de la liste ($nbInv inventaires × $nbRayons emplacements)', deroule.length,
        seuil: nbInv * (1 + 2 * nbRayons), unite: 'requêtes', detail: detail(deroule));

    final ouverture = await compter(serveur, () async {
      final f = find.byKey(const ValueKey('nv-ouvrir-INV1'));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    });
    expect(find.byType(NvInventaireScreen), findsOneWidget);
    mesurer('Requêtes — ouverture d\'un inventaire (avancement déjà connu)', ouverture.length, seuil: 0, unite: 'requêtes', detail: detail(ouverture));
    await fermerApplication(tester);
  });

  testWidgets('saisie de 50 quantités (mode Collecte) puis envoi par lots : plafonds', (tester) async {
    tailleEcran(tester, telephone360);
    final serveur = serveurRempli();
    final app = await lancerApplication(tester, serveur: serveur);
    await seConnecter(tester);
    await choisirInventaire(tester, 'INV1');
    // Choix de l'emplacement : emplacements (1) + état de chacun (comptés 1, restants 1).
    final nbRayons = serveur.catalogue.rayons.length;
    final choix = await compter(serveur, () async {
      await toucher(tester, find.byKey(const ValueKey('nv-saisie-guidee')));
      await tester.pumpAndSettle();
    });
    mesurer('Requêtes — choix de l\'emplacement ($nbRayons emplacements)', choix.length, seuil: 1 + 2 * nbRayons, unite: 'requêtes', detail: detail(choix));
    final ouverture = await compter(serveur, () async {
      await toucher(tester, find.text('S2B2 – ANTIBIOTIQUES'));
      await tester.pumpAndSettle();
    });
    expect(find.byType(NvSaisieGuideeScreen), findsOneWidget);
    mesurer('Requêtes — ouverture de la saisie guidée d\'un emplacement', ouverture.length, seuil: 1, unite: 'requêtes', detail: detail(ouverture));

    final saisie = await compter(serveur, () async {
      for (var i = 0; i < 50; i++) {
        await taperNv(tester, '${1 + i % 9}');
        await tester.pumpAndSettle();
      }
    });
    expect(app.saisies.enAttente(), 50);
    mesurer('Requêtes — saisie de 50 quantités (mode Collecte : gardées sur l\'appareil)', saisie.length, seuil: 0, unite: 'requêtes', detail: detail(saisie));

    final envoi = await compter(serveur, () async {
      await tester.tap(find.byKey(const ValueKey('nv-envoyer-badge')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
    });
    expect(app.saisies.enAttente(), 0);
    // Une requête par quantité + la vérification que l'inventaire est toujours ouvert (1).
    mesurer('Requêtes — envoi des 50 saisies', envoi.length, seuil: 50 + 1, unite: 'requêtes', detail: detail(envoi));
    expect(envoi.where((r) => r.methode == 'PUT').length, 50, reason: 'aucun double envoi');
    await fermerApplication(tester);
  });

  testWidgets('recherche par nom tapée vite : UNE requête après l\'anti-rebond', (tester) async {
    tailleEcran(tester, telephone360);
    final serveur = serveurRempli();
    await lancerApplication(tester, serveur: serveur);
    await seConnecter(tester);
    await ouvrirSaisieAntibiotiques(tester);
    // Mini-clavier « chercher par nom » (sinon le texte est lu comme un code de douchette).
    await tester.tap(find.byTooltip('Clavier (chercher par nom)'));
    await tester.pumpAndSettle();
    final recherche = await compter(serveur, () async {
      var texte = '';
      for (final c in 'AMOXICI'.split('')) {
        texte += c;
        await tester.enterText(find.byKey(const ValueKey('champ-scan')), texte);
        await tester.pump(const Duration(milliseconds: 120)); // frappe rapide : 120 ms entre deux lettres
      }
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    });
    mesurer('Requêtes — recherche par nom tapée vite (7 lettres)', recherche.length, seuil: 1, unite: 'requêtes', detail: detail(recherche));
    expect(recherche.single.parametres['query'], 'AMOXICI', reason: 'le texte complet est cherché');
    await fermerApplication(tester);
  });
}
