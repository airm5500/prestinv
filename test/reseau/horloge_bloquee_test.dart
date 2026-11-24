// RÉSEAU — 5.0.4 : HEURE DU SERVEUR FAUSSE (serveur Prestige, plan du 24/11). Tant que l'heure du serveur est fausse, il
// refuse TOUTE écriture (POST / PUT / DELETE / PATCH, sauf connexion / déconnexion / routes de l'horloge) : HTTP 423
// {"success":false,"horlogeBloquee":true,"msg":"Opération refusée : l'heure du serveur est fausse. …"} ; les lectures
// restent permises. Avant 5.0.4 : 423 = 4xx JSON → la saisie passait en « refusée » (jamais renvoyée seule).
//
// Contre un vrai serveur HTTP local (faux serveur Prestige, données fictives) :
//  - chaque type d'écriture (PUT ws/inventaires/details, POST inventaire/ligne/quantite, versement en lot, création
//    d'inventaire, produits retenus, licence) : message du serveur TEL QUEL, jamais « serveur injoignable », « réseau »,
//    « erreur inconnue » ;
//  - file des saisies : la saisie RESTE en attente (jamais « refusée », jamais perdue, fichier local compris), bandeau
//    « N saisies en attente d'envoi. <message du serveur> » ; quand l'heure est remise, envoyée seule, dans l'ordre,
//    SANS doublon (quantité totale) ; versement en lot : lot gardé, MÊME clé, jamais compté deux fois ;
//  - pas de boucle : reprise automatique espacée (15 s, 30 s, 1 min, 2 min au plus), un envoi groupé s'arrête au
//    premier refus ;
//  - saisie classée « refusée » par ce refus en 5.0.3 : remise en attente au chargement ;
//  - GET horloge/public (écran de connexion) : BLOQUE → bandeau ; OK / REGULARISATION / 404 / autre → rien ;
//  - journal : jamais le message ni une quantité.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_correction.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:prestinv/widgets/bandeau_horloge_serveur.dart';

import '../helpers/banc_essai.dart' show DisqueMemoire;
import '../support/faux_serveur_prestige.dart';

/// Message du serveur (forme exacte de HorlogeBlocageFilter, plan du 24/11).
const _msg = 'Opération refusée : l\'heure du serveur est fausse. Faites « Mettre à jour » ou appelez '
    'l\'administrateur pour remettre l\'heure dans Windows.';

ReponseScriptee _refus423() => ReponseScriptee.json({'success': false, 'horlogeBloquee': true, 'msg': _msg}, code: 423);

const _interdits = ['injoignable', 'réseau', 'inconnue', 'Erreur du serveur', 'Réponse non reconnue'];

void main() {
  late FauxServeurPrestige serveur;
  late String base;
  late DisqueMemoire disque;
  late List<int> ids;
  final journalLignes = <String>[];
  final debugPrintOrigine = debugPrint;

  setUpAll(() => HttpOverrides.global = null);
  setUp(() async {
    ApiService.clientParDefaut = null;
    ApiService.oublierRoutesAbsentes();
    serveur = FauxServeurPrestige(exigerSession: false);
    base = await serveur.demarrer();
    disque = DisqueMemoire();
    ids = [for (final p in serveur.catalogue.produits) p.id];
    journalLignes.clear();
    debugPrint = (String? m, {int? wrapWidth}) => journalLignes.add(m ?? '');
  });
  tearDown(() async {
    debugPrint = debugPrintOrigine;
    await serveur.arreter();
  });

  Future<SaisieQueue> ouvrir({bool direct = true, SaisieStore? store}) async {
    final q = SaisieQueue(store: store ?? disque)
      ..serveurFactory = (() => ApiService(baseUrl: base))
      ..modeDirect = () => direct;
    await q.load();
    return q;
  }

  Future<void> saisir(SaisieQueue q, int id, int quantite) => q.enregistrer(inventaireId: 'INV1', ligneId: id, quantite: quantite);

  void jamaisEnPanne(String? message, {String reason = ''}) {
    for (final mot in _interdits) {
      expect(message, isNot(contains(mot)), reason: '$reason : jamais présenté comme « $mot »');
    }
  }

  void journalSansMessage() {
    final tout = journalLignes.join('\n');
    expect(tout, isNot(contains('heure du serveur est fausse.')), reason: 'le message n\'est pas journalisé');
    expect(tout, isNot(contains('Windows')));
  }

  group('PUT /ws/inventaires/details (file des saisies, mode Direct) : 423 → gardée en attente', () {
    test('gardée à chaque essai (jamais « refusée »), bandeau = message du serveur, puis envoyée sans doublon', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 7);
      await saisir(q, ids[1], 3);
      serveur.scripter('details', _refus423(), methode: 'PUT');
      for (var essai = 1; essai <= 3; essai++) {
        final b = await q.envoyer();
        expect(b.envoyees, 0, reason: 'essai $essai');
        expect(b.refusees, 0, reason: 'essai $essai : jamais « refusée »');
        expect(b.interruption, _msg, reason: 'essai $essai : message du serveur tel quel');
        expect(q.enAttente(), 2, reason: 'essai $essai : rien ne sort de la file');
        expect(q.refusees(), 0);
      }
      expect(serveur.recues('details', methode: 'PUT'), hasLength(3), reason: 'un envoi groupé s\'arrête au premier refus');
      expect(q.horlogeServeurBloquee, isTrue);
      expect(q.serveurInjoignable, isFalse, reason: 'le serveur a répondu : ce n\'est pas une panne');
      expect(q.messageAttenteServeur, '2 saisies en attente d\'envoi. $_msg');
      expect(q.derniereErreur, _msg);
      jamaisEnPanne(q.messageAttenteServeur, reason: 'bandeau');
      expect(disque.saisies.where((s) => s.enAttente), hasLength(2), reason: 'toujours dans le stockage local');
      expect(serveur.catalogue.puts, isEmpty);
      journalSansMessage();

      // La saisie continue pendant le blocage : dernière valeur gagnante (quantité totale).
      await saisir(q, ids[0], 8);
      serveur.oublierScripts(); // l'administrateur a remis l'heure
      await q.relancer();
      expect(q.enAttente(), 0);
      expect(q.refusees(), 0);
      expect(q.messageAttenteServeur, isNull, reason: 'bandeau retiré');
      expect(q.horlogeServeurBloquee, isFalse);
      expect(serveur.catalogue.puts, [(ids[1], 3), (ids[0], 8)], reason: 'ordre de saisie, une pose chacune');
      await q.relancer();
      expect(serveur.catalogue.puts, hasLength(2), reason: 'aucun doublon');
    });

    test('1 saisie : « 1 saisie en attente d\'envoi. » + message', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 2);
      serveur.scripter('details', _refus423(), methode: 'PUT');
      final r = await q.envoyerLigne('INV1', ids[0]);
      expect(r.type, ResultatEnvoi.horlogeBloquee);
      expect(r.message, _msg);
      expect(q.ligne('INV1', ids[0])!.enAttente, isTrue);
      expect(q.ligne('INV1', ids[0])!.motif, _msg, reason: 'visible dans « À envoyer » : « En attente (message) »');
      expect(q.messageAttenteServeur, '1 saisie en attente d\'envoi. $_msg');
    });

    test('423 sans corps lisible : même traitement, message par défaut', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 2);
      serveur.scripter('details', ReponseScriptee.code(423), methode: 'PUT');
      final r = await q.envoyerLigne('INV1', ids[0]);
      expect(r.type, ResultatEnvoi.horlogeBloquee);
      expect(r.message, ApiService.messageHorlogeParDefaut);
      expect(q.enAttente(), 1);
      expect(q.refusees(), 0);
    });

    test('les lectures restent permises : la liste des inventaires ouverts est lue (aucun « inventaire clôturé »)', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 2);
      serveur.scripter('details', _refus423(), methode: 'PUT');
      await q.envoyer();
      expect(serveur.recues('ws/inventaires', methode: 'GET'), isNotEmpty);
      expect(q.refusees(), 0);
    });

    test('redémarrage pendant le blocage : la saisie est relue en attente (fichier saisies_v1.jsonl), puis envoyée une fois', () async {
      final dossier = await Directory.systemTemp.createTemp('prestinv_504_');
      addTearDown(() => dossier.delete(recursive: true));
      final fichier = File('${dossier.path}/saisies_v1.jsonl');
      final q = await ouvrir(store: FichierSaisieStore(fichier));
      await saisir(q, ids[0], 5);
      await saisir(q, ids[2], 1);
      serveur.scripter('details', _refus423(), methode: 'PUT');
      await q.envoyer();
      q.dispose();
      final relue = await ouvrir(store: FichierSaisieStore(fichier));
      expect(relue.enAttente(), 2);
      expect(relue.refusees(), 0);
      serveur.oublierScripts();
      await relue.relancer();
      expect(relue.enAttente(), 0);
      expect(serveur.catalogue.puts, [(ids[0], 5), (ids[2], 1)]);
    });

    test('pas de boucle : reprise automatique espacée (15 s, 30 s, 1 min, puis 2 min au plus)', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 4);
      serveur.scripter('details', _refus423(), methode: 'PUT');
      // 40 tours de 15 s = 10 minutes : sans espacement il y aurait 40 essais.
      for (var tour = 0; tour < 40; tour++) {
        await q.repriseAutomatique();
      }
      final essais = serveur.recues('details', methode: 'PUT').length;
      expect(essais, lessThanOrEqualTo(8), reason: 'espacement : $essais essais en 10 minutes');
      expect(essais, greaterThanOrEqualTo(4), reason: 'mais l\'envoi est bien retenté seul');
      expect(q.toursAvantRelance, lessThanOrEqualTo(SaisieQueue.plafondIntervallesReprise - 1));
      expect(q.enAttente(), 1);
      // L'heure est remise : au plus 2 minutes plus tard, la saisie part seule, une fois.
      serveur.oublierScripts();
      for (var tour = 0; tour < SaisieQueue.plafondIntervallesReprise; tour++) {
        await q.repriseAutomatique();
      }
      expect(q.enAttente(), 0);
      expect(serveur.catalogue.puts, [(ids[0], 4)]);
      expect(q.toursAvantRelance, 0, reason: 'espacement remis à zéro');
    });

    test('mode Collecte (manuel) : « Envoyer » refusé → gardées, l\'envoi demandé reprend seul ensuite', () async {
      final q = await ouvrir(direct: false);
      await saisir(q, ids[0], 1);
      await saisir(q, ids[1], 2);
      serveur.scripter('details', _refus423(), methode: 'PUT');
      final b = await q.envoyer(inventaireId: 'INV1');
      expect(b.interruption, _msg);
      expect(q.enAttente(), 2);
      expect(q.envoiARependre, 'INV1');
      serveur.oublierScripts();
      await q.relancer();
      expect(q.enAttente(), 0);
      expect(serveur.catalogue.puts, [(ids[0], 1), (ids[1], 2)]);
    });

    test('saisie classée « refusée » par ce refus en 5.0.3 : remise en attente au chargement, puis envoyée', () async {
      final ancienne = SaisieLigne(
        inventaireId: 'INV1',
        ligneId: ids[0],
        quantite: 6,
        creeLe: DateTime(2026, 11, 24, 20),
        modifieLe: DateTime(2026, 11, 24, 20),
      )
        ..etat = EtatSaisie.refusee
        ..motif = _msg;
      await disque.ecrire(ancienne);
      final q = await ouvrir();
      expect(q.refusees(), 0);
      expect(q.enAttente(), 1);
      await q.relancer();
      expect(serveur.catalogue.puts, [(ids[0], 6)]);
    });

    test('un vrai refus métier après le blocage reste « refusée » (aucun changement)', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 7);
      serveur.scripter('details', ReponseScriptee.json({'success': 0, 'code': 'LIGNE_INCONNUE', 'message': 'Ligne inconnue.'}, code: 404), methode: 'PUT');
      expect((await q.envoyer()).refusees, 1);
      expect(q.messageAttenteServeur, isNull);
    });

    test('corrections Écarts / Restants : message du serveur tel quel, gardée sur l\'appareil', () {
      final m = messageEchecCorrection(const ReponseEnvoi(ResultatEnvoi.horlogeBloquee, _msg));
      expect(m, startsWith(_msg));
      expect(m, contains('Gardée sur l\'appareil'));
      jamaisEnPanne(m, reason: 'correction');
    });
  });

  group('POST /inventaire/ligne/quantite (versement de la collecte, auteur)', () {
    test('423 : horloge bloquée, message tel quel, la route habituelle n\'est PAS essayée', () async {
      serveur.scripter('ligne/quantite', _refus423(), methode: 'POST');
      final r = await ApiService(baseUrl: base).poserQuantiteSession(ids[0], 6);
      expect(r.type, ResultatEnvoi.horlogeBloquee);
      expect(r.message, _msg);
      expect(serveur.recues('details', methode: 'PUT'), isEmpty, reason: 'pas de repli (ce n\'est pas une route absente)');
      expect(serveur.catalogue.postsQuantite, isEmpty);
      serveur.oublierScripts();
      expect((await ApiService(baseUrl: base).poserQuantiteSession(ids[0], 6)).type, ResultatEnvoi.ok, reason: 'route gardée');
      expect(serveur.recues('details', methode: 'PUT'), isEmpty);
      journalSansMessage();
    });

    test('versement de la collecte, produit par produit : interrompu avec le message, quantité gardée en file, reprise sans doublon', () async {
      final q = await ouvrir(direct: false);
      final etats = <Versement>[];
      final m = MoteurVersement(
        api: ApiService(baseUrl: base),
        queue: q,
        auteur: 'compte.fictif',
        enregistrer: (v) async => etats.add(Versement.fromJson(json.decode(json.encode(v.toJson())) as Map<String, dynamic>)),
      );
      final cip = serveur.catalogue.produits[0].cip;
      final v = Versement.depuisCollecte([CollectedItem(code: cip, quantity: 4, dateScan: DateTime(2026, 11, 24, 9))],
          inventaireId: 'INV1', inventaireLibelle: 'Inventaire fictif', mode: ModeDejaCompte.remplacer, maintenant: DateTime(2026, 11, 24, 10));
      serveur.scripter('ligne/quantite', _refus423(), methode: 'POST');
      final r = await m.executer(v);
      expect(r.statut, StatutVersement.interrompu);
      expect(r.interruption, _msg);
      expect(q.enAttente(), 1, reason: 'quantité gardée dans la file (renvoyée seule)');
      expect(q.refusees(), 0);
      serveur.oublierScripts();
      await q.relancer(); // la file renvoie seule la saisie (envoiAuto)
      expect(q.enAttente(), 0);
      expect(serveur.catalogue.postsQuantite, [(ids[0], 4)], reason: 'une seule pose');
    });
  });

  group('Versement en lot (POST /inventaire/{id}/versement) : 423 → lot gardé, même clé', () {
    setUp(() {
      serveur.serveurRecent = true;
      ApiService.noterServeur(base, recent: true);
    });

    test('refusé : rien d\'enregistré, renvoyé avec la même clé, jamais compté deux fois', () async {
      final api = ApiService(baseUrl: base);
      final lignes = [(serveur.catalogue.produits[0].cip, 2)];
      serveur.scripter('versement', _refus423(), methode: 'POST');
      final r = await api.verserLot('INV1', cle: 'V-FICTIF-H1', ajouter: true, lignes: lignes);
      expect(r.issue, IssueVersementLot.horlogeBloquee);
      expect(r.message, _msg);
      expect(serveur.catalogue.versementsLot, isEmpty);
      serveur.oublierScripts();
      final p = serveur.catalogue.produit(ids[0]);
      final attendu = p.dtUpdated != null ? p.saisi + 2 : 2;
      expect((await api.verserLot('INV1', cle: 'V-FICTIF-H1', ajouter: true, lignes: lignes, reprise: true)).issue, IssueVersementLot.traite);
      expect((await api.verserLot('INV1', cle: 'V-FICTIF-H1', ajouter: true, lignes: lignes, reprise: true)).dejaTraite, isTrue);
      expect(serveur.catalogue.produit(ids[0]).saisi, attendu, reason: 'ajout appliqué une seule fois');
    });

    test('moteur de versement : interrompu avec le message, lot en cours GARDÉ (même clé à la reprise)', () async {
      final q = await ouvrir(direct: false);
      final m = MoteurVersement(api: ApiService(baseUrl: base), queue: q, auteur: 'compte.fictif', enregistrer: (_) async {});
      final cip = serveur.catalogue.produits[0].cip;
      final v = Versement.depuisCollecte([CollectedItem(code: cip, quantity: 3, dateScan: DateTime(2026, 11, 24, 9))],
          inventaireId: 'INV1', inventaireLibelle: 'Inventaire fictif', mode: ModeDejaCompte.remplacer, maintenant: DateTime(2026, 11, 24, 10));
      serveur.scripter('versement', _refus423(), methode: 'POST');
      final r = await m.executer(v);
      expect(r.statut, StatutVersement.interrompu);
      expect(r.interruption, _msg);
      final cle = r.lotEnCours?['cle'];
      expect(cle, isNotNull, reason: 'lot gardé avec sa clé');
      serveur.oublierScripts();
      final r2 = await m.executer(r);
      expect(r2.statut, StatutVersement.termine);
      expect(serveur.catalogue.versementsLot.map((e) => e['cle']), [cle], reason: 'même clé, un seul versement');
      expect(serveur.catalogue.produit(ids[0]).saisi, 3);
    });
  });

  group('Autres écritures : message du serveur tel quel', () {
    test('création d\'inventaire : refus, message tel quel, rien de créé', () async {
      serveur.scripter('creation', _refus423(), methode: 'POST');
      final r = await ApiService(baseUrl: base).creerInventaire('Inventaire fictif', 'Emplacement');
      expect(r.message, _msg);
      expect(serveur.catalogue.creations, isEmpty);
    });

    test('produits retenus (inventaire limité aux produits scannés) : ApiLoadException avec le message', () async {
      serveur.scripter('lignes/retenue', _refus423(), methode: 'POST');
      await expectLater(ApiService(baseUrl: base).retenirProduits('INV1', ['FAM-FICTIF-1']),
          throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', _msg).having((e) => e.reseau, 'réseau', isFalse)));
    });

    test('enregistrement de la licence : message tel quel (pas « Exception: », pas « serveur injoignable »)', () async {
      serveur.scripter('licence/save/CLE-FICTIVE', _refus423(), methode: 'POST');
      await expectLater(ApiService(baseUrl: base).saveLicense('CLE-FICTIVE'), throwsA(predicate((e) => e.toString() == _msg)));
    });
  });

  group('GET /horloge/public (sans session) : bandeau de l\'écran de connexion', () {
    setUp(() async {
      await serveur.arreter();
      serveur = FauxServeurPrestige(); // session exigée partout ailleurs
      base = await serveur.demarrer();
    });

    test('BLOQUE → message avec l\'heure du serveur ; sans cookie', () async {
      serveur.scripter('horloge/public', ReponseScriptee.json({'etat': 'BLOQUE', 'serveur': '24/11/2026 20:52'}), methode: 'GET');
      final h = await HorlogePublique.lire(base);
      expect(h?.bloque, isTrue);
      expect(h!.message, 'L\'heure du serveur est fausse (heure du serveur : 24/11/2026 20:52) : le serveur refuse les enregistrements '
          'tant qu\'elle n\'est pas remise. Les saisies restent gardées sur l\'appareil.');
      expect(serveur.recues('horloge/public').single.cookie, isNull);
      expect(serveur.recues('horloge/public'), hasLength(1), reason: 'une seule lecture, aucune relance');
    });

    test('OK et REGULARISATION (écritures permises) → rien', () async {
      for (final etat in ['OK', 'REGULARISATION']) {
        serveur.scripter('horloge/public', ReponseScriptee.json({'etat': etat, 'serveur': '24/11/2026 20:52'}), methode: 'GET');
        final h = await HorlogePublique.lire(base);
        expect(h?.etat, etat);
        expect(h!.message, isNull, reason: etat);
      }
    });

    test('ancien serveur (404 HTML / JSON), 401, 500, page HTML, JSON inattendu, injoignable → rien (null)', () async {
      final cas = <String, ReponseScriptee>{
        '404 HTML': ReponseScriptee(code: 404, corps: '<html>404</html>', entetes: {'content-type': 'text/html'}),
        '404 JSON': ReponseScriptee.json({'success': false}, code: 404),
        '401': ReponseScriptee.code(401),
        '500': ReponseScriptee.code(500),
        '200 HTML': ReponseScriptee(code: 200, corps: '<html>portail</html>', entetes: {'content-type': 'text/html'}),
        '200 JSON sans etat': ReponseScriptee.json({'success': true}),
        '200 etat inconnu': ReponseScriptee.json({'etat': 'PEUT-ETRE'}),
        '200 liste': ReponseScriptee.json([]),
      };
      for (final e in cas.entries) {
        serveur.scripter('horloge/public', e.value, methode: 'GET');
        expect(await HorlogePublique.lire(base), isNull, reason: e.key);
      }
      serveur.oublierScripts();
      expect(await HorlogePublique.lire(base), isNull, reason: 'faux serveur sans la route (ancien serveur)');
      serveur.couper();
      expect(await HorlogePublique.lire(base), isNull, reason: 'injoignable');
      expect(await HorlogePublique.lire(''), isNull);
    });
  });
}
