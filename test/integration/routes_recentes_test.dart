// INTÉGRATION — 4.15, routes récentes du serveur (réponse aux demandes mobiles du 15/10/2026), contre le
// faux serveur Prestige servi en VRAI HTTP. Chaque route nouvelle a son REPLI : un serveur qui ne l'a pas
// garde exactement le fonctionnement d'avant.
//  - demande 30 : état de tous les rayons en une requête (rayons à compter, états) ; 404 → anciennes routes ;
//    410, 401, 500, réponse tronquée : erreur lisible, jamais une liste vide ;
//  - demande 37 : versement de la collecte en lot, clé anti-doublon (réponse perdue → même clé, rien compté
//    deux fois), « ajouter » fait par le serveur, codes non reconnus → ancien chemin, 401 / 409 / 404 ;
//  - demande 21 : lecture en échec (500) ≠ liste vide ;
//  - demande 8 et « Contradiction 3 » : PUT details sans session → 401 → saisie GARDÉE puis envoyée après
//    reconnexion ; 409 clôturé, 404 ligne inconnue : refus lisible ; 403 « interdit » : refus (pas de
//    reconnexion en boucle).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart';
import '../helpers/coffre_memoire.dart';
import '../helpers/faux_prestige_http.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

late FauxServeurPrestige serveur;

Future<(AuthProvider, AppConfig, ApiService)> connecte() async {
  SharedPreferences.setMockInitialValues({'localApiAddress': '127.0.0.1', 'localApiPort': '${serveur.port}', 'appName': 'prestige'});
  final config = AppConfig();
  await config.load();
  final auth = AuthProvider();
  expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue, reason: auth.errorMessage);
  return (auth, config, ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie));
}

CollectedItem item(String code, int q) => CollectedItem(code: code, quantity: q, dateScan: DateTime(2026, 10, 15, 9));

/// Moteur de versement sur le vrai transport HTTP ; les états enregistrés sont gardés (reprise).
(MoteurVersement, SaisieQueue, List<Versement>) moteur(AuthProvider auth, AppConfig config) {
  final q = SaisieQueue(store: DisqueMemoire());
  q.serveurFactory = () => ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
  final etats = <Versement>[];
  final m = MoteurVersement(
    api: ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie),
    queue: q,
    auteur: CompteFictif.login,
    enregistrer: (v) async => etats.add(Versement.fromJson(json.decode(json.encode(v.toJson())) as Map<String, dynamic>)),
  );
  return (m, q, etats);
}

Versement versement(List<CollectedItem> c, ModeDejaCompte mode) =>
    Versement.depuisCollecte(c, inventaireId: 'INV1', inventaireLibelle: 'Inventaire annuel 2026', mode: mode, maintenant: DateTime(2026, 10, 15, 10));

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
    IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: CoffreMemoire());
  });

  setUp(() async {
    ApiService.clientParDefaut = null;
    ApiService.oublierRoutesAbsentes();
    serveur = FauxServeurPrestige();
    await serveur.demarrer();
  });

  tearDown(() => serveur.arreter());

  group('Demande 30 — état de tous les rayons', () {
    test('serveur à jour : une requête pour les rayons, une pour TOUS les états (au lieu de 1 ou 2 par rayon)', () async {
      serveur.serveurRecent = true;
      final (_, _, api) = await connecte();
      final p = EntryProvider();
      final avant = serveur.requetes.length;
      await p.fetchRayons(api, 'INV1');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(p.rayons.map((r) => r.id), ['S2B2', 'S1A0T2', 'S3']);
      expect(p.rayonStatuses, {'S2B2': 1, 'S1A0T2': 1, 'S3': 1});
      expect(serveur.requetes.skip(avant).map((r) => r.route), ['ws/inventaires/INV1/rayons/etat', 'ws/inventaires/INV1/rayons/etat']);
    });

    test('serveur ancien : AUCUNE requête nouvelle (routes d\'avant, à l\'identique)', () async {
      final (_, _, api) = await connecte();
      expect(api.serveurRecent, isFalse);
      expect(await api.etatRayons('INV1'), isNull);
      await api.fetchRayons('INV1');
      expect(serveur.recues('rayons/etat'), isEmpty);
      expect(serveur.recues('ws/inventaires/rayons'), hasLength(1));
    });

    test('route absente malgré tout (404) : mémorisée, anciennes routes', () async {
      serveur.serveurRecent = true;
      final (_, _, api) = await connecte();
      serveur.scripter('etat', ReponseScriptee.code(404));
      expect((await api.fetchRayons('INV1')).map((r) => r.id).toSet(), {'S1A0T2', 'S2B2', 'S3'});
      await api.fetchRayons('INV1');
      expect(serveur.recues('rayons/etat'), hasLength(1), reason: 'essayée une seule fois');
      expect(serveur.recues('ws/inventaires/rayons'), hasLength(2));
    });

    test('410 (inventaire inconnu), 401, 500, réponse tronquée : erreur lisible, jamais une liste vide', () async {
      serveur.serveurRecent = true;
      final (_, _, api) = await connecte();
      await expectLater(api.etatRayons('INCONNU'), throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('introuvable'))));
      serveur.scripter('etat', ReponseScriptee.code(500, fois: 1));
      await expectLater(api.etatRayons('INV1'), throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('500'))));
      serveur.scripter('etat', ReponseScriptee.tronquee('[{"rayonId":"S3","code":"S3","libelle":"RÉSERVE","totalProduits":4', fois: 1));
      await expectLater(api.etatRayons('INV1'), throwsA(isA<ApiLoadException>()));
      serveur.scripter('etat', ReponseScriptee.json([{'rayonId': 'S3', 'totalProduits': 'beaucoup'}], fois: 1));
      await expectLater(api.etatRayons('INV1'), throwsA(isA<ApiLoadException>().having((e) => e.type, 'type', TypeErreurChargement.donnees)));
      serveur.expirerSessions();
      await expectLater(api.fetchRayons('INV1'), throwsA(isA<ApiLoadException>().having((e) => e.sessionExpiree, 'session', isTrue)));
    });

    test('rayon sans produit à compter (lignes non retenues) : masqué', () async {
      serveur.serveurRecent = true;
      final (_, _, api) = await connecte();
      serveur.scripter(
          'etat',
          ReponseScriptee.json([
            {'rayonId': 'S1A0T2', 'code': 'S1A0T2', 'libelle': 'CANNES', 'totalProduits': 0, 'comptes': 0, 'restants': 0},
            {'rayonId': 'S3', 'code': 'S3', 'libelle': 'RÉSERVE', 'totalProduits': 2, 'comptes': 2, 'restants': 0},
          ]));
      expect((await api.fetchRayons('INV1')).map((r) => r.id), ['S3']);
    });
  });

  group('Demande 21 — lecture en échec ≠ liste vide', () {
    for (final route in ['detailsAll', 'detailsAllEcarts', 'detailsAllUntouched', 'rayons']) {
      test('$route : 500 → erreur « Erreur du serveur », jamais []', () async {
        final (_, _, api) = await connecte();
        serveur.scripter(route, ReponseScriptee.code(500));
        final Future<Object> lecture = switch (route) {
          'detailsAll' => api.fetchProducts('INV1', null),
          'detailsAllEcarts' => api.fetchGlobalVariances('INV1'),
          'detailsAllUntouched' => api.fetchUntouchedProducts('INV1'),
          _ => api.fetchRayons('INV1'),
        };
        await expectLater(lecture, throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', startsWith('Erreur du serveur (code 500)'))));
      });
    }
  });

  group('Demande 37 — versement en lot', () {
    setUp(() => serveur.serveurRecent = true);

    test('une requête pour tout le lot (au lieu d\'une par produit) ; collecte marquée versée ; rapport', () async {
      final (auth, config, _) = await connecte();
      final (m, _, _) = moteur(auth, config);
      final r = await m.executer(versement([item('3400930000001', 12), item('3400938000004', 4), item('3400930000001', 1)], ModeDejaCompte.remplacer));
      expect(r.statut, StatutVersement.termine);
      expect((serveur.catalogue.produit(1).saisi, serveur.catalogue.produit(5).saisi), (13, 4));
      expect(serveur.recues('inventaire/INV1/versement', methode: 'POST'), hasLength(1));
      expect(serveur.recues('ligne/quantite'), isEmpty, reason: 'aucun envoi produit par produit');
      final corps = serveur.catalogue.versementsLot.single;
      expect(corps['mode'], 'remplacer');
      expect(corps['cle'], startsWith(r.id));
      expect(corps['lignes'], [
        {'code': '3400930000001', 'quantite': 13},
        {'code': '3400938000004', 'quantite': 4},
      ]);
      expect(r.versees.map((l) => (l.cip, l.quantiteCible)), [('3400930000001', 13), ('3400938000004', 4)]);
      expect(r.lotEnCours, isNull);
    });

    test('« Ajouter » : fait par le serveur sur la quantité déjà comptée', () async {
      final (auth, config, _) = await connecte();
      final (m, _, _) = moteur(auth, config);
      // EFFERALGAN (3) déjà compté 38.
      final r = await m.executer(versement([item('3400936000002', 5)], ModeDejaCompte.ajouter));
      expect(r.statut, StatutVersement.termine);
      expect(serveur.catalogue.produit(3).saisi, 43);
      expect(r.versees.single.quantiteExistante, 38);
      expect(r.versees.single.quantiteCible, 43);
      expect(r.ajoutees, hasLength(1));
    });

    test('réponse PERDUE après l\'enregistrement : reprise avec la MÊME clé → rien compté deux fois (même en « Ajouter »)', () async {
      final (auth, config, _) = await connecte();
      final (m, _, etats) = moteur(auth, config);
      serveur.catalogue.versementsReponsePerdue = 1;
      final v = versement([item('3400936000002', 5), item('3400930000001', 2)], ModeDejaCompte.ajouter);
      final r1 = await m.executer(v);
      expect(r1.statut, StatutVersement.interrompu);
      expect(r1.interruption, contains('rien ne sera compté deux fois'));
      expect(r1.lotEnCours, isNotNull, reason: 'lot gardé sur l\'appareil');
      expect(serveur.catalogue.produit(3).saisi, 43, reason: 'enregistré une fois côté serveur');
      // Redémarrage : le versement est relu tel qu'enregistré.
      final relu = etats.last;
      final r2 = await m.executer(relu);
      expect(r2.statut, StatutVersement.termine);
      expect(serveur.catalogue.produit(3).saisi, 43, reason: 'pas de second ajout');
      expect(serveur.catalogue.produit(1).saisi, 2);
      final envois = serveur.catalogue.versementsLot;
      expect(envois, hasLength(2));
      expect(envois[1]['cle'], envois[0]['cle']);
      expect(envois[1]['lignes'], envois[0]['lignes']);
    });

    test('code non reconnu par le serveur (EAN-13 34009 d\'un CIP7) : repris par l\'ancien chemin', () async {
      final (auth, config, _) = await connecte();
      serveur.catalogue.produits.add(FauxProduit(2002, '3595583', 'DOLIPRANE 1000 MG', 'S3', 20));
      final (m, _, _) = moteur(auth, config);
      final r = await m.executer(versement([item('3400935955838', 2), item('9999999999999', 1)], ModeDejaCompte.remplacer));
      expect(r.statut, StatutVersement.termine);
      expect(serveur.catalogue.produit(2002).saisi, 2, reason: 'trouvé par sa forme CIP7, posé produit par produit');
      expect(serveur.recues('ligne/quantite', methode: 'POST'), hasLength(1));
      expect(r.nonReconnues.single.code, '9999999999999');
    });

    test('deux codes du même produit dans le lot en « Remplacer » : la SOMME est posée', () async {
      final (auth, config, _) = await connecte();
      serveur.catalogue.produits.add(FauxProduit(2013, '3400930000999', 'SÉRUM PHYSIOLOGIQUE', 'S3', 5, ean: '8712345678906'));
      final (m, _, _) = moteur(auth, config);
      final r = await m.executer(versement([item('3400930000999', 3), item('8712345678906', 4)], ModeDejaCompte.remplacer));
      expect(r.statut, StatutVersement.termine);
      expect(serveur.catalogue.produit(2013).saisi, 7);
      expect(r.lignes.where((l) => l.etat == EtatLigneVersement.regroupee), hasLength(1));
    });

    test('session expirée (401) : rien d\'enregistré, versement interrompu, repris après reconnexion', () async {
      final (auth, config, _) = await connecte();
      final (m, _, _) = moteur(auth, config);
      serveur.expirerSessions();
      final v = versement([item('3400930000001', 6)], ModeDejaCompte.remplacer);
      // La lecture des lignes de l'inventaire échoue déjà : interrompu.
      final r1 = await m.executer(v);
      expect(r1.statut, StatutVersement.interrompu);
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue);
      final r2 = await m.executer(v);
      expect(r2.statut, StatutVersement.termine);
      expect(serveur.catalogue.produit(1).saisi, 6);
    });

    test('inventaire clôturé (409) : rien d\'enregistré, message lisible', () async {
      final (auth, config, _) = await connecte();
      final (m, _, _) = moteur(auth, config);
      serveur.scripter('versement', ReponseScriptee.json({'success': 0, 'code': 'INVENTAIRE_CLOTURE', 'message': 'Inventaire « X » clôturé : rien n\'a été enregistré.'}, code: 409));
      final r = await m.executer(versement([item('3400930000001', 6)], ModeDejaCompte.remplacer));
      expect(r.statut, StatutVersement.interrompu);
      expect(r.interruption, contains('clôturé'));
      expect(r.lotEnCours, isNull);
    });

    test('ligne refusée par le serveur (« Ligne clôturée. ») : en erreur avec le motif, pas renvoyée produit par produit', () async {
      final (auth, config, _) = await connecte();
      final (m, _, _) = moteur(auth, config);
      serveur.scripter(
          'versement',
          ReponseScriptee.json({
            'success': 1,
            'dejaTraite': false,
            'lignes': [
              {'index': 0, 'code': '3400930000001', 'statut': 'refuse', 'ligneId': '1', 'motif': 'Ligne clôturée.'},
            ],
          }));
      final r = await m.executer(versement([item('3400930000001', 6)], ModeDejaCompte.remplacer));
      expect(r.erreurs.single.raison, 'Ligne clôturée.');
      expect(serveur.recues('ligne/quantite'), isEmpty);
      expect(serveur.catalogue.produit(1).saisi, 24, reason: 'rien de posé');
    });

    test('route absente (404) : ancien chemin pour tout, mémorisé', () async {
      final (auth, config, _) = await connecte();
      final (m, _, _) = moteur(auth, config);
      serveur.scripter('versement', ReponseScriptee.code(404));
      final r = await m.executer(versement([item('3400930000001', 6), item('3400938000004', 2)], ModeDejaCompte.remplacer));
      expect(r.statut, StatutVersement.termine);
      expect(serveur.recues('ligne/quantite', methode: 'POST'), hasLength(2));
      final r2 = await m.executer(versement([item('3400939300008', 1)], ModeDejaCompte.remplacer));
      expect(r2.statut, StatutVersement.termine);
      expect(serveur.recues('versement', methode: 'POST'), hasLength(1), reason: 'route absente mémorisée');
    });

    test('saisies de cet inventaire en attente sur l\'appareil : ancien chemin (la saisie locale compte)', () async {
      final (auth, config, _) = await connecte();
      final (m, q, _) = moteur(auth, config);
      await q.enregistrer(inventaireId: 'INV1', ligneId: 3, quantite: 50, envoiAuto: false);
      final r = await m.executer(versement([item('3400936000002', 5)], ModeDejaCompte.ajouter));
      expect(r.statut, StatutVersement.termine);
      expect(serveur.recues('versement'), isEmpty);
      expect(serveur.catalogue.produit(3).saisi, 55, reason: '50 (sur l\'appareil) + 5');
    });

    test('serveur ancien (pas de droits à la connexion) : aucune requête nouvelle', () async {
      serveur.serveurRecent = false;
      final (auth, config, _) = await connecte();
      final (m, _, _) = moteur(auth, config);
      final r = await m.executer(versement([item('3400930000001', 6)], ModeDejaCompte.remplacer));
      expect(r.statut, StatutVersement.termine);
      expect(serveur.recues('versement'), isEmpty);
    });
  });

  group('Demande 8 / Contradiction 3 — PUT details exige une session', () {
    test('401 : la saisie est GARDÉE (« session »), puis envoyée après la reconnexion', () async {
      final (auth, config, api) = await connecte();
      final q = SaisieQueue(store: DisqueMemoire());
      q.serveurFactory = () => ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      await q.load();
      await q.enregistrer(inventaireId: 'INV1', ligneId: 4, quantite: 7, envoiAuto: false);
      serveur.expirerSessions();
      expect((await api.poserQuantite(4, 7)).type, ResultatEnvoi.session);
      await q.envoyer();
      expect(q.enAttente(), 1, reason: 'jamais perdue');
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue);
      expect((await q.envoyer()).complet, isTrue);
      expect(serveur.catalogue.produit(4).saisi, 7);
    });

    test('409 clôturé, 404 ligne inconnue, 400 quantité invalide : refus LISIBLE (pas renvoyé en boucle)', () async {
      final (_, _, api) = await connecte();
      for (final (code, codeMetier, attendu) in [
        (409, 'INVENTAIRE_CLOTURE', 'Inventaire clôturé sur le serveur'),
        (404, 'LIGNE_INCONNUE', 'n\'existe plus'),
        (400, 'QUANTITE_INVALIDE', 'invalide'),
      ]) {
        serveur.scripter('details', ReponseScriptee.json({'success': 0, 'code': codeMetier, 'message': 'x'}, code: code), methode: 'PUT');
        final r = await api.poserQuantite(4, 7);
        expect(r.type, ResultatEnvoi.refus, reason: codeMetier);
        expect(r.message, contains(attendu));
      }
    });

    test('403 « interdit » (droit manquant) : refus, pas de demande de reconnexion', () async {
      final (_, _, api) = await connecte();
      serveur.scripter('details', ReponseScriptee.json({'success': 0, 'interdit': true, 'msg': 'Droit manquant : Saisie d\'inventaire'}, code: 403), methode: 'PUT');
      final r = await api.poserQuantite(4, 7);
      expect(r.type, ResultatEnvoi.refus);
      expect(r.message, 'Droit manquant : Saisie d\'inventaire');
      serveur.scripter('details', ReponseScriptee.code(403), methode: 'PUT');
      expect((await api.poserQuantite(4, 7)).type, ResultatEnvoi.session, reason: '403 sans « interdit » : comme avant');
    });
  });
}
