// lib/screens/recap_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Imports pour la génération PDF et l'impression
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Imports pour la génération et le partage du CSV
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';


class RecapScreen extends StatefulWidget {
  final String inventoryId;
  final String rayonId;
  final String rayonName;
  // Paramètre optionnel pour recevoir les données pré-chargées
  final List<Product>? preloadedProducts;

  const RecapScreen({
    super.key,
    required this.inventoryId,
    required this.rayonId,
    required this.rayonName,
    this.preloadedProducts,
  });

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  late Future<List<Product>> _productsFuture;
  // Variables d'état pour stocker les totaux calculés
  double _totalAchat = 0;
  double _totalVente = 0;
  double _totalEcartValorise = 0;
  late ApiService _apiService;

  // Variable pour empêcher le double-clic et le plantage ANR
  bool _isPrinting = false;

  // Formatteur de nombres pour un affichage plus lisible
  final numberFormat = NumberFormat.currency(locale: 'fr_FR', symbol: 'F', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
      baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );

    // Logique hybride (Pré-chargé OU Téléchargement)
    if (widget.preloadedProducts != null) {
      // On utilise le '!' car on a vérifié que ce n'est pas null
      _productsFuture = Future.value(widget.preloadedProducts!).then((products) {
        if (mounted) {
          _calculateTotals(products);
        }
        return products;
      });
    } else {
      // Sinon, on télécharge comme avant (comportement par défaut)
      _productsFuture = _apiService.fetchProducts(widget.inventoryId, widget.rayonId)
          .then((products) {
        if (mounted) {
          _calculateTotals(products);
        }
        return products;
      });
    }
  }

  /// Calcule tous les totaux nécessaires pour l'écran.
  void _calculateTotals(List<Product> products) {
    double tempAchat = 0, tempVente = 0, tempEcart = 0;
    for (var product in products) {
      tempAchat += product.quantiteSaisie * product.produitPrixAchat;
      tempVente += product.quantiteSaisie * product.produitPrixUni;
      tempEcart += (product.quantiteSaisie - product.quantiteInitiale) * product.produitPrixAchat;
    }
    if (mounted) {
      setState(() {
        _totalAchat = tempAchat;
        _totalVente = tempVente;
        _totalEcartValorise = tempEcart;
      });
    }
  }

  /// Génère le document PDF et lance l'impression avec protection anti-plantage.
  Future<void> _printRecap(List<Product> products) async {
    if (_isPrinting) return;

    setState(() {
      _isPrinting = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Génération du PDF..."),
            ],
          ),
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document();

      // Préparation des données pour le PDF
      final List<List<String>> tableData = [
        ['Désignation', 'Écart Qté', 'Stock Compté', 'Stock Théo.', 'Valorisation'],
        ...products.map((p) {
          final ecart = p.quantiteSaisie - p.quantiteInitiale;
          final valo = ecart * p.produitPrixAchat;
          return [
            p.produitName,
            ecart.toString(),
            p.quantiteSaisie.toString(),
            p.quantiteInitiale.toString(),
            numberFormat.format(valo)
          ];
        })
      ];

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (pw.Context context) => pw.Header(level: 0, text: 'Récapitulatif - ${widget.rayonName}'),
          footer: (pw.Context context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Page ${context.pageNumber} sur ${context.pagesCount}', style: const pw.TextStyle(fontSize: 10)),
          ),
          build: (pw.Context context) => [
            pw.Table.fromTextArray(
              data: tableData,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {1: pw.Alignment.center, 2: pw.Alignment.center, 3: pw.Alignment.center, 4: pw.Alignment.centerRight},
            ),
            pw.Divider(height: 30),
            pw.Text('Total Achat: ${numberFormat.format(_totalAchat)}'),
            pw.Text('Total Vente: ${numberFormat.format(_totalVente)}'),
            pw.Text('Total Écart Valorisé: ${numberFormat.format(_totalEcartValorise)}', style: pw.TextStyle(color: _totalEcartValorise >= 0 ? PdfColors.green : PdfColors.red, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'impression : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context).pop(); // Ferme le dialog de chargement
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  /// Crée le contenu textuel du fichier CSV selon le format demandé.
  String _generateCsvContent(List<Product> products) {
    final StringBuffer csvContent = StringBuffer();
    // Génération locale : CIP,Quantité
    for (final product in products) {
      csvContent.writeln('${product.produitCip},${product.quantiteSaisie}');
    }
    return csvContent.toString();
  }

  /// Génère le fichier localement et lance le menu de partage/sauvegarde.
  Future<void> _shareCsvFile(String csvContent) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

    // Nettoyage du nom du rayon pour le nom de fichier
    final cleanRayonName = widget.rayonName.replaceAll(RegExp(r'[^\w\s]+'),'').replaceAll(' ', '_');

    // Nom du fichier : inventaire_NOMRAYON_DATE_HEURE.csv
    final fileName = 'inventaire_${cleanRayonName}_$timestamp.csv';

    // Récupération du dossier temporaire de l'application
    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);

    // Écriture du fichier sur le disque du terminal
    await file.writeAsString(csvContent);

    // Ouverture du menu de partage (permet de sauvegarder, envoyer par mail, bluetooth...)
    final xFile = XFile(filePath);
    await Share.shareXFiles([xFile], text: 'Export CSV : ${widget.rayonName}');
  }

  /// Copie le contenu CSV dans le presse-papiers.
  void _copyCsvToClipboard(String csvContent) {
    Clipboard.setData(ClipboardData(text: csvContent));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contenu du CSV copié dans le presse-papiers !')),
    );
  }

  /// Affiche une boîte de dialogue pour choisir l'action d'export CSV.
  void _showExportDialog(List<Product> products) {
    final csvContent = _generateCsvContent(products);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exporter les données CSV'),
        content: const Text('Générer le fichier CSV à partir des données affichées ?'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copier le texte'),
            onPressed: () {
              Navigator.of(context).pop();
              _copyCsvToClipboard(csvContent);
            },
          ),
          // Bouton principal pour générer le fichier
          FilledButton.icon(
            icon: const Icon(Icons.file_download),
            label: const Text('Générer et Sauvegarder'),
            onPressed: () {
              Navigator.of(context).pop();
              _shareCsvFile(csvContent);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: Text('Récap: ${widget.rayonName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Exporter en CSV',
            onPressed: () {
              _productsFuture.then((products) {
                if(products.isNotEmpty) _showExportDialog(products);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer le récapitulatif',
            onPressed: _isPrinting
                ? null
                : () {
              _productsFuture.then((products) {
                if (products.isNotEmpty) _printRecap(products);
              });
            },
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('Erreur: ${snapshot.error}'));
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Aucun produit à afficher.'));
                final products = snapshot.data!;
                return SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 20,
                      columns: const [
                        DataColumn(label: Text('Désignation', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Écart Qté'), numeric: true),
                        DataColumn(label: Text('Stock Compté'), numeric: true),
                        DataColumn(label: Text('Stock Théo.'), numeric: true),
                        DataColumn(label: Text('Valorisation Écart', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                      ],
                      rows: products.map((product) {
                        final ecart = product.quantiteSaisie - product.quantiteInitiale;
                        final valorisationEcart = ecart * product.produitPrixAchat;
                        Color ecartColor = Colors.grey.shade700;
                        if (ecart > 0) {
                          ecartColor = Colors.green;
                        } else if (ecart < 0) ecartColor = Colors.red;

                        return DataRow(cells: [
                          DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 250), child: Text(product.produitName, overflow: TextOverflow.ellipsis))),
                          DataCell(Text(ecart.toString(), style: TextStyle(color: ecartColor, fontWeight: FontWeight.bold))),
                          DataCell(Text(product.quantiteSaisie.toString())),
                          DataCell(Text(product.quantiteInitiale.toString())),
                          DataCell(Text(numberFormat.format(valorisationEcart), style: TextStyle(color: ecartColor, fontWeight: FontWeight.bold))),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: primaryColor.withOpacity(0.1),
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTotalColumn('Total Achat', _totalAchat, Colors.orange),
                _buildTotalColumn('Total Vente', _totalVente, Colors.green),
                _buildTotalColumn('Total Écart', _totalEcartValorise, _totalEcartValorise >= 0 ? Colors.blue : Colors.red),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTotalColumn(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(numberFormat.format(value), style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}