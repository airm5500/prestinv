// UNITAIRES — règles de la 4.13 (maquette validée par le pharmacien), sans écran :
//  - filtre du rayon : paires De / À obligatoires, chiffres, bornes, « 1 à total » = aucun filtre,
//    vrai filtre « oublis » distinct du filtre par numéro, pré-remplissage ;
//  - boutons de la liste des inventaires : Commencer (0 %) / Poursuivre (0,1–99,9 %) / Revérifier (100 %) ;
//  - envoi manuel : rappel bloquant après le délai, envoi automatique toutes les 15 min si délai 0
//    (horloge simulée) ;
//  - création d'inventaire : profil (réponse de connexion), réglage, code administrateur ;
//  - masquages dans les PDF / CSV (stock théorique, quantité déjà comptée) ;
//  - taille de l'écran : données d'écran ramenées à l'échelle, réglage mémorisé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/inventaire/autorisation_creation.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/product_filter.dart';
import 'package:prestinv/models/user.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/rappel_envoi.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/filtre_rayon.dart';
import 'package:prestinv/ui/taille_ecran.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart';
import '../helpers/faux_serveur.dart';

Product _p(int id, {int theo = 5, int compte = 5, bool touche = true}) => Product(
      id: id,
      produitCip: '34009$id',
      produitName: 'PRODUIT $id',
      produitPrixAchat: 1000,
      produitPrixUni: 1300,
      quantiteInitiale: theo,
      quantiteSaisie: compte,
      dtUpdated: touche ? '2026-10-13T10:00:00' : null,
    );

void main() {
  group('Filtre du rayon', () {
    test('par numéro : De ET À obligatoires (une valeur sans l\'autre est refusée)', () {
      expect(controlerFiltreNumero('10', '', 130).ok, isFalse);
      expect(controlerFiltreNumero('', '40', 130).ok, isFalse);
      expect(controlerFiltreNumero('', '', 130).ok, isFalse);
      expect(controlerFiltreNumero('10', '', 130).erreur, contains('« De » ET « À »'));
    });

    test('par numéro : chiffres seulement, De ≤ À, bornés de 1 au total', () {
      expect(controlerFiltreNumero('1a', '40', 130).ok, isFalse);
      expect(controlerFiltreNumero('40', '10', 130).ok, isFalse);
      expect(controlerFiltreNumero('0', '10', 130).ok, isFalse);
      expect(controlerFiltreNumero('10', '131', 130).ok, isFalse);
      final r = controlerFiltreNumero(' 10 ', '40', 130);
      expect(r.ok, isTrue);
      expect((r.filtre!.type, r.filtre!.from, r.filtre!.to), (FilterType.numeric, '10', '40'));
      expect(controlerFiltreNumero('7', '7', 130).filtre!.isActive, isTrue, reason: 'un seul produit');
    });

    test('« 1 à total » = aucun filtre', () {
      final r = controlerFiltreNumero('1', '130', 130);
      expect(r.ok, isTrue);
      expect(r.filtre!.isActive, isFalse);
    });

    test('alphabétique : paire obligatoire, De avant À, majuscules', () {
      expect(controlerFiltreAlpha('a', '').ok, isFalse);
      expect(controlerFiltreAlpha('', 'd').ok, isFalse);
      expect(controlerFiltreAlpha('m', 'b').ok, isFalse);
      final r = controlerFiltreAlpha('a', 'd');
      expect((r.filtre!.type, r.filtre!.from, r.filtre!.to), (FilterType.alphabetic, 'A', 'D'));
    });

    test('pré-remplissage : seulement des numéros pour « par numéro » (jamais « Rattrapage / Oublis »)', () {
      final ancien = champsDepuis(ProductFilter(type: FilterType.numeric, from: 'Rattrapage', to: 'Oublis'));
      expect((ancien.deNum, ancien.aNum), ('', ''));
      final oublis = champsDepuis(ProductFilter(type: FilterType.oublis));
      expect((oublis.deNum, oublis.aNum, oublis.type), ('', '', FilterType.numeric));
      final num = champsDepuis(ProductFilter(type: FilterType.numeric, from: '10', to: '40'));
      expect((num.deNum, num.aNum, num.deAlpha), ('10', '40', ''));
      final alpha = champsDepuis(ProductFilter(type: FilterType.alphabetic, from: 'A', to: 'D'));
      expect((alpha.deNum, alpha.deAlpha, alpha.aAlpha, alpha.type), ('', 'A', 'D', FilterType.alphabetic));
    });

    test('libellé de la ligne réservée', () {
      expect(libelleFiltreActif(ProductFilter(), 130), isNull);
      expect(libelleFiltreActif(ProductFilter(type: FilterType.numeric, from: '10', to: '40'), 31), 'Filtre : n° 10 à 40 · 31 produits');
      expect(libelleFiltreActif(ProductFilter(type: FilterType.oublis), 1), 'Filtre : oublis (pas encore comptés) · 1 produit');
      expect(libelleFiltreActif(ProductFilter(type: FilterType.numeric, from: 'Rattrapage', to: 'Oublis'), 2), contains('oublis'));
    });

    test('vrai filtre « oublis » (FilterType.oublis) ; l\'ancien détournement reste pour les écrans d\'origine', () async {
      final b = await preparerBanc();
      final e = EntryProvider(queue: b.queue);
      final f = ProductFilter(type: FilterType.oublis);
      expect(f.isActive && f.estOublis, isTrue);
      e.filtrerOublis();
      expect(e.activeFilter.type, FilterType.oublis);
      e.filterToUncounted();
      expect((e.activeFilter.type, e.activeFilter.from), (FilterType.numeric, 'Rattrapage'), reason: 'inchangé pour l\'interface d\'origine');
      // Index enregistrés inchangés : none 0, numeric 1, alphabetic 2.
      expect(ProductFilter.fromRawJson('{"type":1,"from":"3","to":"9"}').type, FilterType.numeric);
      expect(ProductFilter.fromRawJson('{"type":2,"from":"A","to":"C"}').type, FilterType.alphabetic);
    });
  });

  group('Boutons de la liste des inventaires', () {
    AvancementRayons r({required int total, required Set<int> comptes, int ecarts = 0}) => AvancementRayons(
        inventaireId: 'I', calculeA: DateTime(2026, 10, 13, 10), statuts: const {'R': 1}, total: 1, totalProduits: total, comptes: comptes, ecarts: ecarts);

    test('0 % → Commencer ; 0,1 à 99,9 % → Poursuivre ; 100 % → Revérifier', () {
      expect(etatAvancement(r(total: 130, comptes: {})).action, ActionInventaire.commencer);
      expect(etatAvancement(r(total: 1000, comptes: {1})).action, ActionInventaire.poursuivre);
      expect(etatAvancement(r(total: 130, comptes: {for (var i = 0; i < 110; i++) i})).action, ActionInventaire.poursuivre);
      expect(etatAvancement(r(total: 130, comptes: {for (var i = 0; i < 130; i++) i})).action, ActionInventaire.reverifier);
    });

    test('saisies faites sur le téléphone depuis le calcul : comptées sans nouvelle requête', () {
      final e = etatAvancement(r(total: 130, comptes: {1, 2}), lignesLocales: [2, 3, 4]);
      expect((e.comptes, e.total, e.restants), (4, 130, 126));
      expect(etatAvancement(r(total: 3, comptes: {}), lignesLocales: [1, 2, 3]).action, ActionInventaire.reverifier);
      expect(etatAvancement(null, lignesLocales: [1]).action, ActionInventaire.poursuivre, reason: 'commencé sur ce téléphone');
      expect(etatAvancement(null).action, ActionInventaire.inconnu, reason: 'pas encore calculé : « Ouvrir »');
    });

    test('pourcentage affiché : jamais 0 % si commencé, jamais 100 % si pas fini', () {
      expect(pourcentageAffiche(etatAvancement(r(total: 130, comptes: {}))), '0 %');
      expect(pourcentageAffiche(etatAvancement(r(total: 2000, comptes: {1}))), '0,1 %');
      expect(pourcentageAffiche(etatAvancement(r(total: 130, comptes: {for (var i = 0; i < 110; i++) i}))), '85 %');
      expect(pourcentageAffiche(etatAvancement(r(total: 1000, comptes: {for (var i = 0; i < 999; i++) i}))), '99,9 %');
      expect(pourcentageAffiche(etatAvancement(r(total: 130, comptes: {for (var i = 0; i < 130; i++) i}))), '100 %');
      expect(pourcentageAffiche(etatAvancement(null)), '— %');
    });

    test('ancien calcul gardé (rayons seulement) : toujours lisible', () {
      final ancien = AvancementRayons.fromJson({'inv': 'I', 'a': '2026-10-13T10:00:00.000', 'total': 3, 'statuts': {'A': 2, 'B': 1, 'C': 0}})!;
      expect(ancien.produitsConnus, isFalse);
      final e = etatAvancement(ancien);
      expect((e.pourcentage, e.action), (50.0, ActionInventaire.poursuivre));
      final nouveau = AvancementRayons.fromJson(r(total: 10, comptes: {1, 2}, ecarts: 1).toJson())!;
      expect((nouveau.totalProduits, nouveau.ecarts), (10, 1));
      expect(nouveau.comptes, {1, 2});
    });
  });

  group('Envoi manuel : rappel bloquant ou envoi automatique (horloge simulée)', () {
    final t0 = DateTime(2026, 10, 13, 9);

    test('délai réglé : rien avant, rappel après ; reporté juste après un essai', () {
      DecisionRappel d(Duration ecoule, {DateTime? reporte}) =>
          deciderRappel(envoiManuel: true, delaiMinutes: 30, plusAncienne: t0, maintenant: t0.add(ecoule), reporteJusqua: reporte);
      expect(d(const Duration(minutes: 29)), DecisionRappel.rien);
      expect(d(const Duration(minutes: 30)), DecisionRappel.rappel);
      expect(d(const Duration(minutes: 45), reporte: t0.add(const Duration(minutes: 46))), DecisionRappel.rien);
      expect(d(const Duration(minutes: 47), reporte: t0.add(const Duration(minutes: 46))), DecisionRappel.rappel);
    });

    test('rien à envoyer, ou mode Direct : jamais de rappel', () {
      expect(deciderRappel(envoiManuel: true, delaiMinutes: 30, plusAncienne: null, maintenant: t0.add(const Duration(hours: 5))), DecisionRappel.rien);
      expect(deciderRappel(envoiManuel: false, delaiMinutes: 30, plusAncienne: t0, maintenant: t0.add(const Duration(hours: 5))), DecisionRappel.rien);
    });

    test('délai 0 : pas de rappel, envoi automatique toutes les 15 min', () {
      DecisionRappel d(Duration ecoule, {DateTime? dernier}) =>
          deciderRappel(envoiManuel: true, delaiMinutes: 0, plusAncienne: t0, maintenant: t0.add(ecoule), dernierEnvoiAuto: dernier);
      expect(d(const Duration(minutes: 14)), DecisionRappel.rien);
      expect(d(const Duration(minutes: 15)), DecisionRappel.envoiAuto);
      final dernier = t0.add(const Duration(minutes: 15));
      expect(d(const Duration(minutes: 29), dernier: dernier), DecisionRappel.rien);
      expect(d(const Duration(minutes: 30), dernier: dernier), DecisionRappel.envoiAuto);
    });

    test('gardien : rappel affiché une fois, puis revient tant que rien n\'est envoyé ; délai 0 : envoi', () async {
      var maintenant = t0;
      GardienEnvoi.horloge = () => maintenant;
      addTearDown(() => GardienEnvoi.horloge = DateTime.now);
      final serveur = FauxServeur();
      final q = SaisieQueue(store: DisqueMemoire(), clock: () => maintenant)..serveurFactory = () => serveur;
      await q.enregistrer(inventaireId: 'INV1', ligneId: 1, quantite: 4);
      var delai = 15;
      var rappels = 0;
      final g = GardienEnvoi(
        queue: q,
        envoiManuel: () => true,
        delaiMinutes: () => delai,
        actif: () => true,
        afficherRappel: (n, depuis) async {
          rappels++;
          expect(n, 1);
          expect(depuis, greaterThanOrEqualTo(const Duration(minutes: 16)), reason: 'âge de la plus ancienne saisie');
          return null; // l'opérateur a touché « Envoyer maintenant » mais le réseau a échoué
        },
      );
      maintenant = t0.add(const Duration(minutes: 10));
      expect(await g.verifier(), DecisionRappel.rien);
      maintenant = t0.add(const Duration(minutes: 16));
      expect(await g.verifier(), DecisionRappel.rappel);
      expect(rappels, 1);
      expect(await g.verifier(), DecisionRappel.rien, reason: 'laissé tranquille juste après l\'essai');
      maintenant = maintenant.add(relanceApresEssai);
      maintenant = maintenant.add(const Duration(seconds: 1));
      expect(await g.verifier(), DecisionRappel.rappel, reason: 'revient tant que ce n\'est pas envoyé');

      delai = 0;
      expect(await g.verifier(), DecisionRappel.envoiAuto);
      await q.envoyer(); // attend la fin de l'envoi lancé par le gardien (un seul envoi groupé à la fois)
      expect(serveur.quantites[1], 4, reason: 'saisie envoyée par l\'envoi automatique');
      expect(q.enAttente(), 0);
      expect(await g.verifier(), DecisionRappel.rien, reason: 'plus rien en attente');
    });
  });

  group('Création d\'inventaire', () {
    test('profil lu dans la réponse de connexion (xtypeuser)', () {
      AppUser u(Object? t) => AppUser.fromJson({'str_LOGIN': 'x', if (t != null) 'xtypeuser': t});
      expect(u('dashboard').adminOuPharmacien, isTrue);
      expect(u('mainmenumanager').adminOuPharmacien, isFalse);
      expect(u(null).adminOuPharmacien, isNull, reason: 'serveur plus ancien : profil inconnu');
      expect(AppUser.fromJson({'str_FIRST_NAME': 'Aya', 'str_LAST_NAME': 'Kouassi', 'str_LOGIN': 'ak'}).nomComplet, 'Aya Kouassi');
    });

    test('administrateur / pharmacien toujours ; autres selon le réglage ; inconnu : code administrateur', () {
      expect(accesCreation(adminOuPharmacien: true, autresComptesAutorises: false), AccesCreation.autorise);
      expect(accesCreation(adminOuPharmacien: false, autresComptesAutorises: false), AccesCreation.refuse);
      expect(accesCreation(adminOuPharmacien: false, autresComptesAutorises: true), AccesCreation.autorise);
      expect(accesCreation(adminOuPharmacien: null, autresComptesAutorises: false), AccesCreation.codeAdmin);
      expect(accesCreation(adminOuPharmacien: null, autresComptesAutorises: true), AccesCreation.autorise);
    });
  });

  group('Masquages dans les PDF / CSV', () {
    final ps = [_p(1, theo: 5, compte: 3), _p(2, theo: 2, compte: 4)];

    test('écarts : colonnes retirées selon les réglages (stock théorique, quantité déjà comptée)', () {
      expect(NvExports.tableauEcarts(ps).first, ['CIP', 'Désignation', 'Stock Théo.', 'Stock Corrigé', 'Écart']);
      final sansTheo = NvExports.tableauEcarts(ps, theoVisible: false);
      expect(sansTheo.first, ['CIP', 'Désignation', 'Stock Corrigé', 'Écart']);
      expect(sansTheo[1], ['340091', 'PRODUIT 1', '3', '-2']);
      final rien = NvExports.tableauEcarts(ps, theoVisible: false, compteVisible: false);
      expect(rien.first, ['CIP', 'Désignation', 'Écart']);
      expect(rien.expand((l) => l), isNot(contains('3')), reason: 'quantité comptée absente');

      expect(NvExports.csvEcarts(ps).split('\n').first, 'code_cip;designation;theorique;compte;ecart;valeur');
      final csv = NvExports.csvEcarts(ps, theoVisible: false, compteVisible: false).trim().split('\n');
      expect(csv.first, 'code_cip;designation;ecart;valeur');
      expect(csv[1], '340091;PRODUIT 1;-2;-2000');
    });

    test('récapitulatif : théorique remplacé par *** si masqué', () {
      expect(NvExports.tableauRecap(ps)[1][4], '5');
      expect(NvExports.tableauRecap(ps, theoVisible: false)[1][4], '***');
    });

    test('documents produits (PDF valides) avec et sans masquage', () async {
      for (final (t, c) in [(true, true), (false, false)]) {
        final pdf = await NvExports.pdfEcarts('Rayon', ps, theoVisible: t, compteVisible: c);
        expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      }
      final a = await NvExports.pdfAnalyse(inventaire: 'I', emplacement: 'E', avant: 1, apres: 2, positifs: 1, negatifs: 1, corrects: 0, avantVisible: false);
      expect(String.fromCharCodes(a.take(4)), '%PDF');
    });
  });

  group('Taille de l\'écran', () {
    test('facteurs : Automatique 1,0 ; Compact 0,9 ; Très compact 0,8', () {
      expect(TailleEcran.values.map((t) => t.facteur), [1.0, 0.9, 0.8]);
      expect(TailleEcran.automatique.libelle, 'Automatique');
    });

    test('données d\'écran ramenées à l\'échelle (taille, marges, clavier, densité)', () {
      const mq = MediaQueryData(
        size: Size(360, 720),
        devicePixelRatio: 2,
        padding: EdgeInsets.only(top: 24),
        viewPadding: EdgeInsets.only(top: 24),
        viewInsets: EdgeInsets.only(bottom: 288),
      );
      expect(EchelleInterface.donnees(mq, 1.0), same(mq));
      final c = EchelleInterface.donnees(mq, 0.8);
      expect(c.size, const Size(450, 900));
      expect(c.devicePixelRatio, closeTo(1.6, 1e-9));
      expect(c.padding.top, 30);
      expect(c.viewInsets.bottom, 360);
    });

    test('réglage mémorisé (prochain lancement) ; « Relancer maintenant » l\'applique', () async {
      SharedPreferences.setMockInitialValues({});
      TailleEcranReglage.reinitialiser();
      await TailleEcranReglage.charger();
      expect(TailleEcranReglage.active.value, TailleEcran.automatique);
      await TailleEcranReglage.enregistrer(TailleEcran.tresCompact);
      expect(TailleEcranReglage.active.value, TailleEcran.automatique, reason: 'appliqué au prochain lancement');
      expect(TailleEcranReglage.enAttente, isTrue);
      await TailleEcranReglage.charger(); // nouveau lancement
      expect(TailleEcranReglage.active.value, TailleEcran.tresCompact);
      await TailleEcranReglage.enregistrer(TailleEcran.compact);
      TailleEcranReglage.appliquerMaintenant();
      expect(TailleEcranReglage.active.value, TailleEcran.compact);
      SharedPreferences.setMockInitialValues({TailleEcranReglage.cle: 'inconnue'});
      await TailleEcranReglage.charger();
      expect(TailleEcranReglage.active.value, TailleEcran.automatique, reason: 'valeur abîmée : défaut');
      TailleEcranReglage.reinitialiser();
    });
  });
}
