// Session expirée (401) : « Se reconnecter » dans une fenêtre, sans quitter l'écran ; la file des
// saisies est conservée et repart après la reconnexion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/screens/inventory_list_screen.dart';

import 'helpers/banc_essai.dart';
import 'helpers/faux_serveur.dart';

void main() {
  testWidgets('401 sur la liste : Se reconnecter → fenêtre → liste rechargée', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    b.serveur.codes['inventaires'] = 401;
    await tester.pumpWidget(monter(b, const InventoryListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Session expirée'), findsOneWidget);
    await tester.tap(find.text('Se reconnecter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reconnectez-vous pour continuer'), findsOneWidget);

    b.serveur.codes.clear();
    await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'secret');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Se reconnecter'));
    await tester.pumpAndSettle();
    expect(b.auth.sessionCookie, 'JSESSIONID=abc');
    expect(find.text('Inventaire test'), findsOneWidget);
    await demonter(tester);
  });

  test('file : 401 pendant l\'envoi → saisies gardées ; après reconnexion, elles partent', () async {
    final f = await FileDeTest.creer();
    addTearDown(f.nettoyer);
    final serveur = FauxServeur()..panne = ResultatEnvoi.session;
    final q = await f.ouvrir(serveur: serveur);
    q.modeDirect = () => true;
    for (var i = 1; i <= 3; i++) {
      await saisir(q, i, i);
    }
    final bilan = await q.envoyer();
    expect(bilan.sessionExpiree, isTrue);
    expect(q.enAttente(), 3);

    // « Redémarrage » de l'appli pendant que la session est expirée : rien n'est perdu.
    final q2 = await f.ouvrir(serveur: serveur);
    q2.modeDirect = () => true;
    expect(q2.enAttente(), 3);
    serveur.panne = null;
    q2.signalerReconnexion();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(serveur.quantites, {1: 1, 2: 2, 3: 3});
  });
}
