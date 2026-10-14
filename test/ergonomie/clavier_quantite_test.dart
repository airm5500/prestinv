// ERGONOMIE — le champ de QUANTITÉ reste visible, en saisie guidée et en saisie par scan, dans les
// deux interfaces, sur tout le parc d'appareils et aux deux échelles de texte :
//  A. au-dessus du pavé numérique de l'écran (jamais recouvert, jamais hors de l'écran) ;
//  B. au-dessus du clavier SYSTÈME (viewInsets simulés) quand la fenêtre / feuille de quantité
//     s'ouvre alors que ce clavier est déjà affiché (scan tapé à la main, recherche par nom) ;
//  C. recherche par nom en saisie guidée (seul cas où le clavier système s'ouvre) : aucun
//     débordement, et la quantité revient à l'écran dès que le clavier se referme.
// Un champ caché = une quantité tapée à l'aveugle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/collection_screen.dart';
import 'package:prestinv/screens/inventory_entry_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/taille_ecran.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';

import '../helpers/banc_essai.dart';
import '../helpers/douchette_essai.dart';
import '../helpers/nouvelle_interface.dart';
import '../support/ergonomie.dart';
import 'catalogue_ecrans.dart';

/// Situation de saisie : écran monté puis amené jusqu'à la saisie d'une quantité.
class SituationSaisie {
  final String nom;
  final bool nouvelle;
  final Widget Function() ecran;
  final Future<void> Function(WidgetTester tester) amener;
  final Finder Function() champ;

  /// Fenêtre / feuille de quantité ouverte par un scan (cas B).
  final bool fenetre;

  /// Anomalie connue (test/README.md) qui empêche le cas B partout ; null = exigé.
  final String? anomalieB;

  /// Anomalies connues limitées à certaines configurations : clé « cas|appareil|échelle »
  /// (ex. 'A|Sunmi V2s|1.3'), valeur = raison. Ces seules configurations sont sautées ; toutes les
  /// autres restent exigées (une régression ailleurs fait échouer le test).
  final Map<String, String> anomalies;
  const SituationSaisie(this.nom,
      {required this.nouvelle,
      required this.ecran,
      required this.amener,
      required this.champ,
      this.fenetre = false,
      this.anomalieB,
      this.anomalies = const {}});

  /// Raison de saut pour le cas [cas] sur [a] à l'échelle [e], ou null (exigé).
  String? anomalie(String cas, Appareil a, double e) => cas == 'B' && anomalieB != null ? anomalieB : anomalies['$cas|${a.nom}|$e'];
}

/// Configurations où une anomalie connue se produit (cas × appareils × échelles).
Map<String, String> anomaliesSur(List<String> cas, List<(String, double)> configs, String raison) =>
    {for (final c in cas) for (final (a, e) in configs) '$c|$a|$e': raison};

const _v2s = 'Sunmi V2s', _v3 = 'Sunmi V3 / V3H / V3mix', _tel = 'Téléphone 360×640 dp';

const _a5 = 'Anomalie connue A5 (interface d\'origine) : en saisie guidée, sur écran de 640 dp de haut (Sunmi V3, téléphone) ou en texte agrandi, le '
    'champ de quantité est poussé sous le bas de la liste défilante, derrière le pavé (voir test/README.md)';
const _a4 = 'Anomalie connue A4 (interface d\'origine) : pendant la recherche par nom (clavier système ouvert), le champ de '
    'quantité sort de la zone visible ; il revient à la fermeture du clavier (voir test/README.md)';

Future<void> rien(WidgetTester tester) async {}

Future<void> scannerDouchette(WidgetTester tester) async {
  await douchette(tester, '3400930000001');
  await tester.pumpAndSettle();
}

/// Écran d'origine de la collecte : champ texte simple (douchette en émulation clavier, ou frappe).
Future<void> scannerChampTexte(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Scanner un code'), '3400930000001');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Finder quantiteScanOrigine() => find.byKey(const ValueKey('qte-scan'));

final situations = <SituationSaisie>[
  SituationSaisie('Saisie guidée (nouvelle)',
      nouvelle: true,
      ecran: () => NvSaisieGuideeScreen(inventaire: inventaireEssai, rayonId: 'S2B2'),
      amener: rien,
      champ: quantiteNv),
  SituationSaisie('Scan continu, feuille de quantité (nouvelle)',
      nouvelle: true, ecran: () => NvScanContinuScreen(inventaire: inventaireEssai), amener: scannerDouchette, champ: quantiteNv, fenetre: true),
  SituationSaisie('Collecte, feuille de quantité (nouvelle)',
      nouvelle: true, ecran: () => const NvCollecteScreen(), amener: scannerDouchette, champ: quantiteNv, fenetre: true),
  SituationSaisie('Saisie guidée (origine)',
      nouvelle: false,
      ecran: () => InventoryEntryScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle),
      amener: ouvrirEmplacementOrigine,
      champ: quantiteOrigine,
      anomalies: {
        ...anomaliesSur(['A'], [(_v2s, 1.3), (_v3, 1.0), (_v3, 1.3), (_tel, 1.0), (_tel, 1.3)], _a5),
        for (final a in appareils)
          for (final e in echellesTexte) 'Cbis|${a.nom}|$e': _a4,
      }),
  SituationSaisie('Saisie rapide, fenêtre de quantité (origine)',
      nouvelle: false,
      ecran: () => InventoryEntryScreen(inventoryId: 'INV1', inventoryName: inventaireEssai.libelle, isQuickMode: true),
      amener: scannerDouchette,
      champ: quantiteScanOrigine,
      fenetre: true),
  SituationSaisie('Collecte, fenêtre de quantité (origine)',
      nouvelle: false,
      ecran: () => const CollectionScreen(),
      amener: scannerChampTexte,
      champ: () => quantiteOrigine().last,
      fenetre: true),
];

/// Haut du pavé numérique affiché (nouvelle ou ancienne interface), ou null.
double? hautDuPave(WidgetTester tester) {
  final touches = find.byKey(const ValueKey('touche-1'));
  if (touches.evaluate().isNotEmpty) return tester.getRect(touches.last).top;
  final pave = find.byType(NumericKeyboard);
  if (pave.evaluate().isNotEmpty) return tester.getRect(pave.last).top;
  return null;
}

Future<Banc> monterSituation(WidgetTester tester, SituationSaisie s, {TailleEcran taille = TailleEcran.automatique}) async {
  final b = await preparerBanc(serveur: serveurRealiste());
  b.auth.connecterPourTest(login: 'Awa K.');
  InterfaceVersion.useNew.value = s.nouvelle;
  await tester.pumpWidget(aLaTaille(taille, s.nouvelle ? monterNv(b, s.ecran()) : monter(b, s.ecran())));
  await tester.pumpAndSettle();
  return b;
}

Future<void> fin(WidgetTester tester) async {
  tester.view.resetViewInsets();
  await demonter(tester);
  reinitialiserVue(tester);
}

/// Bascule « Clavier (chercher par nom) » du champ de scan.
Future<void> basculerClavierTexte(WidgetTester tester) async {
  final b = find.byTooltip('Clavier (chercher par nom)');
  await tester.tap(b.evaluate().isNotEmpty ? b.first : find.byTooltip('Masquer le clavier (scan)').first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });
  tearDown(() => InterfaceVersion.useNew.value = false);

  for (final s in situations) {
    group(s.nom, () {
      for (final appareil in appareils) {
        for (final echelle in echellesTexte) {
          // Nouvelle interface : aussi aux tailles Compact et Très compact (réglage 4.13).
          for (final taille in s.nouvelle ? taillesEcran : const [TailleEcran.automatique]) {
          final cas = '$appareil, texte ×$echelle${suffixeTaille(taille)}';

          group('', skip: s.anomalie('A', appareil, echelle), () => testWidgets('$cas — A : quantité à l\'écran, au-dessus du pavé', (tester) async {
            configurer(tester, appareil, echelle);
            final erreurs = await releverErreursRendu(tester, () async {
              await monterSituation(tester, s, taille: taille);
              await s.amener(tester);
            });
            expect(erreurs, isEmpty, reason: constats(erreurs));
            expect(s.champ(), findsWidgets);
            expect(horsDeVueSousClavier(tester, s.champ(), quoi: 'champ de quantité'), isNull);
            final pave = hautDuPave(tester);
            expect(pave, isNotNull, reason: 'pavé numérique affiché');
            expect(tester.getRect(s.champ().first).bottom, lessThanOrEqualTo(pave! + 0.5), reason: 'quantité recouverte par le pavé');
            await fin(tester);
          }));

          if (s.fenetre) {
            group('', skip: s.anomalie('B', appareil, echelle), () => testWidgets('$cas — B : clavier système déjà ouvert, fenêtre de quantité lisible', (tester) async {
              configurer(tester, appareil, echelle);
              final erreurs = await releverErreursRendu(tester, () async {
                await monterSituation(tester, s, taille: taille);
                ouvrirClavier(tester);
                await tester.pumpAndSettle();
                await s.amener(tester);
              });
              expect(erreurs, isEmpty, reason: 'rendu avec le clavier ouvert :\n${constats(erreurs)}');
              expect(horsDeVueSousClavier(tester, s.champ(), quoi: 'champ de quantité'), isNull);
              await fin(tester);
            }));
          } else {
            group('', skip: s.anomalie('C', appareil, echelle), () => testWidgets('$cas — C : recherche par nom (clavier système) sans débordement, quantité de retour ensuite', (tester) async {
              configurer(tester, appareil, echelle);
              final erreurs = await releverErreursRendu(tester, () async {
                await monterSituation(tester, s, taille: taille);
                await s.amener(tester);
                await basculerClavierTexte(tester);
                ouvrirClavier(tester);
                await tester.pumpAndSettle();
              });
              expect(erreurs, isEmpty, reason: 'rendu avec le clavier ouvert :\n${constats(erreurs)}');
              // Fermeture du clavier : retour au scan, quantité de nouveau visible.
              tester.view.resetViewInsets();
              await basculerClavierTexte(tester);
              expect(horsDeVueSousClavier(tester, s.champ(), quoi: 'champ de quantité'), isNull);
              await fin(tester);
            }));

            group('', skip: s.anomalie('Cbis', appareil, echelle), () => testWidgets('$cas — C bis : quantité visible PENDANT la recherche par nom', (tester) async {
              configurer(tester, appareil, echelle);
              await monterSituation(tester, s, taille: taille);
              await s.amener(tester);
              await basculerClavierTexte(tester);
              ouvrirClavier(tester);
              await tester.pumpAndSettle();
              expect(horsDeVueSousClavier(tester, s.champ(), quoi: 'champ de quantité'), isNull);
              await fin(tester);
            }));
          }
          }
        }
      }
    });
  }
}
