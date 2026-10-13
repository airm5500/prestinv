// DE BOUT EN BOUT — les parcours du test d'intégration sur appareil (integration_test/parcours_origine.dart)
// joués ici contre le faux serveur Prestige : integration_test/app_test.dart reste ainsi cohérent
// avec les écrans actuels (il ne peut tourner, lui, qu'avec un terminal et un vrai serveur).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/services/identifiants_securises.dart';

import '../../integration_test/parcours_origine.dart';
import '../helpers/banc_essai.dart';
import '../helpers/coffre_memoire.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

const _p = ParametresEssai(login: CompteFictif.login, motDePasse: CompteFictif.motDePasse, hote: adresseServeurFictive, recherche: 'VOLTARENE');

late FauxServeurPrestige serveur;

Future<void> lancer(WidgetTester tester) async {
  ecranTerminal(tester);
  serveur = FauxServeurPrestige();
  ApiService.clientParDefaut = serveur.client;
  IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: CoffreMemoire());
  reinitialiserDouchette();
  installerFauxRetour();
  await lancerOrigine(tester, _p, store: DisqueMemoire());
}

void main() {
  setUpAll(chargerPolicesReelles);
  tearDown(() {
    ApiService.clientParDefaut = null;
    SaisieQueue.instance = null;
    IdentifiantsSecurises.instance = IdentifiantsSecurises();
  });

  testWidgets('integration_test — flux principal : connexion → saisie → envoi', (tester) async {
    await lancer(tester);
    await connecterOrigine(tester, _p);
    await parcoursSaisieOrigine(tester, _p);
    expect(serveur.catalogue.produits.where((p) => p.saisi == 99), hasLength(1), reason: 'quantité 99 envoyée au serveur');
    await demonter(tester);
  });

  testWidgets('integration_test — déconnexion', (tester) async {
    await lancer(tester);
    await connecterOrigine(tester, _p);
    await parcoursDeconnexionOrigine(tester, _p);
    await demonter(tester);
  });

  testWidgets('integration_test — écarts de l\'emplacement et recherche', (tester) async {
    await lancer(tester);
    await connecterOrigine(tester, _p);
    await parcoursSaisieOrigine(tester, _p);
    await parcoursEcartsOrigine(tester, _p);
    await demonter(tester);
  });
}
