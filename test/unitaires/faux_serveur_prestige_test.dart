// UNITAIRE — le faux serveur Prestige lui-même (test/support/faux_serveur_prestige.dart) : les autres
// tests reposent sur lui, il doit donc se comporter exactement comme annoncé, et de la même façon par
// ses deux transports (en mémoire et HTTP local).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  // Les deux transports, mêmes attentes.
  for (final transport in ['en mémoire', 'HTTP 127.0.0.1']) {
    group('transport $transport', () {
      late FauxServeurPrestige s;
      late http.Client client;
      late String base;
      setUp(() async {
        s = FauxServeurPrestige();
        if (transport == 'en mémoire') {
          client = s.client;
          base = 'http://$adresseServeurFictive:8080/prestige';
        } else {
          base = await s.demarrer();
          client = IOClient(HttpClient());
        }
      });
      tearDown(() async {
        client.close();
        await s.arreter();
      });

      Future<http.Response> connexion([String mdp = CompteFictif.motDePasse]) => client.post(Uri.parse('$base/api/v1/user/auth'),
          headers: {'Content-Type': 'application/json'}, body: json.encode({'login': CompteFictif.login, 'password': mdp}));

      test('connexion : cookie délivré ; mauvais mot de passe : success:false sans cookie', () async {
        final ok = await connexion();
        expect(ok.statusCode, 200);
        expect(ok.headers['set-cookie'], startsWith('JSESSIONID=essai-1'));
        expect(json.decode(ok.body)['success'], isTrue);
        final ko = await connexion('faux');
        expect(json.decode(ko.body), {'success': false, 'message': 'Identifiant ou mot de passe incorrect.'});
        expect(ko.headers['set-cookie'], isNull);
      });

      test('route protégée : 401 sans cookie, 200 avec, 401 après expiration', () async {
        final url = Uri.parse('$base/api/v1/ws/inventaires');
        expect((await client.get(url)).statusCode, 401);
        await connexion();
        expect((await client.get(url, headers: {'Cookie': 'JSESSIONID=essai-1'})).statusCode, 200);
        s.expirerSessions();
        expect((await client.get(url, headers: {'Cookie': 'JSESSIONID=essai-1'})).statusCode, 401);
        expect(s.recues('ws/inventaires').map((r) => r.cookie), [null, 'JSESSIONID=essai-1', 'JSESSIONID=essai-1']);
      });

      test('licence publique ; scénario n fois puis retour à la normale', () async {
        final url = Uri.parse('$base/api/v1/licence/find');
        s.scripter('licence/find', ReponseScriptee.code(503, fois: 2));
        expect([for (var i = 0; i < 3; i++) (await client.get(url)).statusCode], [503, 503, 200]);
      });

      test('success:false scripté, délai, coupure, serveur coupé puis rétabli', () async {
        await connexion();
        final h = {'Cookie': 'JSESSIONID=essai-1'};
        s.scripter('rayons', ReponseScriptee.echec('Inventaire clos.'));
        expect(json.decode((await client.get(Uri.parse('$base/api/v1/ws/inventaires/rayons?idInventaire=INV1'), headers: h)).body),
            {'success': false, 'message': 'Inventaire clos.'});
        s.oublierScripts();
        s.scripter('rayons', ReponseScriptee.lente(const Duration(milliseconds: 200)));
        final debut = DateTime.now();
        final r = await client.get(Uri.parse('$base/api/v1/ws/inventaires/rayons?idInventaire=INV1'), headers: h);
        expect(DateTime.now().difference(debut), greaterThanOrEqualTo(const Duration(milliseconds: 190)));
        expect((json.decode(r.body) as List).length, 3);
        s.scripter('rayons', ReponseScriptee.coupee(fois: 1));
        await expectLater(client.get(Uri.parse('$base/api/v1/ws/inventaires/rayons'), headers: h), throwsA(anything));
        s.couper();
        await expectLater(client.get(Uri.parse('$base/api/v1/licence/find')), throwsA(anything));
        s.retablir();
        expect((await client.get(Uri.parse('$base/api/v1/licence/find'))).statusCode, 200);
      });
    });
  }

  test('données fictives : licence toujours valide aujourd\'hui, compte fictif', () {
    final l = licenceFictive();
    expect(DateTime.parse(l['dateEnd'] as String).isAfter(DateTime.now()), isTrue);
    expect(CompteFictif.login, contains('essai'));
    expect(CompteFictif.motDePasse, contains('fictif'));
  });
}
