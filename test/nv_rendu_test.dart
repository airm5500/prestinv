// Nouvelle interface : chaque écran s'affiche SANS DÉBORDEMENT sur Sunmi V2s (360 × 640 dp), téléphone
// et Sunmi V3 / V3H (360 × 800 dp), tablette portrait (800 × 1280) et paysage (1280 × 800), en thème
// clair et sombre ; maquette A / B sur téléphone, C (menu latéral, tableau) sur tablette ≥ 900 dp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/collecte/collecte_store.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/ui/ecrans/a_envoyer_screen.dart';
import 'package:prestinv/ui/ecrans/accueil_screen.dart';
import 'package:prestinv/ui/ecrans/analyse_screen.dart';
import 'package:prestinv/ui/ecrans/choix_rayon_screen.dart';
import 'package:prestinv/ui/ecrans/collecte_screen.dart';
import 'package:prestinv/ui/ecrans/config_screen.dart';
import 'package:prestinv/ui/ecrans/connexion_screen.dart';
import 'package:prestinv/ui/ecrans/creation_inventaire_screen.dart';
import 'package:prestinv/ui/ecrans/cumuls_screen.dart';
import 'package:prestinv/ui/ecrans/ecarts_screen.dart';
import 'package:prestinv/ui/ecrans/lancement_screen.dart';
import 'package:prestinv/ui/ecrans/licence_screen.dart';
import 'package:prestinv/ui/ecrans/rapport_versement_screen.dart';
import 'package:prestinv/ui/ecrans/recap_screen.dart';
import 'package:prestinv/ui/ecrans/reglages_scan_screen.dart';
import 'package:prestinv/ui/ecrans/restants_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_guidee_screen.dart';
import 'package:prestinv/ui/ecrans/scan_continu_screen.dart';
import 'package:prestinv/ui/ecrans/serveur_injoignable_screen.dart';
import 'package:prestinv/ui/ecrans/versement_screen.dart';
import 'package:prestinv/ui/theme.dart';

import 'helpers/banc_essai.dart';
import 'helpers/douchette_essai.dart';
import 'helpers/faux_prestige_http.dart';
import 'helpers/nouvelle_interface.dart';

final _inv = Inventory(id: 'INV1', libelle: 'Inventaire annuel 2026');

Versement _versement() => Versement(
      id: 'V1',
      inventaireId: 'INV1',
      inventaireLibelle: 'Inventaire annuel 2026',
      mode: ModeDejaCompte.ajouter,
      debut: DateTime(2026, 10, 13, 9, 30),
      statut: StatutVersement.interrompu,
      interruption: 'Réseau coupé : 1 ligne reste à verser.',
      lignes: [
        LigneVersement(code: '3400930000001', quantiteCollectee: 12, etat: EtatLigneVersement.versee, ligneId: 1, nom: 'DOLIPRANE 1000 MG CPR B/8', quantiteCible: 12),
        LigneVersement(code: '9999999999999', quantiteCollectee: 3, etat: EtatLigneVersement.nonReconnue, raison: 'introuvable dans cet inventaire'),
        LigneVersement(code: '3400935959001', quantiteCollectee: 4, etat: EtatLigneVersement.aVerser),
      ],
    );

Future<void> _saisies(Banc b) async {
  await b.queue.enregistrer(inventaireId: 'INV1', ligneId: 1, quantite: 24, cip: '3400930000001', nom: 'DOLIPRANE 1000 MG CPR B/8', rayonLibelle: 'S3', origine: OrigineSaisie.rapide);
  await b.queue.enregistrer(
      inventaireId: 'INV1', ligneId: 10, quantite: 8, cip: '3400939300008', nom: 'BILAN BIOLOGIQUE TOTAL', rayonId: 'S1A0T2', rayonLibelle: 'CANNES', origine: OrigineSaisie.guidee);
}

void main() {
  // Police réelle (Roboto) si le SDK la fournit ; PRESTINV_POLICE_ESSAI=1 : police d'essai (lettres carrées, plus larges).
  setUpAll(chargerPolicesReelles);
  setUp(() {
    reinitialiserDouchette();
    installerFauxRetour();
  });

  final ecrans = <String, Widget Function()>{
    'lancement': () => const NvLancementScreen(),
    'connexion': () => const NvConnexionScreen(),
    'licence': () => const NvLicenceScreen(),
    'serveur injoignable': () => NvServeurInjoignableScreen(reessayer: () async {}),
    'accueil': () => const NvAccueilScreen(),
    'choix du rayon': () => NvChoixRayonScreen(inventaire: _inv),
    'saisie guidée': () => NvSaisieGuideeScreen(inventaire: _inv, rayonId: 'S2B2'),
    'scan continu': () => NvScanContinuScreen(inventaire: _inv),
    'à envoyer': () => const NvAEnvoyerScreen(),
    'écarts': () => NvEcartsScreen(inventaire: _inv),
    'écarts du rayon': () => NvEcartsScreen(inventaire: _inv, rayon: Rayon(id: 'S2B2', code: 'S2B2', libelle: 'ANTIBIOTIQUES')),
    'restants': () => NvRestantsScreen(inventaire: _inv),
    'récapitulatif': () => const NvRecapScreen(inventoryId: 'INV1', rayonId: 'S2B2', rayonName: 'ANTIBIOTIQUES'),
    'analyse': () => const NvAnalyseScreen(),
    'historique des cumuls': () => const NvCumulsScreen(),
    'collecte': () => const NvCollecteScreen(),
    'versement': () => const NvVersementScreen(),
    'rapport de versement': () => NvRapportVersementScreen(versement: _versement()),
    'nouvel inventaire': () => const NvCreationInventaireScreen(),
    'configuration': () => const NvConfigScreen(),
    'réglages scan et sons': () => const NvReglagesScanScreen(),
  };
  final tailles = <String, Size>{
    'V2s 360×640': sunmiV2s,
    'V3 360×800': telephone360,
    'tablette 800×1280': tabletteMoyenne,
    'tablette 1280×800': tablette,
  };

  for (final e in ecrans.entries) {
    for (final t in tailles.entries) {
      for (final sombre in [false, true]) {
        testWidgets('${e.key} · ${t.key}${sombre ? ' · sombre' : ''} : sans débordement', (tester) async {
          tailleEcran(tester, t.value);
          final b = await preparerBanc(serveur: serveurRealiste(), mode: SendMode.collect, cumul: true);
          await _saisies(b);
          await CollecteStore.ecrire([CollectedItem(code: '3400930000001', quantity: 12, dateScan: DateTime(2026, 10, 13, 9))]);
          await NvApparence.choisir(sombre ? Apparence.sombre : Apparence.clair);
          await tester.pumpWidget(monterNv(b, e.value()));
          // Lancement : sablier sans fin (attente de la licence).
          if (e.key == 'lancement') {
            await tester.pump(const Duration(milliseconds: 500));
          } else {
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          // Maquette C (menu latéral bleu) seulement sur grande tablette, pour l'accueil et les écarts.
          final menu = find.byKey(const ValueKey('menu-accueil'));
          if ((e.key == 'accueil' || e.key.startsWith('écarts')) && t.value.width >= 900) {
            expect(menu, findsOneWidget);
          } else {
            expect(menu, findsNothing);
          }
          await NvApparence.choisir(Apparence.systeme);
          await demonter(tester);
        });
      }
    }
  }

  testWidgets('serveur en panne : erreur claire avec Réessayer, jamais une liste vide', (tester) async {
    tailleEcran(tester, telephone360);
    final s = FauxPrestige()..injoignable = true;
    final b = await preparerBanc(serveur: s);
    for (final ecran in [NvEcartsScreen(inventaire: _inv), NvRestantsScreen(inventaire: _inv), NvChoixRayonScreen(inventaire: _inv)]) {
      await tester.pumpWidget(monterNv(b, ecran));
      await tester.pumpAndSettle();
      expect(find.text('Chargement impossible'), findsOneWidget, reason: '$ecran');
      expect(find.byKey(const ValueKey('nv-reessayer')), findsOneWidget);
      expect(find.textContaining('Aucun'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.pumpWidget(monterNv(b, const NvAccueilScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('nv-reessayer')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Chargement impossible'), findsOneWidget);
    s.injoignable = false;
    await tester.tap(find.byKey(const ValueKey('nv-reessayer')));
    await tester.pumpAndSettle();
    expect(find.text('Chargement impossible'), findsNothing);
    // 4.13 : la liste des inventaires de l'accueil se déroule à la demande (flèche ▼).
    await deroulerInventaires(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('nv-inv-INV1')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('nv-inv-INV1')), findsOneWidget);
    await demonter(tester);
  });
}
