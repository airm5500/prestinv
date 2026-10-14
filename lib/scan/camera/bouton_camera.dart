// lib/scan/camera/bouton_camera.dart
// Bouton « appareil photo » posé à côté du champ de scan (4.14). Affiché seulement si le réglage
// protégé « Scan par l'appareil photo » est actif ET que l'appareil a un appareil photo ; sinon RIEN
// n'est ajouté à l'écran (mise en page identique aux versions précédentes).
import 'package:flutter/material.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/scan/camera/scan_camera.dart';
import 'package:provider/provider.dart';

/// Réglage actif ? (faux si la configuration n'est pas fournie, ex. écran monté seul)
bool scanCameraActif(BuildContext context) {
  try {
    return context.select<AppConfig, bool>((c) => c.scanCamera);
  } on ProviderNotFoundException {
    return false;
  }
}

class BoutonCamera extends StatelessWidget {
  /// Aperçu en continu (scan continu, collecte) ou fermé après une lecture (saisie guidée).
  final bool continu;

  /// Destination des codes lus (par défaut : la douchette, même chemin qu'un scan).
  final ValueChanged<String>? surLecture;

  /// Espace laissé à gauche du bouton (seulement s'il est affiché).
  final double marge;

  /// Côté du bouton (≥ 48 dp).
  final double cote;

  const BoutonCamera({super.key, required this.continu, this.surLecture, this.marge = 8, this.cote = 52});

  @override
  Widget build(BuildContext context) {
    if (!scanCameraActif(context)) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: ScanCamera.cameraPresente(),
      builder: (context, presence) {
        if (presence.data != true) return const SizedBox.shrink();
        final couleur = Theme.of(context).colorScheme.primary;
        return Padding(
          padding: EdgeInsets.only(left: marge),
          child: Semantics(
            container: true,
            button: true,
            label: 'Scanner avec l\'appareil photo',
            excludeSemantics: true,
            child: Tooltip(
              message: 'Scanner avec l\'appareil photo',
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: couleur, width: 2)),
                child: InkWell(
                  key: const ValueKey('bouton-camera'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => ScanCamera.ouvrir(context, continu: continu, surLecture: surLecture),
                  child: SizedBox(width: cote, height: cote, child: Icon(Icons.photo_camera_outlined, color: couleur, size: 26)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [child] (le champ de scan) suivi du bouton appareil photo. Réglage inactif : [child] seul, tel quel.
class AvecBoutonCamera extends StatelessWidget {
  final Widget child;
  final bool continu;
  final ValueChanged<String>? surLecture;
  const AvecBoutonCamera({super.key, required this.child, required this.continu, this.surLecture});

  @override
  Widget build(BuildContext context) {
    if (!scanCameraActif(context)) return child;
    return Row(children: [
      Expanded(child: child),
      BoutonCamera(continu: continu, surLecture: surLecture),
    ]);
  }
}
