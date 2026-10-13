// NON-RÉGRESSION — aucun secret réel dans le dépôt.
// Un vrai mot de passe administrateur figurait autrefois dans integration_test/app_test.dart (retiré à
// l'étape 0). Ce garde-fou vérifie qu'il ne revient nulle part : on compare l'EMPREINTE SHA-256 de
// chaque mot des fichiers texte du dépôt à celle du secret retiré (le secret lui-même n'est jamais
// écrit ici). Il vérifie aussi que les tests n'embarquent pas d'identifiants par défaut.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/services/pin_securise.dart';

/// Empreintes SHA-256 (hexadécimal) de secrets réels déjà retirés du dépôt.
const empreintesInterdites = {
  'd45330434fb1b02b426adcf969986bf91b414a3b473768084f8ed98da441bbbd', // mot de passe administrateur retiré (étape 0)
};

const extensionsTexte = {
  '.dart', '.yaml', '.yml', '.md', '.json', '.xml', '.gradle', '.kts', '.properties', '.txt', '.html', '.sh', '.plist', '.kt', '.java', '.swift', '.cfg', '.ini', '.env',
};
const dossiersIgnores = {'.git', '.dart_tool', 'build', '.idea', '.gradle', 'Pods', '.symlinks', 'ephemeral'};

Iterable<File> fichiersTexte(Directory racine) sync* {
  for (final e in racine.listSync(followLinks: false)) {
    final nom = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (e is Directory) {
      if (!dossiersIgnores.contains(nom)) yield* fichiersTexte(e);
    } else if (e is File) {
      final point = nom.lastIndexOf('.');
      if (point >= 0 && extensionsTexte.contains(nom.substring(point).toLowerCase())) yield e;
      if (nom.startsWith('.env')) yield e;
    }
  }
}

String hex(List<int> octets) => octets.map((o) => o.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final racine = Directory.current;

  test('aucun secret retiré ne réapparaît dans un fichier texte du dépôt', () {
    final mots = <String, String>{}; // mot → premier fichier où il apparaît
    final decoupe = RegExp(r'''[^\s'"`,;:(){}\[\]<>=/\\]+''');
    var nbFichiers = 0;
    for (final f in fichiersTexte(racine)) {
      nbFichiers++;
      final String contenu;
      try {
        contenu = f.readAsStringSync();
      } catch (_) {
        continue; // binaire ou encodage inattendu
      }
      for (final m in decoupe.allMatches(contenu)) {
        final mot = m.group(0)!;
        if (mot.length >= 6 && mot.length <= 40) mots.putIfAbsent(mot, () => f.path);
      }
    }
    expect(nbFichiers, greaterThan(100), reason: 'le dépôt a bien été parcouru depuis sa racine');
    final trouves = [
      for (final e in mots.entries)
        if (empreintesInterdites.contains(hex(Pbkdf2Sha256.sha256(utf8.encode(e.key))))) e.value,
    ];
    expect(trouves, isEmpty, reason: 'secret réel retrouvé dans : $trouves');
  });

  test('le test d\'intégration n\'a aucun identifiant ni mot de passe par défaut', () {
    final source = File('${racine.path}/integration_test/app_test.dart').readAsStringSync();
    for (final nom in ['PRESTINV_TEST_LOGIN', 'PRESTINV_TEST_PASSWORD', 'PRESTINV_TEST_HOST']) {
      expect(source, contains("_param('$nom', '')"), reason: '$nom doit être fourni au lancement, jamais écrit dans le code');
    }
  });

  test('aucune configuration de serveur réel ni mot de passe en clair dans lib/', () {
    final motifs = <RegExp>[
      RegExp(r'''password['"]?\s*[:=]\s*['"][^'"$]{4,}['"]''', caseSensitive: false),
      RegExp(r'''motDePasse\s*=\s*['"][^'"$]{4,}['"]'''),
    ];
    final problemes = <String>[];
    for (final f in fichiersTexte(Directory('${racine.path}/lib'))) {
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        if (motifs.any((m) => m.hasMatch(lignes[i]))) problemes.add('${f.path}:${i + 1}');
      }
    }
    expect(problemes, isEmpty);
  });
}
