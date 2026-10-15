// UNITAIRES — 4.15, règles sans écran ni réseau :
//  - droit de création donné par le serveur (`droits.creerInventaire`) : il décide quand il est connu ;
//  - lecture de la réponse de connexion (droits, rôle) ;
//  - état d'un rayon (demande 30) : statut, champs illisibles refusés ;
//  - analyse de la collecte : emplacements triés, produits sans emplacement exclus ;
//  - versement : le lot sans réponse est gardé sur l'appareil (relu tel quel), un versement avec un lot en
//    attente n'est pas « complet » ;
//  - refus de droit (403 « interdit ») reconnu, ≠ session expirée.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/collecte/versement.dart';
import 'package:prestinv/inventaire/autorisation_creation.dart';
import 'package:prestinv/inventaire/produits_collecte.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/models/user.dart';

ProduitServeur produit(String id, String? rayon, {String libelle = ''}) =>
    ProduitServeur(id: id, cip: 'C$id', nom: 'P$id', emplacement: rayon == null ? null : Rayon(id: rayon, code: '', libelle: libelle.isEmpty ? rayon : libelle));

void main() {
  group('Droit de créer un inventaire', () {
    test('droit du serveur connu : il décide (réglage du terminal et profil ignorés)', () {
      for (final admin in [true, false, null]) {
        for (final autres in [true, false]) {
          expect(accesCreation(adminOuPharmacien: admin, autresComptesAutorises: autres, droitServeur: true), AccesCreation.autorise);
          expect(accesCreation(adminOuPharmacien: admin, autresComptesAutorises: autres, droitServeur: false), AccesCreation.refuse);
        }
      }
    });

    test('droit inconnu (serveur ancien) : règles de la 4.13 inchangées', () {
      expect(accesCreation(adminOuPharmacien: true, autresComptesAutorises: false), AccesCreation.autorise);
      expect(accesCreation(adminOuPharmacien: false, autresComptesAutorises: false), AccesCreation.refuse);
      expect(accesCreation(adminOuPharmacien: false, autresComptesAutorises: true), AccesCreation.autorise);
      expect(accesCreation(adminOuPharmacien: null, autresComptesAutorises: false), AccesCreation.codeAdmin);
    });

    test('réponse de connexion : droits.creerInventaire lu ; absent ou illisible → inconnu', () {
      expect(AppUser.fromJson({'droits': {'creerInventaire': true}}).droitCreation, isTrue);
      expect(AppUser.fromJson({'droits': {'creerInventaire': false}}).droitCreation, isFalse);
      expect(AppUser.fromJson({}).droitCreation, isNull);
      expect(AppUser.fromJson({'droits': {'creerInventaire': 'oui'}}).droitCreation, isNull);
      expect(AppUser.fromJson({'droits': 'tous'}).droitCreation, isNull);
    });

    test('serveur récent mémorisé par adresse (oublié par oublierRoutesAbsentes)', () {
      ApiService.noterServeur('http://a/prestige', recent: true);
      expect(ApiService(baseUrl: 'http://a/prestige').serveurRecent, isTrue);
      expect(ApiService(baseUrl: 'http://b/prestige').serveurRecent, isFalse);
      ApiService.noterServeur('http://a/prestige', recent: false);
      expect(ApiService(baseUrl: 'http://a/prestige').serveurRecent, isFalse);
      ApiService.noterServeur('http://a/prestige', recent: true);
      ApiService.oublierRoutesAbsentes();
      expect(ApiService(baseUrl: 'http://a/prestige').serveurRecent, isFalse);
    });
  });

  group('Refus de droit (403 « interdit »)', () {
    test('reconnu avec son message ; 403 sans « interdit » ou autre code : non', () {
      expect(ApiService.droitManquant(http.Response.bytes(utf8.encode('{"success":0,"interdit":true,"msg":"Droit manquant : Créer un inventaire"}'), 403)),
          'Droit manquant : Créer un inventaire');
      expect(ApiService.droitManquant(http.Response('{"interdit":true}', 403)), contains('Droit manquant'));
      expect(ApiService.droitManquant(http.Response('', 403)), isNull);
      expect(ApiService.droitManquant(http.Response('{"interdit":true}', 401)), isNull);
      expect(ApiService.droitManquant(http.Response('<html>', 403)), isNull);
    });
  });

  group('État d\'un rayon (demande 30)', () {
    test('statut : pas commencé / commencé / terminé', () {
      EtatRayon e(int total, int comptes) => EtatRayon.fromJson({'rayonId': 'R', 'totalProduits': total, 'comptes': comptes});
      expect(e(10, 0).statut, 0);
      expect(e(10, 3).statut, 1);
      expect(e(10, 10).statut, 2);
      expect(e(10, 3).restants, 7, reason: 'restants calculé s\'il manque');
    });

    test('champ illisible ou rayon sans identifiant : refusé (jamais un état inventé)', () {
      expect(() => EtatRayon.fromJson({'rayonId': 'R', 'totalProduits': 'x', 'comptes': 0}), throwsFormatException);
      expect(() => EtatRayon.fromJson({'totalProduits': 1, 'comptes': 0}), throwsFormatException);
      expect(EtatRayon.fromJson({'rayonId': 'R', 'code': 'R1', 'libelle': 'RÉSERVE', 'totalProduits': '4', 'comptes': '1', 'restants': 3}).rayon.libelle, 'RÉSERVE');
    });
  });

  group('Analyse de la collecte', () {
    test('emplacements : du plus fourni au moins fourni, puis par libellé ; produits sans emplacement exclus', () {
      final a = AnalyseCollecte(produits: [
        produit('1', 'S3', libelle: 'RÉSERVE'),
        produit('2', 'S2', libelle: 'ANTIBIOTIQUES'),
        produit('3', 'S2', libelle: 'ANTIBIOTIQUES'),
        produit('4', 'S1', libelle: 'CANNES'),
        produit('5', null),
      ]);
      expect([for (final e in a.emplacements) (e.rayon.id, e.produits)], [('S2', 2), ('S1', 1), ('S3', 1)]);
      expect(a.inclus.map((p) => p.id), ['1', '2', '3', '4']);
      expect(a.sansEmplacement.single.id, '5');
      expect(a.creationPossible, isTrue);
    });

    test('rien de retrouvé, ou erreur : création impossible', () {
      expect(const AnalyseCollecte(introuvables: ['X']).creationPossible, isFalse);
      expect(AnalyseCollecte(produits: [produit('5', null)]).creationPossible, isFalse);
      expect(AnalyseCollecte(produits: [produit('1', 'S3')], erreur: const ApiLoadException('panne')).creationPossible, isFalse);
    });
  });

  group('Versement : lot sans réponse gardé sur l\'appareil', () {
    test('relu tel quel (même clé, même contenu) ; versement non « complet » tant qu\'il attend', () {
      final v = Versement.depuisCollecte([CollectedItem(code: '3400930000001', quantity: 2, dateScan: DateTime(2026, 10, 15))],
          inventaireId: 'INV1', inventaireLibelle: 'Inventaire', mode: ModeDejaCompte.ajouter, maintenant: DateTime(2026, 10, 15, 10));
      expect(v.complet, isFalse);
      v.lignes.single.etat = EtatLigneVersement.versee;
      expect(v.complet, isTrue);
      v
        ..lotEnCours = {
          'cle': '${v.id}-L1',
          'idx': [0],
          'codes': ['3400930000001'],
          'q': [2],
        }
        ..lots = 0;
      expect(v.complet, isFalse, reason: 'lot sans réponse : à reprendre');
      final relu = Versement.fromJson(v.toJson());
      expect(relu.lotEnCours, v.lotEnCours);
      expect(relu.lots, 0);
      expect(Versement.fromJson({...v.toJson()}..remove('lot')).lotEnCours, isNull, reason: 'versements d\'avant la 4.15 : lus sans lot');
    });
  });
}
