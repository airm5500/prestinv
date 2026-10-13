// lib/saisie/saisie_store.dart
// Stockage PERSISTANT des saisies : un fichier journal (une ligne JSON par changement, ajoutée puis
// vidée sur disque avant que l'appel ne se termine). Il survit à la fermeture de l'application, à un
// appel téléphonique, à une batterie vide ou à un redémarrage du terminal.
//
// - Écriture : ajout en fin de fichier + flush (rien n'est réécrit à chaque saisie, contrairement à
//   l'ancienne sauvegarde par rayon qui réécrivait toute la liste à chaque OK).
// - Lecture : les lignes sont rejouées dans l'ordre ; la DERNIÈRE ligne coupée par une extinction
//   brutale est ignorée sans perdre les précédentes.
// - Compactage : quand le journal devient long, l'état courant est écrit dans un fichier temporaire,
//   vidé sur disque, puis RENOMMÉ par-dessus le journal (renommage atomique : on a toujours soit
//   l'ancien fichier complet, soit le nouveau complet).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:prestinv/saisie/saisie.dart';

abstract class SaisieStore {
  /// Toutes les saisies gardées (dernier état de chaque ligne).
  Future<List<SaisieLigne>> lire();

  /// Enregistre (ajoute ou remplace) une saisie. Le Future se termine quand c'est écrit sur disque.
  Future<void> ecrire(SaisieLigne s);

  /// Supprime une saisie.
  Future<void> supprimer(String cle);

  /// Réécrit le stockage avec exactement [saisies] (compactage / purge).
  Future<void> remplacerTout(List<SaisieLigne> saisies);
}

class FichierSaisieStore implements SaisieStore {
  final File fichier;

  /// Nombre de lignes du journal au-delà duquel on compacte (en plus de 3 × le nombre de saisies).
  final int seuilCompactage;

  FichierSaisieStore(this.fichier, {this.seuilCompactage = 500});

  File get _temp => File('${fichier.path}.tmp');

  int _lignesJournal = 0;
  final Map<String, SaisieLigne> _etat = {};
  Future<void> _file = Future.value();

  /// Exécute les écritures l'une après l'autre (jamais deux écritures du fichier en même temps).
  Future<T> _enSerie<T>(Future<T> Function() action) {
    final c = Completer<T>();
    _file = _file.then((_) async {
      try {
        c.complete(await action());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  @override
  Future<List<SaisieLigne>> lire() => _enSerie(() async {
        _etat.clear();
        _lignesJournal = 0;
        // Un compactage interrompu après l'écriture du temporaire mais avant le renommage :
        // le journal d'origine est toujours complet, le temporaire est simplement abandonné.
        if (await _temp.exists()) {
          try {
            await _temp.delete();
          } catch (_) {}
        }
        if (!await fichier.exists()) return <SaisieLigne>[];
        final contenu = await fichier.readAsString();
        // Dernière ligne coupée (pas de fin de ligne) : on termine la ligne, sinon la prochaine saisie
        // serait collée derrière le morceau abîmé et perdue avec lui.
        if (contenu.isNotEmpty && !contenu.endsWith('\n')) {
          final raf = await fichier.open(mode: FileMode.append);
          try {
            await raf.writeString('\n');
            await raf.flush();
          } finally {
            await raf.close();
          }
        }
        final lignes = const LineSplitter().convert(contenu);
        for (final brute in lignes) {
          if (brute.trim().isEmpty) continue;
          _lignesJournal++;
          try {
            final j = json.decode(brute) as Map<String, dynamic>;
            final op = j['op'];
            if (op == 'put') {
              final s = SaisieLigne.fromJson(Map<String, dynamic>.from(j['s'] as Map));
              _etat[s.cle] = s;
            } else if (op == 'del') {
              _etat.remove(j['k']);
            }
          } catch (e) {
            // Ligne coupée (extinction pendant l'écriture) ou abîmée : ignorée, les autres sont gardées.
            if (kDebugMode) debugPrint('Saisies : ligne du journal ignorée ($e)');
          }
        }
        return _etat.values.map(_copie).toList();
      });

  SaisieLigne _copie(SaisieLigne s) => SaisieLigne.fromJson(s.toJson());

  Future<void> _ajouter(Map<String, dynamic> ligne) async {
    await fichier.parent.create(recursive: true);
    final raf = await fichier.open(mode: FileMode.append);
    try {
      await raf.writeString('${json.encode(ligne)}\n');
      await raf.flush();
    } finally {
      await raf.close();
    }
    _lignesJournal++;
  }

  @override
  Future<void> ecrire(SaisieLigne s) => _enSerie(() async {
        await _ajouter({'op': 'put', 's': s.toJson()});
        _etat[s.cle] = _copie(s);
        await _compacterSiBesoin();
      });

  @override
  Future<void> supprimer(String cle) => _enSerie(() async {
        await _ajouter({'op': 'del', 'k': cle});
        _etat.remove(cle);
        await _compacterSiBesoin();
      });

  @override
  Future<void> remplacerTout(List<SaisieLigne> saisies) => _enSerie(() async {
        _etat
          ..clear()
          ..addEntries(saisies.map((s) => MapEntry(s.cle, _copie(s))));
        await _reecrire();
      });

  Future<void> _compacterSiBesoin() async {
    if (_lignesJournal > seuilCompactage && _lignesJournal > 3 * _etat.length) await _reecrire();
  }

  Future<void> _reecrire() async {
    await fichier.parent.create(recursive: true);
    final buf = StringBuffer();
    for (final s in _etat.values) {
      buf.writeln(json.encode({'op': 'put', 's': s.toJson()}));
    }
    final raf = await _temp.open(mode: FileMode.write);
    try {
      await raf.writeString(buf.toString());
      await raf.flush();
    } finally {
      await raf.close();
    }
    await _temp.rename(fichier.path);
    _lignesJournal = _etat.length;
  }

  /// Tests : nombre de lignes du journal.
  @visibleForTesting
  int get lignesJournal => _lignesJournal;
}
