// lib/screens/collection_screen.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'; // Pour gérer les permissions Android
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/models/collected_item.dart';
import 'package:prestinv/widgets/numeric_keyboard.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Imports pour l'impression PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _scanController = TextEditingController();
  final _scanFocusNode = FocusNode();

  // Liste locale des produits collectés
  List<CollectedItem> _items = [];
  bool _isLoading = false;

  // Variable pour empêcher le double-clic sur l'impression
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  // --- PERSISTANCE (Sauvegarde locale) ---
  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('collection_data');
    if (data != null) {
      final List<dynamic> jsonList = json.decode(data);
      setState(() {
        _items = jsonList.map((e) => CollectedItem.fromJson(e)).toList();
        // Tri par date décroissante (le dernier ajouté en haut)
        _items.sort((a, b) => b.dateScan.compareTo(a.dateScan));
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = json.encode(_items.map((e) => e.toJson()).toList());
    await prefs.setString('collection_data', data);
  }

  Future<void> _clearList() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vider la liste ?'),
        content: const Text('Attention, toutes les données collectées seront perdues.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Vider', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _items.clear();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('collection_data');
    }
  }

  // Suppression d'une ligne spécifique
  void _deleteItem(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la ligne ?'),
        content: Text('Code : ${_items[index].code}\nQuantité : ${_items[index].quantity}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // Ferme le dialog
              setState(() {
                _items.removeAt(index);
              });
              _saveItems(); // Sauvegarde la nouvelle liste

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ligne supprimée.'), duration: Duration(seconds: 1)),
              );
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- LOGIQUE MÉTIER ---

  void _handleScan(String code) {
    if (code.isEmpty) return;

    _openQuantityDialog(code);

    _scanController.clear();
    _scanFocusNode.requestFocus();
  }

  void _addItem(String code, int quantity) {
    setState(() {
      try {
        // Agrégation : Si le code existe déjà, on ajoute la quantité
        final existingItem = _items.firstWhere((item) => item.code == code);
        existingItem.quantity += quantity;
        // On le remonte en haut de liste pour visibilité
        _items.remove(existingItem);
        _items.insert(0, existingItem);
      } catch (e) {
        // Nouveau produit
        _items.insert(0, CollectedItem(
            code: code,
            quantity: quantity,
            dateScan: DateTime.now()
        ));
      }
    });
    _saveItems();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ajouté : $code (Qté: $quantity)'), duration: const Duration(seconds: 1), backgroundColor: Colors.green),
    );
  }

  // --- POPUP DE SAISIE ---
  void _openQuantityDialog(String code) {
    final qtyController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ajout Collecte', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('Code : $code', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent),
                  decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder()),
                  readOnly: true,
                  autofocus: true,
                  showCursor: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 280,
                  child: NumericKeyboard(
                    onKeyPressed: (key) {
                      if (key == 'OK') {
                        final int qty = int.tryParse(qtyController.text) ?? 0;
                        if (qty > 0) {
                          _addItem(code, qty);
                        }
                        Navigator.of(ctx).pop();
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (mounted) _scanFocusNode.requestFocus();
                        });
                      } else if (key == 'DEL') {
                        if (qtyController.text.isNotEmpty) {
                          qtyController.text = qtyController.text.substring(0, qtyController.text.length - 1);
                        }
                      } else {
                        qtyController.text += key;
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler', style: TextStyle(color: Colors.red))
            ),
          ],
        );
      },
    );
  }

  // --- EXPORT CSV AMÉLIORÉ ---
  Future<void> _exportCsv() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La liste est vide.')));
      return;
    }

    final StringBuffer csvContent = StringBuffer();
    csvContent.writeln('Code;Quantite;Date');
    for (final item in _items) {
      csvContent.writeln('${item.code};${item.quantity};${item.dateScan}');
    }

    // Format horodaté demandé
    final timestamp = DateFormat('ddMMyyyy_HHmm').format(DateTime.now());
    final fileName = 'inventaireCollection_$timestamp.csv';

    try {
      // 1. Demande de Permission
      bool hasPermission = false;
      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        if (status.isGranted) {
          hasPermission = true;
        } else if (await Permission.manageExternalStorage.request().isGranted) {
          hasPermission = true;
        }
      } else {
        hasPermission = true; // iOS géré autrement
      }

      bool directSuccess = false;

      // 2. Tentative d'écriture directe (Download)
      if (hasPermission) {
        try {
          final Directory downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            final String filePath = '${downloadDir.path}/$fileName';
            final File file = File(filePath);
            await file.writeAsString(csvContent.toString());
            directSuccess = true;
          }
        } catch (e) {
          print("Erreur écriture directe: $e");
        }
      }

      // 3. Résultat ou Fallback (Share)
      if (directSuccess) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Succès ! Fichier enregistré dans "Download" :\n$fileName'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            )
        );
      } else {
        // Fallback : On crée le fichier dans le cache de l'app et on le partage
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsString(csvContent.toString());

        final xFile = XFile(filePath);
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sauvegarde directe impossible (Permissions). Veuillez choisir où enregistrer.'), duration: Duration(seconds: 3))
        );

        await Share.shareXFiles([xFile], text: 'Export Inventaire $timestamp');
      }

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur export: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // --- IMPRESSION PDF ---
  Future<void> _printCollection() async {
    if (_isPrinting) return;
    setState(() { _isPrinting = true; });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Génération du PDF...")]),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document();

      final tableData = <List<String>>[
        ['Code', 'Quantité', 'Date Scan'],
        ..._items.map((item) => [
          item.code,
          item.quantity.toString(),
          DateFormat('dd/MM/yyyy HH:mm').format(item.dateScan),
        ])
      ];

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (context) => pw.Header(level: 0, text: 'Rapport de Collecte (Hors-ligne)'),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Page ${context.pageNumber} sur ${context.pagesCount}', style: const pw.TextStyle(fontSize: 10)),
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              context: context,
              data: tableData,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight
              },
            )
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (format) => doc.save());

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur impression: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() { _isPrinting = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mode Collecte (Hors-ligne)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Vider la liste',
            onPressed: _items.isEmpty ? null : _clearList,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer la liste',
            onPressed: (_items.isEmpty || _isPrinting) ? null : _printCollection,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Exporter CSV',
            onPressed: _items.isEmpty ? null : _exportCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _scanController,
              focusNode: _scanFocusNode,
              onSubmitted: _handleScan,
              textInputAction: TextInputAction.done,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Scanner un code',
                hintText: 'EAN, Code barre...',
                prefixIcon: const Icon(Icons.qr_code_scanner, size: 28),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _scanController.clear();
                    _scanFocusNode.requestFocus();
                  },
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('Aucune donnée collectée.', style: TextStyle(color: Colors.grey)),
                  const Text('Scannez des produits pour commencer.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
                : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text('${index + 1}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(item.code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(item.dateScan)),

                    // Affichage Quantité + Bouton Supprimer
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min, // Important pour ne pas prendre toute la largeur
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.accent)
                          ),
                          child: Text(
                            'Qté: ${item.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent, fontSize: 15),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Bouton Supprimer
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: "Supprimer cette ligne",
                          onPressed: () => _deleteItem(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}