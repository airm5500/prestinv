// Contrôles de saisie : quantités entières de 0 à 99 999, champ vide jamais lu comme 0,
// clavier limité à 5 chiffres, recherches/codes bornés et nettoyés.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('quantité', () {
    test('champ vide ou blanc : refusé (jamais 0 implicite)', () {
      expect(SaisieInput.parseQuantite(''), isNull);
      expect(SaisieInput.parseQuantite('   '), isNull);
      expect(SaisieInput.parseQuantite(null), isNull);
      expect(SaisieInput.erreurQuantite(''), 'Veuillez saisir une quantité.');
    });

    test('0 saisi explicitement : accepté', () {
      expect(SaisieInput.parseQuantite('0'), 0);
      expect(SaisieInput.erreurQuantite('0'), isNull);
    });

    test('bornes 0 à 99 999, entiers seulement', () {
      expect(SaisieInput.parseQuantite('99999'), 99999);
      expect(SaisieInput.parseQuantite('100000'), isNull);
      expect(SaisieInput.parseQuantite('123456789012345678901'), isNull); // ne devient plus 0
      expect(SaisieInput.parseQuantite('-3'), isNull);
      expect(SaisieInput.parseQuantite('2.5'), isNull);
      expect(SaisieInput.parseQuantite('1e3'), isNull);
      expect(SaisieInput.erreurQuantite('100000'), contains('99999'));
    });

    test('clavier maison : 5 chiffres au plus, touches non numériques ignorées', () {
      var t = '';
      for (final k in ['1', '2', '3', '4', '5', '6', '7']) {
        t = SaisieInput.ajouterChiffre(t, k);
      }
      expect(t, '12345');
      expect(SaisieInput.ajouterChiffre('12', 'OK'), '12');
      expect(SaisieInput.ajouterChiffre('12', 'DEL'), '12');
    });
  });

  group('recherche / code scanné', () {
    test('caractères de contrôle retirés (préfixe/suffixe de douchette) et longueur bornée', () {
      expect(SaisieInput.nettoyerRecherche('\u0002 3400930000000\r\n'), '3400930000000');
      expect(SaisieInput.nettoyerRecherche('x' * 200).length, SaisieInput.maxRecherche);
      expect(SaisieInput.nettoyerRecherche(null), '');
    });
  });

  group('configuration', () {
    test('adresse : IP, domaine, http:// et https:// acceptés ; le reste refusé', () {
      expect(SaisieInput.erreurAdresse('192.168.1.50'), isNull);
      expect(SaisieInput.erreurAdresse('pharmacie.example.ci'), isNull);
      expect(SaisieInput.erreurAdresse('http://192.168.1.50'), isNull);
      expect(SaisieInput.erreurAdresse('https://prestige.example.ci/'), isNull);
      expect(SaisieInput.erreurAdresse(''), isNotNull);
      expect(SaisieInput.erreurAdresse('', obligatoire: false), isNull);
      expect(SaisieInput.erreurAdresse('192.168.1.300'), isNotNull);
      expect(SaisieInput.erreurAdresse('192.168.1'), isNotNull);
      expect(SaisieInput.erreurAdresse('serveur:8080'), contains('Port'));
      expect(SaisieInput.erreurAdresse('serveur/prestige'), isNotNull);
      expect(SaisieInput.erreurAdresse('mon serveur'), isNotNull);
    });

    test('port 1 à 65535 (vide = défaut), contexte, entiers bornés', () {
      expect(SaisieInput.erreurPort(''), isNull);
      expect(SaisieInput.erreurPort('8080'), isNull);
      expect(SaisieInput.erreurPort('0'), isNotNull);
      expect(SaisieInput.erreurPort('70000'), isNotNull);
      expect(SaisieInput.erreurContexte('prestige'), isNull);
      expect(SaisieInput.erreurContexte('pres tige'), isNotNull);
      expect(SaisieInput.erreurEntier('0', 1, 100, 'Nombre'), isNotNull);
      expect(SaisieInput.erreurEntier('5', 1, 100, 'Nombre'), isNull);
      expect(SaisieInput.erreurEntier('', 0, 600, 'Délai'), isNotNull);
    });

    test('clé de licence nettoyée et bornée', () {
      expect(SaisieInput.nettoyerCleLicence(' AB-12\n'), 'AB-12');
      expect(SaisieInput.nettoyerCleLicence('x' * 500).length, 200);
    });

    test('URL du serveur : http par défaut, https accepté (non imposé), barre finale retirée', () async {
      SharedPreferences.setMockInitialValues({'localApiAddress': 'https://prestige.example.ci/', 'localApiPort': '8443'});
      final c = AppConfig();
      await c.load();
      expect(c.currentApiUrl, 'https://prestige.example.ci:8443/prestige');
      await c.setApiConfig(localAddress: '192.168.1.50', localPort: '8080');
      expect(c.currentApiUrl, 'http://192.168.1.50:8080/prestige');
    });
  });
}
