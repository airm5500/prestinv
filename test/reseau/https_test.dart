// RÉSEAU — HTTPS. L'application accepte une adresse « https://… » (AppConfig.currentApiUrl). Le faux
// serveur Prestige est servi en VRAI HTTPS (HttpServer.bindSecure, 127.0.0.1) avec un certificat de test
// AUTO-SIGNÉ généré à la volée par openssl (jamais versionné : aucune clé privée dans le dépôt) :
//  - certificat approuvé SEULEMENT dans ce test (client HTTP dont le SecurityContext le reconnaît) :
//    licence, connexion, cookie, listes et envoi d'une quantité fonctionnent comme en HTTP ;
//  - client de l'application tel quel (certificat inconnu) : « Certificat du serveur refusé… », message
//    DÉDIÉ, distinct de « serveur injoignable » (licence, connexion, listes, envoi, création) — 4.14.2 ;
//  - écran de démarrage : le motif « certificat » est affiché (voir aussi l'anomalie A7 du README).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/license_provider.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/coffre_memoire.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/application_essai.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

/// Certificat de test auto-signé (127.0.0.1 / localhost), valable 2 jours, généré dans un dossier
/// temporaire. null si openssl est absent (tests sautés, motif affiché).
({String cert, String cle})? genererCertificat() {
  try {
    final d = Directory.systemTemp.createTempSync('prestinv_tls_');
    final r = Process.runSync('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', //
      '-keyout', '${d.path}/cle.pem', '-out', '${d.path}/cert.pem',
      '-subj', '/CN=127.0.0.1', '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost',
    ]);
    if (r.exitCode != 0) return null;
    return (cert: '${d.path}/cert.pem', cle: '${d.path}/cle.pem');
  } on ProcessException {
    return null;
  }
}

final certificat = genererCertificat();
final sansOpenssl = certificat == null ? 'openssl absent : certificat de test impossible à générer' : null;

late FauxServeurPrestige serveur;
late String base;

/// Client HTTP qui approuve le certificat de test (et lui seul).
http.Client clientApprouvant() =>
    IOClient(HttpClient(context: SecurityContext(withTrustedRoots: false)..setTrustedCertificates(certificat!.cert)));

Future<AppConfig> configHttps() async {
  SharedPreferences.setMockInitialValues({'localApiAddress': 'https://127.0.0.1', 'localApiPort': '${serveur.port}', 'appName': 'prestige'});
  final c = AppConfig();
  await c.load();
  return c;
}

void main() {
  group('HTTPS (vrai serveur local, certificat de test)', () {
    setUpAll(() {
      HttpOverrides.global = null;
      IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: CoffreMemoire());
    });

    setUp(() async {
      if (certificat == null) return;
      ApiService.clientParDefaut = null;
      serveur = FauxServeurPrestige();
      final ctx = SecurityContext()
        ..useCertificateChain(certificat!.cert)
        ..usePrivateKey(certificat!.cle);
      base = await serveur.demarrerSecurise(ctx);
    });

    tearDown(() async {
      ApiService.clientParDefaut = null;
      if (certificat != null) await serveur.arreter();
    });

    test('adresse « https://… » : l\'application appelle le serveur en HTTPS', () async {
      final config = await configHttps();
      expect(config.currentApiUrl, startsWith('https://127.0.0.1:'));
      expect(base, startsWith('https://'));
    }, skip: sansOpenssl);

    test('certificat approuvé : licence, connexion (cookie), inventaires, envoi d\'une quantité', () async {
      ApiService.clientParDefaut = clientApprouvant();
      final config = await configHttps();
      final licence = LicenseProvider();
      await licence.checkLicense(ApiService(baseUrl: config.currentApiUrl));
      expect(licence.status, LicenseStatus.valid);

      final auth = AuthProvider();
      expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue, reason: auth.errorMessage);
      final api = ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie);
      final invs = await api.fetchTousInventairesOuverts();
      expect(invs.map((i) => i.id), containsAll(['INV1', 'INV2']));
      expect((await api.poserQuantite(2, 9)).type, ResultatEnvoi.ok);
      expect(serveur.catalogue.produit(2).saisi, 9);
      expect(serveur.recues('details', methode: 'PUT').single.cookie, contains('JSESSIONID='));
    }, skip: sansOpenssl);

    group('certificat refusé (client de l\'application, certificat inconnu)', () {
      bool dedie(String? m) => m != null && m.contains('Certificat du serveur refusé') && !m.toLowerCase().contains('injoignable');

      test('licence au lancement : motif « certificat », jamais « aucune licence »', () async {
        SharedPreferences.setMockInitialValues({});
        final l = LicenseProvider();
        await l.checkLicense(ApiService(baseUrl: base));
        expect(l.status, LicenseStatus.unreachable, reason: 'le serveur n\'est pas en cause pour la licence');
        expect(dedie(l.error), isTrue, reason: '${l.error}');
      }, skip: sansOpenssl);

      test('connexion : message dédié (≠ « Erreur de connexion… réseau »)', () async {
        final config = await configHttps();
        final auth = AuthProvider();
        expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isFalse);
        expect(dedie(auth.errorMessage), isTrue, reason: '${auth.errorMessage}');
        expect(serveur.requetes, isEmpty, reason: 'rien n\'est parti : poignée de main refusée');
      }, skip: sansOpenssl);

      test('listes, « déjà compté », envoi, création : message dédié', () async {
        final api = ApiService(baseUrl: base, sessionCookie: 'JSESSIONID=x');
        await expectLater(api.fetchRayons('INV1'), throwsA(isA<ApiLoadException>().having((e) => dedie(e.message), 'message dédié', isTrue)));
        await expectLater(api.verifierDejaCompte('INV1', '3400930000001'), throwsA(isA<ApiLoadException>().having((e) => dedie(e.message), 'dédié', isTrue)));
        final envoi = await api.poserQuantite(2, 3);
        expect(envoi.type, ResultatEnvoi.reseau, reason: 'saisie gardée, nouvel essai plus tard');
        expect(dedie(envoi.message), isTrue, reason: envoi.message);
        final creation = await api.creerInventaire('Essai', 'Emplacement');
        expect(creation.succes, isFalse);
        expect(creation.incertain, isFalse, reason: 'la demande n\'est jamais partie');
        expect(dedie(creation.message), isTrue, reason: creation.message);
      }, skip: sansOpenssl);

      test('serveur réellement injoignable : toujours « injoignable » (pas « certificat »)', () async {
        await serveur.arreter();
        final api = ApiService(baseUrl: base);
        await expectLater(
            api.fetchRayons('INV1'),
            throwsA(isA<ApiLoadException>()
                .having((e) => e.message, 'message', contains('injoignable'))
                .having((e) => e.message, 'message', isNot(contains('Certificat')))));
      }, skip: sansOpenssl);
    });
  });

  group('Écrans (certificat refusé simulé : exception levée par le client HTTPS)', () {
    setUpAll(chargerPolicesReelles);

    testWidgets('connexion (nouvelle interface) : message « Certificat du serveur refusé », pas « réseau »', (tester) async {
      tailleEcran(tester, telephone360);
      final srv = ServeurCertificatRefuse()..refuser = false;
      await lancerApplication(tester, serveur: srv);
      srv.refuser = true; // certificat du serveur changé après le lancement
      await seConnecter(tester);
      expect(find.textContaining('Certificat du serveur refusé'), findsOneWidget);
      expect(find.textContaining('Erreur de connexion'), findsNothing);
      await fermerApplication(tester);
    });

    testWidgets('connexion (ancienne interface) : message « Certificat du serveur refusé »', (tester) async {
      tailleEcran(tester, telephone360);
      final srv = ServeurCertificatRefuse()..refuser = false;
      await lancerApplication(tester, serveur: srv, nouvelleInterface: false);
      srv.refuser = true;
      await seConnecter(tester);
      expect(find.textContaining('Certificat du serveur refusé'), findsOneWidget);
      await fermerApplication(tester);
    });

    testWidgets('lancement (nouvelle interface, aucune licence en cache) : écran « Certificat du serveur refusé »', (tester) async {
      tailleEcran(tester, telephone360);
      await lancerApplication(tester, serveur: ServeurCertificatRefuse());
      expect(find.byKey(const ValueKey('nv-reessayer-serveur')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('nv-titre-injoignable'))).data, 'Certificat du serveur refusé');
      expect(find.text('Serveur injoignable'), findsNothing);
      expect(find.textContaining('certificat de sécurité (HTTPS)'), findsOneWidget);
      expect(find.text('Application non activée'), findsNothing);
      await fermerApplication(tester);
    });

    testWidgets('lancement (ancienne interface) : motif « Certificat du serveur refusé » affiché', (tester) async {
      tailleEcran(tester, telephone360);
      await lancerApplication(tester, serveur: ServeurCertificatRefuse(), nouvelleInterface: false);
      expect(find.textContaining('Certificat du serveur refusé'), findsOneWidget);
      await fermerApplication(tester);
    });

    group('', skip: 'Anomalie connue A7 : écran d\'origine (gelé) « Serveur injoignable » — titre non dédié au certificat (motif affiché dessous)',
        () => testWidgets('lancement (ancienne interface) : écran au titre « Certificat du serveur refusé »', (tester) async {
      tailleEcran(tester, telephone360);
      await lancerApplication(tester, serveur: ServeurCertificatRefuse(), nouvelleInterface: false);
      expect(find.textContaining('Certificat du serveur refusé'), findsWidgets, reason: 'motif affiché sous le titre');
      expect(find.text('Serveur injoignable'), findsNothing);
      await fermerApplication(tester);
    }));
  });
}

/// Faux serveur dont le client HTTP lève HandshakeException, comme le vrai client quand le certificat
/// est refusé (vérifié en vrai HTTPS ci-dessus) : pour les écrans (temps simulé, pas de vrai socket).
class ServeurCertificatRefuse extends FauxServeurPrestige {
  bool refuser = true;

  @override
  http.Client get client => MockClient((req) async {
        if (refuser) throw const HandshakeException('CERTIFICATE_VERIFY_FAILED: self signed certificate');
        return traiter(req);
      });
}
