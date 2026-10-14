// Outils d'essai du scan par l'appareil photo (4.14) : appareil photo SIMULÉ (aucun module natif), accès
// au système simulé (présence de l'appareil photo, autorisation Caméra), horloge de l'anti-doublon.
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestinv/scan/camera/scan_camera.dart';

/// Moteur simulé : l'aperçu est un simple cadre ; [lire] fait comme si l'appareil photo lisait un code.
class MoteurCameraSimule implements MoteurCamera {
  /// Moteur de l'aperçu actuellement ouvert.
  static MoteurCameraSimule? actif;

  ValueChanged<String>? _surCode;
  ValueChanged<String>? _surErreur;
  final ValueNotifier<bool?> _lampe = ValueNotifier<bool?>(false);
  bool libere = false;

  MoteurCameraSimule() {
    actif = this;
  }

  @override
  Widget apercu(BuildContext context, {required ValueChanged<String> surCode, required ValueChanged<String> surErreur}) {
    _surCode = surCode;
    _surErreur = surErreur;
    return const ColoredBox(key: ValueKey('apercu-simule'), color: Color(0xFF1B1B1B));
  }

  void lire(String code) => _surCode!(code);
  void erreur(String message) => _surErreur!(message);

  @override
  ValueListenable<bool?> get lampe => _lampe;

  @override
  Future<void> basculerLampe() async => _lampe.value = !(_lampe.value ?? false);

  @override
  void liberer() {
    libere = true;
    if (identical(actif, this)) actif = null;
  }
}

class FauxAccesCamera implements AccesCamera {
  bool aUneCamera;
  AutorisationCamera etat;

  /// Réponse de l'utilisateur à la fenêtre d'Android.
  AutorisationCamera reponse;
  int demandes = 0;
  int parametresOuverts = 0;
  FauxAccesCamera({this.aUneCamera = true, this.etat = AutorisationCamera.accordee, this.reponse = AutorisationCamera.accordee});

  @override
  Future<bool> presente() async => aUneCamera;

  @override
  Future<AutorisationCamera> statut() async => etat;

  @override
  Future<AutorisationCamera> demander() async {
    demandes++;
    etat = reponse;
    return reponse;
  }

  @override
  Future<void> ouvrirParametres() async => parametresOuverts++;
}

/// Horloge manuelle de l'anti-doublon.
class HorlogeEssai {
  DateTime t = DateTime(2026, 10, 14, 9);
  void avancer(Duration d) => t = t.add(d);
}

/// Installe l'appareil photo simulé (à appeler dans setUp) ; remis à l'état réel à la fin du test.
FauxAccesCamera installerCameraSimulee({
  bool presente = true,
  AutorisationCamera etat = AutorisationCamera.accordee,
  AutorisationCamera reponse = AutorisationCamera.accordee,
  HorlogeEssai? horloge,
}) {
  ScanCamera.reinitialiser();
  final acces = FauxAccesCamera(aUneCamera: presente, etat: etat, reponse: reponse);
  ScanCamera.acces = acces;
  ScanCamera.moteur = MoteurCameraSimule.new;
  if (horloge != null) ScanCamera.horloge = () => horloge.t;
  addTearDown(ScanCamera.reinitialiser);
  return acces;
}

/// Préférence qui active le réglage « Scan par l'appareil photo ».
const prefsCamera = <String, Object>{'scanCamera': true};

Finder boutonCamera() => find.byKey(const ValueKey('bouton-camera'));

/// Touche le bouton appareil photo et attend l'aperçu (autorisation déjà accordée).
Future<void> ouvrirCamera(WidgetTester tester) async {
  final b = boutonCamera();
  await tester.ensureVisible(b);
  await tester.pumpAndSettle();
  await tester.tap(b);
  await tester.pumpAndSettle();
}

/// L'appareil photo lit [code].
Future<void> lireCamera(WidgetTester tester, String code) async {
  final m = MoteurCameraSimule.actif;
  expect(m, isNotNull, reason: 'aperçu de l\'appareil photo ouvert');
  m!.lire(code);
  await tester.pumpAndSettle();
}

bool apercuOuvert() => find.byKey(const ValueKey('page-camera')).evaluate().isNotEmpty;
