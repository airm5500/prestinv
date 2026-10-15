// INTÉGRATION — 4.13, services contre le faux serveur Prestige servi en VRAI HTTP (127.0.0.1) :
//  - profil de connexion (« xtypeuser ») lu par AuthProvider.login → droit de créer un inventaire ;
//  - création d'inventaire → relu par InventoryProvider (seule source des listes) et retrouvé par son
//    libellé quand le serveur ne donne pas l'identifiant → visible pour la saisie guidée et le scan ;
//  - versement de la collecte dans l'inventaire tout juste créé ;
//  - avancement en PRODUITS (« 110 / 130 », écarts) avec les routes existantes ;
//  - analyse « Tous les emplacements » : un bilan par emplacement avec les routes existantes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/inventaire/autorisation_creation.dart';
import 'package:prestinv/inventaire/creation_inventaire.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/inventory_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/services/identifiants_securises.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/ecrans/analyse_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/banc_essai.dart';
import '../helpers/coffre_memoire.dart';
import '../support/donnees_fictives.dart';
import '../support/faux_serveur_prestige.dart';

late FauxServeurPrestige serveur;

Future<(AuthProvider, AppConfig, ApiService)> connecte() async {
  SharedPreferences.setMockInitialValues({'localApiAddress': '127.0.0.1', 'localApiPort': '${serveur.port}', 'appName': 'prestige'});
  final config = AppConfig();
  await config.load();
  final auth = AuthProvider();
  expect(await auth.login(CompteFictif.login, CompteFictif.motDePasse, config), isTrue, reason: auth.errorMessage);
  return (auth, config, ApiService(baseUrl: config.currentApiUrl, cookie: () => auth.sessionCookie));
}

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
    IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: CoffreMemoire());
  });

  setUp(() async {
    ApiService.clientParDefaut = null;
    ApiService.oublierRoutesAbsentes();
    AvancementCalcul.viderCache();
    serveur = FauxServeurPrestige();
    await serveur.demarrer();
  });

  tearDown(() => serveur.arreter());

  group('Profil de connexion → droit de créer un inventaire', () {
    for (final (type, attendu) in [
      ('dashboard', AccesCreation.autorise),
      ('mainmenumanager', AccesCreation.refuse),
      (null, AccesCreation.codeAdmin),
    ]) {
      test('xtypeuser = $type → $attendu (réglage « autres comptes » désactivé)', () async {
        serveur.typeAccueil = type;
        final (auth, config, _) = await connecte();
        expect(config.creationAutresComptes, isFalse, reason: 'désactivé par défaut');
        expect(accesCreation(adminOuPharmacien: auth.user!.adminOuPharmacien, autresComptesAutorises: config.creationAutresComptes), attendu);
        expect(auth.user!.nomComplet, '${CompteFictif.prenom} ${CompteFictif.nom}');
      });
    }
  });

  test('création → relue par InventoryProvider, identifiant retrouvé par le libellé ; versement de la collecte dedans', () async {
    final (auth, config, api) = await connecte();
    final r = await CreationInventaire(api).creer('Collecte du 13-10-2026', TypeInventaire.emplacement);
    expect(r.ok, isTrue, reason: r.message);
    final provider = InventoryProvider();
    await provider.fetchInventories(api, maxResult: config.maxResult);
    final cree = provider.inventories.where((i) => i.libelle == 'Collecte du 13-10-2026').single;
    expect(cree.id, isNotEmpty);
    expect(provider.inventories.first.id, cree.id, reason: 'le plus récent en tête : visible pour la saisie guidée et le scan');

    final q = SaisieQueue(store: DisqueMemoire())..serveurFactory = () => api;
    final v = Versement.depuisCollecte([
      CollectedItem(code: '3400930000001', quantity: 12, dateScan: DateTime(2026, 10, 13, 9)),
      CollectedItem(code: '9999999999999', quantity: 3, dateScan: DateTime(2026, 10, 13, 9, 5)),
    ], inventaireId: cree.id, inventaireLibelle: cree.libelle, mode: ModeDejaCompte.remplacer);
    final fini = await MoteurVersement(api: api, queue: q, auteur: CompteFictif.login, enregistrer: (_) async {}).executer(v);
    expect(fini.statut, StatutVersement.termine);
    // Le nouvel inventaire a ses propres lignes (comme sur le serveur) : la quantité y est posée.
    expect(serveur.catalogue.crees[cree.id]!.lignes.firstWhere((l) => l.cip == '3400930000001').saisi, 12);
    expect(serveur.catalogue.produit(1).saisi, 24, reason: 'l\'inventaire INV1 n\'est pas touché');
    expect(fini.nonReconnues.single.code, '9999999999999', reason: 'rapport des codes non reconnus');
    expect(serveur.recues('ligne/quantite', methode: 'POST').every((p) => p.cookie == auth.sessionCookie), isTrue);
  });

  test('avancement en produits : comptés / total, écarts, mêmes routes (rayons, comptés, restants)', () async {
    final (_, _, api) = await connecte();
    final c = AvancementCalcul();
    expect(await c.actualiser(api, 'INV1'), FinAvancement.termine);
    final r = c.resultat('INV1')!;
    final cat = serveur.catalogue;
    expect(r.totalProduits, cat.produits.length);
    expect(r.comptes!.length, cat.produits.where((p) => p.dtUpdated != null).length);
    expect(r.ecarts, cat.produits.where((p) => p.dtUpdated != null && p.saisi != p.theorique).length);
    final routes = serveur.requetes.map((x) => x.route.split('/').last).toSet();
    expect(routes, containsAll(['rayons', 'detailsTouchedRayon', 'detailsUntouchedRayon']));
    expect(routes.intersection({'detailsAll', 'detailsAllTouched'}), isEmpty, reason: 'aucune nouvelle route');
    c.dispose();
  });

  test('analyse « Tous les emplacements » : un bilan par emplacement (route existante des produits du rayon)', () async {
    final (_, _, api) = await connecte();
    final rayons = await api.fetchRayons('INV1');
    final bilans = {for (final r in rayons) r.id: BilanEmplacement.de(await api.fetchProducts('INV1', r.id))};
    final total = BilanEmplacement.somme(bilans.values);
    final cat = serveur.catalogue;
    expect(total.produits, cat.produits.length);
    expect(total.enEcart, cat.produits.where((p) => p.saisi != p.theorique).length);
    // Valeur au prix d'achat de chaque produit.
    expect(total.ecartValorise, cat.produits.fold<double>(0, (s, p) => s + (p.saisi - p.theorique) * (p.toJson()['produitPrixAchat'] as num)));
    for (final r in rayons) {
      expect(bilans[r.id]!.produits, cat.produits.where((p) => p.rayon == r.id).length);
    }
    expect(serveur.recues('details').length, rayons.length, reason: 'une requête par emplacement');
  });
}
