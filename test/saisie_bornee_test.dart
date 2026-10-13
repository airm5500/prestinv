// Contrôles de saisie : quantités entières de 0 à 99 999, champ vide jamais lu comme 0,
// clavier limité à 5 chiffres, recherches/codes bornés et nettoyés.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/utils/saisie_input.dart';

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
}
