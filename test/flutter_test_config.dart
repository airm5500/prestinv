// Configuration commune des tests de test/ (chargée automatiquement par flutter test).
//
// Depuis la 4.12.0, la NOUVELLE interface est la valeur par défaut (InterfaceVersion.parDefaut).
// Les tests d'origine (antérieurs à la refonte) vérifient les ÉCRANS D'ORIGINE (lib/screens/…), que
// l'on atteint par les aiguillages HomeScreen / LoginScreen : on les place donc avant chaque test dans
// la situation d'un terminal où l'ancienne interface a été choisie explicitement — situation toujours
// prise en charge, et que ces tests continuent de garantir sans régression. Leurs assertions ne
// changent pas. Les tests de la nouvelle interface l'activent eux-mêmes (activerNouvelleInterface,
// InterfaceVersion.useNew.value = true) ; ceux de l'interrupteur vérifient la valeur par défaut via
// InterfaceVersion.load().
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/interface_version.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => InterfaceVersion.useNew.value = false);
  await testMain();
}
