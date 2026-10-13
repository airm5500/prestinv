// Interrupteur « Nouvelle interface » : éteint par défaut, choix mémorisé, accueil d'origine dans les deux cas.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('éteint par défaut (nouvelle installation)', () async {
    SharedPreferences.setMockInitialValues({});
    await InterfaceVersion.load();
    expect(InterfaceVersion.useNew.value, isFalse);
    expect(InterfaceVersion.home(), isA<HomeScreen>());
  });

  test('le choix est mémorisé', () async {
    SharedPreferences.setMockInitialValues({});
    await InterfaceVersion.setNew(true);
    InterfaceVersion.useNew.value = false;
    await InterfaceVersion.load();
    expect(InterfaceVersion.useNew.value, isTrue);
    // Étape 0 : aucun nouvel écran, l'accueil d'origine reste utilisé.
    expect(InterfaceVersion.home(), isA<HomeScreen>());
    await InterfaceVersion.setNew(false);
  });
}
