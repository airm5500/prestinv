// Faux serveur HTTP Prestige (routes /api/v1/ws/inventaires/*) pour les tests d'écrans :
// mêmes formes de réponse que ErpRessource / InventaireServiceImpl, état des quantités en mémoire.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FauxProduit {
  final int id;
  final String cip;
  final String nom;
  final String rayon;
  final int theorique;
  int saisi;
  String? dtUpdated;

  /// EAN-13 (reconnu par la recherche du serveur, absent de la réponse comme sur le vrai serveur).
  final String? ean;

  /// Auteur de la dernière quantité posée par la route « avec auteur ».
  String? auteur;
  FauxProduit(this.id, this.cip, this.nom, this.rayon, this.theorique, {int? saisi, this.ean}) : saisi = saisi ?? theorique;

  /// Même produit dans un AUTRE inventaire (ligne [nouvelId], jamais comptée).
  FauxProduit copie(int nouvelId) => FauxProduit(nouvelId, cip, nom, rayon, theorique, ean: ean);

  Map<String, dynamic> toJson() => {
        'id': id,
        'produitCip': cip,
        'produitName': nom,
        'produitPrixAchat': 100,
        'produitPrixUni': 150,
        'quantiteInitiale': theorique,
        'quantiteSaisie': saisi,
        'dtUpdated': dtUpdated,
      };
}

/// 4.15 — Inventaire créé pendant le test : ses propres lignes (copies des produits du catalogue, jamais
/// comptées), retenues ou non (bool_INVENTAIRE), comme sur le serveur.
class FauxInventaireCree {
  final List<FauxProduit> lignes;

  /// Ligne d'inventaire → produit du catalogue (lg_FAMILLE_ID « F<id> »).
  final Map<int, int> produitDe;

  /// Lignes retenues (bool_INVENTAIRE = 1).
  final Set<int> retenues;
  FauxInventaireCree(this.lignes, this.produitDe, this.retenues);

  List<FauxProduit> get lignesRetenues => lignes.where((l) => retenues.contains(l.id)).toList();
}

class FauxPrestige {
  final List<FauxProduit> produits = [];
  final Map<String, String> rayons = {'R1': 'RAYON UN', 'R2': 'RAYON DEUX'};

  /// Inventaires ouverts renvoyés par GET /ws/inventaires.
  Map<String, String> inventaires = {'INV1': 'Inventaire test'};

  /// Panne réseau totale (toutes les requêtes échouent comme un serveur injoignable).
  bool injoignable = false;

  /// Routes qui échouent en réseau (fin de chemin, ex. 'detailsAllTouched').
  final Set<String> routesInjoignables = {};

  /// Codes HTTP forcés par fin de chemin (ex. {'detailsAll': 401}).
  final Map<String, int> codes = {};

  /// Délai de réponse de chaque requête (réseau lent).
  Duration delai = Duration.zero;

  /// Délai par fin de chemin (ex. {'detailsAllTouched': 12 s}).
  final Map<String, Duration> delais = {};

  /// Si posé, les PUT attendent ce Completer (pour contrôler l'ordre exact).
  Completer<void>? verrouPut;

  final List<(int, int)> puts = [];
  final List<String> appels = [];

  /// Quantités reçues par POST /inventaire/ligne/quantite (route qui enregistre l'auteur).
  final List<(int, int)> postsQuantite = [];

  /// Demandes de création reçues (libellé, type).
  final List<(String, String)> creations = [];

  /// 4.14.1 : `valeurs` de chaque demande de création (null : absentes = tous les produits).
  final List<List<String>?> creationsValeurs = [];

  /// Emplacements de l'officine (GET /referentiel-article/zones-geographiques) en plus des rayons.
  final Map<String, String> autresEmplacements = {'R3': 'RESERVE'};

  /// Route POST /inventaire/ligne/quantite absente (ancien serveur : 404).
  bool sansRouteLigneQuantite = false;

  /// Création : réponse forcée (corps JSON) ; null = succès.
  Map<String, dynamic>? reponseCreation;

  /// Création : la réponse se perd (réseau coupé APRÈS que le serveur a créé l'inventaire).
  bool creationReponsePerdue = false;

  // --- 4.15 : routes récentes et inventaires limités aux produits ---

  /// Serveur à jour (branche des demandes mobiles) : `rayons/etat`, versement en lot, `lgInventaireId`
  /// dans la réponse de création, `droits` / `role` dans la réponse de connexion.
  bool routesRecentes = false;

  /// Ancien serveur sans `POST /inventaire/lignes/retenue` (404).
  bool sansRouteRetenue = false;

  /// Inventaires créés pendant le test (identifiant → lignes propres).
  final Map<String, FauxInventaireCree> crees = {};

  /// `bool_INVENTAIRE` de chaque demande de création (null : absent → 1).
  final List<int?> creationsRetenue = [];

  /// Demandes reçues par `POST /inventaire/lignes/retenue` (inventaire, produits).
  final List<(String, List<String>)> retenues = [];

  /// Demandes reçues par `POST /inventaire/{id}/versement` (corps décodé).
  final List<Map<String, dynamic>> versementsLot = [];

  /// Noms complets des auteurs de saisie (demande 50), par identifiant.
  final Map<String, String> nomsAuteurs = {'admin': 'Awa Kouassi'};

  /// Demandes de création reçues avec `produits` (demande 46).
  final List<List<String>> creationsProduits = [];

  /// Versement en lot : les N prochaines réponses se perdent APRÈS l'enregistrement (réseau coupé).
  int versementsReponsePerdue = 0;

  /// Clés de versement déjà vues : (inventaire, empreinte du contenu, rapport).
  final Map<String, (String, String, Map<String, dynamic>)> _cles = {};

  /// Lignes RETENUES d'un inventaire (celles que lisent la saisie, les écarts, la clôture).
  List<FauxProduit> lignesDe(String? inventaire) => crees[inventaire]?.lignesRetenues ?? produits;

  FauxProduit? _ligne(int? id) {
    if (id == null) return null;
    final p = produits.where((p) => p.id == id).firstOrNull;
    if (p != null) return p;
    for (final c in crees.values) {
      final l = c.lignes.where((l) => l.id == id).firstOrNull;
      if (l != null) return l;
    }
    return null;
  }

  FauxPrestige({int nombre = 60}) {
    for (var i = 1; i <= nombre; i++) {
      produits.add(FauxProduit(1000 + i, '3400${i.toString().padLeft(9, '0')}', 'PRODUIT ${i.toString().padLeft(3, '0')}', i.isEven ? 'R2' : 'R1', i % 7));
    }
  }

  FauxProduit produit(int id) => produits.firstWhere((p) => p.id == id);

  MockClient get client => MockClient(_traiter);

  Future<http.Response> _traiter(http.Request req) async {
    final chemin = req.url.path;
    final fin = chemin.split('/').last;
    appels.add('${req.method} $fin');
    if (delai > Duration.zero) await Future<void>.delayed(delai);
    final d = delais[fin];
    if (d != null) await Future<void>.delayed(d);
    // Wi-Fi perdu, serveur hors de portée : cas 1 « Serveur injoignable » (comme une connexion refusée,
    // FauxServeurPrestige.couper). Prestige non déployé (404 de Payara) : FauxServeurPrestige.nonDeploye.
    if (injoignable || routesInjoignables.contains(fin)) throw const SocketException('Network is unreachable');
    final code = codes[fin];
    if (code != null) return http.Response('', code);
    final q = req.url.queryParameters;
    final query = (q['query'] ?? '').toLowerCase();
    bool correspond(FauxProduit p) =>
        query.isEmpty || p.cip.contains(query) || p.nom.toLowerCase().contains(query) || (p.ean != null && p.ean!.startsWith(query));
    final lignes = lignesDe(q['idInventaire']);
    List<FauxProduit> touches() => lignes.where((p) => p.dtUpdated != null).toList();
    // Serveur à jour (demande 50) : auteur de la dernière saisie (identifiant, nom), absent sur une ligne jamais saisie.
    Map<String, dynamic> ligneJson(FauxProduit p) => {
          ...p.toJson(),
          if (routesRecentes && p.auteur != null) ...{'auteurId': 'U-${p.auteur}', 'auteurLogin': p.auteur, 'auteurNom': nomsAuteurs[p.auteur] ?? p.auteur},
        };
    http.Response liste(Iterable<FauxProduit> ps) =>
        http.Response.bytes(utf8.encode(json.encode(ps.map(ligneJson).toList())), 200, headers: {'content-type': 'application/json; charset=utf-8'});

    if (req.method == 'POST' && fin == 'quantite') {
      if (sansRouteLigneQuantite) return http.Response('', 404);
      if (verrouPut != null) await verrouPut!.future;
      final b = json.decode(req.body) as Map<String, dynamic>;
      final id = int.tryParse('${b['lg_INVENTAIRE_FAMILLE_ID']}');
      final quantite = (b['int_NUMBER'] as num?)?.toInt();
      if (quantite == null || quantite < 0) return http.Response(json.encode({'success': 0, 'errors': 'Quantite invalide.'}), 200);
      final p = _ligne(id);
      if (p == null) return http.Response(json.encode({'success': 0, 'errors': "Cette ligne d'inventaire n'existe plus."}), 200);
      postsQuantite.add((p.id, quantite));
      p
        ..saisi = quantite
        ..dtUpdated = '2026-10-13T10:00:00'
        ..auteur = 'admin';
      return http.Response(json.encode({'success': 1, 'int_NUMBER': quantite}), 200);
    }
    if (req.method == 'POST' && fin == 'creation') {
      final b = json.decode(req.body) as Map<String, dynamic>;
      final nom = '${b['str_NAME'] ?? ''}'.trim();
      final type = '${b['str_TYPE_TRANSACTION'] ?? ''}'.trim();
      creations.add((nom, type));
      final brut = b['valeurs'];
      final valeurs = brut is List ? [for (final v in brut) '$v'] : null;
      creationsValeurs.add(valeurs);
      final retenue = (b['bool_INVENTAIRE'] as num?)?.toInt();
      creationsRetenue.add(retenue);
      if (reponseCreation != null) return http.Response.bytes(utf8.encode(json.encode(reponseCreation)), 200);
      if (nom.isEmpty) return http.Response(json.encode({'success': 0, 'message': 'Indiquez un libelle pour cet inventaire.'}), 200);
      if (type.isEmpty) return http.Response(json.encode({'success': 0, 'message': "Choisissez un type d'inventaire."}), 200);
      // Comme createInventaireMultiCriteres : sans valeur → tous les produits ; sinon ceux des emplacements.
      final filtre = valeurs?.where((v) => v.isNotEmpty && v != '0' && v != '%%').toSet() ?? const <String>{};
      // Serveur à jour (demande 46) : `produits` → ces produits seulement (dans le critère), lignes retenues, une
      // transaction ; `inconnus` dans la réponse. Serveur plus ancien : le champ est ignoré.
      final demandes = b['produits'] is List ? [for (final e in b['produits'] as List) '$e'] : null;
      if (routesRecentes && demandes != null && demandes.isNotEmpty) {
        creationsProduits.add(demandes);
        if (demandes.length > 500) return http.Response(json.encode({'success': 0, 'message': '500 produits au plus par inventaire.'}), 413);
        final inconnus = <String>[];
        final choisis = <FauxProduit>[];
        for (final d in demandes) {
          final p = produits.where((p) => 'F${p.id}' == d || p.cip == d || p.ean == d).firstOrNull;
          if (p == null || (filtre.isNotEmpty && !filtre.contains(p.rayon))) {
            inconnus.add(d);
          } else if (!choisis.contains(p)) {
            choisis.add(p);
          }
        }
        if (choisis.isEmpty) {
          return http.Response.bytes(
              utf8.encode(json.encode({'success': 0, 'inconnus': inconnus, 'message': "Aucun inventaire n'a ete cree : aucun des produits n'a ete retrouve."})), 200);
        }
        final id = 'NEW${creations.length}';
        inventaires = {id: nom, ...inventaires};
        final base = 100000 * creations.length;
        final copies = [for (final p in choisis) p.copie(base + p.id)];
        crees[id] = FauxInventaireCree(copies, {for (final p in choisis) base + p.id: p.id}, {for (final c in copies) c.id});
        return http.Response.bytes(
            utf8.encode(json.encode({
              'inconnus': inconnus,
              'success': 1,
              'lignes': choisis.length,
              'nombre': '${choisis.length} article(s) inventorie(s)',
              'lgInventaireId': id,
              'libelle': nom,
            })),
            200);
      }
      final inclus = filtre.isEmpty ? produits : produits.where((p) => filtre.contains(p.rayon)).toList();
      if (inclus.isEmpty) return http.Response(json.encode({'success': 0, 'message': "Aucun inventaire n'a ete cree."}), 200);
      // Le plus récent en tête (ORDER BY dtCREATED DESC).
      final id = 'NEW${creations.length}';
      inventaires = {id: nom, ...inventaires};
      final base = 100000 * creations.length;
      final copies = [for (final p in inclus) p.copie(base + p.id)];
      crees[id] = FauxInventaireCree(copies, {for (final p in inclus) base + p.id: p.id}, retenue == 0 ? {} : {for (final c in copies) c.id});
      if (creationReponsePerdue) throw const SocketException('Connection reset');
      return http.Response.bytes(
          utf8.encode(json.encode({
            'success': 1,
            'lignes': inclus.length,
            'nombre': '${inclus.length} article(s) inventorie(s)',
            if (routesRecentes) 'lgInventaireId': id,
            if (routesRecentes) 'libelle': nom,
          })),
          200);
    }
    if (req.method == 'POST' && fin == 'retenue' && chemin.endsWith('lignes/retenue')) {
      if (sansRouteRetenue) return http.Response('', 404);
      final b = json.decode(req.body) as Map<String, dynamic>;
      final inv = '${b['lg_INVENTAIRE_ID'] ?? ''}';
      final ps = [for (final e in (b['produits'] as List? ?? const [])) '$e'];
      final ids = [for (final e in (b['ids'] as List? ?? const [])) '$e'];
      if (ps.isNotEmpty || inv.isNotEmpty) retenues.add((inv, ps));
      final c = crees[inv];
      var count = 0;
      if (c != null) {
        for (final e in c.produitDe.entries) {
          if (ps.contains('F${e.value}') || ids.contains('${e.key}')) {
            c.retenues.add(e.key);
            count++;
          }
        }
      } else if (inventaires.containsKey(inv)) {
        count = produits.where((p) => ps.contains('F${p.id}') || ids.contains('${p.id}')).length;
      }
      if (count == 0) return http.Response(json.encode({'success': 0, 'errors': 'Aucun article a traiter.'}), 200);
      return http.Response(json.encode({'success': 1, 'count': count, 'errors': "$count article(s) ajoute(s) a l'inventaire."}), 200);
    }
    if (req.method == 'GET' && fin == 'etat' && chemin.endsWith('/rayons/etat')) {
      if (!routesRecentes) return http.Response('', 404);
      final segs = req.url.pathSegments;
      final inv = segs[segs.length - 3];
      if (!inventaires.containsKey(inv) && !crees.containsKey(inv)) {
        return http.Response(json.encode({'success': 0, 'code': 'INVENTAIRE_INCONNU'}), 410);
      }
      final c = crees[inv];
      final toutes = c?.lignes ?? produits;
      final retenuesInv = lignesDe(inv).map((p) => p.id).toSet();
      final ids = <String>[];
      // Demande 47 : seulement les rayons qui ont des lignes à compter (HAVING … > 0).
      for (final p in toutes.where((p) => retenuesInv.contains(p.id))) {
        if (!ids.contains(p.rayon)) ids.add(p.rayon);
      }
      ids.sort((a, b) => (rayons[a] ?? a).compareTo(rayons[b] ?? b));
      return http.Response.bytes(
          utf8.encode(json.encode([
            for (final r in ids)
              () {
                final ls = toutes.where((p) => p.rayon == r && retenuesInv.contains(p.id)).toList();
                final comptes = ls.where((p) => p.dtUpdated != null).length;
                return {'rayonId': r, 'code': r, 'libelle': rayons[r] ?? autresEmplacements[r] ?? r, 'totalProduits': ls.length, 'comptes': comptes, 'restants': ls.length - comptes, 'derniereSaisie': null};
              }(),
          ])),
          200);
    }
    if (req.method == 'POST' && fin == 'versement') {
      if (!routesRecentes) return http.Response('', 404);
      final segs = req.url.pathSegments;
      final inv = segs[segs.length - 2];
      Map<String, dynamic> b;
      try {
        b = Map<String, dynamic>.from(json.decode(req.body) as Map);
      } catch (_) {
        return http.Response(json.encode({'success': 0, 'code': 'REQUETE_INVALIDE'}), 400);
      }
      versementsLot.add(b);
      final cle = '${b['cle'] ?? ''}';
      final mode = '${b['mode'] ?? ''}';
      final ls = b['lignes'];
      if (cle.isEmpty || ls is! List || (mode != 'ajouter' && mode != 'remplacer')) {
        return http.Response(json.encode({'success': 0, 'code': 'REQUETE_INVALIDE'}), 400);
      }
      if (ls.length > 500) return http.Response(json.encode({'success': 0, 'code': 'TROP_DE_LIGNES'}), 413);
      if (!inventaires.containsKey(inv) && !crees.containsKey(inv)) return http.Response(json.encode({'success': 0, 'code': 'INVENTAIRE_INCONNU'}), 410);
      final empreinte = '$mode|${json.encode(ls)}';
      final deja = _cles[cle];
      if (deja != null) {
        if (deja.$1 != inv || deja.$2 != empreinte) return http.Response(json.encode({'success': 0, 'code': 'CLE_REUTILISEE'}), 409);
        return http.Response.bytes(utf8.encode(json.encode({...deja.$3, 'dejaTraite': true})), 200);
      }
      final lignesInv = lignesDe(inv);
      final sortie = <Map<String, dynamic>>[];
      for (var i = 0; i < ls.length; i++) {
        final e = ls[i] as Map;
        final code = '${e['code'] ?? ''}'.trim();
        final q = e['quantite'];
        final r = <String, dynamic>{'index': i, 'code': code, 'quantite': q};
        if (code.isEmpty || q is! int || q < 0) {
          sortie.add({...r, 'statut': 'refuse', 'motif': 'Quantité invalide.'});
          continue;
        }
        final trouvees = lignesInv.where((p) => p.cip == code || p.ean == code).toList();
        if (trouvees.isEmpty) {
          sortie.add({...r, 'statut': 'inconnu'});
          continue;
        }
        if (trouvees.length > 1) {
          sortie.add({...r, 'statut': 'ambigu', 'lignesPossibles': [for (final t in trouvees) {'id': '${t.id}', 'cip': t.cip, 'libelle': t.nom}]});
          continue;
        }
        final p = trouvees.single;
        p.saisi = mode == 'ajouter' && p.dtUpdated != null ? p.saisi + q : q;
        p.dtUpdated = '2026-10-15T10:00:00';
        p.auteur = 'admin';
        sortie.add({...r, 'statut': 'ok', 'ligneId': '${p.id}', 'quantiteFinale': p.saisi});
      }
      final rapport = {'success': 1, 'dejaTraite': false, 'mode': mode, 'total': ls.length, 'lignes': sortie};
      _cles[cle] = (inv, empreinte, rapport);
      if (versementsReponsePerdue > 0) {
        versementsReponsePerdue--;
        throw const SocketException('Connection reset');
      }
      return http.Response.bytes(utf8.encode(json.encode(rapport)), 200);
    }
    if (req.method == 'PUT' && fin == 'details') {
      if (verrouPut != null) await verrouPut!.future;
      final b = json.decode(req.body) as Map<String, dynamic>;
      final id = (b['id'] as num).toInt();
      final quantite = (b['quantite'] as num).toInt();
      puts.add((id, quantite));
      final p = _ligne(id);
      if (p == null) return http.Response('', 500); // comme le serveur : NPE → 500
      p.saisi = quantite;
      p.dtUpdated = '2026-10-13T10:00:00';
      return http.Response('', 200);
    }
    switch (fin) {
      case 'inventaires':
        return http.Response.bytes(utf8.encode(json.encode([for (final e in inventaires.entries) {'id': e.key, 'libelle': e.value}])), 200);
      case 'rayons':
        // Comme fetchRayon : les rayons de TOUTES les lignes de l'inventaire (retenues ou non).
        final c = crees[q['idInventaire']];
        // Serveur à jour (demande 47) : seulement les rayons des lignes à compter (retenues).
        final lignesRayons = c == null ? null : (routesRecentes ? c.lignesRetenues : c.lignes);
        final ids = lignesRayons == null ? rayons.keys.toList() : [for (final r in rayons.keys) if (lignesRayons.any((l) => l.rayon == r)) r];
        return http.Response.bytes(utf8.encode(json.encode([for (final r in ids) {'id': r, 'code': r, 'libelle': rayons[r]}])), 200);
      case 'details':
        return liste(lignes.where((p) => p.rayon == q['idRayon'] && correspond(p)));
      case 'detailsAll':
        return liste(lignes.where(correspond));
      case 'detailsAllTouched':
        return liste(touches().where(correspond));
      case 'detailsTouchedRayon':
        return liste(touches().where((p) => p.rayon == q['idRayon'] && correspond(p)));
      case 'detailsAllUntouched':
        return liste(lignes.where((p) => p.dtUpdated == null && correspond(p)));
      case 'detailsUntouchedRayon':
        return liste(lignes.where((p) => p.dtUpdated == null && p.rayon == q['idRayon'] && correspond(p)));
      case 'detailsAllEcarts':
        return liste(touches().where((p) => p.saisi != p.theorique && correspond(p)));
      case 'zones-geographiques':
        final tous = {...rayons, ...autresEmplacements};
        return http.Response.bytes(
            utf8.encode(json.encode({
              'total': tous.length,
              'results': [for (final e in tous.entries) {'lg_ZONE_GEO_ID': e.key, 'str_CODE': e.key, 'str_LIBELLEE': e.value}],
            })),
            200);
      case 'fiche':
        // Recherche de la fiche article (produit-search/fiche) : CIP, EAN-13 ; emplacement en libellé et en identifiant.
        final cherche = q['search_value'] ?? '';
        final ps = produits.where((p) => cherche.isNotEmpty && (p.cip.startsWith(cherche) || (p.ean != null && p.ean!.startsWith(cherche))));
        return http.Response.bytes(
            utf8.encode(json.encode({
              'total': ps.length,
              'results': [
                for (final p in ps.take(int.tryParse(q['limit'] ?? '') ?? 20))
                  {
                    'lg_FAMILLE_ID': 'F${p.id}',
                    'int_CIP': p.cip,
                    'int_EAN13': p.ean ?? '',
                    'str_NAME': p.nom,
                    'lg_ZONE_GEO_ID': rayons[p.rayon] ?? '',
                    'lg_ZONE_GEO_ID_REEL': p.rayon,
                  },
              ],
            })),
            200);
      case 'find':
        // Fin de licence relative à aujourd'hui (une date fixe rendait les tests rouges à son échéance).
        final fin = DateTime.now().add(const Duration(days: 400)).toIso8601String().substring(0, 10);
        return http.Response(json.encode({'id': 'L1', 'dateStart': '2026-01-01', 'dateEnd': fin, 'typeLicence': 'ANNUELLE'}), 200);
      case 'auth':
        return http.Response(
            json.encode({
              'success': true,
              'str_LOGIN': 'admin',
              'str_FIRST_NAME': 'Test',
              if (routesRecentes) 'role': {'code': 'PHARMACIEN', 'libelle': 'Pharmacien'},
              if (routesRecentes) 'droits': {'creerInventaire': true},
            }),
            200,
            headers: {'set-cookie': 'JSESSIONID=abc; Path=/'});
    }
    return http.Response('', 404);
  }
}

/// Client HTTP qui délègue à [interne] mais coupe (erreur réseau) les requêtes désignées par [coupe].
abstract class BaseClientDelegue extends http.BaseClient {
  final http.Client interne;
  BaseClientDelegue(this.interne);

  bool coupe(Uri url, String methode);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (coupe(request.url, request.method)) throw const SocketException('Connexion coupée (essai)');
    return interne.send(request);
  }
}
