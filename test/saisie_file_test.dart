// File persistante des saisies : enregistrement avant envoi, idempotence, reprise après redémarrage,
// une seule requête en vol par ligne, journal abîmé, compactage, inventaire clôturé, erreurs serveur.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/faux_serveur.dart';

void main() {
  late FileDeTest f;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    f = await FileDeTest.creer();
  });
  tearDown(() => f.nettoyer());

  test('une saisie est écrite sur disque avant tout envoi et survit au redémarrage', () async {
    final q = await f.ouvrir(); // aucun serveur : rien ne peut partir
    await saisir(q, 10, 7);
    expect(await f.fichier.exists(), isTrue);

    final apresRedemarrage = await f.ouvrir();
    final s = apresRedemarrage.ligne('INV1', 10);
    expect(s, isNotNull);
    expect(s!.quantite, 7);
    expect(s.enAttente, isTrue);
    expect(apresRedemarrage.enAttente(inventaireId: 'INV1'), 1);
  });

  test('envoi idempotent : le serveur reçoit la quantité TOTALE, renvoyer ne crée pas de doublon', () async {
    final serveur = FauxServeur();
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 1, 5);
    await saisir(q, 1, 8); // correction : remplace, ne s'ajoute pas
    expect(q.lignes().length, 1);
    var bilan = await q.envoyer();
    expect(bilan.envoyees, 1);
    expect(serveur.quantites[1], 8);

    // Même valeur ressaisie puis renvoyée : le serveur reste à 8.
    await saisir(q, 1, 8);
    bilan = await q.envoyer();
    expect(serveur.quantites[1], 8);
    expect(serveur.requetes.map((r) => r.$2), everyElement(8));
    expect(q.ligne('INV1', 1)!.envoyee, isTrue);
  });

  test('reprise après redémarrage : saisies faites hors réseau envoyées au lancement suivant', () async {
    final serveur = FauxServeur()..panne = ResultatEnvoi.reseau;
    final q = await f.ouvrir(serveur: serveur);
    for (var i = 1; i <= 5; i++) {
      await saisir(q, i, i * 10);
    }
    final bilan = await q.envoyer();
    expect(bilan.envoyees, 0);
    expect(bilan.interruption, isNotNull);
    expect(q.enAttente(), 5);

    // Redémarrage, réseau revenu.
    serveur.panne = null;
    final q2 = await f.ouvrir(serveur: serveur);
    expect(q2.enAttente(), 5);
    final b2 = await q2.envoyer();
    expect(b2.envoyees, 5);
    expect(serveur.quantites, {1: 10, 2: 20, 3: 30, 4: 40, 5: 50});

    // L'état « envoyée » est lui aussi gardé.
    final q3 = await f.ouvrir();
    expect(q3.enAttente(), 0);
    expect(q3.ligne('INV1', 3)!.envoyee, isTrue);
  });

  test('une seule requête en vol par ligne, même si on appuie plusieurs fois sur Envoyer', () async {
    final serveur = FauxServeur()..verrou = Completer<void>();
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 1, 3);
    final a = q.envoyerLigne('INV1', 1);
    final b = q.envoyerLigne('INV1', 1);
    final c = q.envoyer();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(serveur.enCours, 1);
    serveur.verrou!.complete();
    await Future.wait([a, b, c]);
    expect(serveur.maxEnCoursParLigne, 1);
    expect(serveur.requetes.length, 1);
    expect(q.ligne('INV1', 1)!.envoyee, isTrue);
  });

  test('journal coupé par une extinction brutale : la dernière ligne abîmée est ignorée, rien d\'autre n\'est perdu', () async {
    final q = await f.ouvrir();
    await saisir(q, 1, 1);
    await saisir(q, 2, 2);
    await f.fichier.writeAsString('{"op":"put","s":{"inv":"INV1","id":3,', mode: FileMode.append);
    final q2 = await f.ouvrir();
    expect(q2.lignes().map((s) => s.ligneId).toSet(), {1, 2});
    // La saisie suivante n'est pas collée derrière la ligne abîmée.
    await saisir(q2, 4, 44);
    final q3 = await f.ouvrir();
    expect(q3.lignes().map((s) => s.ligneId).toSet(), {1, 2, 4});
    expect(q3.ligne('INV1', 4)!.quantite, 44);
  });

  test('compactage atomique : le journal est réécrit sans perdre l\'état', () async {
    final store = FichierSaisieStore(f.fichier, seuilCompactage: 10);
    final q = SaisieQueue(store: store);
    await q.load();
    for (var i = 0; i < 40; i++) {
      await saisir(q, i % 3, i);
    }
    expect(store.lignesJournal, lessThan(40));
    final q2 = await f.ouvrir();
    expect(q2.ligne('INV1', 0)!.quantite, 39);
    expect(q2.ligne('INV1', 1)!.quantite, 37);
    expect(q2.ligne('INV1', 2)!.quantite, 38);
    expect(File('${f.fichier.path}.tmp').existsSync(), isFalse);
  });

  test('inventaire clôturé : rien n\'est envoyé, les saisies passent en « refusée » avec le motif', () async {
    final serveur = FauxServeur()..ouverts = {'AUTRE'};
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 1, 4);
    final bilan = await q.envoyer();
    expect(serveur.requetes, isEmpty);
    expect(bilan.refusees, 1);
    final s = q.ligne('INV1', 1)!;
    expect(s.refusee, isTrue);
    expect(s.motif, SaisieQueue.motifCloture);
    // Jamais renvoyée seule ; « Renvoyer » la remet en attente.
    await q.relancer();
    expect(serveur.requetes, isEmpty);
    await q.renvoyer(s.cle);
    expect(q.ligne('INV1', 1)!.enAttente, isTrue);
  });

  test('liste des inventaires ouverts vide (le serveur la renvoie aussi en cas d\'erreur) : on ne conclut pas', () async {
    final serveur = FauxServeur()..ouverts = {};
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 1, 4);
    final bilan = await q.envoyer();
    expect(bilan.interruption, isNotNull);
    expect(q.ligne('INV1', 1)!.enAttente, isTrue);
    expect(serveur.requetes, isEmpty);
  });

  test('session expirée (401) : saisie gardée en attente, reconnexion signalée', () async {
    final serveur = FauxServeur()..panne = ResultatEnvoi.session;
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 1, 4);
    final bilan = await q.envoyer();
    expect(bilan.sessionExpiree, isTrue);
    expect(q.sessionExpiree, isTrue);
    expect(q.ligne('INV1', 1)!.enAttente, isTrue);
    serveur.panne = null;
    q.signalerReconnexion();
    await q.envoyer();
    expect(q.ligne('INV1', 1)!.envoyee, isTrue);
    expect(q.sessionExpiree, isFalse);
  });

  test('erreur serveur 5xx : réessayée, puis « refusée » après 3 échecs', () async {
    final serveur = FauxServeur()..panne = ResultatEnvoi.erreurServeur;
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 1, 4);
    await q.envoyer();
    expect(q.ligne('INV1', 1)!.enAttente, isTrue);
    await q.envoyer();
    await q.envoyer();
    expect(q.ligne('INV1', 1)!.refusee, isTrue);
    expect(serveur.requetes.length, 3);
  });

  test('refus 4xx : « refusée » tout de suite, visible, jamais renvoyée seule', () async {
    final serveur = FauxServeur()..panne = ResultatEnvoi.refus;
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 1, 4);
    final b = await q.envoyer();
    expect(b.refusees, 1);
    expect(q.refusees(), 1);
    expect(q.aTraiter(), 1);
  });

  test('reprise automatique : en mode Collecte seules les corrections Écarts/Restants partent seules', () async {
    final serveur = FauxServeur();
    final q = await f.ouvrir(serveur: serveur);
    await saisir(q, 1, 1); // guidée, mode Collecte
    await saisir(q, 2, 2, auto: true, origine: OrigineSaisie.ecarts);
    q.modeDirect = () => false;
    await q.relancer();
    expect(serveur.quantites, {2: 2});
    q.modeDirect = () => true;
    await q.relancer();
    expect(serveur.quantites, {1: 1, 2: 2});
  });

  test('les saisies envoyées depuis plus de 7 jours sont purgées, jamais celles en attente', () async {
    var maintenant = DateTime(2026, 10, 1);
    final serveur = FauxServeur();
    final q = await f.ouvrir(serveur: serveur, clock: () => maintenant);
    await saisir(q, 1, 1);
    await q.envoyer();
    serveur.panne = ResultatEnvoi.reseau;
    await saisir(q, 2, 2);
    maintenant = DateTime(2026, 10, 20);
    final q2 = await f.ouvrir(clock: () => maintenant);
    expect(q2.ligne('INV1', 1), isNull);
    expect(q2.ligne('INV1', 2)!.enAttente, isTrue);
  });

  group('reprise des saisies des versions précédentes (inv_*_ray_*_unsynced)', () {
    test('saisies non envoyées reprises sans perte, ancienne clé supprimée après vérification', () async {
      SharedPreferences.setMockInitialValues({
        'inv_INV1_ray_R1_unsynced':
            '[{"id":11,"produitCip":"111","produitName":"A","quantiteSaisie":3,"isSynced":false,"locationLabel":"Rayon 1"},'
                '{"id":12,"produitCip":"112","produitName":"B","quantiteSaisie":0,"isSynced":false}]',
        'inv_INV1_ray_R2_unsynced': '[{"id":21,"produitCip":"211","produitName":"C","quantiteSaisie":9,"isSynced":false}]',
        'inv_INV1_ray_R1_index': 4,
        'autre': 'x',
      });
      final q = await f.ouvrir();
      final n = await q.migrerAnciennesCles();
      expect(n, 3);
      expect(q.ligne('INV1', 11)!.quantite, 3);
      expect(q.ligne('INV1', 12)!.quantite, 0);
      expect(q.ligne('INV1', 21)!.rayonId, 'R2');
      expect(q.ligne('INV1', 11)!.origine, OrigineSaisie.migration);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('inv_INV1_ray_R1_unsynced'), isFalse);
      expect(prefs.containsKey('inv_INV1_ray_R2_unsynced'), isFalse);
      expect(prefs.getInt('inv_INV1_ray_R1_index'), 4); // position et filtres conservés

      // Après redémarrage, elles sont toujours là (et ne sont pas reprises deux fois).
      final q2 = await f.ouvrir();
      expect(q2.enAttente(), 3);
      expect(await q2.migrerAnciennesCles(), 0);
    });

    test('ancienne clé illisible : gardée (rien n\'est effacé sans avoir été repris)', () async {
      SharedPreferences.setMockInitialValues({'inv_INV1_ray_R1_unsynced': '{pas du json'});
      final q = await f.ouvrir();
      expect(await q.migrerAnciennesCles(), 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('inv_INV1_ray_R1_unsynced'), isTrue);
    });
  });
}
