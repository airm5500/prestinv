// lib/saisie/saisie_correction.dart
// Corrections faites dans Écarts et Restants : comme toute saisie, la quantité est d'abord écrite sur
// l'appareil (file persistante), puis envoyée tout de suite. L'écran n'affiche « fait / validé » que
// si le serveur a confirmé ; sinon la saisie reste gardée et repart automatiquement.
import 'package:prestinv/models/product.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';

/// Enregistre sur l'appareil puis envoie la quantité TOTALE [quantite] de [product].
Future<ReponseEnvoi> corrigerQuantite({
  required String inventoryId,
  String inventoryName = '',
  required Product product,
  required int quantite,
  required OrigineSaisie origine,
  String? rayonId,
  String? rayonLibelle,
  String auteur = '',
  SaisieQueue? queue,
}) async {
  final q = queue ?? SaisieQueue.instance;
  if (q == null) return const ReponseEnvoi(ResultatEnvoi.reseau, 'File des saisies indisponible.');
  await q.enregistrer(
    inventaireId: inventoryId,
    ligneId: product.id,
    quantite: quantite,
    inventaireLibelle: inventoryName,
    cip: product.produitCip,
    nom: product.produitName,
    rayonId: rayonId,
    rayonLibelle: rayonLibelle ?? product.locationLabel,
    origine: origine,
    envoiAuto: true, // ces écrans envoient toujours tout de suite, quel que soit le mode d'envoi
    auteur: auteur,
  );
  return q.envoyerLigne(inventoryId, product.id);
}

/// Message à afficher quand le serveur n'a pas confirmé.
String messageEchecCorrection(ReponseEnvoi r) {
  switch (r.type) {
    case ResultatEnvoi.ok:
      return '';
    case ResultatEnvoi.refus:
      return 'Refusée par le serveur : ${r.message}';
    case ResultatEnvoi.session:
      return 'Session expirée : non enregistrée sur le serveur. Gardée sur l\'appareil, elle repartira après reconnexion.';
    case ResultatEnvoi.reseau:
    case ResultatEnvoi.erreurServeur:
      return 'Non enregistrée sur le serveur (${r.message.isEmpty ? 'réseau' : r.message}). '
          'Gardée sur l\'appareil : nouvel essai automatique (voir « À envoyer »).';
  }
}
