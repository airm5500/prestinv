// lib/ui/ecrans/feuille_scanner.dart
// Nouvelle interface — onglet « Scanner » de l'accueil (maquette ScanPopup, 4.13) : une feuille du bas
// « Scanner pour… » évite les écrans intermédiaires :
//  - Collecte (scanner sans inventaire, verser plus tard) ;
//  - Scan continu dans un inventaire : liste déroulante (dernier inventaire utilisé présélectionné,
//    avancement connu affiché) puis « Commencer le scan → » : un seul toucher pour démarrer.
import 'package:flutter/material.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/ui/avancement.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

/// Choix fait dans la feuille.
sealed class ChoixScanner {
  const ChoixScanner();
}

class ScannerCollecte extends ChoixScanner {
  const ScannerCollecte();
}

class ScannerInventaire extends ChoixScanner {
  final Inventory inventaire;
  const ScannerInventaire(this.inventaire);
}

/// Ouvre la feuille « Scanner pour… ». [inventaires] : inventaires ouverts ; [courantId] : présélection.
Future<ChoixScanner?> ouvrirFeuilleScanner(BuildContext context, {required List<Inventory> inventaires, String? courantId}) =>
    showModalBottomSheet<ChoixScanner>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => FeuilleScanner(inventaires: inventaires, courantId: courantId),
    );

class FeuilleScanner extends StatefulWidget {
  final List<Inventory> inventaires;
  final String? courantId;
  const FeuilleScanner({super.key, required this.inventaires, this.courantId});

  @override
  State<FeuilleScanner> createState() => _FeuilleScannerState();
}

class _FeuilleScannerState extends State<FeuilleScanner> {
  Inventory? _choisi;

  @override
  void initState() {
    super.initState();
    _choisi = widget.inventaires.where((i) => i.id == widget.courantId).firstOrNull ?? widget.inventaires.firstOrNull;
  }

  String _libelle(Inventory i, SaisieQueue? q) {
    final r = AvancementCalcul.enCache(i.id);
    if (r == null) return i.libelle;
    final e = etatAvancement(r, lignesLocales: q?.lignes(inventaireId: i.id).map((s) => s.ligneId) ?? const []);
    return '${i.libelle} — ${pourcentageAffiche(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final nv = context.nv;
    SaisieQueue? q;
    try {
      q = context.watch<SaisieQueue>();
    } catch (_) {}
    final titre = TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: context.nvSombre ? nv.encre : Pal.navy);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.centerLeft, child: Semantics(header: true, child: Text('Scanner pour…', style: titre))),
        const SizedBox(height: 12),
        Material(
          color: nv.ok.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: nv.ok.fg.withValues(alpha: 0.3))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('nv-scanner-collecte'),
            onTap: () => Navigator.of(context).pop(const ScannerCollecte()),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(Icons.download_for_offline_outlined, color: nv.ok.fg, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Collecte', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: nv.ok.fg)),
                      Text('Scanner sans inventaire, verser plus tard', style: TextStyle(fontSize: 13, color: nv.ok.fg)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: nv.ok.fg),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: nv.ligne)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Scan continu dans un inventaire', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: nv.action)),
            const SizedBox(height: 10),
            if (widget.inventaires.isEmpty)
              Text('Aucun inventaire ouvert.', style: TextStyle(color: nv.gris))
            else
              DropdownButtonFormField<String>(
                key: const ValueKey('nv-scanner-inventaire'),
                value: _choisi?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Inventaire', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                items: [
                  for (final i in widget.inventaires)
                    DropdownMenuItem(value: i.id, child: Text(_libelle(i, q), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) => setState(() => _choisi = widget.inventaires.where((i) => i.id == id).firstOrNull),
              ),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('nv-scanner-commencer'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _choisi == null ? null : () => Navigator.of(context).pop(ScannerInventaire(_choisi!)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Commencer le scan'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 20)]),
            ),
            const SizedBox(height: 6),
            Text('Le dernier inventaire utilisé est présélectionné.', style: TextStyle(fontSize: 12.5, color: nv.gris)),
          ]),
        ),
      ]),
    );
  }
}
