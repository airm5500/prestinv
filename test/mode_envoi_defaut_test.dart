// Mode d'envoi par défaut : Direct pour une NOUVELLE installation ; un utilisateur existant garde
// son choix enregistré, ou Collecte (l'ancien défaut) s'il n'avait jamais touché au réglage.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(AppConfig, SharedPreferences)> charger(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final c = AppConfig();
  await c.load();
  return (c, await SharedPreferences.getInstance());
}

void main() {
  test('nouvelle installation : Direct, et ce choix est enregistré', () async {
    final (c, p) = await charger({});
    expect(c.sendMode, SendMode.direct);
    expect(p.getInt('sendMode'), SendMode.direct.index);
  });

  test('installation existante sans choix enregistré (tournait en Collecte) : Collecte conservé', () async {
    final (c, p) = await charger({'localApiAddress': '192.168.1.10', 'cached_license': '{}'});
    expect(c.sendMode, SendMode.collect);
    expect(p.getInt('sendMode'), SendMode.collect.index);
  });

  test('installation existante repérée par des saisies en attente seulement', () async {
    final (c, _) = await charger({'inv_A_ray_B_unsynced': '[]'});
    expect(c.sendMode, SendMode.collect);
  });

  test('choix enregistré Direct : conservé', () async {
    final (c, _) = await charger({'localApiAddress': 'x', 'sendMode': SendMode.direct.index});
    expect(c.sendMode, SendMode.direct);
  });

  test('choix enregistré Collecte : conservé', () async {
    final (c, _) = await charger({'sendMode': SendMode.collect.index});
    expect(c.sendMode, SendMode.collect);
  });

  test('valeurs abîmées : pas de plantage', () async {
    final (c, _) = await charger({'sendMode': 9, 'apiMode': -1, 'localApiAddress': 'x'});
    expect(c.sendMode, SendMode.collect);
    expect(c.apiMode, ApiMode.local);
  });
}
