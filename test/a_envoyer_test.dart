// « À envoyer » : les saisies en attente de TOUS les rayons (et de la saisie rapide) sont visibles
// depuis l'accueil, avec leur état ; envoi de tout ; inventaire clôturé = refusées avec le motif.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/screens/a_envoyer_screen.dart';
import 'package:prestinv/screens/home_screen.dart';

import 'helpers/banc_essai.dart';

Future<void> remplir(Banc b) async {
  final p = b.serveur.produits;
  await b.queue.enregistrer(inventaireId: 'INV1', inventaireLibelle: 'Inventaire test', ligneId: p[0].id, quantite: 3, nom: p[0].nom, cip: p[0].cip, rayonId: 'R1', rayonLibelle: 'RAYON UN');
  await b.queue.enregistrer(inventaireId: 'INV1', inventaireLibelle: 'Inventaire test', ligneId: p[1].id, quantite: 4, nom: p[1].nom, cip: p[1].cip, rayonId: 'R2', rayonLibelle: 'RAYON DEUX');
  await b.queue.enregistrer(inventaireId: 'INV1', inventaireLibelle: 'Inventaire test', ligneId: p[2].id, quantite: 5, nom: p[2].nom, cip: p[2].cip, origine: OrigineSaisie.rapide);
  await b.queue.enregistrer(inventaireId: 'INV2', inventaireLibelle: 'Ancien inventaire', ligneId: 777, quantite: 6, nom: 'PRODUIT CLOS');
}

void main() {
  testWidgets('accueil : compteur de toutes les saisies en attente (tous rayons, saisie rapide, autres inventaires)', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    await tester.pumpWidget(monter(b, const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('à envoyer'), findsNothing); // rien en attente : accueil inchangé

    await remplir(b);
    await tester.pumpAndSettle();
    expect(find.text('4 saisie(s) à envoyer'), findsOneWidget);

    await tester.tap(find.text('4 saisie(s) à envoyer'));
    await tester.pumpAndSettle();
    expect(find.byType(AEnvoyerScreen), findsOneWidget);
    expect(find.text('Inventaire test'), findsOneWidget);
    expect(find.text('Ancien inventaire'), findsOneWidget);
    expect(find.textContaining('RAYON UN'), findsOneWidget);
    expect(find.textContaining('RAYON DEUX'), findsOneWidget);
    expect(find.textContaining('Saisie rapide'), findsOneWidget);
    expect(find.text('4 en attente · 0 refusée(s)'), findsOneWidget);
    await demonter(tester);
  });

  testWidgets('Envoyer maintenant : tout part ; l\'inventaire clôturé est refusé avec son motif, rien d\'envoyé', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    await remplir(b);
    await tester.pumpWidget(monter(b, const AEnvoyerScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer maintenant'));
    await tester.pumpAndSettle();

    expect(b.serveur.puts.map((p) => p.$1).toSet(), {b.serveur.produits[0].id, b.serveur.produits[1].id, b.serveur.produits[2].id});
    expect(b.serveur.puts.any((p) => p.$1 == 777), isFalse); // INV2 clôturé : jamais envoyé
    expect(find.text('0 en attente · 1 refusée(s)'), findsOneWidget);
    expect(find.textContaining(SaisieQueue.motifCloture), findsOneWidget);

    // Supprimer la saisie refusée (avec confirmation).
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer').last);
    await tester.pumpAndSettle();
    expect(find.text('Tout est envoyé.'), findsOneWidget);
    expect(b.queue.aTraiter(), 0);
    await demonter(tester);
  });

  testWidgets('serveur injoignable : message clair, saisies toujours en attente', (tester) async {
    ecranTerminal(tester);
    final b = await preparerBanc();
    await remplir(b);
    b.serveur.injoignable = true;
    await tester.pumpWidget(monter(b, const AEnvoyerScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer maintenant'));
    await tester.pumpAndSettle();
    expect(b.queue.enAttente(), 4);
    expect(find.textContaining('Serveur injoignable'), findsWidgets);
    await demonter(tester);
  });
}
