// Versement de la collecte hors ligne dans un inventaire ouvert : correspondance des codes (CIP, EAN,
// 34009 → CIP7), Remplacer / Ajouter pour les lignes déjà comptées, codes non reconnus dans le rapport,
// idempotence et reprise après coupure (aucun doublon, même en « Ajouter »), route qui enregistre
// l'auteur (et repli sur l'ancienne route), collecte marquée « versée » seulement après confirmation,
// rapport exporté (CSV / PDF) et partagé.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/collecte/rapport_versement.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/screens/collection_screen.dart';
import 'package:prestinv/screens/rapport_versement_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/faux_prestige_http.dart';

CollectedItem item(String code, int q, {int minute = 0}) => CollectedItem(code: code, quantity: q, dateScan: DateTime(2026, 10, 13, 9, minute));

/// Banc : inventaire INV1 avec 6 produits, dont un connu par EAN, un CIP7 français, un déjà compté.
Future<(Banc, MoteurVersement, List<Versement>)> banc({bool sansRoute = false}) async {
  final b = await preparerBanc(serveur: FauxPrestige(nombre: 3));
  ApiService.oublierRoutesAbsentes();
  b.serveur.sansRouteLigneQuantite = sansRoute;
  b.serveur.produits.addAll([
    FauxProduit(2001, '8050457', 'ABZ 200MG SUSP', 'R1', 11, ean: '3000000258453'),
    FauxProduit(2002, '3595583', 'DOLIPRANE 1000', 'R1', 20),
    FauxProduit(2003, '8438629', 'ABZ 400MG CPR', 'R2', 2, saisi: 6)..dtUpdated = '2026-10-13T08:55:00',
  ]);
  final enregistres = <Versement>[];
  final moteur = MoteurVersement(
    api: ApiService(baseUrl: b.config.currentApiUrl, cookie: () => b.auth.sessionCookie),
    queue: b.queue,
    auteur: 'admin',
    enregistrer: (v) async {
      enregistres.add(Versement.fromJson(json.decode(json.encode(v.toJson())) as Map<String, dynamic>));
      await StockageVersements.ecrire(v);
    },
    surLigneVersee: (l, v) => CollecteStore.marquerVersees(l.codes.toSet(), v.inventaireLibelle, DateTime(2026, 10, 13, 12)),
  );
  return (b, moteur, enregistres);
}

Versement nouveau(List<CollectedItem> c, ModeDejaCompte mode) =>
    Versement.depuisCollecte(c, inventaireId: 'INV1', inventaireLibelle: 'Inventaire test', mode: mode, maintenant: DateTime(2026, 10, 13, 10));

void main() {
  tearDown(() => ApiService.clientParDefaut = null);

  test('préparation : lignes non versées regroupées par code (quantités additionnées)', () {
    final v = nouveau([item('8050457', 2), item('8050457', 3), item(' 8438629 ', 1), item('X1', 9)..verseLe = DateTime(2026)], ModeDejaCompte.remplacer);
    expect(v.lignes.map((l) => (l.code, l.quantiteCollectee)), [('8050457', 5), ('8438629', 1)]);
  });

  test('correspondance : CIP identique, EAN-13 (serveur), EAN 34009 → CIP7 ; codes inconnus et partiels non reconnus', () async {
    final (b, moteur, _) = await banc();
    final v = nouveau([
      item('8050457', 4), // CIP identique
      item('3400935955838', 2), // EAN-13 français → CIP7 3595583
      item('3000000258453', 1), // EAN-13 local : trouvé par le serveur → même produit que 8050457
      item('9999999999999', 7), // inconnu
      item('805045', 3), // début de CIP seulement : refusé (pas de devinette)
    ], ModeDejaCompte.remplacer);
    final r = await moteur.executer(v);
    expect(r.statut, StatutVersement.termine);
    final parCode = {for (final l in r.lignes) l.code: l};
    expect(parCode['8050457']!.ligneId, 2001);
    expect(parCode['3400935955838']!.ligneId, 2002);
    expect(parCode['3000000258453']!.etat, EtatLigneVersement.regroupee, reason: 'même produit que 8050457');
    expect(parCode['8050457']!.quantiteCollectee, 5, reason: '4 (CIP) + 1 (EAN)');
    expect(parCode['9999999999999']!.etat, EtatLigneVersement.nonReconnue);
    expect(parCode['9999999999999']!.raison, 'introuvable dans cet inventaire');
    expect(parCode['805045']!.etat, EtatLigneVersement.nonReconnue);
    expect(parCode['805045']!.raison, contains('partielle'));
    expect(b.serveur.produit(2001).saisi, 5);
    expect(b.serveur.produit(2002).saisi, 2);
    expect(r.nonReconnues.map((l) => (l.code, l.quantiteCollectee)), [('9999999999999', 7), ('805045', 3)]);
  });

  test('Remplacer : la ligne déjà comptée reçoit la quantité collectée', () async {
    final (b, moteur, _) = await banc();
    final r = await moteur.executer(nouveau([item('8438629', 4), item('8050457', 2)], ModeDejaCompte.remplacer));
    expect(b.serveur.produit(2003).saisi, 4);
    expect(r.remplacees.single.quantiteExistante, 6);
    expect(r.nouvelles.single.cip, '8050457');
    expect(r.ajoutees, isEmpty);
  });

  test('Ajouter : déjà compté (serveur) + collecté ; une saisie en attente sur l\'appareil compte aussi', () async {
    final (b, moteur, _) = await banc();
    // Saisie manuelle encore sur l'appareil pour 8050457 : 3.
    await b.queue.enregistrer(inventaireId: 'INV1', ligneId: 2001, quantite: 3, cip: '8050457');
    final r = await moteur.executer(nouveau([item('8438629', 4), item('8050457', 2)], ModeDejaCompte.ajouter));
    expect(b.serveur.produit(2003).saisi, 10, reason: '6 + 4');
    expect(b.serveur.produit(2001).saisi, 5, reason: '3 (sur l\'appareil) + 2');
    expect(r.ajoutees.length, 2);
    expect(r.remplacees, isEmpty);
  });

  test('envoi par la route qui enregistre l\'auteur (POST /inventaire/ligne/quantite), via la file persistante', () async {
    final (b, moteur, _) = await banc();
    await moteur.executer(nouveau([item('8050457', 2)], ModeDejaCompte.remplacer));
    expect(b.serveur.postsQuantite, [(2001, 2)]);
    expect(b.serveur.puts, isEmpty);
    expect(b.serveur.produit(2001).auteur, 'admin');
    final s = b.disque.saisies.single;
    expect(s.origine, OrigineSaisie.versement);
    expect(s.envoyee, isTrue);
  });

  test('serveur sans la route « avec auteur » (404) : repli sur la route habituelle', () async {
    final (b, moteur, _) = await banc(sansRoute: true);
    final r = await moteur.executer(nouveau([item('8050457', 2), item('3595583', 1)], ModeDejaCompte.remplacer));
    expect(r.versees.length, 2);
    expect(b.serveur.puts, [(2001, 2), (2002, 1)]);
    expect(b.serveur.appels.where((a) => a == 'POST quantite').length, 1, reason: 'route absente mémorisée : un seul essai');
  });

  test('coupure réseau au milieu : interrompu, ce qui est envoyé reste envoyé ; reprise sans doublon (Ajouter)', () async {
    final (b, moteur, _) = await banc();
    final v = nouveau([item('8050457', 2), item('8438629', 4), item('3595583', 1)], ModeDejaCompte.ajouter);
    // Le 2ᵉ envoi tombe en panne réseau.
    var n = 0;
    b.serveur.codes.remove('quantite');
    final client = b.serveur.client;
    ApiService.clientParDefaut = MockClientPanne(client, () => ++n == 2);
    final r1 = await moteur.executer(v);
    expect(r1.statut, StatutVersement.interrompu);
    expect(r1.interruption, isNotNull);
    expect(r1.versees.length, 1);
    expect(b.serveur.produit(2001).saisi, 2);
    expect(b.serveur.produit(2003).saisi, 6, reason: 'pas encore envoyé');
    final ligne2003 = r1.lignes.firstWhere((l) => l.ligneId == 2003);
    expect(ligne2003.quantiteCible, 10, reason: 'total calculé et gardé AVANT l\'envoi');
    expect(r1.complet, isFalse);

    // « Redémarrage » : versement relu du stockage, nouvelle file sur le même disque.
    ApiService.clientParDefaut = client;
    final relu = (await StockageVersements.aReprendre())!;
    expect(relu.id, v.id);
    final q2 = SaisieQueue(store: b.disque)..serveurFactory = b.queue.serveurFactory;
    await q2.load();
    final m2 = MoteurVersement(api: moteur.api, queue: q2, auteur: 'admin');
    final r2 = await m2.executer(relu);
    expect(r2.statut, StatutVersement.termine);
    expect(r2.versees.length, 3);
    expect(b.serveur.produit(2003).saisi, 10, reason: '6 + 4 une seule fois (pas 14)');
    expect(b.serveur.produit(2001).saisi, 2, reason: 'déjà versé : pas renvoyé ni rajouté');
    expect(b.serveur.postsQuantite.where((p) => p.$1 == 2001).length, 1);

    // Troisième passage (double appui sur « Reprendre ») : rien n'est renvoyé.
    final avant = b.serveur.postsQuantite.length;
    await m2.executer(r2);
    expect(b.serveur.postsQuantite.length, avant);
  });

  test('coupure juste APRÈS l\'envoi (confirmé par le serveur, versement non noté) : rien n\'est renvoyé ni rajouté', () async {
    final (b, moteur, enregistres) = await banc();
    final v = nouveau([item('8438629', 4)], ModeDejaCompte.ajouter);
    await moteur.executer(v);
    expect(b.serveur.produit(2003).saisi, 10);
    // État enregistré juste avant la confirmation (total calculé, ligne pas encore marquée « versée »).
    final avantConfirmation = enregistres.lastWhere((x) => x.lignes.single.quantiteCible != null && x.lignes.single.etat == EtatLigneVersement.aVerser);
    final r = await moteur.executer(avantConfirmation);
    expect(r.versees.length, 1);
    expect(b.serveur.produit(2003).saisi, 10, reason: 'toujours 10, pas 14');
    expect(b.serveur.postsQuantite.length, 1, reason: 'aucun renvoi');
  });

  test('annulation : la ligne en cours se termine, le reste attend une reprise', () async {
    final (b, moteur, _) = await banc();
    final v = nouveau([item('8050457', 2), item('8438629', 4), item('3595583', 1)], ModeDejaCompte.remplacer);
    // « Arrêter » pendant l'envoi de la 2ᵉ ligne.
    final r = await moteur.executer(v, onAvancement: (a) {
      if (a.fait == 1) moteur.annuler();
    });
    expect(r.statut, StatutVersement.interrompu);
    expect(r.versees.length, 2, reason: 'la ligne en cours se termine');
    expect(r.aVerser.length, 1);
    expect(b.serveur.postsQuantite.length, 2);
    final r2 = await moteur.executer(r);
    expect(r2.versees.length, 3);
    expect(b.serveur.postsQuantite.length, 3, reason: 'rien n\'est renvoyé deux fois');
  });

  test('inventaire clôturé pendant le versement : lignes en erreur (à reverser), rien d\'envoyé', () async {
    final (b, moteur, _) = await banc();
    b.serveur.inventaires = {'AUTRE': 'Autre'};
    final r = await moteur.executer(nouveau([item('8050457', 2)], ModeDejaCompte.remplacer));
    expect(r.erreurs.single.raison, contains('clôturé'));
    expect(b.serveur.postsQuantite, isEmpty);
    expect(r.complet, isFalse);
  });

  test('collecte marquée « versée » seulement pour les lignes confirmées ; non reconnues et erreurs restent', () async {
    final (b, moteur, _) = await banc();
    await CollecteStore.ecrire([item('8050457', 2), item('9999999999999', 7), item('8438629', 1)]);
    b.serveur.codes.remove('quantite');
    var n = 0;
    ApiService.clientParDefaut = MockClientPanne(b.serveur.client, () => ++n == 2); // 2ᵉ envoi en panne
    final v = Versement.depuisCollecte(await CollecteStore.lire(), inventaireId: 'INV1', inventaireLibelle: 'Inventaire test', mode: ModeDejaCompte.remplacer);
    await moteur.executer(v);
    final apres = {for (final i in await CollecteStore.lire()) i.code: i};
    expect(apres['8050457']!.versee, isTrue);
    expect(apres['8050457']!.verseDans, 'Inventaire test');
    expect(apres['9999999999999']!.versee, isFalse, reason: 'non reconnu : reste dans la collecte');
    expect(apres['8438629']!.versee, isFalse, reason: 'en erreur : reste à reverser');
  });

  test('rapport : compteurs, codes non reconnus (code, quantité, raison) dans le CSV ; PDF généré', () async {
    final (_, moteur, _) = await banc();
    final r = await moteur.executer(nouveau([item('8050457', 2), item('8438629', 4), item('9999999999999', 7)], ModeDejaCompte.remplacer));
    final csv = rapportCsv(r);
    expect(csv, contains('Inventaire;Inventaire test'));
    expect(csv, contains('Code;Quantité collectée;Résultat;CIP;Produit;Déjà compté;Quantité envoyée;Raison'));
    expect(csv, contains('9999999999999;7;Code non reconnu;;;;;introuvable dans cet inventaire'));
    expect(csv, contains('8438629;4;Déjà compté — remplacé;8438629;ABZ 400MG CPR;6;4;'));
    expect(csv, contains('8050457;2;Versé;8050457;ABZ 200MG SUSP;;2;'));
    final resume = resumeVersement(r);
    expect(resume, contains('Versés : 1'));
    expect(resume, contains('Déjà comptés remplacés : 1'));
    expect(resume, contains('Non reconnus : 1'));
    final pdf = await rapportPdf(r);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(pdf.length, greaterThan(1000));
  });

  testWidgets('parcours écran : Collecte → Verser → inventaire → Remplacer/Ajouter → rapport (non reconnus) → export', (tester) async {
    ecranTerminal(tester);
    reinitialiserDouchette();
    installerFauxRetour();
    final b = await preparerBanc(serveur: FauxPrestige(nombre: 3));
    b.serveur.produits.add(FauxProduit(2003, '8438629', 'ABZ 400MG CPR', 'R2', 2, saisi: 6)..dtUpdated = '2026-10-13T08:55:00');
    await CollecteStore.ecrire([item('8438629', 4), item('9999999999999', 7, minute: 1), item(b.serveur.produits[0].cip, 2, minute: 2)]);
    final partages = <List<String>>[];
    final dossier = (await tester.runAsync(() => Directory.systemTemp.createTemp('prestinv_rapport_')))!;
    RapportVersementScreen.dossierExport = () async => dossier;
    RapportVersementScreen.partager = (fichiers, texte) async => partages.add(fichiers.map((f) => f.path).toList());

    await tester.pumpWidget(monter(b, const CollectionScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('verser-collecte')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 ligne(s) à verser'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('versement-inv-INV1')));
    await tester.pumpAndSettle();
    expect(find.text('Verser la collecte'), findsWidgets);
    // Réglage Cumul désactivé → « Remplacer » proposé ; on choisit « Ajouter ».
    await tester.tap(find.byKey(const ValueKey('mode-ajouter')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirmer-versement')));
    await tester.pumpAndSettle();

    expect(find.text('Rapport de versement'), findsOneWidget);
    expect(find.byKey(const ValueKey('section-non-reconnus')), findsOneWidget);
    expect(find.textContaining('code 9999999999999 · collecté 7 · introuvable dans cet inventaire'), findsOneWidget);
    expect(b.serveur.produit(2003).saisi, 10);
    expect(b.serveur.produits[0].saisi, 2);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('partager-rapport')));
      for (var i = 0; i < 50 && partages.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();
    expect(partages.single.map((p) => p.split('.').last), ['pdf', 'csv']);
    final csv = (await tester.runAsync(() => File(partages.single.last).readAsString()))!;
    expect(csv, contains('9999999999999;7;Code non reconnu'));

    // Retour à la collecte : lignes versées cochées, le code inconnu reste à verser.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('✓ versé le'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('bandeau-collecte-versee')), findsNothing);
    await tester.runAsync(() => dossier.delete(recursive: true));
    await demonter(tester);
  });
}

/// Client HTTP qui simule une coupure réseau sur les envois de quantité quand [panne] répond vrai.
class MockClientPanne extends BaseClientDelegue {
  final bool Function() panne;
  MockClientPanne(super.interne, this.panne);

  @override
  bool coupe(Uri url, String methode) => methode == 'POST' && url.path.endsWith('/quantite') && panne();
}
