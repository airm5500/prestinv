// ERGONOMIE — 5.0.2 (demande du pharmacien) : titre « Prestige Inventaire v3 » (v minuscule) des écrans de
// LANCEMENT et de CONNEXION (deux interfaces), sur UNE SEULE ligne : écran étroit (320 dp), terminal Sunmi
// (360 dp), téléphone, tablette, police d'Android ×1,0 et ×1,3. Jamais de retour à la ligne, jamais de débordement
// (ni hors de l'écran, ni sous le bouton « Configuration »), texte encore lisible. Le nom du lanceur
// (« Prestige Inventaire V3 », [nomAppli]) ne change pas.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/identite_appli.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/login_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/lancement_screen.dart';

import '../helpers/banc_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/ergonomie.dart';
import 'catalogue_ecrans.dart';

/// Largeurs exigées : 320 dp (le plus étroit), Sunmi 360 dp, téléphone 360 dp, Sunmi V3, tablette.
const _appareils = <Appareil>[
  Appareil('Écran étroit 320 dp', Size(640, 1280), 2.0),
  ...appareils,
];

/// Écrans qui affichent le titre de connexion.
final _ecrans = <EcranControle>[
  EcranControle('Lancement', nouvelle: true, construire: () => const NvLancementScreen(), anime: true),
  EcranControle('Connexion', nouvelle: true, construire: () => const NvConnexionScreen()),
  EcranControle('Connexion (origine)', nouvelle: false, construire: () => const AncienLoginScreen()),
];

/// Nombre de lignes du texte affiché (boîtes de sélection de tout le texte, regroupées par ligne).
int _lignes(RenderParagraph p) {
  final boites = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: titreConnexion.length));
  return boites.map((b) => b.top.round()).toSet().length;
}

void main() {
  setUpAll(chargerPolicesReelles);
  tearDown(() => InterfaceVersion.useNew.value = false);

  test('titre de connexion « Prestige Inventaire v3 » ; nom de l\'application (lanceur) inchangé', () {
    expect(titreConnexion, 'Prestige Inventaire v3');
    expect(nomAppli, 'Prestige Inventaire V3');
    expect(tailleTitreConnexion, lessThan(22), reason: 'taille réduite (avant : 22)');
  });

  for (final ecran in _ecrans) {
    group(ecran.nom, () {
      for (final appareil in _appareils) {
        for (final echelle in echellesTexte) {
          testWidgets('$appareil, texte ×$echelle : « $titreConnexion » sur une seule ligne', (tester) async {
            configurer(tester, appareil, echelle);
            final b = await preparerBanc(serveur: serveurRealiste());
            final rendu = await releverErreursRendu(tester, () async {
              await tester.pumpWidget(ecran.monterAvec(b));
              if (ecran.anime) {
                await tester.pump(const Duration(milliseconds: 800));
              } else {
                await tester.pumpAndSettle();
              }
            });
            expect(rendu, isEmpty, reason: 'aucun débordement ni erreur de rendu');

            final titre = find.text(titreConnexion);
            expect(titre, findsOneWidget);
            expect(find.text(nomAppli), findsNothing, reason: 'plus de « V3 » majuscule dans le titre');
            final texte = tester.widget<Text>(titre);
            expect(texte.maxLines, 1);
            expect(texte.softWrap, isFalse);
            final p = tester.renderObject<RenderParagraph>(titre);
            expect(p.didExceedMaxLines, isFalse);
            expect(_lignes(p), 1, reason: 'jamais de retour à la ligne');

            // Dans l'écran, entier, et lisible (rétréci au plus juste si la place manque).
            final largeur = appareil.dp.width;
            final r = tester.getRect(titre);
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(largeur + 0.01), reason: 'débordement à droite : $r sur $largeur dp');
            expect(r.height, greaterThanOrEqualTo(14), reason: 'texte encore lisible : $r');
            // Taille réduite : au plus la taille demandée (jamais agrandi).
            if (ecran.nom == 'Connexion') {
              expect(r.height, lessThanOrEqualTo(tailleTitreConnexion * echelle * 1.5));
              // Jamais sous le bouton « Configuration » de l'en-tête.
              final config = tester.getRect(find.byTooltip('Configuration'));
              expect(r.right, lessThanOrEqualTo(config.left + 0.01), reason: 'titre $r, Configuration $config');
            }
            expect(tester.takeException(), isNull);
            await demonter(tester);
            reinitialiserVue(tester);
          });
        }
      }
    });
  }
}
