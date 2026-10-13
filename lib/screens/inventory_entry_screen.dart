// lib/screens/inventory_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/utils/journal.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/providers/entry_provider.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';
import 'package:prestinv/screens/recap_screen.dart';
import 'package:prestinv/screens/variance_screen.dart';
import 'package:prestinv/utils/app_utils.dart';
import 'package:prestinv/models/product.dart';
import 'dart:async';
import 'package:prestinv/models/product_filter.dart';
import 'package:prestinv/screens/cumul_history_screen.dart';
import 'package:prestinv/saisie/saisie_queue.dart';
import 'package:prestinv/saisie/saisie_serveur.dart';
import 'package:prestinv/utils/saisie_input.dart';
import 'package:prestinv/widgets/chargement_erreur.dart';
import 'package:prestinv/widgets/reconnexion.dart';
import 'package:prestinv/saisie/saisie.dart';
import 'package:prestinv/scan/champ_douchette.dart';
import 'package:prestinv/scan/code_scan.dart';
import 'package:prestinv/scan/douchette.dart';
import 'package:prestinv/scan/file_scans.dart';
import 'package:prestinv/scan/journal_scans.dart';
import 'package:prestinv/scan/retour_scan.dart';

import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class InventoryEntryScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;
  final bool isQuickMode;
  const InventoryEntryScreen(
      {super.key, required this.inventoryId, this.inventoryName = '', this.isQuickMode = false});

  @override
  State<InventoryEntryScreen> createState() => _InventoryEntryScreenState();
}

class _InventoryEntryScreenState extends State<InventoryEntryScreen> with DouchetteCibleMixin {
  final _quantityController = TextEditingController();
  final _quantityFocusNode = FocusNode();
  int? _lastDisplayedProductId;
  late ApiService _apiService;
  String? _notificationMessage;
  Color? _notificationColor;
  Timer? _notificationTimer;
  Timer? _sendReminderTimer;

  Timer? _debounceTimer;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;
  List<Product> _filteredProducts = [];
  bool _showSearchResults = false;

  /// OK en cours de traitement : un second appui est ignoré (double appui = produit sauté / cumul doublé).
  bool _validationEnCours = false;

  // --- Douchette toujours prête (étape 3) ---
  /// Codes scannés en attente de traitement (rafales : aucun perdu).
  late final FileScans _fileScans;

  /// Fenêtre de quantité ouverte (les scans continuent d'arriver dans la file).
  bool _feuilleOuverte = false;

  /// Clavier à l'écran affiché dans le champ de scan (recherche par nom).
  bool _clavierTexte = false;

  /// Codes lus sans saisie (introuvables, recherche impossible) : journal « à vérifier ».
  final List<ScanSansSaisie> _sansSaisie = [];

  /// Produits trouvés par scan (prix, stock… pour corriger une saisie depuis le journal).
  final Map<int, Product> _produitsVus = {};

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
        baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
        cookie: () => authProvider.sessionCookie);

    // Le pavé numérique ne se cache que si le clavier à l'écran est affiché (recherche par nom) :
    // le champ de scan garde le focus en permanence sans le masquer.
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isSearching = _searchFocusNode.hasFocus && _clavierTexte;
      });
    });

    _fileScans = FileScans(traiter: _traiterCode, pret: _pretPourScan);
    brancherDouchette(CibleDouchette(
      active: () => mounted && (_routeCourante || _feuilleOuverte),
      onCode: _recevoirCode,
      onChiffres: widget.isQuickMode ? null : (t) => t.split('').forEach(_onKeyPressed),
      onEffacer: widget.isQuickMode ? null : () => _onKeyPressed('DEL'),
      onValider: widget.isQuickMode ? null : () => _onKeyPressed('OK'),
      onToucheScan: _reprendreFocusScan,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = Provider.of<EntryProvider>(context, listen: false);
        provider.reset();
        provider.auteur = authProvider.user?.login ?? '';
        provider.ouvrirInventaire(widget.inventoryId, libelle: widget.inventoryName);
        if (!widget.isQuickMode) {
          provider.fetchRayons(_apiService, widget.inventoryId);
        }
      }
    });
  }

  bool get _routeCourante => ModalRoute.of(context)?.isCurrent ?? true;

  /// Le champ de scan reprend le focus (après OK, après une fenêtre, après une erreur).
  void _reprendreFocusScan() {
    if (!mounted) return;
    if (_searchFocusNode.canRequestFocus) _searchFocusNode.requestFocus();
  }

  /// Le code suivant peut être traité : écran au premier plan, aucune validation en cours.
  bool _pretPourScan() => mounted && _routeCourante && !_validationEnCours && !_feuilleOuverte;

  /// Code lu par la douchette (ou validé dans le champ de scan) : mis en file, traité dans l'ordre.
  void _recevoirCode(String code) {
    final c = CodeScan.nettoyer(code);
    if (c.isEmpty) return;
    _fileScans.ajouter(c);
  }

  void _retour(TypeRetour type) {
    final config = Provider.of<AppConfig>(context, listen: false);
    RetourScan.jouer(type, son: config.sonScan, vibration: config.vibrationScan);
  }

  void _noterSansSaisie(String code, String raison, {bool aRelancer = false}) {
    setState(() {
      _sansSaisie.add(ScanSansSaisie(code, DateTime.now(), raison, aRelancer: aRelancer));
      if (_sansSaisie.length > 50) _sansSaisie.removeAt(0);
    });
  }

  /// Traite UN code scanné : recherche dans l'inventaire (variantes du code), puis fenêtre de quantité.
  /// Introuvable ou erreur : message clair + bip long, la file continue avec le code suivant.
  Future<void> _traiterCode(String code) async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (!widget.isQuickMode && provider.selectedRayon == null) {
      _retour(TypeRetour.erreur);
      _showNotification('Choisissez d\'abord un emplacement.', Colors.red);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Code lu : choisissez d\'abord un emplacement.'), backgroundColor: Colors.red));
      return;
    }
    final candidats = CodeScan.candidats(code);
    if (candidats.isEmpty) return;
    Product? exact;
    final possibles = <int, Product>{};
    try {
      for (final c in candidats) {
        final r = await provider.searchProductOnline(_apiService, widget.inventoryId, c);
        if (!mounted) return;
        final memeCode = r.where((p) => p.produitCip.trim() == c).toList();
        if (memeCode.length == 1) {
          exact = memeCode.first;
          break;
        }
        // Un seul produit pour ce code (EAN reconnu par le serveur) : c'est lui.
        if (r.length == 1) {
          exact = r.first;
          break;
        }
        for (final p in r) {
          possibles[p.id] = p;
        }
      }
    } catch (e) {
      if (!mounted) return;
      _retour(TypeRetour.erreur);
      _noterSansSaisie(code, 'recherche impossible (${estSessionExpiree(e) ? 'session expirée' : 'réseau'}) — toucher pour relancer', aRelancer: true);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Code lu : ${CodeScan.affichage(code)} — ${messageErreur(e)}'),
          backgroundColor: Colors.red,
          action: estSessionExpiree(e)
              ? SnackBarAction(label: 'Se reconnecter', textColor: Colors.white, onPressed: () => demanderReconnexion(context))
              : null));
      _reprendreFocusScan();
      return;
    }
    if (!mounted) return;
    if (exact == null && possibles.isNotEmpty) {
      exact = await _choisirParmi(code, possibles.values.toList());
      if (!mounted) return;
      if (exact == null) {
        _reprendreFocusScan();
        return;
      }
    }
    if (exact == null) {
      _retour(TypeRetour.erreur);
      final message = widget.isQuickMode
          ? CodeScan.messageIntrouvable(code)
          : 'Code lu : ${CodeScan.affichage(code)} — introuvable dans cet emplacement';
      _noterSansSaisie(code, widget.isQuickMode ? 'pas dans cet inventaire' : 'pas dans cet emplacement');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          key: const ValueKey('code-introuvable'), content: Text(message), backgroundColor: Colors.red, duration: const Duration(seconds: 3)));
      _reprendreFocusScan();
      return;
    }
    await _ouvrirProduitScanne(exact);
  }

  /// Plusieurs produits pour un code : l'opérateur choisit (la file attend).
  Future<Product?> _choisirParmi(String code, List<Product> produits) {
    _retour(TypeRetour.dejaCompte);
    return showDialog<Product>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Code ${CodeScan.affichage(code)} : plusieurs produits', maxLines: 2, overflow: TextOverflow.ellipsis),
        children: [
          for (final p in produits.take(20))
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: Text('${p.produitCip} — ${p.produitName}', maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  /// Quantité déjà comptée connue sans requête : saisie gardée sur l'appareil, sinon date de comptage
  /// renvoyée par le serveur avec le produit.
  int? _dejaCompteConnu(Product p) {
    final locale = _queue?.ligne(widget.inventoryId, p.id);
    if (locale != null) return locale.quantite;
    if (p.dtUpdated != null) return p.quantiteSaisie;
    return null;
  }

  Future<void> _ouvrirProduitScanne(Product p) async {
    _produitsVus[p.id] = p;
    final deja = _dejaCompteConnu(p);
    _retour(deja != null ? TypeRetour.dejaCompte : TypeRetour.succes);
    _searchController.clear();
    if (_showSearchResults) {
      setState(() {
        _showSearchResults = false;
        _filteredProducts = [];
      });
    }
    await _openQuickEntryDialog(p, dejaCompte: deja);
  }

  /// Correction rapide d'une saisie du journal (la quantité saisie remplace la précédente).
  Future<void> _corrigerSaisie(SaisieLigne s) async {
    if (_fileScans.occupe || _feuilleOuverte) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patientez : un scan est en cours de traitement.')));
      return;
    }
    final p = _produitsVus[s.ligneId] ??
        Product(
          id: s.ligneId,
          produitCip: s.cip,
          produitName: s.nom,
          produitPrixAchat: 0,
          produitPrixUni: 0,
          quantiteInitiale: 0,
          quantiteSaisie: s.quantite,
          locationLabel: s.rayonLibelle,
        );
    await _openQuickEntryDialog(p, correction: s.quantite);
    _fileScans.relancer();
  }

  @override
  void dispose() {
    _fileScans.dispose();
    _quantityController.dispose();
    _quantityFocusNode.dispose();
    _notificationTimer?.cancel();
    _sendReminderTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  String _getFilterDisplay(ProductFilter filter) {
    if (!filter.isActive) return "";
    if (filter.from == "Rattrapage") return " (Oublis)";
    String prefix = filter.type == FilterType.numeric ? "N°" : "";
    return " ($prefix${filter.from} à $prefix${filter.to})";
  }

  Future<void> _exportProductsToCsv(
      List<Product> products, String suffixName) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune donnée à exporter.')));
      return;
    }

    final StringBuffer csvContent = StringBuffer();
    csvContent.writeln('code_cip;quantite');

    for (final p in products) {
      csvContent.writeln('${p.produitCip};${p.quantiteSaisie}');
    }

    final timestamp = DateFormat('ddMMyyyy_HHmm').format(DateTime.now());
    final cleanSuffix = suffixName.replaceAll(RegExp(r'[^\w\s]+'), '');
    final fileName = 'Export_${cleanSuffix}_$timestamp.csv';

    try {
      if (Platform.isAndroid) {
        final Directory downloadDir = Directory('/storage/emulated/0/Download');
        if (!await downloadDir.exists()) {
          try {
            await downloadDir.create(recursive: true);
          } catch (e) {
            journal("Err create dir: $e");
          }
        }

        final String filePath = '${downloadDir.path}/$fileName';
        final File file = File(filePath);

        bool saveSuccess = false;

        try {
          await file.writeAsString(csvContent.toString());
          saveSuccess = true;
        } catch (e) {
          var status = await Permission.storage.status;
          if (!status.isGranted) status = await Permission.storage.request();

          if (status.isGranted) {
            try {
              await file.writeAsString(csvContent.toString());
              saveSuccess = true;
            } catch (e2) {
              journal("Echec permissions: $e2");
            }
          }
        }

        if (saveSuccess) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ Export réussi dans Téléchargements :\n$fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
                label: 'Partager',
                textColor: Colors.white,
                onPressed: () {
                  Share.shareXFiles([XFile(filePath)], text: 'Export CSV');
                }),
          ));
          return;
        }
      }

      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvContent.toString());

      if (!mounted) return;
      Share.shareXFiles([XFile(filePath)], text: 'Export CSV $suffixName');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur export: $e'), backgroundColor: Colors.red));
    }
  }

  /// Toutes les saisies de l'inventaire gardées sur l'appareil (envoyées ou non), pour l'export CSV
  /// de la saisie rapide (avant : seul le dernier produit scanné était exporté).
  List<Product> _saisiesDeLInventaire() {
    final q = _queue;
    if (q == null) return Provider.of<EntryProvider>(context, listen: false).allProducts;
    return q
        .lignes(inventaireId: widget.inventoryId)
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

  void _navigateToRecap() async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
            content: Row(children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Chargement du récap..."),
            ])));
    try {
      final provider = Provider.of<EntryProvider>(context, listen: false);
      String targetRayonId = provider.selectedRayon?.id ?? "";
      String targetRayonName = provider.selectedRayon?.libelle ?? "Global";
      List<Product> products;
      if (targetRayonId.isNotEmpty) {
        products = await _apiService.fetchProducts(
            widget.inventoryId, targetRayonId);
      } else {
        products = provider.allProducts;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecapScreen(
              inventoryId: widget.inventoryId,
              rayonId: targetRayonId,
              rayonName: targetRayonName,
              preloadedProducts: products)));
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showNotification(String message, Color color) {
    _notificationTimer?.cancel();
    setState(() {
      _notificationMessage = message;
      _notificationColor = color;
    });
    _notificationTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _notificationMessage = null;
        });
      }
    });
  }

  void _resetSendReminderTimer() {
    _sendReminderTimer?.cancel();
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (appConfig.sendMode == SendMode.collect &&
        appConfig.sendReminderMinutes > 0) {
      _sendReminderTimer =
          Timer(Duration(minutes: appConfig.sendReminderMinutes), () {
            if (provider.hasUnsyncedData && mounted) {
              _showSendReminderNotification();
            }
          });
    }
  }

  void _showSendReminderNotification() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Rappel : Vous avez des données non envoyées !'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 5)));
  }

  void _onKeyPressed(String value) {
    if (value == 'DEL') {
      if (_quantityController.text.isNotEmpty) {
        _quantityController.text = _quantityController.text
            .substring(0, _quantityController.text.length - 1);
      }
    } else if (value == 'OK') {
      _validateAndProceed();
    } else {
      _quantityController.text = SaisieInput.ajouterChiffre(_quantityController.text, value);
    }
  }

  SaisieQueue? get _queue => Provider.of<EntryProvider>(context, listen: false).queue;

  /// Envoie les saisies en attente de l'inventaire (tous rayons). Renvoie `true` si tout est confirmé.
  Future<bool> _sendDataToServer() async {
    if (!mounted) return false;
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final enAttente = provider.pendingCountInventory;

    if (appConfig.sendMode == SendMode.direct && enAttente == 0) {
      _showNotification('Mode Direct : Tout est déjà synchronisé.', Colors.blue);
      return true;
    }

    if (enAttente == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucune donnée en attente d\'envoi.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2)));
      return true;
    }

    final ValueNotifier<String> progressNotifier = ValueNotifier('Connexion au serveur...');
    showProgressDialog(context, progressNotifier);

    final bilan = await provider.envoyerInventaire(widget.inventoryId, (int current, int total) {
      progressNotifier.value = 'Envoi... ($current/$total)';
    });

    if (bilan.complet && bilan.refusees == 0) {
      progressNotifier.value = '✅ ${bilan.envoyees} article(s) traité(s) avec succès.';
    } else if (bilan.envoyees > 0) {
      progressNotifier.value = '⚠️ Réseau instable : ${bilan.envoyees}/$enAttente envoyé(s). '
          'Le reste est gardé sur l\'appareil (« À envoyer »).';
    } else if (bilan.refusees > 0 && bilan.interruption == null) {
      progressNotifier.value = '❌ ${bilan.refusees} saisie(s) refusée(s) par le serveur (voir « À envoyer »).';
    } else {
      progressNotifier.value = '❌ Échec : ${bilan.interruption ?? 'Vérifiez votre connexion au serveur.'} '
          'Les saisies restent sur l\'appareil.';
    }

    _sendReminderTimer?.cancel();

    // On laisse le message affiché 2.5 secondes pour que l'utilisateur puisse lire l'erreur
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) Navigator.of(context).pop();
    return bilan.complet;
  }

  /// Mode Direct : envoi immédiat de la ligne (déjà enregistrée sur l'appareil).
  void _envoyerDirect(Product product) {
    final q = _queue;
    if (q == null) return;
    q.envoyerLigne(widget.inventoryId, product.id).then((r) {
      if (!r.estOk && mounted) {
        // Inventaire clôturé / refus : motif du serveur ; réseau : gardé sur l'appareil, nouvel essai.
        _showNotification(
            r.type == ResultatEnvoi.refus ? r.message : 'Non envoyé (réseau) : gardé sur l\'appareil, nouvel essai automatique.',
            Colors.red);
      }
    });
  }

  void _validateAndProceed() async {
    if (!mounted || _validationEnCours) return;
    _validationEnCours = true;
    try {
      await _validerEtAvancer();
    } finally {
      _validationEnCours = false;
      _reprendreFocusScan();
      _fileScans.relancer();
    }
  }

  Future<void> _validerEtAvancer() async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    final erreur = SaisieInput.erreurQuantite(_quantityController.text);
    if (erreur != null) {
      _showNotification(erreur, Colors.orange);
      return;
    }

    final inputQuantity = SaisieInput.parseQuantite(_quantityController.text)!;
    int finalQuantity = inputQuantity;

    final currentProductAtClick = provider.currentProduct;
    if (currentProductAtClick == null) return;

    if (appConfig.isCumulEnabled) {
      int? existingQty;

      if (widget.isQuickMode) {
        final verif = await _verifierDejaCompte(context, currentProductAtClick);
        if (!verif.ok) return; // vérification impossible : rien n'est enregistré
        existingQty = verif.quantite;
      } else {
        existingQty = await provider
            .checkExistingQuantityLocal(currentProductAtClick.produitCip);
      }

      if (existingQty != null) {
        bool? shouldCumulate = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text("⚠️ Déjà compté"),
              backgroundColor: const Color(0xFFFFF3CD),
              content: _buildCumulContent(currentProductAtClick.produitName,
                  existingQty!, inputQuantity),
              actions: [
                TextButton(
                    child: const Text("NON (Écraser)",
                        style: TextStyle(color: Colors.red)),
                    onPressed: () => Navigator.of(context).pop(false)),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white),
                    child: const Text("OUI (Additionner)"),
                    onPressed: () => Navigator.of(context).pop(true)),
              ],
            );
          },
        );

        if (shouldCumulate == true) {
          finalQuantity = existingQty + inputQuantity;
          provider.addCumulLog(
              currentProductAtClick, existingQty, inputQuantity);
        }
      }
    }

    Future<void> proceedToNext(int quantityToSave, Product productToUpdate) async {
      // 1. Enregistrée sur l'appareil AVANT tout envoi et avant de passer au produit suivant.
      try {
        await provider.updateQuantity(quantityToSave.toString(), widget.inventoryId);
      } catch (e) {
        if (mounted) _showNotification('Enregistrement impossible sur l\'appareil : $e', Colors.red);
        return;
      }
      if (!mounted) return;
      _resetSendReminderTimer();

      // 2. Mode Direct : envoi immédiat (la file renvoie une correction faite pendant l'envoi).
      if (appConfig.sendMode == SendMode.direct) {
        _envoyerDirect(productToUpdate);
      }

      bool isLastProduct =
          provider.currentProductIndex >= provider.totalProducts - 1;
      if (isLastProduct && provider.totalProducts > 0) {
        _sendReminderTimer?.cancel();
        if (!mounted) return;
        _showFinishDialog();
      } else {
        provider.nextProduct(widget.inventoryId);
        _quantityController.clear();
        // Le champ de scan garde le focus : un scan juste après OK n'est plus perdu (avant, le focus
        // allait au champ Quantité en lecture seule, qui ignorait la douchette).
        _reprendreFocusScan();
      }
    }

    if (finalQuantity > appConfig.largeValueThreshold) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
              title: const Text('Alerte Grande Quantité'),
              content: Text('Total : $finalQuantity. Confirmer ?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Non')),
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Oui'))
              ]));
      if (confirmed == true) await proceedToNext(finalQuantity, currentProductAtClick);
    } else {
      await proceedToNext(finalQuantity, currentProductAtClick);
    }
  }

  void _showFinishDialog() {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    int remaining = provider.uncountedProductsCount;

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: Text(remaining > 0 ? "⚠️ Emplacement incomplet" : "Fin de l'emplacement"),
            content: Text(remaining > 0
                ? "Il reste $remaining produits n'ayant jamais été touchés.\n\nVoulez-vous les traiter maintenant ?"
                : "Tous les produits ont été touchés. Voulez-vous envoyer les données ?"),
            actions: [
              if (remaining > 0)
                ElevatedButton(onPressed: () { Navigator.pop(ctx); provider.filterToUncounted(); }, child: const Text("OUI (Traiter oublis)")),
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Non')),
              TextButton(onPressed: () { Navigator.of(ctx).pop(); _sendDataToServer(); }, child: const Text('Oui'))
            ]));
  }

  // --- LOGIQUE DE SÉCURITÉ DE SORTIE RÉVISÉE ---
  Future<bool> _handleExitSecurity() async {
    _sendReminderTimer?.cancel();

    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    int remaining = provider.uncountedProductsCount;
    bool hasUnsynced = provider.hasUnsyncedData;

    if (remaining == 0 && !hasUnsynced) {
      return true;
    }

    if (appConfig.sendMode == SendMode.direct) {
      if (remaining == 0) return true;
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Quitter l\'inventaire ?'),
          content: Text('Il reste encore $remaining produit(s) jamais touchés dans ce rayon.'),
          actions: [
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A38D)),
                onPressed: () {
                  Navigator.pop(ctx, false);
                  provider.filterToUncounted();
                },
                child: const Text("Voir les oublis")
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ignorer et Quitter', style: TextStyle(color: Colors.red))
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Rester')
            ),
          ],
        ),
      ) ?? false;
    }

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter l\'inventaire ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasUnsynced)
              const Text('⚠️ Des données n\'ont pas été envoyées vers le serveur.',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 8),
            if (remaining > 0)
              Text('Il reste encore $remaining produit(s) jamais touchés dans ce rayon.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Rester')),

          if (remaining > 0)
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A38D)),
                onPressed: () {
                  Navigator.pop(ctx, false);
                  provider.filterToUncounted();
                },
                child: const Text("Voir les oublis")
            ),

          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ignorer et Quitter', style: TextStyle(color: Colors.red))
          ),

          if (hasUnsynced)
            ElevatedButton(
                onPressed: () async {
                  final toutEnvoye = await _sendDataToServer();
                  if (!ctx.mounted) return;
                  // On ne quitte que si tout est réellement envoyé ; sinon on reste (les saisies
                  // restent de toute façon enregistrées sur l'appareil).
                  Navigator.of(ctx).pop(toutEnvoye);
                  if (!toutEnvoye && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Envoi incomplet : les saisies restent sur l\'appareil (« À envoyer »).'),
                        backgroundColor: Colors.orange));
                  }
                },
                child: const Text('Envoyer et Quitter')),
        ],
      ),
    ) ?? false;
  }

  void _showPendingDataDialog() {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    provider.acknowledgedPendingSession();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saisie non terminée'),
        content: const Text(
            'Des saisies non envoyées de la dernière session ont été trouvées. Voulez-vous les envoyer maintenant ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Non')),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _sendDataToServer();
              },
              child: const Text('Oui, envoyer')),
        ],
      ),
    );
  }

  void _onLocationChanged(Rayon? newValue) async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (newValue?.id != provider.selectedRayon?.id) {

      bool canChange = await _handleExitSecurity();
      if (!canChange) return;

      if (mounted) {
        _sendReminderTimer?.cancel();
        _searchController.clear();
        _showSearchResults = false;
        if (newValue == null) {
          provider.reset();
        } else {
          provider
              .fetchProducts(_apiService, widget.inventoryId, newValue.id)
              .then((_) {
            _resetSendReminderTimer();
            _reprendreFocusScan();
          });
        }
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (query.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _filteredProducts = [];
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _handleScanOrSearch(query, fromTyping: true);
    });
  }

  Future<void> _handleScanOrSearch(String query,
      {bool fromTyping = false}) async {
    // Code de douchette nettoyé (caractères de contrôle) et longueur bornée.
    query = SaisieInput.nettoyerRecherche(query);
    if (query.isEmpty) return;
    _debounceTimer?.cancel();
    final provider = Provider.of<EntryProvider>(context, listen: false);
    if (!fromTyping) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recherche...'), duration: Duration(milliseconds: 500)));
    }

    try {
      final onlineMatches = await provider.searchProductOnline(
          _apiService, widget.inventoryId, query);
      if (!mounted) return;

      if (onlineMatches.isNotEmpty) {
        setState(() {
          _filteredProducts = onlineMatches;
          _showSearchResults = true;
        });
        if (!fromTyping) {
          if (onlineMatches.length == 1) {
            _ouvrirProduitScanne(onlineMatches.first);
            _searchController.clear();
            setState(() {
              _showSearchResults = false;
            });
            FocusScope.of(context).unfocus();
          } else {
            FocusScope.of(context).unfocus();
          }
        }
      } else {
        if (!fromTyping) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Produit introuvable.'),
              backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      // Erreur réseau / session ≠ « produit introuvable ».
      if (mounted && !fromTyping) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(messageErreur(e)),
            backgroundColor: Colors.red,
            action: estSessionExpiree(e)
                ? SnackBarAction(label: 'Se reconnecter', textColor: Colors.white, onPressed: () => demanderReconnexion(context))
                : null));
      }
    }
  }

  /// Fenêtre de quantité après un scan (ou une correction depuis le journal).
  /// - [dejaCompte] : quantité déjà comptée connue (affichée ; la question Remplacer / Ajouter reste
  ///   celle du réglage « Cumul », inchangée) ;
  /// - [correction] : quantité actuelle de la saisie corrigée (elle est remplacée, sans question) ;
  /// - quantité proposée : réglage « Quantité proposée après un scan » (1 par défaut) ; elle est
  ///   remplacée dès qu'on tape un chiffre ; bornes 0 à 99 999 ;
  /// - clavier physique / douchette : chiffres, Retour arrière, Entrée = OK ; un code scanné pendant
  ///   que la fenêtre est ouverte attend son tour dans la file (jamais perdu).
  /// Se termine quand la fenêtre est fermée.
  Future<void> _openQuickEntryDialog(Product product, {int? dejaCompte, int? correction}) async {
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final proposee = correction ?? appConfig.quantiteScanDefaut;
    final quickQtyController = TextEditingController(text: proposee?.toString() ?? '');
    // Valeur proposée : remplacée par le premier chiffre tapé.
    final estProposee = ValueNotifier<bool>(proposee != null);
    final catcherController = TextEditingController();
    final catcherFocus = FocusNode();
    // OK verrouillé pendant le traitement (double appui = cumul proposé deux fois).
    var okEnCours = false;
    var ouverte = true;
    BuildContext? dialogCtx;

    void poser(String texte) {
      quickQtyController.text = texte;
      estProposee.value = false;
    }

    Future<void> valider(BuildContext ctx) async {
      if (okEnCours) return;
      final erreur = SaisieInput.erreurQuantite(quickQtyController.text);
      if (erreur != null) {
        _retour(TypeRetour.erreur);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur), backgroundColor: Colors.orange));
        return;
      }
      final int saisie = SaisieInput.parseQuantite(quickQtyController.text)!;
      okEnCours = true;
      try {
        int inputQty = saisie;
        int finalQty = inputQty;

        if (appConfig.isCumulEnabled && correction == null) {
          // P2 : un échec de la vérification ne veut JAMAIS dire « jamais compté ».
          final verif = await _verifierDejaCompte(ctx, product);
          if (!verif.ok) return; // rien n'est enregistré, la fenêtre reste ouverte
          final int? existingQty = verif.quantite;
          if (existingQty != null && ctx.mounted) {
            bool? shouldCumulate = await showDialog<bool>(
              context: ctx,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("⚠️ Déjà compté"),
                  backgroundColor: const Color(0xFFFFF3CD),
                  content: _buildCumulContent(product.produitName, existingQty, inputQty),
                  actions: [
                    TextButton(
                        child: const Text("NON (Écraser)", style: TextStyle(color: Colors.red)),
                        onPressed: () => Navigator.of(context).pop(false)),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                        child: const Text("OUI (Additionner)"),
                        onPressed: () => Navigator.of(context).pop(true)),
                  ],
                );
              },
            );
            if (shouldCumulate == true) {
              finalQty = existingQty + inputQty;
              provider.addCumulLog(product, existingQty, inputQty);
            }
          }
        }
        if (finalQty > SaisieInput.maxQuantite) {
          _retour(TypeRetour.erreur);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Total $finalQty : au-delà de ${SaisieInput.maxQuantite}, non enregistré.'), backgroundColor: Colors.red));
          }
          return;
        }
        // Seuil « grande quantité » (comme en saisie guidée).
        if (finalQty > appConfig.largeValueThreshold && ctx.mounted) {
          final confirme = await showDialog<bool>(
              context: ctx,
              builder: (c) => AlertDialog(title: const Text('Alerte Grande Quantité'), content: Text('Total : $finalQty. Confirmer ?'), actions: [
                    TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Non')),
                    TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Oui')),
                  ]));
          if (confirme != true) return;
        }

        // Enregistrée sur l'appareil AVANT de fermer la fenêtre.
        final enregistre = await _saveScannedQuantity(product, finalQty);
        if (!enregistre) {
          _retour(TypeRetour.erreur);
          return;
        }
        if (!ctx.mounted) return;
        Navigator.of(ctx).pop();
      } finally {
        okEnCours = false;
      }
    }

    void appui(String key) {
      final ctx = dialogCtx;
      if (okEnCours || ctx == null) return;
      if (key == 'OK') {
        valider(ctx);
      } else if (key == 'DEL') {
        if (estProposee.value) {
          poser('');
        } else if (quickQtyController.text.isNotEmpty) {
          poser(quickQtyController.text.substring(0, quickQtyController.text.length - 1));
        }
      } else if (key == '+1' || key == '-1') {
        final v = SaisieInput.parseQuantite(quickQtyController.text) ?? 0;
        final n = (v + (key == '+1' ? 1 : -1)).clamp(0, SaisieInput.maxQuantite);
        poser('$n');
      } else {
        poser(SaisieInput.ajouterChiffre(estProposee.value ? '' : quickQtyController.text, key));
      }
    }

    final cible = CibleDouchette(
      active: () => ouverte,
      onChiffres: (t) => t.split('').forEach(appui),
      onEffacer: () => appui('DEL'),
      onValider: () => appui('OK'),
      onEchap: () {
        final ctx = dialogCtx;
        if (!okEnCours && ctx != null && ctx.mounted) Navigator.of(ctx).pop();
      },
    );
    Douchette.instance.ajouter(cible);
    setState(() => _feuilleOuverte = true);

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogCtx = ctx;
          // Contrôleurs libérés quand la fenêtre disparaît (après son animation de fermeture).
          return _Liberer(
            objets: [quickQtyController, catcherController, catcherFocus, estProposee],
            child: AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            title: _buildQuickDialogTitle(product, appConfig, dejaCompte: dejaCompte, correction: correction),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Champ de scan invisible : garde le focus pendant la fenêtre (douchette en
                  // « remplissage direct » : le code lu attend son tour dans la file).
                  SizedBox(
                    width: 1,
                    height: 1,
                    child: Opacity(
                      opacity: 0,
                      child: ChampDouchette(
                        key: const ValueKey('champ-scan-feuille'),
                        controller: catcherController,
                        focusNode: catcherFocus,
                        onCode: _recevoirCode,
                        label: '',
                        hint: '',
                      ),
                    ),
                  ),
                  Row(children: [
                    IconButton(
                      key: const ValueKey('qte-moins'),
                      tooltip: '−1',
                      icon: const Icon(Icons.remove_circle_outline, size: 32),
                      onPressed: () => appui('-1'),
                    ),
                    Expanded(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: estProposee,
                        builder: (_, prop, __) => TextField(
                            key: const ValueKey('qte-scan'),
                            controller: quickQtyController,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: prop ? Colors.grey.shade600 : AppColors.accent),
                            decoration: InputDecoration(
                                labelText: prop ? 'Quantité (proposée)' : 'Quantité', border: const OutlineInputBorder()),
                            keyboardType: TextInputType.none,
                            readOnly: true,
                            showCursor: true),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('qte-plus'),
                      tooltip: '+1',
                      icon: const Icon(Icons.add_circle_outline, size: 32),
                      onPressed: () => appui('+1'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: NumericKeyboard(onKeyPressed: appui),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annuler', style: TextStyle(color: Colors.red))),
            ],
          ),
          );
        },
      );
    } finally {
      ouverte = false;
      Douchette.instance.retirer(cible);
      if (mounted) {
        setState(() {
          _feuilleOuverte = false;
          _showSearchResults = false;
          _filteredProducts = [];
        });
        _searchController.clear();
        // Après la fenêtre (OK ou Annuler), le champ de scan reprend le focus et la file continue.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _reprendreFocusScan();
          _fileScans.relancer();
        });
      }
    }
  }

  /// Le produit est-il déjà compté (cumul) ?
  ///
  /// 1. Une saisie de cette ligne encore en attente sur l'appareil fait foi (plus récente que le serveur).
  /// 2. Sinon on demande au serveur. En cas d'échec (réseau lent, serveur injoignable, session expirée),
  ///    on NE CONCLUT PAS « jamais compté » : l'utilisateur peut réessayer ou annuler — la quantité
  ///    n'est alors pas enregistrée (sinon on écraserait le comptage d'un collègue).
  /// Renvoie `ok: false` si l'utilisateur a annulé.
  Future<({bool ok, int? quantite})> _verifierDejaCompte(BuildContext ctx, Product product) async {
    final locale = _queue?.ligne(widget.inventoryId, product.id);
    if (locale != null && locale.enAttente) return (ok: true, quantite: locale.quantite);
    while (true) {
      if (!ctx.mounted) return (ok: false, quantite: null);
      showDialog(
          context: ctx,
          barrierDismissible: false,
          builder: (c) => const Center(child: CircularProgressIndicator()));
      try {
        final q = await _apiService.verifierDejaCompte(widget.inventoryId, product.produitCip, ligneId: product.id);
        if (ctx.mounted) Navigator.of(ctx).pop();
        return (ok: true, quantite: q);
      } on ApiLoadException catch (e) {
        if (ctx.mounted) Navigator.of(ctx).pop();
        if (!ctx.mounted) return (ok: false, quantite: null);
        final reessayer = await showDialog<bool>(
          context: ctx,
          barrierDismissible: false,
          builder: (d) => AlertDialog(
            title: const Text('Vérification impossible'),
            content: Text('${e.message}\n\n'
                'On ne peut pas savoir si ce produit a déjà été compté : la quantité n\'est PAS enregistrée. '
                'Réessayez (ou annulez et rescannez plus tard).'),
            actions: [
              TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
              ElevatedButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Réessayer')),
            ],
          ),
        );
        if (reessayer != true) return (ok: false, quantite: null);
      }
    }
  }

  Widget _buildCumulContent(String productName, int oldQty, int newQty) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Produit : $productName"),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Déjà en base :"),
          Text("$oldQty",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Votre saisie :"),
          Text("$newQty",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
        ]),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("TOTAL :",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text("${oldQty + newQty}",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue))
        ]),
        const SizedBox(height: 15),
        const Text("Voulez-vous ADDITIONNER ?",
            style: TextStyle(fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _buildQuickDialogTitle(Product product, AppConfig appConfig, {int? dejaCompte, int? correction}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Saisie Rapide',
            style: TextStyle(fontSize: 14, color: Colors.grey)),
        if (correction != null)
          Container(
            key: const ValueKey('bandeau-correction'),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
            child: Text('Correction : saisie actuelle $correction (la nouvelle quantité la remplace)',
                style: TextStyle(fontSize: 13, color: Colors.blue.shade900, fontWeight: FontWeight.bold)),
          )
        else if (dejaCompte != null)
          Container(
            key: const ValueKey('bandeau-deja-compte'),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(6)),
            child: Text(
                appConfig.isCumulEnabled
                    ? 'Déjà compté : $dejaCompte — Remplacer ou Ajouter vous sera demandé'
                    : 'Déjà compté : $dejaCompte — votre saisie le remplacera',
                style: const TextStyle(fontSize: 13, color: Color(0xFF7A4B00), fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 4),
        Text(product.produitName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text('CIP: ${product.produitCip}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        if (product.locationLabel != null)
          Text('(${product.locationLabel})',
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.blueGrey,
                  fontStyle: FontStyle.italic)),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('PA: ${product.produitPrixAchat.toStringAsFixed(0)} F',
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold)),
          Text('PV: ${product.produitPrixUni.toStringAsFixed(0)} F',
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold))
        ]),
        const SizedBox(height: 4),
        Visibility(
            visible: appConfig.showTheoreticalStock,
            child: Text('Stock Théo: ${product.quantiteInitiale}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: product.quantiteInitiale < 0
                        ? Colors.red
                        : Colors.green))),
      ],
    );
  }

  /// Saisie rapide : la quantité est écrite dans la file persistante (même sans rayon choisi) avant
  /// tout envoi. Chaque scan ajoute sa saisie à la file : aucune ne remplace celle d'un autre produit.
  Future<bool> _saveScannedQuantity(Product product, int quantity) async {
    final provider = Provider.of<EntryProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    product.quantiteSaisie = quantity;

    try {
      await provider.updateSpecificProduct(product, widget.inventoryId);
    } catch (e) {
      if (mounted) _showNotification('Enregistrement impossible sur l\'appareil : $e', Colors.red);
      return false;
    }

    if (mounted) {
      _showNotification(
          'Saisie enregistrée : ${product.produitName}', Colors.green);
    }
    if (appConfig.sendMode == SendMode.direct) {
      _envoyerDirect(product);
    }
    return true;
  }

  void _selectProduct(Product product) {
    _produitsVus[product.id] = product;
    _openQuickEntryDialog(product, dejaCompte: _dejaCompteConnu(product));
  }

  void _showLocationSelector(BuildContext context, EntryProvider provider) {
    provider.loadRayonStatuses(_apiService, widget.inventoryId);

    showDialog(
      context: context,
      builder: (ctx) {
        List<Rayon> filteredRayons = provider.rayons;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Choisir un emplacement'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                          labelText: 'Rechercher un rayon',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder()),
                      onChanged: (value) {
                        setState(() {
                          filteredRayons = provider.rayons
                              .where((r) => r.displayName
                              .toLowerCase()
                              .contains(value.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Consumer<EntryProvider>(
                          builder: (context, entryProvider, child) {
                            return filteredRayons.isEmpty
                                ? const Center(
                                child: Text("Aucun emplacement trouvé"))
                                : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredRayons.length,
                              itemBuilder: (ctx, index) {
                                final rayon = filteredRayons[index];
                                final isSelected = rayon.id ==
                                    entryProvider.selectedRayon?.id;

                                final int status =
                                    entryProvider.rayonStatuses[rayon.id] ??
                                        0;

                                Color bgColor;
                                IconData icon;
                                Color iconColor;

                                if (status == 2) {
                                  bgColor = Colors.green.shade100;
                                  icon = Icons.check_circle;
                                  iconColor = Colors.green;
                                } else if (status == 1) {
                                  bgColor = Colors.orange.shade100;
                                  icon = Icons.hourglass_bottom;
                                  iconColor = Colors.orange.shade800;
                                } else {
                                  bgColor = isSelected
                                      ? AppColors.primary.withOpacity(0.1)
                                      : Colors.transparent;
                                  icon = Icons.location_on;
                                  iconColor = isSelected
                                      ? AppColors.primary
                                      : Colors.grey;
                                }

                                return Container(
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    border: Border(
                                        bottom: BorderSide(
                                            color: Colors.grey.shade200)),
                                  ),
                                  child: ListTile(
                                    leading: Icon(icon, color: iconColor),
                                    title: Text(rayon.libelle,
                                        style: TextStyle(
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: Colors.black)),
                                    subtitle: Text(rayon.code,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600])),
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      _onLocationChanged(rayon);
                                    },
                                  ),
                                );
                              },
                            );
                          }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Annuler'))
              ],
            );
          },
        );
      },
    );
  }

  void _showFilterDialog(BuildContext context, EntryProvider provider) {
    final currentFilter = provider.activeFilter;
    final totalProducts = provider.totalProductsInRayon;
    final _fromNumController = TextEditingController(
        text: currentFilter.type == FilterType.numeric
            ? currentFilter.from
            : '');
    final _toNumController = TextEditingController(
        text:
        currentFilter.type == FilterType.numeric ? currentFilter.to : '');
    final _fromAlphaController = TextEditingController(
        text: currentFilter.type == FilterType.alphabetic
            ? currentFilter.from
            : '');
    final _toAlphaController = TextEditingController(
        text: currentFilter.type == FilterType.alphabetic
            ? currentFilter.to
            : '');
    FilterType selectedType = currentFilter.type;

    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setPopupState) {
            return AlertDialog(
                title: const Text('Appliquer un filtre'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      RadioListTile<FilterType>(
                          title: const Text('Intervalle numérique'),
                          value: FilterType.numeric,
                          groupValue: selectedType,
                          onChanged: (val) =>
                              setPopupState(() => selectedType = val!)),
                      Row(children: [
                        Expanded(
                            child: TextFormField(
                                controller: _fromNumController,
                                decoration: const InputDecoration(
                                    labelText: 'De (N°)',
                                    border: OutlineInputBorder()),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(5)
                                ],
                                enabled: selectedType == FilterType.numeric)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextFormField(
                                controller: _toNumController,
                                decoration: const InputDecoration(
                                    labelText: 'À (N°)',
                                    border: OutlineInputBorder()),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(5)
                                ],
                                enabled: selectedType == FilterType.numeric))
                      ]),
                      const SizedBox(height: 16),
                      RadioListTile<FilterType>(
                          title: const Text('Intervalle alphabétique'),
                          value: FilterType.alphabetic,
                          groupValue: selectedType,
                          onChanged: (val) =>
                              setPopupState(() => selectedType = val!)),
                      Row(children: [
                        Expanded(
                            child: TextFormField(
                                controller: _fromAlphaController,
                                decoration: const InputDecoration(
                                    labelText: 'De (Texte)',
                                    border: OutlineInputBorder()),
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(3)
                                ],
                                enabled: selectedType == FilterType.alphabetic)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextFormField(
                                controller: _toAlphaController,
                                decoration: const InputDecoration(
                                    labelText: 'À (Texte)',
                                    border: OutlineInputBorder()),
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(3)
                                ],
                                enabled: selectedType == FilterType.alphabetic))
                      ])
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Annuler')),
                  ElevatedButton(
                      child: const Text('Appliquer'),
                      onPressed: () {
                        ProductFilter newFilter = ProductFilter();
                        if (selectedType == FilterType.numeric) {
                          int from = int.tryParse(_fromNumController.text) ?? 0;
                          int to = int.tryParse(_toNumController.text) ?? 0;
                          if (from <= 0) from = 1;
                          if (to > totalProducts) to = totalProducts;
                          if (to == 0) to = totalProducts;
                          if (from > to) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Erreur : "De" doit être inférieur à "À"'),
                                    backgroundColor: Colors.red));
                            return;
                          }
                          newFilter = ProductFilter(
                              type: FilterType.numeric,
                              from: from.toString(),
                              to: to.toString());
                        } else if (selectedType == FilterType.alphabetic) {
                          String from = _fromAlphaController.text.toUpperCase();
                          String to = _toAlphaController.text.toUpperCase();
                          if (from.isEmpty || to.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Erreur : Les champs ne peuvent pas être vides'),
                                    backgroundColor: Colors.red));
                            return;
                          }
                          if (from.compareTo(to) > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Erreur : "De" doit être alphabétiquement avant "À"'),
                                    backgroundColor: Colors.red));
                            return;
                          }
                          newFilter = ProductFilter(
                              type: FilterType.alphabetic,
                              from: from,
                              to: to);
                        }

                        provider.applyFilter(newFilter, widget.inventoryId);
                        Navigator.of(ctx).pop();
                      })
                ]);
          });
        });
  }

  void _showJumpDialog(EntryProvider provider) {
    final TextEditingController jumpController = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
              title: const Text('Aller au produit'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Entrez une position (ex: 45), un nom ou un code :"),
                const SizedBox(height: 10),
                TextField(
                    controller: jumpController,
                    inputFormatters: SaisieInput.rechercheFormatters,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Position, Nom ou Code',
                        prefixIcon: Icon(Icons.directions)),
                    onSubmitted: (_) =>
                        _performJump(ctx, provider, jumpController.text))
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Annuler')),
                ElevatedButton(
                    onPressed: () =>
                        _performJump(ctx, provider, jumpController.text),
                    child: const Text('Aller'))
              ]);
        });
  }

  void _performJump(
      BuildContext dialogContext, EntryProvider provider, String input) {
    if (input.isEmpty) return;
    Navigator.of(dialogContext).pop();
    final products = provider.products;
    int targetIndex = -1;
    if (RegExp(r'^\d+$').hasMatch(input)) {
      int pos = int.parse(input);
      if (pos > 0 && pos <= products.length) {
        targetIndex = pos - 1;
      }
    }
    if (targetIndex == -1) {
      targetIndex = products.indexWhere((p) =>
      p.produitCip.contains(input) ||
          p.produitName.toLowerCase().contains(input.toLowerCase()));
    }
    if (targetIndex != -1) {
      final targetProduct = products[targetIndex];

      provider.jumpToProduct(targetProduct, widget.inventoryId);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Position ${targetIndex + 1} : ${targetProduct.produitName}'),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun produit trouvé.'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleExitSecurity,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async { if (await _handleExitSecurity()) Navigator.pop(context); }
            ),
            title: Text(widget.isQuickMode
                ? 'Scan'
                : 'Saisie Inventaire'),
            actions: [
              Consumer<EntryProvider>(
                builder: (context, provider, child) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: !provider.inventaireAJour
                        ? const Tooltip(
                      message: "Envoi au serveur...",
                      child: Icon(Icons.cloud_upload, color: Colors.orangeAccent),
                    )
                        : const Tooltip(
                      message: "Serveur à jour",
                      child: Icon(Icons.cloud_done, color: Colors.greenAccent),
                    ),
                  );
                },
              ),
              IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Envoyer les données',
                  onPressed: _sendDataToServer),
              IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'Historique des cumuls',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CumulHistoryScreen()));
                  }),
              if (widget.isQuickMode)
                Consumer<EntryProvider>(
                  builder: (context, provider, child) => IconButton(
                    icon: const Icon(Icons.file_download),
                    tooltip: 'Exporter la session (CSV)',
                    onPressed: () => _exportProductsToCsv(
                        _saisiesDeLInventaire(), "Saisie_Rapide"),
                  ),
                ),
              Consumer<EntryProvider>(builder: (context, provider, child) {
                if (provider.selectedRayon == null)
                  return const SizedBox.shrink();
                return Row(children: [
                  IconButton(
                      icon: const Icon(Icons.list_alt_outlined),
                      tooltip: 'Récapitulatif',
                      onPressed: () {
                        _navigateToRecap();
                      }),
                  IconButton(
                      icon: const Icon(Icons.edit_note_outlined),
                      tooltip: 'Correction écarts',
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => VarianceScreen(
                                inventoryId: widget.inventoryId,
                                rayonId: provider.selectedRayon!.id,
                                rayonName: provider.selectedRayon!.libelle)));
                      })
                ]);
              })
            ]),
        body: Consumer<EntryProvider>(
          builder: (context, provider, child) {
            bool showLocationSelector = !widget.isQuickMode;
            bool showSearchAndBody =
                widget.isQuickMode || provider.selectedRayon != null;
            if (provider.error != null) {
              // Échec de chargement : message clair + Réessayer / Se reconnecter (avant : texte rouge
              // seul à la place de l'écran, sans moyen de relancer).
              return LoadErrorView.depuis(provider.errorObject ?? provider.error!, onRetry: () {
                final rayon = provider.selectedRayon;
                if (rayon != null) {
                  provider.fetchProducts(_apiService, widget.inventoryId, rayon.id);
                } else {
                  provider.fetchRayons(_apiService, widget.inventoryId);
                }
              });
            }
            if (provider.isLoading &&
                provider.rayons.isEmpty &&
                !widget.isQuickMode) {
              return const Center(child: CircularProgressIndicator());
            }

            final currentProduct = provider.currentProduct;
            if (!widget.isQuickMode &&
                currentProduct != null &&
                currentProduct.id != _lastDisplayedProductId) {
              _lastDisplayedProductId = currentProduct.id;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _quantityController.clear();
                  _reprendreFocusScan();
                }
              });
            }
            if (provider.hasPendingSession) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showPendingDataDialog();
              });
            }

            return Column(
              children: [
                if (showLocationSelector)
                  Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: Colors.grey.shade300)),
                      child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                              borderRadius: BorderRadius.circular(8.0),
                              onTap: () =>
                                  _showLocationSelector(context, provider),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12.0, vertical: 16.0),
                                  child: Row(children: [
                                    const Icon(Icons.touch_app_outlined,
                                        color: AppColors.primary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(
                                            provider.selectedRayon?.libelle ??
                                                'Sélectionner un emplacement',
                                            style: TextStyle(
                                                color: provider.selectedRayon ==
                                                    null
                                                    ? Colors.grey.shade700
                                                    : AppColors.primary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis)),
                                    if (provider.selectedRayon != null)
                                      IconButton(
                                        icon: const Icon(Icons.file_download,
                                            color: Colors.blue),
                                        tooltip: "Exporter le rayon (CSV)",
                                        onPressed: () => _exportProductsToCsv(
                                            provider.allProducts,
                                            "Rayon_${provider.selectedRayon!.libelle}"),
                                      ),
                                    if (provider.selectedRayon == null)
                                      const Icon(Icons.arrow_drop_down,
                                          color: AppColors.primary)
                                  ]))))),
                if (showSearchAndBody)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                      child: Row(children: [
                        Expanded(
                            // Champ de scan : garde le focus, sans clavier à l'écran (icône ⌨ pour
                            // chercher par nom). La douchette n'y est jamais perdue.
                            child: ChampDouchette(
                                key: const ValueKey('champ-scan'),
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                autofocus: true,
                                label: 'Rechercher / Scanner',
                                hint: widget.isQuickMode ? 'Scannez le produit suivant' : 'Scan ou recherche',
                                onCode: (texte) {
                                  // Clavier à l'écran : texte tapé → recherche (un code tapé suit le chemin du scan).
                                  if (_clavierTexte && !CodeScan.ressembleACode(texte)) {
                                    _handleScanOrSearch(texte, fromTyping: false);
                                  } else {
                                    _recevoirCode(texte);
                                  }
                                },
                                onTexte: _onSearchChanged,
                                onClavier: (v) => setState(() {
                                  _clavierTexte = v;
                                  _isSearching = _searchFocusNode.hasFocus && v;
                                  if (!v) {
                                    _showSearchResults = false;
                                    _filteredProducts = [];
                                  }
                                }))),
                        if (!widget.isQuickMode) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(12),
                                  minimumSize: Size.zero),
                              onPressed: provider.selectedRayon == null
                                  ? null
                                  : () => _showFilterDialog(context, provider),
                              child: const Icon(Icons.filter_alt_outlined)),
                          const SizedBox(width: 8),
                          OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(12),
                                  minimumSize: Size.zero),
                              onPressed: (provider.selectedRayon == null ||
                                  !provider.activeFilter.isActive)
                                  ? null
                                  : () => provider.applyFilter(
                                  ProductFilter(type: FilterType.none), widget.inventoryId),
                              child: const Icon(Icons.delete_outline))
                        ]
                      ])),
                const Divider(height: 1, thickness: 1),
                if (showSearchAndBody)
                  Expanded(
                      child: Stack(children: [
                        // Scan continu : journal des 10 dernières saisies (maquette B), quel que soit
                        // le résultat du dernier scan.
                        if (widget.isQuickMode)
                          ListenableBuilder(
                            listenable: _fileScans,
                            builder: (context, _) => Column(children: [
                              if (provider.isLoading)
                                const LinearProgressIndicator(minHeight: 2)
                              else
                                const SizedBox(height: 2),
                              Expanded(
                                child: JournalScans(
                                  inventaireId: widget.inventoryId,
                                  sansSaisie: _sansSaisie,
                                  scansEnAttente: _fileScans.enAttente,
                                  onCorriger: _corrigerSaisie,
                                  onRelancer: (c) {
                                    setState(() => _sansSaisie.remove(c));
                                    _recevoirCode(c.code);
                                  },
                                ),
                              ),
                            ]),
                          )
                        else
                        (provider.isLoading && provider.products.isEmpty)
                            ? const Center(child: CircularProgressIndicator())
                            : (provider.products.isEmpty ||
                            provider.currentProduct == null)
                            ? Center(
                            child: Text(provider.activeFilter.isActive
                                ? 'Aucun produit correspondant au filtre.'
                                : 'Aucun produit dans cet emplacement.'))
                            : buildProductView(provider),
                        if (_showSearchResults)
                          Container(
                              color: AppColors.background.withOpacity(0.98),
                              child: _filteredProducts.isEmpty
                                  ? const Center(
                                  child: Text("Aucun produit trouvé"))
                                  : ListView.builder(
                                  itemCount: _filteredProducts.length,
                                  itemBuilder: (context, index) {
                                    final product = _filteredProducts[index];
                                    final appConfig = Provider.of<AppConfig>(
                                        context,
                                        listen: false);
                                    return Card(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        child: ListTile(
                                            title: Text(product.produitName,
                                                maxLines: 1,
                                                overflow:
                                                TextOverflow.ellipsis),
                                            subtitle: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  Text(appConfig
                                                      .showTheoreticalStock
                                                      ? 'CIP: ${product.produitCip} / Stock Théo: ${product.quantiteInitiale}'
                                                      : 'CIP: ${product.produitCip}'),
                                                  Text(
                                                      'Prix Vente: ${product.produitPrixUni.toStringAsFixed(0)} F',
                                                      style: TextStyle(
                                                          color: Colors
                                                              .grey.shade800,
                                                          fontWeight:
                                                          FontWeight.w500))
                                                ]),
                                            onTap: () =>
                                                _selectProduct(product)));
                                  }))
                      ])),
                if (showSearchAndBody && !widget.isQuickMode && !_isSearching)
                  NumericKeyboard(onKeyPressed: _onKeyPressed),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNotificationArea() {
    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _notificationMessage == null
            ? const SizedBox(height: 48, key: ValueKey('empty'))
            : Container(
            key: const ValueKey('notification'),
            height: 48,
            child: Center(
                child: Text(_notificationMessage!,
                    style: TextStyle(
                        color: _notificationColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)))));
  }

  Widget buildProductView(EntryProvider provider) {
    final Product product = provider.currentProduct!;
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isSmallScreen = screenHeight < 700;

    double stockFontSize = isSmallScreen ? 14 : 16;
    double titleFontSize = isSmallScreen ? 14 : 16;
    double priceFontSize = isSmallScreen ? 13 : 16;
    double quantityFontSize = isSmallScreen ? 22 : 26;
    double buttonSize = isSmallScreen ? 56 : 64;
    double buttonIconSize = isSmallScreen ? 28 : 30;

    const double lineHeightMultiplier = 1.3;
    final double fixedTitleHeight = titleFontSize * lineHeightMultiplier * 2;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      children: [
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Builder(builder: (context) {
            int currentGlobalIndex =
            provider.allProducts.indexWhere((p) => p.id == product.id);
            int displayIndex = (currentGlobalIndex != -1)
                ? currentGlobalIndex
                : provider.currentProductIndex;
            return Text(
                '${displayIndex + 1} / ${provider.totalProductsInRayon}',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: stockFontSize));
          }),
          if (provider.activeFilter.isActive)
            Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(
                    'Filtré${_getFilterDisplay(provider.activeFilter)} : ${provider.currentProductIndex + 1}/${provider.totalProducts}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue))),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: fixedTitleHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${product.produitCip} - ${product.produitName}',
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  height: lineHeightMultiplier,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('PA: ${product.produitPrixAchat} F',
              style: TextStyle(fontSize: priceFontSize, color: Colors.orange)),
          Text('PV: ${product.produitPrixUni} F',
              style: TextStyle(
                  fontSize: priceFontSize, color: AppColors.accent))
        ]),
        const SizedBox(height: 8),

        // --- BLOC : STOCK THÉORIQUE ET QUANTITÉ SAISIE ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Consumer<AppConfig>(builder: (context, appConfig, child) {
              return Visibility(
                  visible: appConfig.showTheoreticalStock,
                  child: Text('Stock Théo: ${product.quantiteInitiale}',
                      style: TextStyle(
                          fontSize: stockFontSize,
                          fontWeight: FontWeight.bold,
                          color: product.quantiteInitiale < 0
                              ? Colors.red.shade700
                              : const Color(0xFF1B5E20))));
            }),
            Builder(builder: (context) {
              final isTouched = product.dtUpdated != null || provider.isProductTouched(product.id);
              if (isTouched) {
                return Text('Compté : ${product.quantiteSaisie}',
                    style: TextStyle(
                        fontSize: stockFontSize,
                        fontWeight: FontWeight.w900,
                        color: Colors.blue));
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
        // --------------------------------------------------------

        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    side: const BorderSide(color: Colors.deepPurple, width: 2),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => provider.previousProduct(widget.inventoryId),
                  child: Icon(Icons.chevron_left,
                      size: buttonIconSize, color: Colors.deepPurple))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: _quantityController,
                  focusNode: _quantityFocusNode,
                  textAlign: TextAlign.center,
                  readOnly: true,
                  style: TextStyle(
                      fontSize: quantityFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple),
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), labelText: 'Quantité'))),
          const SizedBox(width: 8),
          SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    side: const BorderSide(color: Colors.blue, width: 2),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _showJumpDialog(provider),
                  child: Icon(Icons.find_in_page,
                      size: buttonIconSize * 0.9, color: Colors.blue)))
        ]),
        _buildNotificationArea(),
      ],
    );
  }
}

/// Libère des contrôleurs quand le widget quitte l'écran (fenêtre fermée, animation terminée).
class _Liberer extends StatefulWidget {
  final List<ChangeNotifier> objets;
  final Widget child;
  const _Liberer({required this.objets, required this.child});

  @override
  State<_Liberer> createState() => _LibererState();
}

class _LibererState extends State<_Liberer> {
  @override
  void dispose() {
    for (final o in widget.objets) {
      o.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
