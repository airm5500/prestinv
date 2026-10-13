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

  // --- FILE DES SAISIES (SaisieServeur) ---

  /// Pose la quantité TOTALE sur une ligne (PUT /ws/inventaires/details). Ne lève jamais.
  @override
  Future<ReponseEnvoi> poserQuantite(int ligneId, int quantite) async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires/details');
    try {
      final response = await _httpPut(url, jsonEncode({'id': ligneId, 'quantite': quantite})).timeout(const Duration(seconds: 15));
      final code = response.statusCode;
      if (code >= 200 && code < 300) return ReponseEnvoi.ok;
      if (code == 401 || code == 403) return ReponseEnvoi(ResultatEnvoi.session, 'Session expirée ou accès refusé (code $code).');
      if (code >= 400 && code < 500) return ReponseEnvoi(ResultatEnvoi.refus, 'Le serveur a refusé la quantité (code $code).');
      return ReponseEnvoi(ResultatEnvoi.erreurServeur, 'Erreur du serveur (code $code).');
    } on TimeoutException {
      return const ReponseEnvoi(ResultatEnvoi.reseau, 'Le serveur met trop de temps à répondre.');
    } catch (e) {
      if (_estErreurReseau(e)) return const ReponseEnvoi(ResultatEnvoi.reseau, 'Serveur injoignable.');
      return ReponseEnvoi(ResultatEnvoi.reseau, 'Envoi impossible : $e');
    }
  }

  /// Serveurs (adresse de base) sans la route `POST /inventaire/ligne/quantite` (anciennes versions de
  /// Prestige) : la route habituelle est utilisée directement.
  static final Set<String> _sansRouteSession = {};

  /// Tests : oublie les serveurs mémorisés sans route « avec auteur ».
  static void oublierRoutesAbsentes() => _sansRouteSession.clear();

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
        _sansRouteSession.add(baseUrl);
        return poserQuantite(ligneId, quantite);
      }
      if (code == 401 || code == 403) return ReponseEnvoi(ResultatEnvoi.session, 'Session expirée ou accès refusé (code $code).');
      if (code >= 500) return ReponseEnvoi(ResultatEnvoi.erreurServeur, 'Erreur du serveur (code $code).');
      if (code >= 400) return ReponseEnvoi(ResultatEnvoi.refus, 'Le serveur a refusé la quantité (code $code).');
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
      if (_estErreurReseau(e)) return const ReponseEnvoi(ResultatEnvoi.reseau, 'Serveur injoignable.');
      return ReponseEnvoi(ResultatEnvoi.reseau, 'Envoi impossible : $e');
    }
  }

  /// Tous les inventaires ouverts (GET /ws/inventaires sans limite). `null` si la liste n'a pas pu être lue.
  @override
  Future<InventairesOuverts?> inventairesOuverts() async {
    final url = Uri.parse('$baseUrl/api/v1/ws/inventaires');
    try {
      final response = await _httpGet(url).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is! List) return null;
      return InventairesOuverts({for (final i in data) if (i is Map && i['id'] != null) '${i['id']}'});
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
      throw ApiLoadException('Le serveur met trop de temps à répondre ($quoi non chargés). Vérifiez le réseau puis réessayez.',
          TypeErreurChargement.reseau);
    } catch (e) {
      if (_estErreurReseau(e)) {
        throw ApiLoadException('Serveur injoignable ($quoi non chargés). Vérifiez le Wi-Fi et l\'adresse du serveur puis réessayez.',
            TypeErreurChargement.reseau);
      }
      throw ApiLoadException('Impossible de charger les $quoi : $e', TypeErreurChargement.reseau);
    }
    final code = response.statusCode;
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
  /// disponible, non comptée) ; aucun produit → aucun inventaire. Réponse : {"success":1,"lignes":N}.
  /// La réponse ne donne pas l'identifiant : il est relu dans la liste des inventaires ouverts.
  Future<ResultatCreationServeur> creerInventaire(String libelle, String type) async {
    final url = Uri.parse('$baseUrl/api/v1/inventaire/creation');
    final http.Response response;
    try {
      response = await _httpPost(url, jsonEncode({'str_NAME': libelle, 'str_TYPE_TRANSACTION': type}))
          // Plusieurs milliers de produits : la création peut prendre du temps.
          .timeout(const Duration(seconds: 180));
    } on TimeoutException {
      return const ResultatCreationServeur.incertain('Le serveur met trop de temps à répondre.');
    } catch (e) {
      // La demande a pu partir avant la coupure : on ne sait pas si l'inventaire existe.
      return ResultatCreationServeur.incertain(_estErreurReseau(e) ? 'Serveur injoignable.' : 'Création impossible : $e');
    }
    final code = response.statusCode;
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
    if (succes == 1 || succes == true) return ResultatCreationServeur.ok((m['lignes'] as num?)?.toInt());
    if (message.toLowerCase().contains('connecter')) return const ResultatCreationServeur.session();
    return ResultatCreationServeur.refus(message.isEmpty ? 'Création refusée par le serveur.' : message);
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
      throw const ApiLoadException('Serveur injoignable : impossible de savoir si ce produit est déjà compté.', TypeErreurChargement.reseau);
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

  Future<List<Rayon>> fetchRayons(String idInventaire) =>
      _loadList('emplacements', _uri('/rayons', {'idInventaire': idInventaire}), Rayon.fromJson);

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
      return (await _loadList('produits comptés', _uri('/detailsTouchedRayon', {'idInventaire': inventoryId, 'idRayon': rayonId}), (m) => m,
              delai: const Duration(seconds: 8)))
          .isNotEmpty;
    } on ApiLoadException {
      return null;
    }
  }

  /// Reste-t-il des produits à compter ? `null` si on ne peut pas le savoir.
  Future<bool?> hasUntouchedProductsInRayon(String inventoryId, String rayonId) async {
    try {
      return (await _loadList('restants', _uri('/detailsUntouchedRayon', {'idInventaire': inventoryId, 'idRayon': rayonId}), (m) => m,
              delai: const Duration(seconds: 8)))
          .isNotEmpty;
    } on ApiLoadException {
      return null;
    }
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
      throw Exception(_estErreurReseau(e) ? 'Serveur injoignable.' : 'Enregistrement de la licence impossible.');
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
      throw const ApiLoadException('Serveur injoignable : impossible de vérifier la licence.', TypeErreurChargement.reseau);
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

  const ResultatCreationServeur.ok(this.lignes)
      : succes = true,
        session = false,
        incertain = false,
        message = '';
  const ResultatCreationServeur.refus(this.message)
      : succes = false,
        lignes = null,
        session = false,
        incertain = false;
  const ResultatCreationServeur.session()
      : succes = false,
        lignes = null,
        session = true,
        incertain = false,
        message = 'Session expirée : reconnectez-vous.';
  const ResultatCreationServeur.incertain(this.message)
      : succes = false,
        lignes = null,
        session = false,
        incertain = true;
}
