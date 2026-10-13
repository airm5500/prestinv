// Essai RÉEL contre un serveur Prestige de test (hors CI : dossier test_reel/).
//   flutter test test_reel/essai_serveur_reel_test.dart \
//     --dart-define=PRESTINV_REEL_HOTE=localhost --dart-define=PRESTINV_REEL_PORT=8080 \
//     --dart-define=PRESTINV_REEL_LOGIN=admin --dart-define=PRESTINV_REEL_MDP=... \
//     --dart-define=PRESTINV_REEL_LIGNE=2
// La ligne PRESTINV_REEL_LIGNE de l'inventaire ouvert reçoit des quantités de test puis sa quantité
// d'origine est renvoyée ; la date de comptage (dt_UPDATED) doit être remise à part (SQL).
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const hote = String.fromEnvironment('PRESTINV_REEL_HOTE');
const port = String.fromEnvironment('PRESTINV_REEL_PORT', defaultValue: '8080');
const login = String.fromEnvironment('PRESTINV_REEL_LOGIN', defaultValue: 'admin');
const mdp = String.fromEnvironment('PRESTINV_REEL_MDP');
const ligneTest = int.fromEnvironment('PRESTINV_REEL_LIGNE', defaultValue: 2);

void main() {
  final sansServeur = hote.isEmpty || mdp.isEmpty;

  test('essai réel : lecture, déjà compté, file persistante, inventaire ouvert, session, licence', skip: sansServeur ? 'serveur non fourni' : null,
      () async {
    SharedPreferences.setMockInitialValues({'localApiAddress': hote, 'localApiPort': port, 'sendMode': SendMode.direct.index});
    final config = AppConfig();
    await config.load();
    final journal = <String>[];
    void noter(String s) {
      journal.add(s);
      // ignore: avoid_print
      print('ESSAI RÉEL : $s');
    }

    // 1. Connexion
    final auth = AuthProvider();
    expect(await auth.login(login, mdp, config), isTrue, reason: auth.errorMessage);
    expect(auth.sessionCookie, startsWith('JSESSIONID='));
    noter('connexion OK (${config.currentApiUrl})');
    final api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);

    // 2. Lecture des inventaires / rayons / produits
    final inventaires = await api.fetchInventories(maxResult: 5);
    expect(inventaires, isNotEmpty);
    final inv = inventaires.first;
    noter('inventaires ouverts : ${inventaires.map((i) => i.libelle).join(', ')}');
    final rayons = await api.fetchRayons(inv.id);
    expect(rayons, isNotEmpty);
    final produits = await api.fetchProducts(inv.id, rayons.first.id);
    noter('${rayons.length} emplacement(s), ${produits.length} produit(s) dans « ${rayons.first.libelle} »');
    final cible = produits.firstWhere((p) => p.id == ligneTest);
    final origine = cible.quantiteSaisie;
    noter('ligne de test ${cible.id} « ${cible.produitName} » : quantité d\'origine $origine, comptée : ${cible.dtUpdated != null}');

    // 3. Inventaires ouverts (contrôle « inventaire clôturé »)
    final ouverts = await api.inventairesOuverts();
    expect(ouverts!.ids, contains(inv.id));

    // 4. « Déjà compté ? »
    final avant = await api.verifierDejaCompte(inv.id, cible.produitCip, ligneId: cible.id);
    noter('déjà compté avant essai : $avant');

    // 5. File persistante : saisie, envoi, correction pendant l'envoi, redémarrage
    final dossier = await Directory.systemTemp.createTemp('prestinv_reel_');
    final fichier = File('${dossier.path}/saisies_v1.jsonl');
    final q = SaisieQueue(store: FichierSaisieStore(fichier))..serveurFactory = () => api;
    await q.load();
    await q.enregistrer(inventaireId: inv.id, ligneId: cible.id, quantite: origine + 3, cip: cible.produitCip, nom: cible.produitName);
    final premier = q.envoyerLigne(inv.id, cible.id);
    await q.enregistrer(inventaireId: inv.id, ligneId: cible.id, quantite: origine + 7, cip: cible.produitCip, nom: cible.produitName);
    final r = await premier;
    await q.envoyerLigne(inv.id, cible.id);
    expect(r.estOk, isTrue, reason: r.message);
    expect(q.ligne(inv.id, cible.id)!.envoyee, isTrue);
    expect(q.ligne(inv.id, cible.id)!.quantiteEnvoyee, origine + 7);
    final apres = await api.verifierDejaCompte(inv.id, cible.produitCip, ligneId: cible.id);
    expect(apres, origine + 7);
    noter('file : correction pendant l\'envoi → serveur à ${origine + 7} (attendu ${origine + 7})');

    final q2 = SaisieQueue(store: FichierSaisieStore(fichier))..serveurFactory = () => api;
    await q2.load();
    expect(q2.ligne(inv.id, cible.id)!.envoyee, isTrue);
    noter('après redémarrage : saisie relue « envoyée »');

    // 6. Remise de la quantité d'origine
    await q2.enregistrer(inventaireId: inv.id, ligneId: cible.id, quantite: origine);
    final bilan = await q2.envoyer();
    expect(bilan.envoyees, 1);
    final fin = await api.fetchProducts(inv.id, rayons.first.id);
    expect(fin.firstWhere((p) => p.id == cible.id).quantiteSaisie, origine);
    noter('quantité d\'origine $origine renvoyée');
    await dossier.delete(recursive: true);

    // 7. Session absente : 401 → ApiLoadException « session » (et non liste vide)
    final sansSession = ApiService(baseUrl: config.currentApiUrl);
    await expectLater(sansSession.fetchProducts(inv.id, null, query: '1'),
        throwsA(isA<ApiLoadException>().having((e) => e.sessionExpiree, 'session', isTrue)));
    noter('sans session : detailsAll → 401 reconnu comme « session expirée »');

    // 8. Licence
    final licence = LicenseProvider();
    await licence.checkLicense(api);
    noter('licence : ${licence.status} (${licence.error ?? 'ok'})');
    final injoignable = ApiService(baseUrl: 'http://$hote:1/prestige');
    final l2 = LicenseProvider();
    SharedPreferences.setMockInitialValues({});
    await l2.checkLicense(injoignable);
    expect(l2.status, LicenseStatus.unreachable);
    noter('serveur injoignable (port 1) : ${l2.status}');
    final cle = await api.saveLicense('CLE-TEST').catchError((_) => false);
    noter('activation de licence depuis l\'app (POST) : ${cle ? 'acceptée' : 'refusée (attendu : 405)'}');

    await auth.logout(config);
  });
}
