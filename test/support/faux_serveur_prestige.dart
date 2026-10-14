// Faux serveur Prestige RÉUTILISABLE (tests d'intégration, de bout en bout, d'ergonomie).
//
// Une seule logique de routes, deux transports :
//  - [FauxServeurPrestige.demarrer] : vrai serveur HTTP local (HttpServer sur 127.0.0.1, port libre) —
//    pour les tests d'intégration des services (`test(...)`, entrées/sorties réelles : en-têtes, cookie,
//    codes HTTP, connexion coupée) ;
//  - [FauxServeurPrestige.client] : même traitement, en mémoire (MockClient) — pour les tests de widgets
//    et de bout en bout, qui tournent en temps simulé (`testWidgets`) où un vrai socket n'avance pas.
//
// Routes servies (mêmes formes de réponse que le serveur Prestige) :
//   POST /api/v1/user/auth             {login, password} → {success:true, …} + Set-Cookie JSESSIONID
//                                      (mauvais identifiants : {success:false})
//   POST /api/v1/user/logout           invalide la session
//   GET  /api/v1/licence/find          licence fictive (fin relative à aujourd'hui) ; publique
//   tout le reste (/ws/inventaires/*, /inventaire/creation, /inventaire/ligne/quantite) : catalogue
//   en mémoire de [FauxPrestige] (test/helpers/faux_prestige_http.dart), quantités modifiables.
//
// Scénarios scriptables, par route (fin de chemin, ex. 'inventaires', 'licence/find', 'details') :
//   [scripter] → 200 JSON, `success:false`, 401, 403, 500, délai, coupure réseau, n fois ou toujours ;
//   [exigerSession] → toute route protégée sans cookie de session valide répond 401 ;
//   [expirerSessions] → les cookies délivrés ne valent plus (session expirée côté serveur) ;
//   [couper] / [retablir] → serveur injoignable (connexion refusée / fermée) puis de retour.
// Chaque requête reçue est journalisée ([requetes]) avec son cookie et son corps.
//
// Données : uniquement FICTIVES (test/support/donnees_fictives.dart) — jamais de vrais identifiants.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/faux_prestige_http.dart';
import 'donnees_fictives.dart';

/// Réponse imposée à une route.
class ReponseScriptee {
  final int code;
  final Object? corps;
  final Duration delai;

  /// Connexion coupée sans réponse (comme un Wi-Fi qui lâche).
  final bool coupure;
  final Map<String, String> entetes;

  /// Nombre d'utilisations restantes (null : toujours).
  int? fois;

  ReponseScriptee({this.code = 200, this.corps, this.delai = Duration.zero, this.coupure = false, this.entetes = const {}, this.fois});

  /// 200 avec un corps JSON.
  factory ReponseScriptee.json(Object corps, {int code = 200, int? fois}) => ReponseScriptee(code: code, corps: corps, fois: fois);

  /// Refus applicatif lisible : 200 {"success": false, "message": …}.
  factory ReponseScriptee.echec(String message, {int? fois}) =>
      ReponseScriptee(corps: {'success': false, 'message': message}, fois: fois);

  /// Code HTTP seul (401, 403, 404, 500…), corps vide.
  factory ReponseScriptee.code(int code, {int? fois}) => ReponseScriptee(code: code, corps: '', fois: fois);

  /// Réponse normale de la route, mais après [delai] (réseau lent).
  factory ReponseScriptee.lente(Duration delai, {int? fois}) => ReponseScriptee(delai: delai, fois: fois, code: -1);

  /// Coupure réseau pendant la requête.
  factory ReponseScriptee.coupee({int? fois}) => ReponseScriptee(coupure: true, fois: fois);

  /// Délai seul, puis traitement normal de la route.
  bool get seulementDelai => code == -1;
}

/// Requête reçue par le faux serveur.
class RequeteRecue {
  final String methode;

  /// Chemin après « /api/v1/ » (ex. 'ws/inventaires/details', 'user/auth').
  final String route;
  final Map<String, String> parametres;
  final String? cookie;
  final String corps;
  const RequeteRecue(this.methode, this.route, this.parametres, this.cookie, this.corps);

  @override
  String toString() => '$methode $route';
}

class _Coupure implements Exception {
  const _Coupure();
}

class FauxServeurPrestige {
  /// Catalogue (inventaires, rayons, lignes, quantités) — modifiable par les tests.
  final FauxPrestige catalogue;

  /// Comptes acceptés par /user/auth (login → mot de passe). Fictifs.
  final Map<String, String> comptes = {CompteFictif.login: CompteFictif.motDePasse};

  /// Profil renvoyé par /user/auth (« xtypeuser ») : 'dashboard' (administrateur / pharmacien) par
  /// défaut ; 'mainmenumanager' (autre profil) ; null : champ absent (serveur plus ancien).
  String? typeAccueil = 'dashboard';

  /// Si vrai, toute route protégée exige un cookie JSESSIONID délivré par /user/auth (401 sinon).
  bool exigerSession;

  /// Routes accessibles sans session (comme le vrai serveur : connexion et lecture de la licence).
  final Set<String> routesPubliques = {'user/auth', 'licence/find'};

  /// Licence renvoyée par /licence/find (null : corps vide = aucune licence enregistrée).
  Map<String, dynamic>? licence = licenceFictive();

  final Map<String, ReponseScriptee> _scripts = {};
  final List<RequeteRecue> requetes = [];
  final Set<String> _sessions = {};
  int _numeroSession = 0;
  bool _coupe = false;
  HttpServer? _http;

  FauxServeurPrestige({FauxPrestige? catalogue, this.exigerSession = true}) : catalogue = catalogue ?? catalogueFictif();

  // --- Scénarios ---

  /// Impose [reponse] à la route [route] (fin de chemin : 'inventaires', 'details', 'licence/find'…),
  /// pour [methode] seulement si elle est donnée.
  void scripter(String route, ReponseScriptee reponse, {String? methode}) => _scripts['${methode ?? '*'} $route'] = reponse;

  /// Retire tous les scénarios.
  void oublierScripts() => _scripts.clear();

  /// Les sessions ouvertes ne valent plus : la prochaine requête protégée répond 401.
  void expirerSessions() => _sessions.clear();

  /// Serveur injoignable (toutes les requêtes échouent en réseau).
  void couper() => _coupe = true;
  void retablir() => _coupe = false;
  bool get estCoupe => _coupe;

  /// Cookies de session actuellement valides.
  Set<String> get sessionsValides => Set.unmodifiable(_sessions);

  /// Requêtes reçues sur une route (fin de chemin), éventuellement pour une méthode.
  List<RequeteRecue> recues(String route, {String? methode}) =>
      requetes.where((r) => (r.route == route || r.route.endsWith('/$route')) && (methode == null || r.methode == methode)).toList();

  // --- Transports ---

  /// Transport en mémoire (tests de widgets / bout en bout, temps simulé).
  http.Client get client => MockClient((req) async {
        try {
          return await traiter(req);
        } on _Coupure {
          throw const SocketException('Connexion refusée (faux serveur coupé)');
        }
      });

  /// Démarre un vrai serveur HTTP local ; renvoie l'adresse de base à donner à ApiService
  /// (« http://127.0.0.1:<port>/prestige »).
  Future<String> demarrer() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http = s;
    s.listen(_servirHttp);
    return adresse;
  }

  /// Adresse de base du serveur HTTP démarré.
  String get adresse => 'http://127.0.0.1:${_http!.port}/prestige';

  /// Port du serveur HTTP démarré.
  int get port => _http!.port;

  /// Arrête le serveur HTTP (les connexions suivantes sont refusées par le système).
  Future<void> arreter() async {
    await _http?.close(force: true);
    _http = null;
  }

  Future<void> _servirHttp(HttpRequest r) async {
    final corps = await utf8.decodeStream(r);
    final req = http.Request(r.method, r.requestedUri);
    r.headers.forEach((nom, valeurs) => req.headers[nom] = valeurs.join(', '));
    req.bodyBytes = utf8.encode(corps);
    try {
      final rep = await traiter(req);
      r.response.statusCode = rep.statusCode;
      rep.headers.forEach((nom, valeur) => r.response.headers.set(nom, valeur));
      r.response.add(rep.bodyBytes);
      await r.response.close();
    } on _Coupure {
      // Fermeture brutale, sans réponse : le client voit une connexion coupée.
      final socket = await r.response.detachSocket(writeHeaders: false);
      socket.destroy();
    }
  }

  // --- Traitement commun ---

  static String _route(Uri url) {
    final p = url.path;
    final i = p.indexOf('/api/v1/');
    return i < 0 ? p : p.substring(i + '/api/v1/'.length);
  }

  ReponseScriptee? _script(String methode, String route) {
    for (final cle in ['$methode $route', '* $route']) {
      final s = _scripts[cle];
      if (s != null) return s;
    }
    // Fin de chemin (ex. 'details' pour 'ws/inventaires/details').
    for (final e in _scripts.entries) {
      final espace = e.key.indexOf(' ');
      final m = e.key.substring(0, espace);
      final r = e.key.substring(espace + 1);
      if ((m == '*' || m == methode) && route.endsWith('/$r')) return e.value;
    }
    return null;
  }

  static http.Response _json(Object corps, {int code = 200, Map<String, String> entetes = const {}}) => http.Response.bytes(
      utf8.encode(corps is String ? corps : json.encode(corps)), code,
      headers: {'content-type': 'application/json; charset=utf-8', ...entetes});

  static String? _jsession(String? cookie) {
    if (cookie == null) return null;
    for (final morceau in cookie.split(RegExp(r'[;,]'))) {
      final m = morceau.trim();
      if (m.startsWith('JSESSIONID=')) return m;
    }
    return null;
  }

  /// Traite une requête (les deux transports passent par ici).
  Future<http.Response> traiter(http.Request req) async {
    final route = _route(req.url);
    final cookie = req.headers['cookie'];
    requetes.add(RequeteRecue(req.method, route, req.url.queryParameters, cookie, req.body));
    if (_coupe) throw const _Coupure();

    final script = _script(req.method, route);
    if (script != null) {
      if (script.fois != null) {
        script.fois = script.fois! - 1;
        if (script.fois! <= 0) _scripts.removeWhere((_, v) => identical(v, script));
      }
      if (script.delai > Duration.zero) await Future<void>.delayed(script.delai);
      if (script.coupure) throw const _Coupure();
      if (!script.seulementDelai) return _json(script.corps ?? '', code: script.code, entetes: script.entetes);
    }

    if (route == 'user/auth' && req.method == 'POST') return _connexion(req);
    if (route == 'user/logout') {
      final s = _jsession(cookie);
      if (s != null) _sessions.remove(s);
      return _json({'success': true});
    }
    if (route == 'licence/find') return licence == null ? http.Response('', 200) : _json(licence!);

    if (exigerSession && !routesPubliques.contains(route)) {
      final s = _jsession(cookie);
      if (s == null || !_sessions.contains(s)) return http.Response('', 401);
    }

    // Catalogue : on transmet la requête au faux serveur des tests d'écrans.
    final copie = http.Request(req.method, req.url)
      ..headers.addAll(req.headers)
      ..bodyBytes = req.bodyBytes;
    final rep = await catalogue.client.send(copie);
    final octets = await rep.stream.toBytes();
    return http.Response.bytes(octets, rep.statusCode, headers: rep.headers);
  }

  http.Response _connexion(http.Request req) {
    Map<String, dynamic> b;
    try {
      b = Map<String, dynamic>.from(json.decode(req.body) as Map);
    } catch (_) {
      return _json({'success': false, 'message': 'Requête illisible.'}, code: 400);
    }
    final login = '${b['login'] ?? ''}';
    final attendu = comptes[login];
    if (attendu == null || attendu != '${b['password'] ?? ''}') {
      return _json({'success': false, 'message': 'Identifiant ou mot de passe incorrect.'});
    }
    final session = 'JSESSIONID=essai-${++_numeroSession}';
    _sessions.add(session);
    return _json(utilisateurFictif(login, typeAccueil: typeAccueil), entetes: {'set-cookie': '$session; Path=/prestige; HttpOnly'});
  }
}
