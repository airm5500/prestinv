// Faux serveur Prestige pour les tests de la file des saisies : garde la dernière quantité posée par
// ligne (comme le vrai : « quantite = X »), compte les requêtes et peut simuler pannes et lenteurs.
import 'dart:async';
import 'dart:io';

import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/saisie/saisie_store.dart';

class FauxServeur implements SaisieServeur {
  /// Quantité enregistrée par ligne (état du serveur).
  final Map<int, int> quantites = {};

  /// Toutes les requêtes reçues (ligne, quantité), dans l'ordre.
  final List<(int, int)> requetes = [];

  /// Inventaires ouverts (null : la liste ne peut pas être lue).
  Set<String>? ouverts = {'INV1'};

  /// Réponse forcée (null : succès).
  ResultatEnvoi? panne;

  /// Délai de chaque requête (réseau lent).
  Duration delai = Duration.zero;

  /// Si posé, chaque requête attend ce Completer (pour contrôler l'ordre exact dans les tests).
  Completer<void>? verrou;

  int enCours = 0;
  int maxEnCoursParLigne = 0;
  final Map<int, int> _enCoursParLigne = {};

  @override
  Future<ReponseEnvoi> poserQuantite(int ligneId, int quantite) async {
    requetes.add((ligneId, quantite));
    enCours++;
    final n = (_enCoursParLigne[ligneId] ?? 0) + 1;
    _enCoursParLigne[ligneId] = n;
    if (n > maxEnCoursParLigne) maxEnCoursParLigne = n;
    try {
      if (delai > Duration.zero) await Future<void>.delayed(delai);
      if (verrou != null) await verrou!.future;
      final p = panne;
      if (p != null) {
        if (p == ResultatEnvoi.reseau) throw const SocketException('injoignable');
        return ReponseEnvoi(p, 'panne simulée ($p)');
      }
      quantites[ligneId] = quantite;
      return ReponseEnvoi.ok;
    } on SocketException {
      return const ReponseEnvoi(ResultatEnvoi.reseau, 'Serveur injoignable.');
    } finally {
      enCours--;
      _enCoursParLigne[ligneId] = (_enCoursParLigne[ligneId] ?? 1) - 1;
    }
  }

  /// Requêtes reçues par la route « avec auteur » (versement de la collecte).
  final List<(int, int)> requetesSession = [];

  @override
  Future<ReponseEnvoi> poserQuantiteSession(int ligneId, int quantite) {
    requetesSession.add((ligneId, quantite));
    return poserQuantite(ligneId, quantite);
  }

  @override
  Future<InventairesOuverts?> inventairesOuverts() async {
    if (panne == ResultatEnvoi.reseau) return null;
    final o = ouverts;
    return o == null ? null : InventairesOuverts(o);
  }
}

/// File sur un fichier temporaire (supprimé par [nettoyer]).
class FileDeTest {
  final Directory dossier;
  FileDeTest._(this.dossier);

  static Future<FileDeTest> creer() async => FileDeTest._(await Directory.systemTemp.createTemp('prestinv_saisies_'));

  File get fichier => File('${dossier.path}/saisies_v1.jsonl');

  /// Nouvelle file sur le même fichier (= application redémarrée).
  Future<SaisieQueue> ouvrir({SaisieServeur? serveur, DateTime Function()? clock}) async {
    final q = SaisieQueue(store: FichierSaisieStore(fichier), clock: clock);
    if (serveur != null) q.serveurFactory = () => serveur;
    await q.load();
    return q;
  }

  Future<void> nettoyer() async {
    try {
      await dossier.delete(recursive: true);
    } catch (_) {}
  }
}

/// Enregistre une saisie simple sur INV1.
Future<SaisieLigne> saisir(SaisieQueue q, int ligne, int quantite, {String inv = 'INV1', bool auto = false, OrigineSaisie origine = OrigineSaisie.guidee}) =>
    q.enregistrer(inventaireId: inv, ligneId: ligne, quantite: quantite, cip: 'CIP$ligne', nom: 'Produit $ligne', origine: origine, envoiAuto: auto);
