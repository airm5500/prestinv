// RÉSEAU — 5.0.2 (demande du pharmacien) : SERVEUR QUI S'ÉTEINT PENDANT L'INVENTAIRE. Contre un vrai serveur HTTP
// local (faux serveur Prestige, données fictives) :
//  - 500 répétés (avant 5.0.2 : « refusée » après 3 essais, la relance s'arrêtait), 501, 502 / 503 / 504, délai
//    dépassé, relais (407), 408, 429, connexion coupée en pleine requête, serveur ARRÊTÉ (connexion refusée) :
//    chaque saisie RESTE « en attente » dans la file locale, aucune n'est « refusée » ;
//  - au retour du serveur la file se vide seule, dans l'ordre de saisie, dernière valeur, SANS doublon ;
//  - la file survit à un redémarrage de l'application pendant la panne ;
//  - relances espacées (15 s, 30 s, 1 min, 2 min au plus) tant que le serveur ne répond pas, remises à zéro au retour ;
//  - mode Collecte (manuel) : rien ne part sans « Envoyer » ; un envoi DEMANDÉ interrompu reprend seul ;
//  - refus MÉTIER (400 / 404 JSON / 409 / 422 avec message) : « refusée » tout de suite, comme avant ;
//  - bandeau « N saisies en attente d'envoi (serveur injoignable) ».
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';

import '../helpers/banc_essai.dart' show DisqueMemoire;
import '../support/faux_serveur_prestige.dart';

void main() {
  late FauxServeurPrestige serveur;
  late String base;
  late DisqueMemoire disque;
  late List<int> ids;

  setUpAll(() => HttpOverrides.global = null);
  setUp(() async {
    ApiService.clientParDefaut = null;
    ApiService.oublierRoutesAbsentes();
    serveur = FauxServeurPrestige(exigerSession: false);
    base = await serveur.demarrer();
    disque = DisqueMemoire();
    ids = [for (final p in serveur.catalogue.produits) p.id];
  });
  tearDown(() => serveur.arreter());

  /// File de l'application sur le disque [disque] (adresse lue à chaque envoi, comme main()).
  Future<SaisieQueue> ouvrir({bool direct = true}) async {
    final q = SaisieQueue(store: disque)
      ..serveurFactory = (() => ApiService(baseUrl: base))
      ..modeDirect = () => direct;
    await q.load();
    return q;
  }

  Future<void> saisir(SaisieQueue q, int id, int quantite) => q.enregistrer(inventaireId: 'INV1', ligneId: id, quantite: quantite);

  /// Quantités posées (PUT) sur le serveur, dans l'ordre.
  List<(int, int)> poses() => List.of(serveur.catalogue.puts);

  void sansDoublon() {
    final p = poses();
    expect(p.toSet().length, p.length, reason: 'aucune valeur posée deux fois : $p');
  }

  group('Panne du serveur : la saisie RESTE en attente, jamais « refusée »', () {
    final pannes = <String, ReponseScriptee Function()>{
      '500 (×6)': () => ReponseScriptee.code(500),
      '501': () => ReponseScriptee.code(501),
      '502': () => ReponseScriptee.code(502),
      '503': () => ReponseScriptee.code(503),
      '504': () => ReponseScriptee.code(504),
      '407 (relais / proxy)': () => ReponseScriptee.code(407),
      '408': () => ReponseScriptee.code(408),
      '429': () => ReponseScriptee.code(429),
      'connexion coupée en pleine requête': () => ReponseScriptee.coupee(),
    };
    for (final e in pannes.entries) {
      test('${e.key} : gardée en attente à chaque essai, puis envoyée au retour, sans doublon', () async {
        final q = await ouvrir();
        await saisir(q, ids[0], 7);
        await saisir(q, ids[1], 3);
        serveur.scripter('details', e.value(), methode: 'PUT');
        for (var essai = 1; essai <= 6; essai++) {
          final b = await q.envoyer();
          expect(b.refusees, 0, reason: 'essai $essai');
          expect(b.interruption, isNotNull, reason: 'essai $essai : envoi incomplet signalé');
          expect(q.enAttente(), 2, reason: 'essai $essai : rien ne sort de la file');
          expect(q.refusees(), 0, reason: 'essai $essai : jamais « refusée »');
        }
        expect(q.serveurInjoignable, isTrue);
        expect(q.messageAttenteServeur, '2 saisies en attente d\'envoi (serveur injoignable)');
        expect(poses(), isEmpty, reason: 'rien d\'appliqué sur le serveur pendant la panne');

        serveur.oublierScripts();
        final b = await q.envoyer();
        expect(b.complet, isTrue);
        expect(b.envoyees, 2);
        expect(q.enAttente(), 0);
        expect(q.messageAttenteServeur, isNull, reason: 'bandeau retiré au retour du serveur');
        expect(poses(), [(ids[0], 7), (ids[1], 3)], reason: 'ordre de saisie, une seule pose chacune');
      });
    }

    test('délai dépassé (TimeoutException) : gardée en attente, puis envoyée', () async {
      var panne = true;
      final client = MockClient((req) async {
        if (panne) throw TimeoutException('délai simulé');
        return http.Response('{"success":true}', 200);
      });
      // La liste des inventaires ouverts est lue sur le vrai serveur local : seule la pose de la quantité expire.
      final api = ApiService(baseUrl: base);
      final r = await ApiService(baseUrl: base, client: client).poserQuantite(ids[0], 4);
      expect(r.type, ResultatEnvoi.reseau);
      final q = SaisieQueue(store: disque)
        ..serveurFactory = (() => _ServeurMixte(api, ApiService(baseUrl: base, client: client)))
        ..modeDirect = () => true;
      await q.load();
      await saisir(q, ids[0], 4);
      for (var i = 0; i < 4; i++) {
        await q.envoyer();
        expect(q.ligne('INV1', ids[0])!.enAttente, isTrue);
      }
      panne = false;
      expect((await q.envoyer()).complet, isTrue);
      expect(q.ligne('INV1', ids[0])!.envoyee, isTrue);
    });

    test('serveur ARRÊTÉ (PC éteint : connexion refusée) puis redémarré : la file se vide seule', () async {
      final q = await ouvrir();
      for (var i = 0; i < 4; i++) {
        await saisir(q, ids[i], 10 + i);
      }
      await serveur.arreter();
      final b = await q.envoyer();
      expect(b.envoyees, 0);
      expect(b.interruption, contains('injoignable'));
      expect(q.enAttente(), 4);
      expect(q.messageAttenteServeur, '4 saisies en attente d\'envoi (serveur injoignable)');
      // Saisie qui continue pendant la panne (correction d'une ligne déjà saisie : dernière valeur gagnante).
      await saisir(q, ids[1], 99);
      await q.relancer();
      expect(q.enAttente(), 4);

      base = await serveur.demarrer(); // retour du serveur (nouveau port)
      await q.relancer(); // reprise automatique (mode Direct)
      expect(q.enAttente(), 0);
      expect(q.refusees(), 0);
      for (final (i, attendu) in [(0, 10), (1, 99), (2, 12), (3, 13)]) {
        expect(serveur.catalogue.produit(ids[i]).saisi, attendu, reason: 'ligne ${ids[i]}');
      }
      sansDoublon();
    });
  });

  test('500 puis redémarrage de l\'application pendant la panne : rien de perdu, envoyé au retour', () async {
    final q = await ouvrir();
    await saisir(q, ids[0], 5);
    await saisir(q, ids[1], 6);
    serveur.scripter('details', ReponseScriptee.code(500), methode: 'PUT');
    for (var i = 0; i < 4; i++) {
      await q.envoyer();
    }
    q.dispose();

    final apres = await ouvrir(); // même disque : l'application redémarre
    expect(apres.enAttente(), 2);
    expect(apres.refusees(), 0);
    serveur.oublierScripts();
    await apres.relancer();
    expect(apres.enAttente(), 0);
    expect(poses(), [(ids[0], 5), (ids[1], 6)]);
  });

  test('saisies « refusées » par une erreur 5xx d\'une version précédente : remises en attente au chargement', () async {
    final ancienne = SaisieLigne(
      inventaireId: 'INV1',
      ligneId: ids[0],
      quantite: 8,
      etat: EtatSaisie.refusee,
      motif: 'Erreur du serveur (code 500).',
      tentatives: 3,
      creeLe: DateTime(2026, 11, 20, 9),
      modifieLe: DateTime(2026, 11, 20, 9),
    );
    final metier = SaisieLigne(
      inventaireId: 'INV1',
      ligneId: ids[1],
      quantite: 2,
      etat: EtatSaisie.refusee,
      motif: 'Quantité refusée par le serveur (invalide).',
      creeLe: DateTime(2026, 11, 20, 9, 1),
      modifieLe: DateTime(2026, 11, 20, 9, 1),
    );
    await disque.ecrire(ancienne);
    await disque.ecrire(metier);
    final q = await ouvrir();
    expect(q.ligne('INV1', ids[0])!.enAttente, isTrue, reason: 'erreur du serveur : pas un refus');
    expect(q.ligne('INV1', ids[1])!.refusee, isTrue, reason: 'refus métier : gardé tel quel');
    await q.relancer();
    expect(serveur.catalogue.produit(ids[0]).saisi, 8);
    expect(poses(), [(ids[0], 8)], reason: 'le refus métier n\'est jamais renvoyé seul');
  });

  group('Refus MÉTIER du serveur (4xx explicite) : « refusée » tout de suite, comme avant', () {
    final refus = <String, ReponseScriptee>{
      '400': ReponseScriptee.json({'success': 0, 'message': 'Quantité invalide.'}, code: 400),
      '404 JSON (ligne inconnue)': ReponseScriptee.json({'success': 0, 'code': 'LIGNE_INCONNUE', 'message': 'Ligne inconnue.'}, code: 404),
      '409': ReponseScriptee.json({'success': 0, 'message': 'Inventaire clôturé.'}, code: 409),
      '422': ReponseScriptee.json({'success': 0, 'message': 'Quantité hors limites.'}, code: 422),
    };
    for (final e in refus.entries) {
      test(e.key, () async {
        final q = await ouvrir();
        await saisir(q, ids[0], 7);
        serveur.scripter('details', e.value, methode: 'PUT');
        final b = await q.envoyer();
        expect(b.refusees, 1);
        expect(q.ligne('INV1', ids[0])!.refusee, isTrue);
        expect(q.messageAttenteServeur, isNull, reason: 'le serveur a répondu : pas « injoignable »');
        final n = serveur.recues('details', methode: 'PUT').length;
        await q.relancer();
        expect(serveur.recues('details', methode: 'PUT').length, n, reason: 'jamais renvoyée seule');
      });
    }
  });

  test('une erreur 500 sur UNE ligne ne bloque pas les suivantes ; deux de suite interrompent l\'envoi', () async {
    final q = await ouvrir();
    for (var i = 0; i < 4; i++) {
      await saisir(q, ids[i], 20 + i);
    }
    serveur.scripter('details', ReponseScriptee.code(500, fois: 1), methode: 'PUT');
    final b = await q.envoyer();
    expect(b.envoyees, 3);
    expect(b.refusees, 0);
    expect(b.interruption, contains('Erreur du serveur'));
    expect(q.ligne('INV1', ids[0])!.enAttente, isTrue);
    expect(q.ligne('INV1', ids[0])!.motif, contains('500'));
    expect((await q.envoyer()).complet, isTrue);
    expect(q.ligne('INV1', ids[0])!.motif, isNull);

    // Serveur qui s'arrête (500 partout) : on n'insiste pas, deux essais puis interruption.
    for (var i = 0; i < 4; i++) {
      await saisir(q, ids[i], 40 + i);
    }
    serveur.scripter('details', ReponseScriptee.code(500), methode: 'PUT');
    final avant = serveur.recues('details', methode: 'PUT').length;
    final b2 = await q.envoyer();
    expect(serveur.recues('details', methode: 'PUT').length - avant, SaisieQueue.erreursServeurAvantInterruption);
    expect(b2.restantes, 4);
    serveur.oublierScripts();
    await q.envoyer();
    expect(q.enAttente(), 0);
    sansDoublon();
  });

  test('reprise automatique espacée (15 s, 30 s, 1 min, 2 min) pendant la panne, immédiate au retour', () async {
    final q = await ouvrir();
    await saisir(q, ids[0], 3);
    serveur.couper();
    final essais = <int>[];
    for (var tour = 1; tour <= 24; tour++) {
      await q.repriseAutomatique();
      essais.add(q.toursAvantRelance);
    }
    // Après 1, 2, 3, 4… échecs : 0, 1, 3, 7 tours sautés (15 s, 30 s, 1 min, 2 min), plafond 7.
    expect(essais.take(12).toList(), [0, 1, 0, 3, 2, 1, 0, 7, 6, 5, 4, 3]);
    expect(essais.reduce((a, b) => a > b ? a : b), SaisieQueue.plafondIntervallesReprise - 1);
    expect(q.enAttente(), 1);

    serveur.retablir();
    // Au plus 8 tours (2 min) après le retour, la file est vide ; l'espacement est remis à zéro.
    var tours = 0;
    while (q.enAttente() > 0 && tours < SaisieQueue.plafondIntervallesReprise) {
      await q.repriseAutomatique();
      tours++;
    }
    expect(q.enAttente(), 0, reason: 'envoyée au plus 2 min après le retour du serveur');
    expect(q.toursAvantRelance, 0);
    expect(poses(), [(ids[0], 3)]);
  });

  test('mode Collecte (manuel) : rien ne part seul ; un envoi DEMANDÉ interrompu par la panne reprend seul', () async {
    final q = await ouvrir(direct: false);
    await saisir(q, ids[0], 1);
    await saisir(q, ids[1], 2);
    await q.relancer();
    expect(poses(), isEmpty, reason: 'mode manuel : pas d\'envoi sans « Envoyer »');

    serveur.scripter('details', ReponseScriptee.code(503), methode: 'PUT');
    final b = await q.envoyer(inventaireId: 'INV1'); // « Envoyer » pendant la panne
    expect(b.envoyees, 0);
    expect(q.enAttente(), 2);
    expect(q.envoiARependre, 'INV1');

    serveur.oublierScripts();
    await q.relancer(); // reprise automatique : l'envoi demandé repart seul
    expect(q.enAttente(), 0);
    expect(q.envoiARependre, isNull);
    expect(poses(), [(ids[0], 1), (ids[1], 2)]);

    // Après l'envoi complet, le mode manuel est de nouveau respecté.
    await saisir(q, ids[2], 9);
    await q.relancer();
    expect(q.enAttente(), 1);
  });
}

/// Liste des inventaires ouverts lue sur [lecture], quantités posées par [pose] (délai simulé).
class _ServeurMixte implements SaisieServeur {
  final ApiService lecture;
  final ApiService pose;
  _ServeurMixte(this.lecture, this.pose);

  @override
  Future<InventairesOuverts?> inventairesOuverts() => lecture.inventairesOuverts();

  @override
  Future<ReponseEnvoi> poserQuantite(int ligneId, int quantite) => pose.poserQuantite(ligneId, quantite);

  @override
  Future<ReponseEnvoi> poserQuantiteSession(int ligneId, int quantite) => pose.poserQuantiteSession(ligneId, quantite);
}
