// lib/scan/camera/page_camera.dart
// Aperçu plein écran du scan par l'appareil photo (4.14) : cadre de visée, lampe, bouton Fermer.
// - Saisie guidée ([continu] faux) : se ferme après la première lecture, le code part vers l'écran.
// - Scan continu / collecte ([continu] vrai) : reste ouvert et enchaîne les lectures ; pendant que la
//   feuille de quantité (ou une fenêtre) est posée au-dessus, les lectures sont ignorées.
// Anti-doublon ([AntiDoublon]) : le même code est ignoré pendant ~1,5 s après avoir été vu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestinv/scan/camera/scan_camera.dart';
import 'package:prestinv/scan/code_scan.dart';

class PageCamera extends StatefulWidget {
  final bool continu;
  final ValueChanged<String> surLecture;
  const PageCamera({super.key, required this.continu, required this.surLecture});

  @override
  State<PageCamera> createState() => _PageCameraState();
}

class _PageCameraState extends State<PageCamera> {
  late final MoteurCamera _moteur = ScanCamera.moteur();
  final AntiDoublon _anti = AntiDoublon(horloge: ScanCamera.horloge);
  bool _fini = false;
  String? _erreur;
  String? _dernier;
  int _lus = 0;
  bool _eclair = false;
  Timer? _finEclair;

  @override
  void dispose() {
    _finEclair?.cancel();
    _moteur.liberer();
    super.dispose();
  }

  void _surCode(String brut) {
    if (_fini || !mounted) return;
    // Feuille de quantité, fenêtre… au-dessus de l'aperçu : la lecture n'est pas prise (mais notée,
    // pour ne pas relire aussitôt la boîte restée devant l'objectif).
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      _anti.noter(brut);
      return;
    }
    if (!_anti.accepter(brut)) return;
    if (!widget.continu) {
      _fini = true;
      Navigator.of(context).pop();
      widget.surLecture(brut);
      return;
    }
    setState(() {
      _dernier = brut;
      _lus++;
      _eclair = true;
    });
    _finEclair?.cancel();
    _finEclair = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _eclair = false);
    });
    widget.surLecture(brut);
  }

  void _surErreur(String message) {
    if (mounted) setState(() => _erreur = message);
  }

  Widget _bouton({required Key key, required IconData icone, required String libelle, required VoidCallback? onPressed}) => Semantics(
        container: true,
        button: true,
        label: libelle,
        excludeSemantics: true,
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            key: key,
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(width: 56, height: 56, child: Icon(icone, color: Colors.white, size: 28)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.sizeOf(context);
    final cote = (taille.shortestSide * 0.7).clamp(160.0, 300.0);
    final aide = widget.continu ? 'Visez les codes l\'un après l\'autre : chaque code lu est saisi' : 'Placez le code dans le cadre';
    return Scaffold(
      key: const ValueKey('page-camera'),
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        _moteur.apercu(context, surCode: _surCode, surErreur: _surErreur),
        if (_erreur == null)
          IgnorePointer(
            child: Center(
              child: AnimatedContainer(
                key: const ValueKey('camera-cadre'),
                duration: const Duration(milliseconds: 150),
                width: cote,
                height: cote,
                decoration: BoxDecoration(
                  border: Border.all(color: _eclair ? const Color(0xFF34D399) : Colors.white, width: _eclair ? 5 : 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        if (_erreur != null)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_erreur!, key: const ValueKey('camera-erreur'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _bouton(
                  key: const ValueKey('camera-fermer'),
                  icone: Icons.close,
                  libelle: 'Fermer l\'appareil photo',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.continu ? 'Scan continu' : 'Scanner un code',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                ValueListenableBuilder<bool?>(
                  valueListenable: _moteur.lampe,
                  builder: (_, allumee, __) => allumee == null
                      ? const SizedBox(width: 56, height: 56)
                      : _bouton(
                          key: const ValueKey('camera-lampe'),
                          icone: allumee ? Icons.flashlight_off : Icons.flashlight_on,
                          libelle: allumee ? 'Éteindre la lampe' : 'Allumer la lampe',
                          onPressed: _moteur.basculerLampe,
                        ),
                ),
              ]),
              const Spacer(),
              if (_erreur == null)
                DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(aide, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
                      if (_dernier != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Lu ($_lus) : ${CodeScan.affichage(_dernier!)}',
                            key: const ValueKey('camera-dernier'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
