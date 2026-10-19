// lib/api/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/models/license.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/utils/journal.dart';

/// Nature d'un échec de chargement (jamais confondu avec « liste vide »).
enum TypeErreurChargement { reseau, session, refus, donnees }

/// Échec de chargement : message lisible + nature (réseau, session expirée, refus, données illisibles).
class ApiLoadException implements Exception {
  final String message;
  final TypeErreurChargement type;
  const ApiLoadException(this.message, [this.type = TypeErreurChargement.refus]);

  bool get sessionExpiree => type == TypeErreurChargement.session;
  bool get reseau => type == TypeErreurChargement.reseau;

  @override
  String toString() => message;
}

class ApiService implements SaisieServeur {
  final String baseUrl;
  final String? sessionCookie;

  /// Cookie de session lu au moment de chaque appel (après une reconnexion, le nouveau est utilisé).
  final String? Function()? cookie;

  /// Client HTTP (remplaçable dans les tests).
  final http.Client? client;

  ApiService({required this.baseUrl, this.sessionCookie, this.cookie, this.client});

  /// Tests : client HTTP utilisé par toutes les instances qui n'en reçoivent pas (faux serveur).
  static http.Client? clientParDefaut;

  http.Client? get _client => client ?? clientParDefaut;

  String? get _cookieCourant => cookie != null ? cookie!() : sessionCookie;

  Map<String, String> _getHeaders() {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    final c = _cookieCourant;
    if (c != null && c.isNotEmpty) {
      headers['Cookie'] = c;
    }
    return headers;
  }

  Future<http.Response> _httpGet(Uri url) => _client != null ? _client!.get(url, headers: _getHeaders()) : http.get(url, headers: _getHeaders());

  Future<http.Response> _httpPost(Uri url, String body) =>
      _client != null ? _client!.post(url, headers: _getHeaders(), body: body) : http.post(url, headers: _getHeaders(), body: body);

  Future<http.Response> _httpPut(Uri url, String body) =>
      _client != null ? _client!.put(url, headers: _getHeaders(), body: body) : http.put(url, headers: _getHeaders(), body: body);

  static bool _estErreurReseau(Object e) => e is SocketException || e is TimeoutException || e is http.ClientException || e is HandshakeException;

  /// 4.14.2 — Connexion HTTPS dont le certificat est refusé (auto-signé non reconnu, expiré, autre nom) :
  /// ce n'est PAS un serveur injoignable (le serveur a répondu) ; message dédié.
  static bool estCertificatRefuse(Object e) =>
      e is TlsException || (e is http.ClientException && e.message.contains('CERTIFICATE_VERIFY_FAILED'));

  /// Message affiché quand le certificat du serveur est refusé.
  static const messageCertificat = 'Certificat du serveur refusé : connexion sécurisée (HTTPS) impossible. '
      'Vérifiez l\'adresse du serveur ou faites installer un certificat valide sur le serveur.';

  // 4.15.3 (retour du pharmacien) — DEUX cas distincts, dans les deux interfaces (connexion, lancement,
  // listes) :
  //  1. aucune réponse (délai dépassé, hôte ou réseau inaccessible, connexion refusée = PC serveur éteint ou
  //     Payara arrêté) → [messageInjoignable] ;
  //  2. le serveur répond mais Prestige n'est pas déployé (404 HTML / vide de Payara, 502 / 503 / 504) →
  //     [messageIndisponible].

  /// Cas 1 : le serveur ne répond pas.
  static const messageInjoignable = 'Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé.';

  /// Cas 2 : le serveur répond, Prestige n'est pas (encore) déployé.
  static const messageIndisponible =
      'Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant.';

  /// Cas 1 pour une lecture ou une opération ([quoi]).
  static String injoignable(String quoi) => 'Serveur injoignable ($quoi). Vérifiez le Wi-Fi et que le PC serveur est allumé.';

  /// Cas 2 pour une lecture ou une opération ([quoi]).
  static String indisponible(String quoi) =>
      'Serveur indisponible ($quoi) : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant.';

  /// Réponse d'un serveur INDISPONIBLE (et non un refus) : 502 / 503 / 504 (relais ou serveur
  /// d'applications sans Prestige), ou 404 SANS réponse de Prestige (page HTML ou corps vide : application
  /// non chargée pendant un redéploiement). Un 404 « métier » des routes de Prestige porte un corps JSON
  /// (`{code:"LIGNE_INCONNUE"…}`) : il n'est PAS concerné.
  static bool serveurIndisponible(http.Response r) {
    final c = r.statusCode;
    if (c == 502 || c == 503 || c == 504) return true;
    if (c != 404) return false;
    try {
      final d = json.decode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (d is Map) return false;
    } catch (_) {}
    return true;
  }

  /// Connexion REFUSÉE (la machine répond, le serveur d'applications ne l'écoute pas : arrêt, redémarrage).
  static bool connexionRefusee(Object e) {
    if (e is! SocketException) return false;
    final code = e.osError?.errorCode;
    if (code == 111 || code == 61 || code == 10061) return true; // ECONNREFUSED Linux / Android, macOS, Windows
    final m = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    return m.contains('connection refused') || m.contains('connexion refusée');
  }

  /// Message d'une panne réseau pendant une lecture ([quoi] : « inventaires », « produits »…) : cas 1.
  static String messageReseau(String quoi, Object e) => injoignable('$quoi non chargés');

  // --- FILE DES SAISIES (SaisieServeur) ---

  /// Pose la quantité TOTALE sur une ligne (PUT /ws/inventaires/details). Ne lève jamais.
  @override
  Future<ReponseEnvoi> poserQuantite(int ligneId, int quantite) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/details');
    try {
      final response = await _httpPut(url, jsonEncode({'id': ligneId, 'quantite': quantite})).timeout(const Duration(seconds: 15));
      final code = response.statusCode;
      if (code >= 200 && code < 300) return ReponseEnvoi.ok;
      // Prestige indisponible (redéploiement : 404 sans réponse de Prestige, 502 / 503 / 504) : la saisie est
      // gardée et renvoyée (jamais « refusée » à tort).
      if (serveurIndisponible(response)) return const ReponseEnvoi(ResultatEnvoi.reseau, messageIndisponible);
      // Droit manquant (403 « interdit », serveurs récents) : refus visible, pas de reconnexion en boucle.
      if (droitManquant(response) != null) return ReponseEnvoi(ResultatEnvoi.refus, _refusSaisie(response));
      // Session absente (PUT exige une session depuis le 12/10) : la saisie reste sur l'appareil.
      if (code == 401 || code == 403) return ReponseEnvoi(ResultatEnvoi.session, 'Session expirée ou accès refusé (code $code).');
      if (code >= 400 && code < 500) return ReponseEnvoi(ResultatEnvoi.refus, _refusSaisie(response));
      return ReponseEnvoi(ResultatEnvoi.erreurServeur, 'Erreur du serveur (code $code).');
    } on TimeoutException {
      return const ReponseEnvoi(ResultatEnvoi.reseau, 'Le serveur met trop de temps à répondre.');
    } catch (e) {
      if (estCertificatRefuse(e)) return const ReponseEnvoi(ResultatEnvoi.reseau, messageCertificat);
      if (_estErreurReseau(e)) return const ReponseEnvoi(ResultatEnvoi.reseau, messageInjoignable);
      return ReponseEnvoi(ResultatEnvoi.reseau, 'Envoi impossible : $e');
    }
  }

  /// Serveurs (adresse de base) sans la route `POST /inventaire/ligne/quantite` (anciennes versions de
  /// Prestige) : la route habituelle est utilisée directement.
  static final Set<String> _sansRouteSession = {};

  /// Tests : oublie les serveurs mémorisés sans route « avec auteur », les routes absentes et les
  /// serveurs reconnus récents.
  static void oublierRoutesAbsentes() {
    _sansRouteSession.clear();
    _routesAbsentes.clear();
    _routesPresentes.clear();
    _serveursRecents.clear();
  }

  // --- 4.15 : ROUTES RÉCENTES (réponse du serveur aux demandes mobiles du 15/10/2026) ---
  //
  // Les nouvelles routes (état des rayons, versement en lot) n'existent que sur les serveurs à jour. Un
  // serveur récent se reconnaît SANS requête de plus : sa réponse de connexion porte `role` et `droits`
  // (demande 10). Ancien serveur : les anciennes routes, exactement comme avant (aucune requête en plus).
  // Une route absente malgré tout (404 / 405) est mémorisée pour ce serveur : l'ancien chemin est pris.

  static final Set<String> _serveursRecents = {};
  static final Map<String, Set<String>> _routesAbsentes = {};
  static final Map<String, Set<String>> _routesPresentes = {};

  /// Après la connexion : ce serveur ([baseUrl]) a-t-il les routes récentes ?
  static void noterServeur(String baseUrl, {required bool recent}) {
    if (recent) {
      _serveursRecents.add(baseUrl);
    } else {
      _serveursRecents.remove(baseUrl);
    }
  }

  /// Serveur reconnu récent à la connexion (réponse avec `role` / `droits`).
  bool get serveurRecent => _serveursRecents.contains(baseUrl);

  /// 4.15.3 (retour du pharmacien) — un 404 sur une route NOUVELLE ne prouve pas un serveur ancien : pendant
  /// un démarrage ou un redéploiement de Prestige, TOUT répond 404. Vérification légère, faite SEULEMENT après
  /// un tel 404 (aucune requête en plus en fonctionnement normal) : `GET /licence/find`, route publique déjà lue
  /// au lancement. Prestige répond → la route manque vraiment (serveur ancien) ; sinon → Prestige n'est pas
  /// déployé (serveur indisponible : rien n'est conclu, on réessaiera).
  Future<bool> _prestigeDeploye() async {
    try {
      final r = await _httpGet(Uri.parse('$baseUrl/api/v1/licence/find')).timeout(const Duration(seconds: 10));
      return !serveurIndisponible(r) && r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  bool _absente(String route) => _routesAbsentes[route]?.contains(baseUrl) ?? false;
  void _marquerAbsente(String route) => _routesAbsentes.putIfAbsent(route, () => {}).add(baseUrl);

  /// Message lisible d'un refus de la saisie par un serveur récent (demande 8 : 404 LIGNE_INCONNUE,
  /// 409 INVENTAIRE_CLOTURE, 400 QUANTITE_INVALIDE ; 403 droit manquant).
  static String _refusSaisie(http.Response r) {
    final interdit = droitManquant(r);
    if (interdit != null) return interdit;
    var code = '';
    var message = '';
    try {
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (d is Map) {
        code = '${d['code'] ?? ''}';
        message = '${d['message'] ?? d['msg'] ?? d['errors'] ?? ''}'.trim();
      }
    } catch (_) {}
    switch (code) {
      case 'INVENTAIRE_CLOTURE':
        return 'Inventaire clôturé sur le serveur : quantité non enregistrée.';
      case 'LIGNE_INCONNUE':
        return 'Cette ligne n\'existe plus dans l\'inventaire : quantité non enregistrée.';
      case 'QUANTITE_INVALIDE':
        return 'Quantité refusée par le serveur (invalide).';
    }
    return message.isEmpty ? 'Le serveur a refusé la quantité (code ${r.statusCode}).' : message;
  }

  /// Pose la quantité TOTALE par `POST /inventaire/ligne/quantite` {lg_INVENTAIRE_FAMILLE_ID, int_NUMBER} :
  /// session exigée, AUTEUR enregistré par le serveur (str_UPDATED_ID). Réponses du serveur :
  /// {"success":1,"int_NUMBER":q} ; refus {"success":0,"errors":"…"} (ligne inexistante, quantité
  /// invalide) ; 401 sans session. Route absente (404/405, serveur plus ancien) : route habituelle
  /// (PUT /ws/inventaires/details). Ne lève jamais.
  @override
  Future<ReponseEnvoi> poserQuantiteSession(int ligneId, int quantite) async {
    if (_sansRouteSession.contains(baseUrl)) return poserQuantite(ligneId, quantite);
    final url = Uri.parse('$baseUrl/api/v1/inventaire/ligne/quantite');
    try {
      final response = await _httpPost(url, jsonEncode({'lg_INVENTAIRE_FAMILLE_ID': '$ligneId', 'int_NUMBER': quantite}))
          .timeout(const Duration(seconds: 15));
      final code = response.statusCode;
      if (code == 404 || code == 405) {
        final r = await poserQuantite(ligneId, quantite);
        // Route habituelle également indisponible (redéploiement) : rien n'est mémorisé.
        if (!(r.type == ResultatEnvoi.reseau && r.message == messageIndisponible)) _sansRouteSession.add(baseUrl);
        return r;
      }
      if (serveurIndisponible(response)) return const ReponseEnvoi(ResultatEnvoi.reseau, messageIndisponible);
      if (droitManquant(response) != null) return ReponseEnvoi(ResultatEnvoi.refus, _refusSaisie(response));
      if (code == 401 || code == 403) return ReponseEnvoi(ResultatEnvoi.session, 'Session expirée ou accès refusé (code $code).');
      if (code >= 500) return ReponseEnvoi(ResultatEnvoi.erreurServeur, 'Erreur du serveur (code $code).');
      if (code >= 400) return ReponseEnvoi(ResultatEnvoi.refus, _refusSaisie(response));
      final dynamic data;
      try {
        data = json.decode(utf8.decode(response.bodyBytes));
      } catch (_) {
        return const ReponseEnvoi(ResultatEnvoi.erreurServeur, 'Réponse illisible du serveur.');
      }
      if (data is! Map) return const ReponseEnvoi(ResultatEnvoi.erreurServeur, 'Réponse inattendue du serveur.');
      final succes = data['success'];
      if (succes == 1 || succes == true) return ReponseEnvoi.ok;
      final message = '${data['errors'] ?? data['message'] ?? data['msg'] ?? 'Quantité refusée.'}';
      // Session perdue côté serveur (réponse « Veuillez vous connecter »).
      if (message.toLowerCase().contains('connecter')) return ReponseEnvoi(ResultatEnvoi.session, message);
      return ReponseEnvoi(ResultatEnvoi.refus, message);
    } on TimeoutException {
      return const ReponseEnvoi(ResultatEnvoi.reseau, 'Le serveur met trop de temps à répondre.');
    } catch (e) {
      if (estCertificatRefuse(e)) return const ReponseEnvoi(ResultatEnvoi.reseau, messageCertificat);
      if (_estErreurReseau(e)) return const ReponseEnvoi(ResultatEnvoi.reseau, messageInjoignable);
      return ReponseEnvoi(ResultatEnvoi.reseau, 'Envoi impossible : $e');
    }
  }

  /// Tous les inventaires ouverts (GET /ws/inventaires sans limite). `null` si la liste n'a pas pu être lue.
  @override
  Future<InventairesOuverts?> inventairesOuverts() async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 20));
      final code = response.statusCode;
      if (code == 401 || code == 403) throw SessionServeurExpiree('Session expirée ou accès refusé (code $code).');
      if (code != 200) return null;
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is Map) {
        // Session perdue côté serveur (réponse « Veuillez vous connecter » au lieu de la liste).
        final message = '${data['errors'] ?? data['message'] ?? data['msg'] ?? ''}';
        if (message.toLowerCase().contains('connecter')) throw SessionServeurExpiree(message);
      }
      if (data is! List) return null;
      return InventairesOuverts({for (final i in data) if (i is Map && i['id'] != null) '${i['id']}'});
    } on SessionServeurExpiree {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  // --- CHARGEMENT COMMUN : un échec n'est JAMAIS une liste vide ---

  /// GET d'une liste JSON. Lève [ApiLoadException] (réseau, session expirée, refus, données
  /// illisibles) au lieu de renvoyer une liste vide.
  Future<List<T>> _loadList<T>(String quoi, Uri url, T Function(Map<String, dynamic>) parse,
      {Duration delai = const Duration(seconds: 20)}) async {
    final http.Response response;
    try {
      response = await _httpGet(url).timeout(delai);
    } on TimeoutException {
      throw ApiLoadException(injoignable('$quoi non chargés, délai dépassé'),
          TypeErreurChargement.reseau);
    } catch (e) {
      if (estCertificatRefuse(e)) throw ApiLoadException('$messageCertificat ($quoi non chargés)', TypeErreurChargement.reseau);
      if (_estErreurReseau(e)) throw ApiLoadException(messageReseau(quoi, e), TypeErreurChargement.reseau);
      throw ApiLoadException('Impossible de charger les $quoi : $e', TypeErreurChargement.reseau);
    }
    final code = response.statusCode;
    if (serveurIndisponible(response)) {
      throw ApiLoadException(indisponible('$quoi non chargés'), TypeErreurChargement.reseau);
    }
    if (code == 401 || code == 403) {
      throw ApiLoadException('Session expirée ($quoi non chargés) : reconnectez-vous.', TypeErreurChargement.session);
    }
    // Demande 21 : une lecture en échec côté serveur répond 500 (jamais `[]`) — jamais une liste vide ici.
    if (code >= 500) throw ApiLoadException('Erreur du serveur (code $code) : $quoi non chargés. Réessayez dans un instant.');
    if (code != 200) throw ApiLoadException('Le serveur a refusé le chargement des $quoi (code $code).');
    final dynamic data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiLoadException('Réponse illisible du serveur pour les $quoi.', TypeErreurChargement.donnees);
    }
    if (data is! List) throw ApiLoadException('Réponse inattendue du serveur pour les $quoi.', TypeErreurChargement.donnees);
    try {
      return [for (final item in data) parse(Map<String, dynamic>.from(item as Map))];
    } catch (e) {
      throw ApiLoadException('Données des $quoi illisibles.', TypeErreurChargement.donnees);
    }
  }

  static List<Product> _parTri(List<Product> ps) => ps..sort((a, b) => a.produitName.compareTo(b.produitName));

  Uri _uri(String route, Map<String, String?> params) {
    final q = <String, String>{
      for (final e in params.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    return Uri.parse('$baseUrl/api/v1/ws/inventaires$route').replace(queryParameters: q.isEmpty ? null : q);
  }

  // --- INVENTAIRES ---

  Future<List<Inventory>> fetchInventories({int maxResult = 3}) =>
      _loadList('inventaires', _uri('', {'maxResult': '$maxResult'}), Inventory.fromJson);

  /// TOUS les inventaires ouverts, du plus récent au plus ancien (choix de l'inventaire d'un versement,
  /// contrôle des doublons à la création).
  Future<List<Inventory>> fetchTousInventairesOuverts() => _loadList('inventaires', _uri('', {}), Inventory.fromJson);

  /// Création d'un inventaire : `POST /inventaire/creation` {str_NAME, str_TYPE_TRANSACTION}.
  ///
  /// Comportement du serveur (InventaireRessource.creerInventaire, vérifié) : session exigée (401
  /// sinon) ; libellé et type obligatoires (refus lisible {"success":0,"message":…}) ; types
  /// reconnus : Emplacement, Famille, Grossiste. Sans valeurs choisies, l'inventaire est PRÉ-REMPLI
  /// avec TOUS les produits actifs de l'officine (une ligne par produit, stock théorique = stock
  /// disponible, non comptée) ; aucun produit → aucun inventaire. Réponse : {"success":1,"lignes":N}
  /// (+ `lgInventaireId` et `libelle` sur les serveurs récents, demande 20 ; sinon l'identifiant est
  /// relu dans la liste des inventaires ouverts). Droit manquant (serveurs récents, demande 10) :
  /// 403 {interdit:true, msg:"Droit manquant : Créer un inventaire"} → refus (≠ session expirée).
  ///
  /// [valeurs] = identifiants cochés sur l'axe du type (pour « Emplacement » : les lg_ZONE_GEO_ID des
  /// rayons) : le serveur ne met QUE les produits actifs de ces emplacements (createInventaireMultiCriteres,
  /// un appel de la procédure par valeur). Absent ou vide : TOUS les produits (comportement d'origine).
  ///
  /// 4.15 — [nonRetenues] : `bool_INVENTAIRE = 0`, comme l'inventaire « unitaire » de Prestige : les
  /// lignes sont créées mais NON retenues (invisibles des lectures ws/inventaires, de la saisie et de la
  /// clôture) jusqu'à [retenirProduits]. C'est ainsi que Prestige crée un inventaire limité à une liste
  /// de produits (écran web « Inventaire unitaire » puis « Ajouter des articles »).
  ///
  /// 4.16.1 (demande serveur 46) — [produits] (lg_FAMILLE_ID) : un serveur à jour crée l'inventaire de CES produits
  /// seulement, lignes retenues, en UNE transaction, et répond `inconnus` (éléments non retrouvés) ; un serveur plus
  /// ancien ignore le champ et applique [valeurs] / [nonRetenues] (méthode en deux temps, voir
  /// CreationInventaire.creerDepuisCollecte). [ResultatCreationServeur.inconnus] non null ⇔ pris en compte.
  Future<ResultatCreationServeur> creerInventaire(String libelle, String type,
      {List<String>? valeurs, bool nonRetenues = false, List<String>? produits}) async {
    final url = Uri.parse('$baseUrl/api/v1/inventaire/creation');
    final http.Response response;
    try {
      response = await _httpPost(
              url,
              jsonEncode({
                'str_NAME': libelle,
                'str_TYPE_TRANSACTION': type,
                if (valeurs != null && valeurs.isNotEmpty) 'valeurs': valeurs,
                if (nonRetenues) 'bool_INVENTAIRE': 0,
                if (produits != null && produits.isNotEmpty) 'produits': produits,
              }))
          // Plusieurs milliers de produits : la création peut prendre du temps.
          .timeout(const Duration(seconds: 180));
    } on TimeoutException {
      return const ResultatCreationServeur.incertain('Le serveur met trop de temps à répondre.');
    } catch (e) {
      // Certificat refusé : la demande n'est jamais partie (poignée de main HTTPS refusée).
      if (estCertificatRefuse(e)) return const ResultatCreationServeur.refus(messageCertificat);
      // La demande a pu partir avant la coupure : on ne sait pas si l'inventaire existe.
      if (connexionRefusee(e)) return const ResultatCreationServeur.refus(messageInjoignable); // rien n'est parti
      return ResultatCreationServeur.incertain(_estErreurReseau(e) ? messageInjoignable : 'Création impossible : $e');
    }
    final code = response.statusCode;
    // Prestige indisponible : PEUT-ÊTRE rien de créé (relais 502 / 504) → la liste est relue avant tout.
    if (serveurIndisponible(response)) return const ResultatCreationServeur.incertain(messageIndisponible);
    final interdit = droitManquant(response);
    if (interdit != null) return ResultatCreationServeur.refus(interdit);
    if (code == 401 || code == 403) return const ResultatCreationServeur.session();
    dynamic data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } catch (_) {
      data = null;
    }
    final m = data is Map ? data : const {};
    final message = '${m['message'] ?? m['nombre'] ?? m['msg'] ?? ''}'.trim();
    if (code >= 500) {
      return ResultatCreationServeur.refus(message.isEmpty ? 'Erreur du serveur (code $code).' : 'Erreur du serveur : $message');
    }
    if (code != 200 || data is! Map) return ResultatCreationServeur.refus('Le serveur a refusé la création (code $code).');
    final succes = m['success'];
    final inconnus = m['inconnus'] is List ? [for (final e in m['inconnus'] as List) '$e'] : null;
    if (succes == 1 || succes == true) {
      final id = '${m['lgInventaireId'] ?? ''}'.trim();
      return ResultatCreationServeur.ok((m['lignes'] as num?)?.toInt(), inventaireId: id.isEmpty ? null : id, inconnus: inconnus);
    }
    if (message.toLowerCase().contains('connecter')) return const ResultatCreationServeur.session();
    return ResultatCreationServeur.refus(message.isEmpty ? 'Création refusée par le serveur.' : message);
  }

  /// Serveurs récents (réponse aux demandes mobiles) : un DROIT manquant répond 403
  /// {interdit:true, msg:"Droit manquant : …"} — l'application ne doit pas demander de reconnexion.
  /// Renvoie le message à afficher, ou null si la réponse n'est pas un refus de droit.
  static String? droitManquant(http.Response r) {
    if (r.statusCode != 403) return null;
    try {
      final d = json.decode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (d is Map && d['interdit'] == true) {
        final m = '${d['msg'] ?? d['message'] ?? ''}'.trim();
        return m.isEmpty ? 'Droit manquant dans Prestige pour cette opération.' : m;
      }
    } catch (_) {}
    return null;
  }

  // --- EMPLACEMENTS DE L'OFFICINE (création d'un inventaire depuis la collecte, 4.14.1) ---

  /// GET JSON (objet ou liste). Mêmes erreurs que [_loadList] : jamais une réponse vide trompeuse.
  Future<dynamic> _loadJson(String quoi, Uri url, {Duration delai = const Duration(seconds: 20)}) async {
    final http.Response response;
    try {
      response = await _httpGet(url).timeout(delai);
    } on TimeoutException {
      throw ApiLoadException(injoignable('$quoi non chargés, délai dépassé'),
          TypeErreurChargement.reseau);
    } catch (e) {
      if (estCertificatRefuse(e)) throw ApiLoadException('$messageCertificat ($quoi non chargés)', TypeErreurChargement.reseau);
      if (_estErreurReseau(e)) throw ApiLoadException(messageReseau(quoi, e), TypeErreurChargement.reseau);
      throw ApiLoadException('Impossible de charger les $quoi : $e', TypeErreurChargement.reseau);
    }
    final code = response.statusCode;
    if (serveurIndisponible(response)) {
      throw ApiLoadException(indisponible('$quoi non chargés'), TypeErreurChargement.reseau);
    }
    if (code == 401 || code == 403) {
      throw ApiLoadException('Session expirée ($quoi non chargés) : reconnectez-vous.', TypeErreurChargement.session);
    }
    if (code != 200) throw ApiLoadException('Le serveur a refusé le chargement des $quoi (code $code).');
    final dynamic data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiLoadException('Réponse illisible du serveur pour les $quoi.', TypeErreurChargement.donnees);
    }
    if (data is Map && data['success'] == false) {
      final m = '${data['message'] ?? data['msg'] ?? ''}';
      if (m.toLowerCase().contains('connecter')) {
        throw ApiLoadException('Session expirée ($quoi non chargés) : reconnectez-vous.', TypeErreurChargement.session);
      }
      throw ApiLoadException(m.isEmpty ? 'Le serveur a refusé le chargement des $quoi.' : m);
    }
    return data;
  }

  /// Produit de l'officine retrouvé par un code tel que scanné (CIP, EAN-13, EAN fabricant, code article
  /// grossiste) : `GET /api/v1/produit-search/fiche?search_value=…` (recherche de la fiche article, « commence
  /// par » pour un code numérique) → results:[{lg_FAMILLE_ID, int_CIP, int_EAN13, str_NAME,
  /// lg_ZONE_GEO_ID (libellé de l'emplacement), lg_ZONE_GEO_ID_REEL (son identifiant)}].
  ///
  /// Correspondance SÛRE (jamais un produit voisin) : CIP ou EAN-13 identique au code, en un seul
  /// produit ; sinon un résultat unique trouvé par un AUTRE code que le début de son CIP / EAN (code
  /// article, EAN fabricant). Plusieurs produits possibles ou correspondance partielle : null.
  /// Lève [ApiLoadException] (réseau, session, refus) — jamais « inconnu » sur une panne.
  Future<ProduitServeur?> produitParCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final url = Uri.parse('$baseUrl/api/v1/produit-search/fiche').replace(queryParameters: {'search_value': c, 'start': '0', 'limit': '5'});
    final data = await _loadJson('produits de la collecte', url, delai: const Duration(seconds: 15));
    final liste = data is Map ? data['results'] : data;
    if (liste is! List) return null;
    final lignes = [for (final l in liste.whereType<Map>()) if ('${l['lg_FAMILLE_ID'] ?? ''}'.trim().isNotEmpty) l];
    if (lignes.isEmpty) return null;
    String champ(Map l, String k) => '${l[k] ?? ''}'.trim();
    final exacts = lignes.where((l) => champ(l, 'int_CIP') == c || champ(l, 'CIP') == c || champ(l, 'int_EAN13') == c).toList();
    final ids = exacts.map((l) => champ(l, 'lg_FAMILLE_ID')).toSet();
    Map? retenu;
    if (ids.length == 1) {
      retenu = exacts.first;
    } else if (ids.isEmpty && lignes.length == 1) {
      final l = lignes.first;
      // Trouvé par le DÉBUT de son CIP / EAN seulement : correspondance partielle, refusée.
      final partiel = champ(l, 'int_CIP').startsWith(c) || champ(l, 'int_EAN13').startsWith(c);
      if (!partiel) retenu = l;
    }
    if (retenu == null) return null;
    final zone = champ(retenu, 'lg_ZONE_GEO_ID_REEL');
    return ProduitServeur(
      id: champ(retenu, 'lg_FAMILLE_ID'),
      cip: champ(retenu, 'int_CIP'),
      nom: champ(retenu, 'str_NAME'),
      emplacement: zone.isEmpty ? null : Rayon(id: zone, code: '', libelle: champ(retenu, 'lg_ZONE_GEO_ID')),
    );
  }

  // --- 4.15 : INVENTAIRE LIMITÉ AUX PRODUITS COLLECTÉS (lignes retenues, comme Prestige) ---

  /// La route `POST /inventaire/lignes/retenue` existe-t-elle ? Essai SANS effet : aucun identifiant
  /// envoyé, le serveur répond {"success":0,"errors":"Aucun article a traiter."}. 404 / 405 : serveur plus
  /// ancien (faux). Lève [ApiLoadException] (réseau, session, erreur du serveur).
  Future<bool> routeRetenueDisponible() async {
    if (_absente('lignes/retenue')) return false;
    if (serveurRecent || (_routesPresentes['lignes/retenue']?.contains(baseUrl) ?? false)) return true;
    final r = await _envoyerJson('création de l\'inventaire', 'inventaire/lignes/retenue', {'lg_INVENTAIRE_ID': '', 'ids': <String>[]});
    if (r.statusCode == 404 || r.statusCode == 405) {
      if (r.statusCode == 404 && !await _prestigeDeploye()) {
        throw ApiLoadException(indisponible('création de l\'inventaire'), TypeErreurChargement.reseau);
      }
      _marquerAbsente('lignes/retenue');
      return false;
    }
    _controlerReponse(r, 'création de l\'inventaire');
    _routesPresentes.putIfAbsent('lignes/retenue', () => {}).add(baseUrl);
    return true;
  }

  /// Nombre maximal de produits retenus par requête.
  static const int retenueParLot = 200;

  /// RETIENT les lignes des produits [produitIds] (lg_FAMILLE_ID) dans l'inventaire [inventaireId] :
  /// `POST /inventaire/lignes/retenue` {lg_INVENTAIRE_ID, produits, retenue:true} → {success, count}
  /// (route de l'écran web « Ajouter des articles » d'un inventaire unitaire). Idempotent : une ligne
  /// déjà retenue le reste. Renvoie le nombre de lignes retenues (0 : aucun de ces produits dans
  /// l'inventaire). Lève [ApiLoadException] (réseau, session, refus, route absente : refus).
  Future<int> retenirProduits(String inventaireId, List<String> produitIds) async {
    final ids = produitIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    var total = 0;
    for (var i = 0; i < ids.length; i += retenueParLot) {
      final lot = ids.sublist(i, (i + retenueParLot).clamp(0, ids.length));
      final r = await _envoyerJson('produits de l\'inventaire', 'inventaire/lignes/retenue',
          {'lg_INVENTAIRE_ID': inventaireId, 'produits': lot, 'retenue': true});
      if (r.statusCode == 404 || r.statusCode == 405) {
        if (r.statusCode == 404 && !await _prestigeDeploye()) {
          throw ApiLoadException(indisponible('produits de l\'inventaire'), TypeErreurChargement.reseau);
        }
        _marquerAbsente('lignes/retenue');
        throw const ApiLoadException('Ce serveur Prestige ne permet pas encore de créer un inventaire limité aux produits scannés. '
            'Mettez le serveur à jour ou versez la collecte dans un inventaire existant.');
      }
      final m = _controlerReponse(r, 'produits de l\'inventaire');
      final n = (m['count'] as num?)?.toInt() ?? 0;
      final succes = m['success'] == 1 || m['success'] == true;
      final message = '${m['errors'] ?? m['message'] ?? m['msg'] ?? ''}'.trim();
      if (!succes && n == 0 && message.isNotEmpty && !message.toLowerCase().contains('aucun article')) throw ApiLoadException(message);
      total += n;
    }
    return total;
  }

  /// POST JSON : erreurs réseau traduites en [ApiLoadException] (jamais un résultat trompeur).
  Future<http.Response> _envoyerJson(String quoi, String route, Object corps, {Duration delai = const Duration(seconds: 30)}) async {
    final url = Uri.parse('$baseUrl/api/v1/$route');
    try {
      return await _httpPost(url, jsonEncode(corps)).timeout(delai);
    } on TimeoutException {
      throw ApiLoadException('Le serveur met trop de temps à répondre ($quoi). Vérifiez le réseau puis réessayez.', TypeErreurChargement.reseau);
    } catch (e) {
      if (estCertificatRefuse(e)) throw ApiLoadException('$messageCertificat ($quoi)', TypeErreurChargement.reseau);
      if (_estErreurReseau(e)) throw ApiLoadException(injoignable(quoi), TypeErreurChargement.reseau);
      throw ApiLoadException('Envoi impossible ($quoi) : $e', TypeErreurChargement.reseau);
    }
  }

  /// Contrôle commun d'une réponse JSON objet : droit manquant, session, erreur du serveur, illisible.
  Map<dynamic, dynamic> _controlerReponse(http.Response r, String quoi) {
    if (serveurIndisponible(r)) throw ApiLoadException(indisponible(quoi), TypeErreurChargement.reseau);
    final interdit = droitManquant(r);
    if (interdit != null) throw ApiLoadException(interdit);
    final code = r.statusCode;
    if (code == 401 || code == 403) throw ApiLoadException('Session expirée ($quoi) : reconnectez-vous.', TypeErreurChargement.session);
    if (code >= 500) throw ApiLoadException('Erreur du serveur (code $code, $quoi). Réessayez dans un instant.');
    // 4.16.1 (demande serveur 48) : inventaire clôturé (409 INVENTAIRE_CLOTURE) → message du serveur.
    if (code == 409) {
      var m = '';
      try {
        final d = json.decode(utf8.decode(r.bodyBytes, allowMalformed: true));
        if (d is Map) m = '${d['msg'] ?? d['errors'] ?? d['message'] ?? ''}'.trim();
      } catch (_) {}
      throw ApiLoadException(m.isEmpty ? 'Inventaire clôturé : aucune ligne n\'a été modifiée.' : m);
    }
    if (code != 200) throw ApiLoadException('Le serveur a refusé la demande ($quoi, code $code).');
    final dynamic d;
    try {
      d = json.decode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw ApiLoadException('Réponse illisible du serveur ($quoi).', TypeErreurChargement.donnees);
    }
    if (d is! Map) throw ApiLoadException('Réponse inattendue du serveur ($quoi).', TypeErreurChargement.donnees);
    final m = '${d['errors'] ?? d['message'] ?? d['msg'] ?? ''}';
    if ((d['success'] == false || d['success'] == 0) && m.toLowerCase().contains('connecter')) {
      throw ApiLoadException('Session expirée ($quoi) : reconnectez-vous.', TypeErreurChargement.session);
    }
    return d;
  }

  // --- CUMUL / VERIFICATION ---

  /// Quantité déjà comptée sur le serveur pour ce produit (`null` = jamais compté).
  ///
  /// IMPORTANT : un échec (réseau lent, serveur injoignable, session expirée, réponse illisible) LÈVE
  /// [ApiLoadException] — il ne signifie JAMAIS « jamais compté » (sinon on écraserait le comptage d'un
  /// collègue). Si [ligneId] est fourni, c'est cette ligne précise qui compte (un même produit peut
  /// figurer dans deux emplacements) ; sinon la première ligne de ce CIP déjà comptée.
  Future<int?> verifierDejaCompte(String inventoryId, String cip, {int? ligneId}) async {
    if (cip.isEmpty) return null;
    final uri = Uri.parse('$baseUrl/api/v1/ws/inventaires/detailsAllTouched').replace(queryParameters: {
      'idInventaire': inventoryId,
      'query': cip,
    });
    final http.Response response;
    try {
      response = await _httpGet(uri).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const ApiLoadException('Le serveur met trop de temps à répondre : impossible de savoir si ce produit est déjà compté.', TypeErreurChargement.reseau);
    } catch (e) {
      if (estCertificatRefuse(e)) throw const ApiLoadException(messageCertificat, TypeErreurChargement.reseau);
      throw ApiLoadException(injoignable('impossible de savoir si ce produit est déjà compté'), TypeErreurChargement.reseau);
    }
    if (serveurIndisponible(response)) {
      throw ApiLoadException(indisponible('impossible de savoir si ce produit est déjà compté'), TypeErreurChargement.reseau);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ApiLoadException('Session expirée : reconnectez-vous pour vérifier si ce produit est déjà compté.', TypeErreurChargement.session);
    }
    if (response.statusCode != 200) {
      throw ApiLoadException('Le serveur a refusé la vérification « déjà compté » (code ${response.statusCode}).');
    }
    final List<dynamic> data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    } catch (_) {
      throw const ApiLoadException('Réponse illisible du serveur pour la vérification « déjà compté ».', TypeErreurChargement.donnees);
    }
    int? qteDe(dynamic item) {
      if (item is! Map || item['dtUpdated'] == null || item['quantiteSaisie'] is! num) return null;
      return (item['quantiteSaisie'] as num).toInt();
    }

    if (ligneId != null) {
      final memeLigne = data.where((i) => i is Map && i['id'] is num && (i['id'] as num).toInt() == ligneId).toList();
      if (memeLigne.isNotEmpty) return qteDe(memeLigne.first);
      // La réponse ne contient pas cette ligne : jamais comptée (les lignes comptées sont toutes renvoyées).
      if (data.any((i) => i is Map && i['id'] is num)) return null;
    }
    for (final item in data) {
      if (item is Map && item['produitCip']?.toString() == cip) {
        final q = qteDe(item);
        if (q != null) return q;
      }
    }
    return null;
  }

  // --- RAYONS & PRODUITS ---

  /// Rayons (emplacements) d'un inventaire, du moins au plus récent : seulement ceux qui ont des produits
  /// À COMPTER. Serveur récent : `GET /ws/inventaires/{id}/rayons/etat` (une requête, comme avant) dont
  /// on garde les rayons à au moins un produit retenu — un inventaire limité à quelques produits (créé
  /// depuis la collecte, ou « unitaire » dans Prestige) n'affiche que leurs emplacements. Sinon (ou route
  /// absente / en erreur) : `GET /ws/inventaires/rayons`, comme avant.
  Future<List<Rayon>> fetchRayons(String idInventaire) async {
    List<EtatRayon>? etat;
    try {
      etat = await etatRayons(idInventaire);
    } on ApiLoadException catch (e) {
      // Session expirée, réseau : l'ancienne route échouerait de même. Autre refus : ancienne route.
      if (e.sessionExpiree || e.reseau) rethrow;
      etat = null;
    }
    if (etat != null) return [for (final e in etat) if (e.totalProduits > 0) e.rayon];
    return _loadList('emplacements', _uri('/rayons', {'idInventaire': idInventaire}), Rayon.fromJson);
  }

  /// Demande 30 — état de comptage de TOUS les rayons en une requête :
  /// `GET /ws/inventaires/{id}/rayons/etat` → [{rayonId, code, libelle, totalProduits, comptes, restants,
  /// derniereSaisie}] (lignes retenues seulement). null : serveur ancien ou route absente (404 / 405,
  /// mémorisé) — l'appelant prend l'ancien chemin. 410 : inventaire inconnu (clôturé, supprimé).
  /// Lève [ApiLoadException] (réseau, session, erreur, réponse illisible ou tronquée) : jamais une
  /// liste vide trompeuse.
  Future<List<EtatRayon>?> etatRayons(String idInventaire) async {
    if (!serveurRecent || _absente('rayons/etat') || idInventaire.isEmpty) return null;
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/${Uri.encodeComponent(idInventaire)}/rayons/etat');
    const quoi = 'emplacements';
    final http.Response response;
    try {
      response = await _httpGet(url).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiLoadException(injoignable('$quoi non chargés, délai dépassé'),
          TypeErreurChargement.reseau);
    } catch (e) {
      if (estCertificatRefuse(e)) throw const ApiLoadException('$messageCertificat ($quoi non chargés)', TypeErreurChargement.reseau);
      throw ApiLoadException(messageReseau(quoi, e), TypeErreurChargement.reseau);
    }
    final code = response.statusCode;
    if (code == 502 || code == 503 || code == 504) {
      throw ApiLoadException(indisponible('$quoi non chargés'), TypeErreurChargement.reseau);
    }
    if (code == 404 || code == 405) {
      if (code == 404 && !await _prestigeDeploye()) throw ApiLoadException(indisponible('$quoi non chargés'), TypeErreurChargement.reseau);
      _marquerAbsente('rayons/etat');
      return null;
    }
    if (code == 410) throw const ApiLoadException('Inventaire introuvable sur le serveur (clôturé ou supprimé).');
    if (code == 401 || (code == 403 && droitManquant(response) == null)) {
      throw const ApiLoadException('Session expirée ($quoi non chargés) : reconnectez-vous.', TypeErreurChargement.session);
    }
    if (code >= 500) throw ApiLoadException('Erreur du serveur (code $code) : $quoi non chargés. Réessayez dans un instant.');
    if (code != 200) throw ApiLoadException('Le serveur a refusé le chargement des $quoi (code $code).');
    final dynamic data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const ApiLoadException('Réponse illisible du serveur pour les $quoi.', TypeErreurChargement.donnees);
    }
    if (data is! List) throw const ApiLoadException('Réponse inattendue du serveur pour les $quoi.', TypeErreurChargement.donnees);
    try {
      return [for (final e in data) EtatRayon.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      throw const ApiLoadException('Données des $quoi illisibles.', TypeErreurChargement.donnees);
    }
  }

  /// Récupère les produits.
  /// - [idRayon] vide : 'detailsAll' (Mode Global / Saisie Rapide)
  /// - [idRayon] renseigné : 'details' (Mode par Emplacement)
  Future<List<Product>> fetchProducts(String idInventaire, String? idRayon, {String? query}) async {
    final parRayon = idRayon != null && idRayon.isNotEmpty;
    final url = _uri(parRayon ? '/details' : '/detailsAll', {
      'idInventaire': idInventaire,
      if (parRayon) 'idRayon': idRayon,
      'query': query,
    });
    journal('Chargement des produits${parRayon ? ' (emplacement)' : ''}');
    return _parTri(await _loadList('produits', url, Product.fromJson));
  }

  // --- ÉCARTS ---

  Future<List<Product>> fetchGlobalVariances(String idInventaire, {String? query}) async =>
      _parTri(await _loadList('écarts', _uri('/detailsAllEcarts', {'idInventaire': idInventaire, 'query': query}), Product.fromJson));

  // --- NON INVENTORIÉS ---

  Future<List<Product>> fetchUntouchedProducts(String idInventaire, {String? query}) async =>
      _parTri(await _loadList('restants', _uri('/detailsAllUntouched', {'idInventaire': idInventaire, 'query': query}), Product.fromJson));

  Future<List<Product>> fetchUntouchedProductsByRayon(String idInventaire, String idRayon, {String? query}) async => _parTri(await _loadList(
      'restants de l\'emplacement',
      _uri('/detailsUntouchedRayon', {'idInventaire': idInventaire, 'idRayon': idRayon, 'query': query}),
      Product.fromJson));

  Future<List<Product>> fetchTouchedProductsByRayon(String inventoryId, String rayonId, {String? query}) => _loadList(
      'produits comptés de l\'emplacement',
      _uri('/detailsTouchedRayon', {'idInventaire': inventoryId, 'idRayon': rayonId, 'query': query}),
      Product.fromJson);

  /// Le rayon a-t-il été entamé ? `null` si on ne peut pas le savoir (erreur : état inconnu, et non
  /// plus « pas commencé »).
  Future<bool?> hasTouchedProductsInRayon(String inventoryId, String rayonId) async {
    try {
      return await rayonAProduitsComptes(inventoryId, rayonId);
    } on ApiLoadException {
      return null;
    }
  }

  /// Même requête que [hasTouchedProductsInRayon], mais l'échec est levé ([ApiLoadException] : réseau,
  /// session expirée, refus…) pour que l'appelant puisse en donner le motif exact.
  Future<bool> rayonAProduitsComptes(String inventoryId, String rayonId) async =>
      (await _loadList('produits comptés', _uri('/detailsTouchedRayon', {'idInventaire': inventoryId, 'idRayon': rayonId}), (m) => m,
              delai: const Duration(seconds: 8)))
          .isNotEmpty;

  /// Lignes déjà comptées d'un emplacement (id, quantités), même requête que [rayonAProduitsComptes] ;
  /// l'échec est levé ([ApiLoadException]). Sert au calcul de l'avancement en produits.
  Future<List<Map<String, dynamic>>> lignesCompteesRayon(String inventoryId, String rayonId) =>
      _loadList('produits comptés', _uri('/detailsTouchedRayon', {'idInventaire': inventoryId, 'idRayon': rayonId}), (m) => m,
          delai: const Duration(seconds: 8));

  /// Lignes restant à compter d'un emplacement, même requête que [rayonAProduitsRestants] (échec levé).
  Future<List<Map<String, dynamic>>> lignesRestantesRayon(String inventoryId, String rayonId) =>
      _loadList('restants', _uri('/detailsUntouchedRayon', {'idInventaire': inventoryId, 'idRayon': rayonId}), (m) => m,
          delai: const Duration(seconds: 8));

  /// Reste-t-il des produits à compter ? `null` si on ne peut pas le savoir.
  Future<bool?> hasUntouchedProductsInRayon(String inventoryId, String rayonId) async {
    try {
      return await rayonAProduitsRestants(inventoryId, rayonId);
    } on ApiLoadException {
      return null;
    }
  }

  /// Même requête que [hasUntouchedProductsInRayon], échec levé ([ApiLoadException]).
  Future<bool> rayonAProduitsRestants(String inventoryId, String rayonId) async =>
      (await _loadList('restants', _uri('/detailsUntouchedRayon', {'idInventaire': inventoryId, 'idRayon': rayonId}), (m) => m,
              delai: const Duration(seconds: 8)))
          .isNotEmpty;

  // --- 4.15 : VERSEMENT DE LA COLLECTE EN LOT (demande 37) ---

  /// Lignes au plus par versement (le serveur en accepte 500).
  static const int versementParLot = 200;

  /// La route du versement en lot peut-elle être essayée sur ce serveur ?
  bool get versementLotPossible => serveurRecent && !_absente('versement');

  /// `POST /inventaire/{id}/versement` {cle, mode:"ajouter"|"remplacer", lignes:[{code, quantite}]} →
  /// rapport par ligne (ok + ligneId + quantiteFinale, inconnu, ambigu, refuse). Même [cle] et même
  /// contenu → le serveur rend le rapport d'origine sans rien refaire (`dejaTraite`) : une reprise après
  /// coupure ne compte jamais deux fois. Ne lève jamais : l'issue est classée.
  ///
  /// [reprise] : lot DÉJÀ envoyé dont la réponse s'est perdue — renvoyé même si le serveur n'est plus
  /// reconnu récent (seul un 404 / 405 prouve que rien n'a été enregistré).
  Future<ResultatVersementLot> verserLot(String inventaireId,
      {required String cle, required bool ajouter, required List<(String, int)> lignes, bool reprise = false}) async {
    if (_absente('versement') || (!reprise && !serveurRecent)) return const ResultatVersementLot(IssueVersementLot.routeAbsente);
    final url = Uri.parse('$baseUrl/api/v1/inventaire/${Uri.encodeComponent(inventaireId)}/versement');
    final http.Response response;
    try {
      response = await _httpPost(
              url,
              jsonEncode({
                'cle': cle,
                'mode': ajouter ? 'ajouter' : 'remplacer',
                'lignes': [for (final (code, q) in lignes) {'code': code, 'quantite': q}],
              }))
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      return const ResultatVersementLot(IssueVersementLot.incertain, 'Le serveur met trop de temps à répondre.');
    } catch (e) {
      if (estCertificatRefuse(e)) return const ResultatVersementLot(IssueVersementLot.reseau, messageCertificat);
      return ResultatVersementLot(IssueVersementLot.incertain, _estErreurReseau(e) ? messageInjoignable : 'Envoi impossible.');
    }
    final code = response.statusCode;
    if (code == 404 || code == 405) {
      // Prestige non déployé (redéploiement) : rien n'est conclu, le lot est gardé et renvoyé plus tard.
      if (code == 404 && !await _prestigeDeploye()) return const ResultatVersementLot(IssueVersementLot.indisponible, messageIndisponible);
      _marquerAbsente('versement');
      return const ResultatVersementLot(IssueVersementLot.routeAbsente);
    }
    if (code == 401 || code == 403) return const ResultatVersementLot(IssueVersementLot.session, 'Session expirée : reconnectez-vous.');
    Map? m;
    try {
      final d = json.decode(utf8.decode(response.bodyBytes));
      if (d is Map) m = d;
    } catch (_) {}
    final codeMetier = '${m?['code'] ?? ''}';
    final message = '${m?['message'] ?? m?['msg'] ?? ''}'.trim();
    if (code == 409 && codeMetier == 'INVENTAIRE_CLOTURE') {
      return ResultatVersementLot(IssueVersementLot.refuse, message.isEmpty ? 'Inventaire clôturé : rien n\'a été enregistré.' : message);
    }
    if (code == 410) return const ResultatVersementLot(IssueVersementLot.refuse, 'Inventaire introuvable sur le serveur (clôturé ou supprimé).');
    if (code == 409) return const ResultatVersementLot(IssueVersementLot.cleReutilisee, 'Versement déjà enregistré avec un autre contenu : vérifiez les quantités dans Prestige.');
    // 400 / 413 : rien n'a été enregistré, l'ancien chemin (produit par produit) prend le relais.
    if (code == 400 || code == 413) return ResultatVersementLot(IssueVersementLot.nonTraite, 'Versement en lot refusé (code $code).');
    // 5xx, réponse illisible ou tronquée : a PEUT-ÊTRE été enregistré → même clé à la reprise.
    if (code != 200 || m == null || m['lignes'] is! List) {
      return ResultatVersementLot(IssueVersementLot.incertain,
          serveurIndisponible(response) ? messageIndisponible : (code >= 500 ? 'Erreur du serveur (code $code).' : 'Réponse illisible du serveur.'));
    }
    final out = <LigneRapportLot>[];
    for (final e in (m['lignes'] as List).whereType<Map>()) {
      final index = (e['index'] as num?)?.toInt();
      if (index == null) continue;
      out.add(LigneRapportLot(
        index: index,
        statut: '${e['statut'] ?? ''}',
        ligneId: int.tryParse('${e['ligneId'] ?? ''}'),
        quantiteFinale: (e['quantiteFinale'] is num) ? (e['quantiteFinale'] as num).toInt() : int.tryParse('${e['quantiteFinale'] ?? ''}'),
        motif: '${e['motif'] ?? ''}',
      ));
    }
    return ResultatVersementLot.rapport(dejaTraite: m['dejaTraite'] == true, lignes: out);
  }

  // --- GESTION LICENCE ---

  /// Enregistre une nouvelle licence.
  ///
  /// ÉCART CONNU AVEC LE SERVEUR (non corrigé ici, voir docs/NOTE_VERSION_FIABILITE.md) : le serveur
  /// expose `GET /licence/save/{clé}` (LicenceRessource) et l'app envoie un POST (→ 405) ; de plus la
  /// route exige une session alors que l'écran d'activation s'affiche avant la connexion (→ 401).
  /// L'activation depuis l'application ne peut donc pas aboutir sans changement côté serveur.
  Future<bool> saveLicense(String key) async {
    final url = Uri.parse('$baseUrl/api/v1/licence/save/${Uri.encodeComponent(key)}');
    try {
      final response = await (_client != null ? _client!.post(url, headers: _getHeaders()) : http.post(url, headers: _getHeaders()))
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      throw Exception(estCertificatRefuse(e)
          ? messageCertificat
          : (_estErreurReseau(e) ? 'Serveur injoignable.' : 'Enregistrement de la licence impossible.'));
    }
  }

  /// Récupère la licence active.
  /// - serveur injoignable / délai dépassé : [ApiLoadException] de type réseau ;
  /// - réponse sans licence ou illisible : [ApiLoadException] de type refus / données.
  Future<License> findLicense() async {
    final url = Uri.parse('$baseUrl/api/v1/licence/find');
    final http.Response response;
    try {
      response = await _httpGet(url).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (estCertificatRefuse(e)) throw const ApiLoadException(messageCertificat, TypeErreurChargement.reseau);
      // Cas 1 (aucune réponse, délai dépassé compris) : la licence n'est pas en cause.
      throw ApiLoadException(injoignable('licence non vérifiée, la licence n\'est pas en cause'), TypeErreurChargement.reseau);
    }
    // Erreur du serveur (5xx) ou réponse d'accès inattendue : le serveur n'a pas pu répondre,
    // on ne conclut RIEN sur la licence (même règle que les autres applications Prestige).
    // 4.15.2 : 404 sans réponse de Prestige (redéploiement) : serveur indisponible, jamais « aucune licence ».
    // 4.15.3 : 502 / 503 / 504 aussi (cas 2), avec le code.
    if (serveurIndisponible(response)) {
      throw ApiLoadException(indisponible('code ${response.statusCode}, la licence n\'est pas en cause'), TypeErreurChargement.reseau);
    }
    if (response.statusCode >= 500 || response.statusCode == 401 || response.statusCode == 403) {
      throw ApiLoadException(
          'Le serveur Prestige a répondu par une erreur (code ${response.statusCode}) : la licence n\'est pas en cause. Réessayez dans un instant.',
          TypeErreurChargement.reseau);
    }
    if (response.statusCode != 200) {
      throw ApiLoadException('Aucune licence valide trouvée (code ${response.statusCode}).');
    }
    try {
      final dynamic data = json.decode(utf8.decode(response.bodyBytes));
      return License.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (_) {
      throw const ApiLoadException('Aucune licence enregistrée sur le serveur.', TypeErreurChargement.donnees);
    }
  }
}

/// Réponse du serveur à une demande de création d'inventaire.
class ResultatCreationServeur {
  final bool succes;

  /// Lignes créées (produits mis dans l'inventaire).
  final int? lignes;

  /// Session expirée / non connecté.
  final bool session;

  /// Pas de réponse (réseau, délai) : l'inventaire a PEUT-ÊTRE été créé.
  final bool incertain;
  final String message;

  /// Identifiant de l'inventaire créé (`lgInventaireId`, serveurs récents, demande 20) ; null : à
  /// retrouver dans la liste des inventaires ouverts.
  final String? inventaireId;

  /// 4.16.1 — Éléments de `produits` non retrouvés par le serveur ; null : champ `produits` ignoré (serveur ancien).
  final List<String>? inconnus;

  const ResultatCreationServeur.ok(this.lignes, {this.inventaireId, this.inconnus})
      : succes = true,
        session = false,
        incertain = false,
        message = '';
  const ResultatCreationServeur.refus(this.message)
      : succes = false,
        lignes = null,
        session = false,
        incertain = false,
        inventaireId = null,
        inconnus = null;
  const ResultatCreationServeur.session()
      : succes = false,
        lignes = null,
        session = true,
        incertain = false,
        inventaireId = null,
        inconnus = null,
        message = 'Session expirée : reconnectez-vous.';
  const ResultatCreationServeur.incertain(this.message)
      : succes = false,
        lignes = null,
        session = false,
        incertain = true,
        inventaireId = null,
        inconnus = null;
}

/// Produit de l'officine retrouvé par son code (fiche article).
class ProduitServeur {
  /// lg_FAMILLE_ID.
  final String id;
  final String cip;
  final String nom;

  /// Emplacement (rayon) du produit ; null : sans emplacement.
  final Rayon? emplacement;
  const ProduitServeur({required this.id, required this.cip, required this.nom, this.emplacement});
}

/// Issue d'un versement en lot.
enum IssueVersementLot {
  /// Rapport reçu (lignes classées).
  traite,

  /// Serveur sans cette route : ancien chemin (produit par produit).
  routeAbsente,

  /// Demande refusée AVANT tout enregistrement (400, 413) : ancien chemin.
  nonTraite,

  /// Session expirée : rien n'a été enregistré.
  session,

  /// Certificat refusé : rien n'est parti.
  reseau,

  /// Pas de réponse lisible : a PEUT-ÊTRE été enregistré — renvoyer la MÊME clé à la reprise.
  incertain,

  /// 4.15.3 — Prestige non déployé (404 de Payara, vérifié) : rien n'est enregistré ni conclu ; le lot est
  /// gardé et renvoyé à l'identique plus tard (jamais l'ancien chemin à cause d'un redéploiement).
  indisponible,

  /// Inventaire clôturé ou inconnu : rien n'a été enregistré.
  refuse,

  /// La clé a déjà servi pour un autre contenu (ne devrait jamais arriver).
  cleReutilisee,
}

class LigneRapportLot {
  /// Rang de la ligne dans la demande.
  final int index;

  /// ok, inconnu, ambigu, refuse.
  final String statut;
  final int? ligneId;
  final int? quantiteFinale;
  final String motif;
  const LigneRapportLot({required this.index, required this.statut, this.ligneId, this.quantiteFinale, this.motif = ''});
}

class ResultatVersementLot {
  final IssueVersementLot issue;
  final String message;
  final bool dejaTraite;
  final List<LigneRapportLot> lignes;
  const ResultatVersementLot(this.issue, [this.message = ''])
      : dejaTraite = false,
        lignes = const [];
  const ResultatVersementLot.rapport({required this.dejaTraite, required this.lignes})
      : issue = IssueVersementLot.traite,
        message = '';
}
