// lib/ui/ecrans/scan_continu_screen.dart
// Nouvelle interface — scan continu (maquette B, au centre) : scanner → quantité → scanner, sans
// rayon ; journal des dernières saisies avec leur état d'envoi ; « N en attente · M envoyées » avec
// Envoyer ; feuille de quantité rapide (Remplacer / Ajouter). Même logique que la « Saisie rapide
// (Scan) » de l'écran d'origine (voir saisie_commune.dart).
import 'package:flutter/material.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/ui/dialogues.dart';
import 'package:prestinv/ui/ecrans/cumuls_screen.dart';
import 'package:prestinv/ui/ecrans/saisie_commune.dart';
import 'package:prestinv/ui/ecrans/widgets_saisie.dart';
import 'package:prestinv/ui/etats.dart';
import 'package:prestinv/ui/exports.dart';
import 'package:prestinv/ui/presentation_style.dart';
import 'package:prestinv/ui/responsive.dart';
import 'package:prestinv/ui/theme.dart';
import 'package:provider/provider.dart';

class NvScanContinuScreen extends StatefulWidget {
  final Inventory inventaire;
  const NvScanContinuScreen({super.key, required this.inventaire});

  @override
  State<NvScanContinuScreen> createState() => _NvScanContinuScreenState();
}

class _NvScanContinuScreenState extends State<NvScanContinuScreen> with DouchetteCibleMixin, SaisieCommune {
  @override
  Inventory get inventaire => widget.inventaire;

  @override
  bool get modeScan => true;

  @override
  void initState() {
    super.initState();
    initSaisie();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = entry;
      p.reset();
      p.auteur = context.read<AuthProvider>().user?.login ?? '';
      p.ouvrirInventaire(inventoryId, libelle: inventaire.libelle);
    });
  }

  @override
  void dispose() {
    disposeSaisie();
    super.dispose();
  }

  /// Toutes les saisies de l'inventaire gardées sur l'appareil (export CSV, comme l'écran d'origine).
  List<Product> _saisies() {
    final q = queue;
    if (q == null) return entry.allProducts;
    return q
        .lignes(inventaireId: inventoryId)
        .map((s) => Product(
              id: s.ligneId,
              produitCip: s.cip,
              produitName: s.nom,
              produitPrixAchat: 0,
              produitPrixUni: 0,
              quantiteInitiale: 0,
              quantiteSaisie: s.quantite,
              isSynced: s.envoyee,
            ))
        .toList();
  }

  Future<void> _exporter() async {
    final ps = _saisies();
    if (ps.isEmpty) {
      nvMessage(context, 'Aucune donnée à exporter.');
      return;
    }
    try {
      final r = await NvExports.ecrireCsv(NvExports.csvSaisies(ps), 'Export_Saisie_Rapide_${NvExports.horodatage()}.csv', 'Export CSV Saisie_Rapide');
      if (!mounted) return;
      if (r.cheminTelechargements != null) {
        nvMessage(context, 'Export réussi dans Téléchargements.', ton: context.nv.ok, duree: const Duration(seconds: 4));
      }
    } catch (e) {
      if (mounted) nvMessage(context, 'Erreur export : $e', ton: context.nv.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntryProvider>();
    final q = context.watch<SaisieQueue>();
    final appConfig = context.watch<AppConfig>();
    final nv = context.nv;
    final lignes = q.lignes(inventaireId: inventoryId);
    final attente = q.enAttente(inventaireId: inventoryId);
    final envoyees = lignes.where((s) => s.envoyee).length;
    final aJour = provider.inventaireAJour;

    final colonneScan = <Widget>[
      ChampScanNv(
        controller: champScanCtrl,
        focusNode: champScanFocus,
        label: 'Scannez le produit suivant',
        hint: 'Clavier : recherche par nom',
        onCode: surCodeChamp,
        onTexte: surFrappe,
        onClavier: surClavier,
      ),
      ListenableBuilder(
        listenable: fileScans,
        builder: (_, __) => provider.isLoading || fileScans.enAttente > 0
            ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.hourglass_top, size: 18, color: nv.gris),
                  const SizedBox(width: 8),
                  Text(fileScans.enAttente > 0 ? '${fileScans.enAttente} scan(s) à traiter' : 'Recherche…', style: TextStyle(color: nv.gris)),
                ]),
              )
            : const SizedBox.shrink(),
      ),
      const SizedBox(height: 10),
      Bandeau(
        key: const ValueKey('journal-resume'),
        ton: attente > 0 ? nv.attente : nv.ok,
        texte: '$attente en attente · $envoyees envoyée(s)',
        action: attente > 0 ? 'Envoyer' : null,
        actionKey: const ValueKey('nv-envoyer-scan'),
        onAction: envoyerInventaire,
      ),
    ];

    final journal = <Widget>[
      SectionTitre(
        'Dernières saisies',
        trailing: lignes.isEmpty
            ? null
            : TextButton.icon(
                key: const ValueKey('corriger-derniere'),
                onPressed: () => corrigerSaisie(lignes.last),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Corriger la dernière'),
              ),
      ),
      NvJournal(
        inventaireId: inventoryId,
        sansSaisie: sansSaisie,
        onCorriger: corrigerSaisie,
        onRelancer: (c) {
          setState(() => sansSaisie.remove(c));
          recevoirCode(c.code);
        },
      ),
    ];

    final large = Responsive.columns(context) > 1;
    final contenu = large
        ? ListView(padding: const EdgeInsets.all(16), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: colonneScan)),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: journal)),
            ]),
          ])
        : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [...colonneScan, ...journal]);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await securiteSortie() && mounted) nav.pop();
      },
      child: NvScaffold(
        title: 'Scan continu',
        subtitle: '${inventaire.libelle} · ${lignes.length} saisie(s)',
        wide: true,
        actions: [
          Semantics(
            label: aJour ? 'Serveur à jour' : 'Envoi au serveur en attente',
            child: Tooltip(
              message: aJour ? 'Serveur à jour' : 'Envoi au serveur…',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(aJour ? Icons.cloud_done : Icons.cloud_upload, color: aJour ? const Color(0xFF6EE7A0) : Pal.amber),
              ),
            ),
          ),
          ActionEntete(icon: Icons.file_download_outlined, tooltip: 'Exporter la session (CSV)', onPressed: _exporter),
          IconButton(
            key: const ValueKey('nv-menu-scan'),
            tooltip: 'Plus d\'actions',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () async {
              final v = await nvMenu<String>(context, entrees: const [
                NvEntree(Icons.cloud_upload_outlined, 'Envoyer les saisies maintenant', 'envoyer'),
                NvEntree(Icons.history, 'Historique des cumuls', 'cumuls'),
                NvEntree(Icons.close, 'Quitter le scan', 'quitter', danger: true),
              ]);
              if (!context.mounted) return;
              if (v == 'envoyer') envoyerInventaire();
              if (v == 'cumuls') Navigator.of(context).push(nvRoute(const NvCumulsScreen()));
              if (v == 'quitter') {
                final nav = Navigator.of(context);
                if (await securiteSortie() && mounted) nav.pop();
              }
              reprendreFocusScan();
            },
          ),
        ],
        body: Stack(children: [
          contenu,
          if (afficherResultats)
            Positioned.fill(
              top: 96,
              child: ListeResultats(produits: resultats, stockVisible: appConfig.showTheoreticalStock, onTap: choisirResultat),
            ),
        ]),
      ),
    );
  }
}
