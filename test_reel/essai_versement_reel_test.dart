// Essai RÉEL (hors CI : dossier test_reel/) — création d'inventaire et versement de la collecte contre
// un serveur Prestige de TEST. À lancer avec test_reel/essai_versement_reel.sh (instantané de la base
// avant / après, suppression de l'inventaire de test) ou à la main :
//   flutter test test_reel/essai_versement_reel_test.dart \
//     --dart-define=PRESTINV_REEL_HOTE=localhost --dart-define=PRESTINV_REEL_PORT=8080 \
//     --dart-define=PRESTINV_REEL_LOGIN=admin --dart-define=PRESTINV_REEL_MDP=... \
//     --dart-define=PRESTINV_REEL_CODES=3000000258453:5,8438629:2,1234567890128:3 \
//     [--dart-define=PRESTINV_REEL_CIP_SECOURS=8050457,8438629,8521508]
//
// 1. Création d'un inventaire « ESSAI PRESTINV <heure> » par l'écran de création (service) ; contrôle
//    anti double (deuxième demande = doublon, rien de créé).
// 2. Si la création est impossible sur ce serveur (ex. serveur de test sans configuration historique),
//    un inventaire de test est créé par la route existante d'import CSV (PRESTINV_REEL_CIP_SECOURS) :
//    seulement pour disposer d'un inventaire où verser.
// 3. Versement des codes PRESTINV_REEL_CODES (code:quantité), dont un inconnu, mode « Remplacer » :
//    rapport (versés / non reconnus), quantités relues sur le serveur, reprise sans doublon.
// La ligne « ESSAI-INVENTAIRE <id> » de la sortie permet au script de supprimer l'inventaire de test.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/rapport_versement.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const hote = String.fromEnvironment('PRESTINV_REEL_HOTE');
const port = String.fromEnvironment('PRESTINV_REEL_PORT', defaultValue: '8080');
const login = String.fromEnvironment('PRESTINV_REEL_LOGIN', defaultValue: 'admin');
const mdp = String.fromEnvironment('PRESTINV_REEL_MDP');
const codes = String.fromEnvironment('PRESTINV_REEL_CODES');
const cipSecours = String.fromEnvironment('PRESTINV_REEL_CIP_SECOURS');

void main() {
  final sansServeur = hote.isEmpty || mdp.isEmpty || codes.isEmpty;

  test('essai réel : création d\'inventaire, versement de 3 codes dont 1 inconnu', skip: sansServeur ? 'serveur non fourni' : null, () async {
    SharedPreferences.setMockInitialValues({'localApiAddress': hote, 'localApiPort': port, 'sendMode': SendMode.direct.index});
    final config = AppConfig();
    await config.load();
    void noter(String s) => print('ESSAI RÉEL : $s');

    final auth = AuthProvider();
    expect(await auth.login(login, mdp, config), isTrue, reason: auth.errorMessage);
    final api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
    noter('connexion OK (${config.currentApiUrl})');

    // 1. Création par le service de l'application.
    final libelle = 'ESSAI PRESTINV ${DateTime.now().toIso8601String().substring(11, 19).replaceAll(':', 'h')}';
    final service = CreationInventaire(api);
    final r = await service.creer(libelle, TypeInventaire.emplacement);
    noter('création « $libelle » : ${r.issue.name}${r.lignes != null ? ' (${r.lignes} lignes)' : ''}${r.message.isEmpty ? '' : ' — ${r.message}'}');
    Inventory? inv = r.inventaire;
    if (r.ok) {
      expect(inv, isNotNull);
      print('ESSAI-INVENTAIRE ${inv!.id}');
      final double = await service.creer(libelle, TypeInventaire.emplacement);
      expect(double.issue, IssueCreation.doublon);
      noter('2ᵉ demande avec le même libellé : ${double.issue.name} (rien de créé)');
      final lignes = await api.fetchProducts(inv.id, null);
      noter('inventaire créé : ${lignes.length} ligne(s), comptées : ${lignes.where((p) => p.dtUpdated != null).length}');
    } else {
      // 2. Inventaire de test par la route d'import CSV (secours).
      expect(cipSecours, isNotEmpty, reason: 'création impossible et aucun CIP de secours fourni');
      final rep = await http.post(Uri.parse('${config.currentApiUrl}/api/v1/inventaire/import-csv'),
          headers: {'Content-Type': 'application/json', 'Cookie': auth.sessionCookie ?? ''},
          body: jsonEncode({'csvContent': cipSecours.split(',').join('\n')}));
      noter('secours import-csv : ${rep.statusCode} ${utf8.decode(rep.bodyBytes)}');
      final ouverts = await api.fetchTousInventairesOuverts();
      inv = ouverts.firstWhere((i) => i.libelle == 'INVENTAIRE CSV');
      print('ESSAI-INVENTAIRE ${inv.id}');
    }

    // 3. Versement.
    final collecte = [
      for (final c in codes.split(','))
        CollectedItem(code: c.split(':').first, quantity: int.parse(c.split(':').last), dateScan: DateTime.now()),
    ];
    final dossier = await Directory.systemTemp.createTemp('prestinv_reel_versement_');
    final queue = SaisieQueue(store: FichierSaisieStore(File('${dossier.path}/saisies_v1.jsonl')))..serveurFactory = () => api;
    await queue.load();
    final moteur = MoteurVersement(api: api, queue: queue, auteur: login);
    final v = Versement.depuisCollecte(collecte, inventaireId: inv.id, inventaireLibelle: inv.libelle, mode: ModeDejaCompte.remplacer);
    final fini = await moteur.executer(v, onAvancement: (a) => noter('avancement ${a.fait}/${a.total} ${a.etape}'));
    noter('rapport : ${resumeVersement(fini).replaceAll('\n', ' | ')}');
    for (final l in fini.lignes) {
      noter('  ${l.code} ×${l.quantiteCollectee} → ${libelleEtatLigne(l, fini.mode)}${l.ligneId != null ? ' (ligne ${l.ligneId}, CIP ${l.cip})' : ''}${l.raison != null ? ' — ${l.raison}' : ''}');
    }
    expect(fini.nonReconnues.length, 1);
    expect(fini.versees.length, collecte.length - 1);
    final apres = {for (final p in await api.fetchProducts(inv.id, null)) p.id: p};
    for (final l in fini.versees) {
      expect(apres[l.ligneId]!.quantiteSaisie, l.quantiteCible);
      expect(apres[l.ligneId]!.dtUpdated, isNotNull);
    }
    noter('quantités relues sur le serveur : ${fini.versees.map((l) => '${l.cip}=${apres[l.ligneId]!.quantiteSaisie}').join(', ')}');

    // Reprise / double appui : rien n'est renvoyé.
    final requetesAvant = queue.lignes().where((s) => s.envoyee).map((s) => s.version).toList();
    await moteur.executer(fini);
    expect(queue.lignes().where((s) => s.envoyee).map((s) => s.version).toList(), requetesAvant);
    noter('2ᵉ exécution du même versement : aucune quantité renvoyée');
    print('CSV-RAPPORT\n${rapportCsv(fini)}FIN-CSV');

    await dossier.delete(recursive: true);
    await auth.logout(config);
  });
}
