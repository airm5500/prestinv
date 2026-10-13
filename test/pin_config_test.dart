// Configuration du serveur protégée par le code administrateur (empreinte PBKDF2, jamais en clair,
// anti-force brute, code par défaut à changer obligatoirement).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/services/pin_securise.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/banc_essai.dart';
import 'helpers/coffre_memoire.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late CoffreMemoire coffre;
  late DateTime maintenant;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    coffre = CoffreMemoire();
    maintenant = DateTime(2026, 10, 13, 9);
    CodeAdmin.instance = CodeAdmin(coffre: coffre, iterations: 1000, horloge: () => maintenant);
  });

  test('PBKDF2-HMAC-SHA256 : vecteur de test RFC 7914 (passwd / salt / 1 itération)', () {
    final dk = Pbkdf2Sha256.deriver(utf8.encode('passwd'), utf8.encode('salt'), 1, 64);
    expect(hex(dk),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783');
  });

  test('code par défaut 1234 : n\'ouvre que le changement obligatoire ; nouveau code gardé en EMPREINTE', () async {
    final c = CodeAdmin.instance;
    expect(await c.verifier('1234'), VerificationPin.changementObligatoire);
    expect(await c.definir('1234'), isNotNull); // défaut interdit
    expect(await c.definir('1111'), isNotNull); // trop simple
    expect(await c.definir('3456'), isNotNull); // suite
    expect(await c.definir('7391'), isNull);
    final garde = coffre.valeurs[CodeAdmin.cleSure]!;
    expect(garde, startsWith('pbkdf2-sha256\$'));
    expect(garde, isNot(contains('7391')));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => '${prefs.get(k)}'.contains('7391')), isFalse);
    expect(await c.verifier('7391'), VerificationPin.accepte);
    expect(await c.verifier('1234'), VerificationPin.refuse);
  });

  test('anti-force brute : après 5 erreurs, attente', () async {
    final c = CodeAdmin.instance;
    await c.definir('7391');
    for (var i = 0; i < 4; i++) {
      expect(await c.verifier('0000'), VerificationPin.refuse);
    }
    expect(await c.verifier('0000'), VerificationPin.bloque);
    expect(await c.verifier('7391'), VerificationPin.bloque); // même le bon code attend
    maintenant = maintenant.add(const Duration(seconds: 31));
    expect(await c.verifier('7391'), VerificationPin.accepte);
  });

  testWidgets('Configuration : adresse du serveur verrouillée ; code correct → modifiable et enregistrée', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const ConfigScreen()));
    await tester.pumpAndSettle();

    final adresse = find.widgetWithText(TextFormField, 'serveur-test');
    expect(tester.widget<TextFormField>(adresse).enabled, isFalse);

    // Premier usage : 1234 puis choix obligatoire d'un nouveau code.
    await tester.tap(find.text('Modifier la connexion (code administrateur)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Code'), '1234');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir le code administrateur'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nouveau code'), '7391');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmer le code'), '7391');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(adresse).enabled, isTrue);

    await tester.enterText(adresse, '10.0.0.5');
    await tester.ensureVisible(find.text('VALIDER LA CONFIGURATION'));
    await tester.tap(find.text('VALIDER LA CONFIGURATION'));
    await tester.pumpAndSettle();
    expect(b.config.localApiAddress, '10.0.0.5');
    await demonter(tester);
  });

  testWidgets('Configuration : mauvais code → reste verrouillée', (tester) async {
    ecranTerminal(tester);
    await CodeAdmin.instance.definir('7391');
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const ConfigScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier la connexion (code administrateur)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Code'), '0000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Code incorrect.'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'serveur-test')).enabled, isFalse);
    await demonter(tester);
  });
}
