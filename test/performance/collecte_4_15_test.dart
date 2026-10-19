// PERFORMANCE — 4.15 : création d'un inventaire depuis la collecte, versement en lot, état des rayons.
// Plafonds de NOMBRE DE REQUÊTES (fonctionnement voulu, sans marge) et de durée (temps réel, serveur qui
// répond en 50 ms par requête : marge ×3 pour la CI) :
//  - analyse de 40 codes : une requête par code, 4 en parallèle (bien plus court qu'en série) ;
//  - création depuis la collecte : serveur actuel (essai de route + liste ×2 + création + retenue) et
//    serveur à jour (liste + création + retenue : l'identifiant est donné, aucune relecture) ;
//  - versement de 300 lignes : 1 lecture + 2 lots (au lieu de 300 envois produit par produit) ;
//  - choix de l'emplacement (serveur à jour) : 2 requêtes quel que soit le nombre d'emplacements (avant :
//    1 + 2 par emplacement).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/inventaire/produits_collecte.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';

import '../helpers/banc_essai.dart';
import '../support/faux_serveur_prestige.dart';
import '../support/performance.dart';

/// 3 emplacements × 100 produits (CIP 34009…), aucun compté.
FauxServeurPrestige serveurCollecte({bool recent = false}) {
  final c = grandCatalogue(rayons: 3, parRayon: 100);
  final s = FauxServeurPrestige(catalogue: c, exigerSession: false);
  if (recent) s.serveurRecent = true;
  return s;
}

ApiService api(FauxServeurPrestige s, {bool recent = false}) {
  ApiService.oublierRoutesAbsentes();
  ApiService.clientParDefaut = s.client;
  const base = 'http://perf.invalid/prestige';
  ApiService.noterServeur(base, recent: recent);
  return ApiService(baseUrl: base, sessionCookie: 'JSESSIONID=perf');
}

String detail(List<RequeteRecue> rs) {
  final par = <String, int>{};
  for (final r in rs) {
    final k = '${r.methode} ${r.route.split('/').last}';
    par[k] = (par[k] ?? 0) + 1;
  }
  return par.entries.map((e) => '${e.key} ×${e.value}').join(', ');
}

void main() {
  tearDown(() {
    ApiService.clientParDefaut = null;
    ApiService.oublierRoutesAbsentes();
  });

  test('analyse de 40 codes collectés : 40 requêtes, 4 en parallèle', () async {
    final s = serveurCollecte();
    s.catalogue.delai = const Duration(milliseconds: 50);
    final a = api(s);
    final codes = [for (final p in s.catalogue.produits.take(40)) p.cip];
    final sw = Stopwatch()..start();
    final r = await ProduitsCollecte.analyser(a, codes);
    sw.stop();
    expect(r.produits, hasLength(40));
    mesurer('Requêtes — analyse de 40 codes collectés', s.requetes.length, seuil: 40, unite: 'requêtes', detail: detail(s.requetes));
    // En série : 40 × 50 ms = 2 000 ms ; 4 à la fois : ~500 ms.
    mesurer('Durée — analyse de 40 codes (serveur à 50 ms)', sw.elapsedMilliseconds, seuil: 1500, unite: 'ms');
  });

  for (final recent in [false, true]) {
    final nom = recent ? 'serveur à jour' : 'serveur actuel';
    test('création depuis la collecte (40 produits, 3 emplacements), $nom : requêtes', () async {
      final s = serveurCollecte(recent: recent);
      final a = api(s, recent: recent);
      final codes = [
        for (var i = 0; i < 40; i++) s.catalogue.produits[i * 7].cip,
      ];
      final analyse = await ProduitsCollecte.analyser(a, codes);
      final avant = s.requetes.length;
      final r = await CreationInventaire(a).creerDepuisCollecte('Collecte performance', analyse);
      final rs = s.requetes.sublist(avant);
      expect(r.ok, isTrue, reason: r.message);
      expect(r.retenus, 40);
      // Actuel : essai de la route + doublon (liste) + création + identifiant (liste) + retenue = 5.
      // À jour (4.16.1, demande 46) : doublon (liste) + création atomique des produits = 2.
      mesurer('Requêtes — création depuis la collecte, $nom', rs.length, seuil: recent ? 2 : 5, unite: 'requêtes', detail: detail(rs));
    });
  }

  test('versement de 300 lignes (serveur à jour) : 1 lecture + 2 lots', () async {
    final s = serveurCollecte(recent: true);
    final a = api(s, recent: true);
    final q = SaisieQueue(store: DisqueMemoire());
    final m = MoteurVersement(api: a, queue: q, enregistrer: (_) async {});
    final v = Versement.depuisCollecte(
        [for (final p in s.catalogue.produits) CollectedItem(code: p.cip, quantity: 2, dateScan: DateTime(2026, 10, 15))],
        inventaireId: 'INV1',
        inventaireLibelle: 'Inventaire test',
        mode: ModeDejaCompte.remplacer);
    final sw = Stopwatch()..start();
    final r = await m.executer(v);
    sw.stop();
    expect(r.statut, StatutVersement.termine);
    expect(r.versees, hasLength(300));
    mesurer('Requêtes — versement de 300 lignes (en lot)', s.requetes.length, seuil: 3, unite: 'requêtes', detail: detail(s.requetes));
    mesurer('Durée — versement de 300 lignes (en lot, serveur instantané)', sw.elapsedMilliseconds, seuil: 3000, unite: 'ms');
  });

  test('état des emplacements (serveur à jour) : 2 requêtes pour 3 emplacements (avant : 1 + 2 × 3)', () async {
    final s = serveurCollecte(recent: true);
    final a = api(s, recent: true);
    final p = EntryProvider(queue: SaisieQueue(store: DisqueMemoire()));
    await p.fetchRayons(a, 'INV1');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(p.rayonStatuses.length, 3);
    mesurer('Requêtes — emplacements et leur état (serveur à jour, 3 emplacements)', s.requetes.length, seuil: 2, unite: 'requêtes', detail: detail(s.requetes));
  });
}
