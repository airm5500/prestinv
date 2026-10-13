// ERGONOMIE / COHÉRENCE D'AFFICHAGE — chaque écran principal (catalogue_ecrans.dart), dans les deux
// interfaces, rendu sur tout le parc (Sunmi V2s 720×1440, Sunmi V3/V3H/V3mix 1080×1920, téléphone
// 360×640 dp, tablette 1920×1200) aux échelles de texte 1,0 et 1,3 :
//  - aucun débordement ni exception de rendu ;
//  - cibles tactiles ≥ 48 dp (androidTapTargetGuideline) et contraste du texte (textContrastGuideline).
// Variable PRESTINV_RELEVE=1 : relève tous les manquements sans faire échouer (diagnostic).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';

import '../helpers/banc_essai.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/ergonomie.dart';
import 'catalogue_ecrans.dart';

final bool releve = Platform.environment['PRESTINV_RELEVE'] == '1';

Future<Banc> banc() async {
  final b = await preparerBanc(serveur: serveurRealiste());
  b.auth.connecterPourTest(login: 'Awa K.', prenom: 'Awa');
  return b;
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });
  tearDown(() => InterfaceVersion.useNew.value = false);

  for (final ecran in [...ecransNouvelleInterface, ...ecransAncienneInterface]) {
    group(ecran.nom, () {
      for (final appareil in appareils) {
        for (final echelle in echellesTexte) {
          testWidgets('$appareil, texte ×$echelle', (tester) async {
            configurer(tester, appareil, echelle);
            final b = await banc();
            final rendu = await releverErreursRendu(tester, () async {
              await tester.pumpWidget(ecran.monterAvec(b));
              if (ecran.anime) {
                await tester.pump(const Duration(milliseconds: 800));
              } else {
                await tester.pumpAndSettle();
              }
              if (ecran.apres != null) await ecran.apres!(tester);
            });
            final semantique = tester.ensureSemantics();
            final acces = await manquementsAccessibilite(tester, ignorer: ecran.exemptions.keys.toSet());
            semantique.dispose();
            final tout = [...rendu.map((e) => 'rendu : $e'), ...acces];
            if (releve && tout.isNotEmpty) {
              // ignore: avoid_print
              print('RELEVÉ ${ecran.nom} | $appareil | ×$echelle\n${constats(tout)}');
            } else {
              expect(tout, isEmpty, reason: '${ecran.nom} sur $appareil, texte ×$echelle :\n${constats(tout)}');
            }
            await demonter(tester);
            reinitialiserVue(tester);
          });
        }
      }
    });
  }
}
