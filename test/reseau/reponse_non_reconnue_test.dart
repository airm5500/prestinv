// RÉSEAU — 5.0.3 : RÉPONSE QUI N'EST PAS CELLE DU SERVEUR PRESTIGE (portail captif, relais, box, autre service à la
// même adresse). Défaut constaté en 5.0.2 : tout 2xx sur l'envoi des quantités (PUT /ws/inventaires/details) comptait
// comme un succès, même une page HTML → la saisie sortait de la file locale sans être arrivée (perte silencieuse).
//
// Contre un vrai serveur HTTP local (faux serveur Prestige, données fictives) :
//  - 200 HTML, 200 HTML sans type annoncé, 200 texte, 200 JSON inattendu (objet sans `success`, liste), 200 JSON
//    `success:1` d'une AUTRE ligne, 302 vers une page de connexion, 400 HTML, 201 vide : la saisie RESTE en attente
//    (classée « serveur injoignable », jamais « refusée »), bandeau, rien n'est appliqué ; au retour du vrai serveur la
//    file se vide seule, dans l'ordre de saisie, SANS doublon ;
//  - 200 vide (réponse réelle de Prestige), 204, 200 JSON {success:1, id, quantite} : succès ;
//  - JSON `success:false` avec message : « refusée » (session si « Veuillez vous connecter ») ;
//  - route « avec auteur » (versement de la collecte) : même vérification ; `success:0` + message : refusée comme avant ;
//  - versement en lot : réponse non reconnue → lot GARDÉ (même clé), jamais l'ancien chemin ni une perte ;
//  - lectures : une page HTML n'est jamais une liste vide (aucun cache effacé) ;
//  - mode Collecte (manuel) inchangé ;
//  - journal : seulement « réponse non reconnue (code, type, taille) », jamais le contenu reçu ni un scan GS1 brut.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/saisie/saisie_store.dart';

import '../helpers/banc_essai.dart' show DisqueMemoire;
import '../support/faux_serveur_prestige.dart';

/// Contenu d'une page de portail captif FICTIVE : marqueurs qui ne doivent JAMAIS se retrouver dans le journal, les
/// messages, ni le fichier des saisies (dont un scan GS1 brut fictif).
const _marqueur = 'PORTAIL-FICTIF-7Q2';
const _gs1Brut = '0103400930000001172712311OLOT-FICTIF';
const _pageHtml = '<!DOCTYPE html><html><head><title>Wi-Fi invités</title></head>'
    '<body><form action="/login">$_marqueur $_gs1Brut <input name="password"></form></body></html>';

ReponseScriptee _html({int code = 200, String type = 'text/html; charset=utf-8', String corps = _pageHtml}) =>
    ReponseScriptee(code: code, corps: corps, entetes: {'content-type': type});

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

  List<(int, int)> poses() => List.of(serveur.catalogue.puts);

  /// Ni le journal, ni les messages, ni le stockage des saisies ne contiennent le contenu reçu.
  void rienDuContenu(SaisieQueue q) {
    final tout = [...journalLignes, q.derniereErreur ?? '', ...disque.donnees.values, for (final s in q.lignes()) s.motif ?? ''].join('\n');
    expect(tout, isNot(contains(_marqueur)), reason: 'contenu de la page reçue jamais écrit');
    expect(tout, isNot(contains(_gs1Brut)), reason: 'scan GS1 brut jamais écrit');
    expect(tout, isNot(contains('<html')), reason: 'aucun morceau de HTML');
    expect(tout, isNot(contains('/login')), reason: 'ni l\'adresse de la redirection');
  }

  group('PUT /ws/inventaires/details : réponse non reconnue → gardée en attente (serveur injoignable)', () {
    final cas = <String, ReponseScriptee Function()>{
      '200 HTML (portail captif)': () => _html(),
      '200 HTML sans type annoncé': () => _html(type: ''),
      '200 HTML vide annoncé text/html': () => _html(corps: ''),
      '200 texte': () => _html(type: 'text/plain', corps: 'OK $_marqueur'),
      '200 JSON inattendu (objet d\'un autre service)': () => ReponseScriptee.json({'status': 'ok', 'service': _marqueur}),
      '200 JSON inattendu (liste)': () => ReponseScriptee.json([]),
      '200 JSON success:1 mais pour une AUTRE ligne': () => ReponseScriptee.json({'success': 1, 'id': 999999, 'quantite': 7}),
      '200 JSON success:1 mais une autre quantité': () => ReponseScriptee.json({'success': 1, 'quantite': 123}),
      '302 vers une page de connexion': () =>
          ReponseScriptee(code: 302, corps: _pageHtml, entetes: {'content-type': 'text/html', 'location': 'http://portail.invalid/login?jeton=$_marqueur'}),
      '400 HTML (relais)': () => _html(code: 400),
      '201 vide (pas la réponse de Prestige)': () => ReponseScriptee.code(201),
    };
    for (final e in cas.entries) {
      test('${e.key} : gardée à chaque essai, puis envoyée au retour du vrai serveur, dans l\'ordre, sans doublon', () async {
        final q = await ouvrir();
        await saisir(q, ids[0], 7);
        await saisir(q, ids[1], 3);
        serveur.scripter('details', e.value(), methode: 'PUT');
        for (var essai = 1; essai <= 4; essai++) {
          final b = await q.envoyer();
          expect(b.envoyees, 0, reason: 'essai $essai : jamais « envoyée » sur une réponse non reconnue');
          expect(b.refusees, 0, reason: 'essai $essai');
          expect(b.interruption, contains('Réponse non reconnue'), reason: 'essai $essai');
          expect(q.enAttente(), 2, reason: 'essai $essai : rien ne sort de la file');
          expect(q.refusees(), 0, reason: 'essai $essai : jamais « refusée »');
        }
        expect(disque.saisies.where((s) => s.enAttente), hasLength(2), reason: 'toujours dans le fichier local');
        expect(q.serveurInjoignable, isTrue);
        expect(q.messageAttenteServeur, '2 saisies en attente d\'envoi (serveur injoignable)');
        expect(poses(), isEmpty);
        rienDuContenu(q);
        expect(journalLignes.where((l) => l.contains('réponse non reconnue (')), isNotEmpty, reason: 'une ligne de journal (type, taille)');

        // Saisie qui continue pendant la panne : dernière valeur gagnante.
        await saisir(q, ids[0], 8);
        serveur.oublierScripts();
        await q.relancer(); // reprise automatique (mode Direct)
        expect(q.enAttente(), 0);
        expect(q.refusees(), 0);
        expect(q.messageAttenteServeur, isNull, reason: 'bandeau retiré au retour du serveur');
        expect(poses(), [(ids[1], 3), (ids[0], 8)], reason: 'ordre de saisie (dernière modification), une pose chacune');
        expect(serveur.catalogue.produit(ids[0]).saisi, 8);
        expect(serveur.catalogue.produit(ids[1]).saisi, 3);
      });
    }

    test('l\'adresse vraie répond de nouveau : file vidée dans l\'ordre, sans doublon, même après redémarrage', () async {
      final q = await ouvrir();
      for (var i = 0; i < 4; i++) {
        await saisir(q, ids[i], 10 + i);
      }
      serveur.scripter('details', _html(), methode: 'PUT');
      await q.envoyer();
      await q.envoyer();
      q.dispose();
      final apres = await ouvrir(); // redémarrage de l'application pendant le portail
      expect(apres.enAttente(), 4);
      serveur.oublierScripts();
      await apres.relancer();
      expect(apres.enAttente(), 0);
      expect(poses(), [for (var i = 0; i < 4; i++) (ids[i], 10 + i)]);
      expect(poses().toSet().length, poses().length, reason: 'aucun doublon');
    });

    test('fichier local saisies_v1.jsonl : la saisie y reste, sans rien de la page reçue', () async {
      final dossier = await Directory.systemTemp.createTemp('prestinv_503_');
      addTearDown(() => dossier.delete(recursive: true));
      final fichier = File('${dossier.path}/saisies_v1.jsonl');
      final q = await ouvrir(store: FichierSaisieStore(fichier));
      await saisir(q, ids[0], 5);
      serveur.scripter('details', _html(), methode: 'PUT');
      await q.envoyer();
      final relue = await ouvrir(store: FichierSaisieStore(fichier));
      expect(relue.ligne('INV1', ids[0])!.enAttente, isTrue, reason: 'toujours en attente dans le fichier');
      final contenu = await fichier.readAsString();
      expect(contenu, isNot(contains(_marqueur)));
      expect(contenu, isNot(contains(_gs1Brut)));
      serveur.oublierScripts();
      await relue.relancer();
      expect(relue.enAttente(), 0);
      expect(poses(), [(ids[0], 5)]);
    });
  });

  group('PUT /ws/inventaires/details : réponses de Prestige reconnues', () {
    test('200 vide (réponse réelle du serveur) : envoyée', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 4);
      expect((await q.envoyer()).complet, isTrue);
      expect(q.ligne('INV1', ids[0])!.envoyee, isTrue);
      expect(poses(), [(ids[0], 4)]);
    });

    test('204 sans corps : envoyée', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 4);
      serveur.scripter('details', ReponseScriptee.code(204), methode: 'PUT');
      expect((await q.envoyer()).complet, isTrue);
      expect(q.ligne('INV1', ids[0])!.envoyee, isTrue);
    });

    test('200 JSON {success:1, id, quantite} correct : envoyée', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 7);
      serveur.scripter('details', ReponseScriptee.json({'success': 1, 'id': ids[0], 'quantite': 7}), methode: 'PUT');
      expect((await q.envoyer()).complet, isTrue);
      expect(q.ligne('INV1', ids[0])!.envoyee, isTrue);
      expect(q.messageAttenteServeur, isNull);
    });

    test('200 JSON success:false avec message métier : « refusée » (jamais renvoyée seule)', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 7);
      serveur.scripter('details', ReponseScriptee.json({'success': 0, 'code': 'INVENTAIRE_CLOTURE', 'message': 'Inventaire clôturé.'}), methode: 'PUT');
      final b = await q.envoyer();
      expect(b.refusees, 1);
      expect(q.ligne('INV1', ids[0])!.refusee, isTrue);
      expect(q.messageAttenteServeur, isNull, reason: 'le serveur a répondu');
    });

    test('200 JSON success:false « Veuillez vous connecter » : session (gardée, reconnexion)', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 7);
      serveur.scripter('details', ReponseScriptee.json({'success': false, 'msg': 'Veuillez vous connecter'}), methode: 'PUT');
      final b = await q.envoyer();
      expect(b.sessionExpiree, isTrue);
      expect(q.enAttente(), 1);
    });

    test('refus métier 4xx en JSON : « refusée », comme avant', () async {
      final q = await ouvrir();
      await saisir(q, ids[0], 7);
      serveur.scripter('details', ReponseScriptee.json({'success': 0, 'code': 'LIGNE_INCONNUE', 'message': 'Ligne inconnue.'}, code: 404), methode: 'PUT');
      expect((await q.envoyer()).refusees, 1);
    });
  });

  group('POST /inventaire/ligne/quantite (versement de la collecte, auteur enregistré)', () {
    Future<ReponseEnvoi> poser(ReponseScriptee r, {int quantite = 6}) {
      serveur.scripter('ligne/quantite', r, methode: 'POST');
      return ApiService(baseUrl: base).poserQuantiteSession(ids[0], quantite);
    }

    test('réponses non reconnues : serveur injoignable (jamais « envoyée », jamais « refusée »)', () async {
      final cas = <String, ReponseScriptee>{
        '200 HTML': _html(),
        '200 texte': _html(type: 'text/plain', corps: 'OK'),
        '200 JSON sans success (avant : « refusée »)': ReponseScriptee.json({'status': 'ok'}),
        '200 JSON liste': ReponseScriptee.json([1, 2]),
        '200 success:1 autre quantité': ReponseScriptee.json({'success': 1, 'int_NUMBER': 99}),
        '302 page de connexion': ReponseScriptee(code: 302, corps: _pageHtml, entetes: {'content-type': 'text/html', 'location': 'http://portail.invalid/login'}),
        '400 HTML': _html(code: 400),
      };
      for (final e in cas.entries) {
        final r = await poser(e.value);
        expect(r.type, ResultatEnvoi.reseau, reason: e.key);
        expect(r.message, startsWith('Réponse non reconnue'), reason: e.key);
        expect(r.message, isNot(contains(_marqueur)), reason: e.key);
      }
      expect(serveur.catalogue.postsQuantite, isEmpty);
    });

    test('303 (POST redirigé en GET vers la page de connexion) : non reconnue', () async {
      serveur.scripter('portail/connexion', _html(), methode: 'GET');
      final r = await poser(ReponseScriptee(code: 303, corps: '', entetes: {'location': '$base/portail/connexion'}));
      expect(r.type, ResultatEnvoi.reseau);
    });

    test('réponses de Prestige : {success:1, int_NUMBER} envoyée ; {success:0, errors} refusée ; « connecter » session', () async {
      expect((await poser(ReponseScriptee.json({'success': 1, 'int_NUMBER': 6}))).type, ResultatEnvoi.ok);
      expect((await poser(ReponseScriptee.json({'success': true}))).type, ResultatEnvoi.ok);
      final refus = await poser(ReponseScriptee.json({'success': 0, 'errors': 'Cette ligne d\'inventaire n\'existe plus.'}));
      expect(refus.type, ResultatEnvoi.refus);
      expect(refus.message, 'Cette ligne d\'inventaire n\'existe plus.');
      expect((await poser(ReponseScriptee.json({'success': false, 'msg': 'Veuillez vous connecter'}))).type, ResultatEnvoi.session);
      serveur.oublierScripts();
      expect((await ApiService(baseUrl: base).poserQuantiteSession(ids[0], 6)).type, ResultatEnvoi.ok, reason: 'vrai serveur');
      expect(serveur.catalogue.postsQuantite.last, (ids[0], 6));
    });
  });

  group('Versement en lot (POST /inventaire/{id}/versement) : réponse non reconnue → lot gardé, même clé', () {
    setUp(() {
      serveur.serveurRecent = true;
      ApiService.noterServeur(base, recent: true);
    });
    final cas = <String, ReponseScriptee Function()>{
      '200 HTML': () => _html(),
      '200 JSON sans rapport': () => ReponseScriptee.json({'status': 'ok'}),
      '200 rapport vide': () => ReponseScriptee.json({'success': 1, 'lignes': []}),
      '302 page de connexion': () => ReponseScriptee(code: 302, corps: '', entetes: {'location': 'http://portail.invalid/login'}),
      '400 HTML (avant : ancien chemin)': () => _html(code: 400),
      '409 HTML (avant : « clé déjà utilisée »)': () => _html(code: 409),
      '410 HTML (avant : « inventaire introuvable »)': () => _html(code: 410),
    };
    for (final e in cas.entries) {
      test(e.key, () async {
        final api = ApiService(baseUrl: base);
        final lignes = [(serveur.catalogue.produits[0].cip, 2)];
        serveur.scripter('versement', e.value(), methode: 'POST');
        final r = await api.verserLot('INV1', cle: 'V-FICTIF-L1', ajouter: true, lignes: lignes);
        expect(r.issue, IssueVersementLot.incertain, reason: 'rien de conclu : lot gardé, même clé à la reprise');
        expect(r.message, isNot(contains(_marqueur)));
        serveur.oublierScripts();
        final p = serveur.catalogue.produit(ids[0]);
        final attendu = p.dtUpdated != null ? p.saisi + 2 : 2;
        final r2 = await api.verserLot('INV1', cle: 'V-FICTIF-L1', ajouter: true, lignes: lignes, reprise: true);
        expect(r2.issue, IssueVersementLot.traite);
        final r3 = await api.verserLot('INV1', cle: 'V-FICTIF-L1', ajouter: true, lignes: lignes, reprise: true);
        expect(r3.dejaTraite, isTrue, reason: 'la même clé n\'est jamais comptée deux fois');
        expect(serveur.catalogue.produit(ids[0]).saisi, attendu, reason: 'ajout appliqué une seule fois');
        expect(serveur.catalogue.versementsLot.where((v) => v['cle'] == 'V-FICTIF-L1'), hasLength(2), reason: 'reprise + relecture');
      });
    }
  });

  group('Lectures : une page HTML n\'est jamais une liste vide (aucun cache effacé)', () {
    final routes = <String, Future<Object?> Function(ApiService)>{
      'inventaires': (a) => a.fetchInventories(),
      'detailsAll': (a) => a.fetchProducts('INV1', null),
      'rayons': (a) => a.fetchRayons('INV1'),
      'detailsAllEcarts': (a) => a.fetchGlobalVariances('INV1'),
      'detailsAllTouched': (a) => a.verifierDejaCompte('INV1', '3400930000001'),
      'licence/find': (a) => a.findLicense(),
    };
    for (final e in routes.entries) {
      test('${e.key} : 200 HTML → erreur levée (jamais une liste vide ni des données)', () async {
        serveur.scripter(e.key, _html(), methode: 'GET');
        await expectLater(
            e.value(ApiService(baseUrl: base)),
            throwsA(isA<ApiLoadException>()
                // Licence : serveur injoignable (la licence n'est pas en cause) ; listes : données illisibles, comme avant.
                .having((x) => x.type, 'type', e.key == 'licence/find' ? TypeErreurChargement.reseau : TypeErreurChargement.donnees)
                .having((x) => x.message, 'message', allOf(contains('Réponse non reconnue'), isNot(contains(_marqueur))))));
      });
    }

    test('302 vers une page de connexion (lecture : redirection suivie) → erreur, pas une liste vide', () async {
      serveur.scripter('portail/connexion', _html(), methode: 'GET');
      serveur.scripter('inventaires', ReponseScriptee(code: 302, corps: '', entetes: {'location': '$base/portail/connexion'}), methode: 'GET');
      await expectLater(ApiService(baseUrl: base).fetchInventories(), throwsA(isA<ApiLoadException>().having((x) => x.message, 'message', contains('Réponse non reconnue'))));
    });

    test('liste des inventaires ouverts (file des saisies) : page HTML → « inconnue », jamais « clôturé »', () async {
      serveur.scripter('inventaires', _html(), methode: 'GET');
      expect(await ApiService(baseUrl: base).inventairesOuverts(), isNull);
      final q = await ouvrir();
      await saisir(q, ids[0], 2);
      final b = await q.envoyer();
      expect(b.refusees, 0, reason: 'jamais « inventaire clôturé » sur une page de portail');
      expect(q.enAttente(), 1);
      expect(q.messageAttenteServeur, '1 saisie en attente d\'envoi (serveur injoignable)');
    });
  });

  test('mode Collecte (manuel) inchangé : rien ne part seul ; « Envoyer » sur un portail → gardées, reprise seule', () async {
    final q = await ouvrir(direct: false);
    await saisir(q, ids[0], 1);
    await saisir(q, ids[1], 2);
    await q.relancer();
    expect(poses(), isEmpty, reason: 'mode manuel : pas d\'envoi sans « Envoyer »');
    serveur.scripter('details', _html(), methode: 'PUT');
    final b = await q.envoyer(inventaireId: 'INV1');
    expect(b.envoyees, 0);
    expect(q.enAttente(), 2);
    expect(q.envoiARependre, 'INV1');
    serveur.oublierScripts();
    await q.relancer();
    expect(q.enAttente(), 0);
    expect(poses(), [(ids[0], 1), (ids[1], 2)]);
    await saisir(q, ids[2], 9);
    await q.relancer();
    expect(q.enAttente(), 1, reason: 'de nouveau : rien ne part seul');
  });

  test('description sans contenu : code, type, taille', () {
    expect(ApiService.descriptionReponse(_reponse(200, 'text/html; charset=utf-8', _pageHtml)),
        '200, text/html, ${utf8.encode(_pageHtml).length} octets');
    expect(ApiService.descriptionReponse(_reponse(302, '', '')), '302 redirection, sans type, 0 octets');
    expect(ApiService.typeContenu(_reponse(200, 'text/html;"><script>$_marqueur', '')), 'text/html');
  });
}

/// Réponse HTTP construite en mémoire (contrôle de la description).
http.Response _reponse(int code, String type, String corps) =>
    http.Response.bytes(utf8.encode(corps), code, headers: type.isEmpty ? const {} : {'content-type': type});
