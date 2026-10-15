// PERFORMANCE — TRAITEMENT LOCAL (sans écran) :
//  - file d'envoi : 5 000 saisies enregistrées sur un VRAI fichier (FichierSaisieStore, dossier
//    temporaire), relues au redémarrage, puis toutes envoyées à un serveur instantané ;
//  - normalisation de 10 000 codes scannés (appareil photo : EAN-13, UPC-A, UPC-E, Code 39, Codabar,
//    DataMatrix GS1 ; puis codes candidats de la recherche, comme la douchette).
// Temps réels (Stopwatch) comparés aux seuils de test/support/performance.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_store.dart';
import 'package:prestinv/scan/camera/moteur_mobile_scanner.dart';
import 'package:prestinv/scan/code_scan.dart';

import '../helpers/faux_serveur.dart';
import '../support/performance.dart';

void main() {
  test('file d\'envoi : 5 000 saisies enregistrées sur fichier, relues, envoyées', () async {
    final dossier = await Directory.systemTemp.createTemp('prestinv_perf_');
    addTearDown(() => dossier.delete(recursive: true));
    final fichier = File('${dossier.path}/saisies.jsonl');
    final serveur = FauxServeur()..ouverts = {'INV1'};

    final sw = Stopwatch()..start();
    final file = SaisieQueue(store: FichierSaisieStore(fichier));
    await file.load();
    for (var i = 0; i < 5000; i++) {
      await file.enregistrer(inventaireId: 'INV1', ligneId: 10000 + i, quantite: i % 50, cip: '34009${i.toString().padLeft(8, '0')}', nom: 'PRODUIT $i', rayonId: 'E${i % 20}');
    }
    final enregistrement = sw.elapsedMicroseconds / 1000;

    // Redémarrage de l'application : relecture du fichier.
    final relue = SaisieQueue(store: FichierSaisieStore(fichier))..serveurFactory = () => serveur;
    await relue.load();
    expect(relue.enAttente(), 5000);
    final relecture = sw.elapsedMicroseconds / 1000 - enregistrement;

    final bilan = await relue.envoyer();
    final total = sw.elapsedMicroseconds / 1000;
    expect(bilan.envoyees, 5000);
    expect(relue.enAttente(), 0);
    expect(serveur.requetes, hasLength(5000), reason: 'une requête par saisie, aucun double envoi');
    final envoi = total - enregistrement - relecture;
    mesurer('File d\'envoi, 5 000 saisies — enregistrement sur fichier, par saisie', enregistrement / 5000,
        seuil: Seuils.enregistrementParSaisieMs, unite: 'ms', detail: 'total ${(enregistrement / 1000).toStringAsFixed(1)} s');
    mesurer('File d\'envoi, 5 000 saisies — relecture au redémarrage', relecture, seuil: Seuils.relecture5000Ms, unite: 'ms');
    mesurer('File d\'envoi, 5 000 saisies — envoi, par saisie', envoi / 5000,
        seuil: Seuils.envoiParSaisieMs, unite: 'ms', detail: 'total ${(envoi / 1000).toStringAsFixed(1)} s');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('normalisation de 10 000 codes scannés (appareil photo + codes candidats)', () {
    String cle13(String douze) {
      var s = 0;
      for (var i = 0; i < 12; i++) {
        s += int.parse(douze[i]) * (i.isEven ? 1 : 3);
      }
      return '$douze${(10 - s % 10) % 10}';
    }

    final codes = <Barcode>[];
    for (var i = 0; i < 10000; i++) {
      final n = i.toString().padLeft(7, '0');
      final ean = cle13('34009$n');
      codes.add(switch (i % 6) {
        0 => Barcode(format: BarcodeFormat.ean13, rawValue: ean),
        1 => Barcode(format: BarcodeFormat.upcA, rawValue: ean.substring(1)),
        2 => Barcode(format: BarcodeFormat.upcE, rawValue: '0${n.substring(1)}'),
        3 => Barcode(format: BarcodeFormat.code39, rawValue: '*$n*'),
        4 => Barcode(format: BarcodeFormat.codabar, rawValue: 'A$n\r\nB'),
        _ => Barcode(format: BarcodeFormat.dataMatrix, rawValue: '010$ean\u001d17271231' '10LOT$n\u001d21S$i'),
      });
    }
    final sw = Stopwatch()..start();
    var candidats = 0;
    for (final b in codes) {
      final v = MoteurMobileScanner.valeur(b);
      if (v != null) candidats += CodeScan.candidats(v).length;
    }
    final ms = sw.elapsedMicroseconds / 1000;
    expect(candidats, greaterThanOrEqualTo(10000), reason: 'chaque code donne au moins un code à chercher');
    mesurer('Normalisation de 10 000 codes scannés', ms, seuil: Seuils.normalisation10000Ms, unite: 'ms', detail: '$candidats codes candidats');
  });
}
