import 'dart:typed_data';
import 'dart:ui' as ui; // Gardez l'alias 'ui' s'il est utilisé ailleurs, sinon il peut être enlevé
import 'package:flutter/material.dart'; // Ajouté pour Colors, Theme, etc.
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw; // pw est un alias commun pour pdf/widgets
import 'package:printing/printing.dart';
import 'package:provider/provider.dart'; // Supposant que vous l'utilisez comme dans recap_screen
import 'package:intl/intl.dart';      // Pour NumberFormat
import 'package:fl_chart/fl_chart.dart'; // Supposant que vous utilisez fl_chart pour PieChart

// Supposons que ces modèles existent et sont correctement importés
import '../models/inventory.dart';
import '../models/rayon.dart';
import '../models/product.dart'; // Assurez-vous que ce Product a les propriétés nécessaires
import '../api/api_service.dart';
import '../providers/auth_provider.dart';
import '../config/app_config.dart';


class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late ApiService _apiService;
  final NumberFormat numberFormat = NumberFormat.currency(locale: 'fr_FR', symbol: 'F', decimalDigits: 0);

  // Clé pour capturer le widget du graphique en tant qu'image
  final GlobalKey _chartKey = GlobalKey();

  List<Inventory> _inventories = [];
  Inventory? _selectedInventory;
  List<Rayon> _rayons = [];
  Rayon? _selectedRayon;
  List<Product> _products = [];
  bool _isLoading = false;

  // Variables pour les statistiques
  int _positiveCount = 0;
  int _negativeCount = 0;
  int _correctCount = 0;

  // Variables pour la valorisation
  double _valeurStockAvant = 0;
  double _valeurStockApres = 0;
  double _valeurEcart = 0;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _apiService = ApiService(
      baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl,
      sessionCookie: authProvider.sessionCookie,
    );
    _fetchInventories();
  }

  Future<void> _fetchInventories() async {
    setState(() => _isLoading = true);
    try {
      _inventories = await _apiService.fetchInventories(maxResult: 100);
    } catch (e) {
      if (mounted) { // CORRIGÉ : Accolades ajoutées
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur de chargement des inventaires: $e"), backgroundColor: Colors.red));
      }
    }
    if (mounted) { // CORRIGÉ : Accolades ajoutées
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchRayons(String inventoryId) async {
    setState(() { _isLoading = true; _rayons = []; _selectedRayon = null; _clearAnalysis(); });
    try {
      _rayons = await _apiService.fetchRayons(inventoryId);
    } catch (e) {
      if (mounted) { // CORRIGÉ : Accolades ajoutées
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur de chargement des emplacements: $e"), backgroundColor: Colors.red));
      }
    }
    if (mounted) { // CORRIGÉ : Accolades ajoutées
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchProductsAndAnalyze(String inventoryId, String rayonId) async {
    setState(() { _isLoading = true; _clearAnalysis(); });
    try {
      _products = await _apiService.fetchProducts(inventoryId, rayonId);
      _performAnalysis(_products);
    } catch (e) {
      if (mounted) { // CORRIGÉ : Accolades ajoutées
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur de chargement des produits: $e"), backgroundColor: Colors.red));
      }
    }
    if (mounted) { // CORRIGÉ : Accolades ajoutées
      setState(() => _isLoading = false);
    }
  }

  void _clearAnalysis() {
    setState(() {
      _products = [];
      _positiveCount = 0;
      _negativeCount = 0;
      _correctCount = 0;
      _valeurStockAvant = 0;
      _valeurStockApres = 0;
      _valeurEcart = 0;
    });
  }

  void _performAnalysis(List<Product> products) {
    if (products.isEmpty) { // CORRIGÉ : Accolades ajoutées
      return;
    }

    int pos = 0, neg = 0, correct = 0;
    double valAvant = 0, valApres = 0;

    for (final product in products) {
      // Assurez-vous que votre modèle Product a bien ces propriétés
      final ecart = product.quantiteSaisie - product.quantiteInitiale;
      if (ecart > 0) { // CORRIGÉ : Accolades ajoutées (ligne originale 116 approx.)
        pos++;
      } else if (ecart < 0) { // CORRIGÉ : Accolades ajoutées
        neg++;
      } else { // CORRIGÉ : Accolades ajoutées
        correct++;
      }

      valAvant += product.quantiteInitiale * product.produitPrixAchat;
      valApres += product.quantiteSaisie * product.produitPrixAchat;
    }

    if (mounted) {
      setState(() {
        _positiveCount = pos;
        _negativeCount = neg;
        _correctCount = correct;
        _valeurStockAvant = valAvant;
        _valeurStockApres = valApres;
        _valeurEcart = valApres - valAvant;
      });
    }
  }

  /// Génère le document PDF de l'analyse et lance l'impression.
  Future<void> _printAnalysis() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Préparation du PDF...')));

    // 1. Capturer le graphique en tant qu'image
    final boundary = _chartKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0); // Augmenter pixelRatio pour une meilleure qualité
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la capture du graphique.'), backgroundColor: Colors.red,));
      }
      return;
    }
    final Uint8List pngBytes = byteData.buffer.asUint8List();
    final chartImage = pw.MemoryImage(pngBytes);

    // 2. Créer le document PDF
    final doc = pw.Document();

    final total = _products.length;
    final double positiveRate = total > 0 ? (_positiveCount / total) * 100 : 0;
    final double negativeRate = total > 0 ? (_negativeCount / total) * 100 : 0;
    final double correctRate = total > 0 ? (_correctCount / total) * 100 : 0;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 0, text: 'Rapport d\'Analyse d\'Inventaire',
                  textStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Inventaire: ${_selectedInventory?.libelle ?? 'N/A'}'),
              pw.Text('Emplacement: ${_selectedRayon?.displayName ?? 'N/A'}'),
              pw.Divider(height: 20, thickness: 1),

              pw.Header(level: 1, text: 'Valorisation de l\'inventaire'),
              pw.Text('Valeur Avant: ${numberFormat.format(_valeurStockAvant)}'),
              pw.Text('Valeur Après: ${numberFormat.format(_valeurStockApres)}'),
              pw.Text('Écart Total: ${numberFormat.format(_valeurEcart)}',
                  style: pw.TextStyle(color: _valeurEcart >= 0 ? PdfColors.green : PdfColors.red, fontWeight: pw.FontWeight.bold)
              ),
              pw.SizedBox(height: 20),

              pw.Header(level: 1, text: 'Répartition des Écarts (Quantité d\'articles)'),
              pw.Center(
                child: pw.SizedBox(
                  width: 250, // Ajustez la taille si nécessaire
                  height: 250,
                  child: pw.Image(chartImage),
                ),
              ),
              pw.SizedBox(height: 20),

              // CORRIGÉ : Utilisation de TableHelper.fromTextArray
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignments: { // Alignements spécifiques par colonne
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                },
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                },
                border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                data: <List<String>>[ // Type explicite pour la liste de listes
                  <String>['Catégorie', 'Nombre d\'articles', 'Pourcentage'],
                  <String>['Écarts Positifs', '$_positiveCount', '${positiveRate.toStringAsFixed(1)}%'],
                  <String>['Écarts Négatifs', '$_negativeCount', '${negativeRate.toStringAsFixed(1)}%'],
                  <String>['Stocks Corrects', '$_correctCount', '${correctRate.toStringAsFixed(1)}%'],
                ],
              ),
            ],
          );
        },
      ),
    );

    // 3. Lancer l'impression
    try {
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
      if(mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur lors de l'impression PDF: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyse des Inventaires'),
        actions: [
          if (_products.isNotEmpty) // Condition pour afficher le bouton
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimer l\'analyse',
              onPressed: _printAnalysis, // Appel direct
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Pour étirer les Dropdown
          children: [
            _buildSelectors(),
            const SizedBox(height: 24),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_products.isNotEmpty)
              Expanded(child: _buildResults())
            else
              const Expanded(child: Center(child: Text('Veuillez sélectionner un inventaire et un emplacement.'))),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectors() {
    return Column(
      children: [
        DropdownButtonFormField<Inventory>(
          value: _selectedInventory,
          hint: const Text('Choisir un inventaire'),
          isExpanded: true,
          items: _inventories.map((inv) => DropdownMenuItem(value: inv, child: Text(inv.libelle))).toList(),
          onChanged: (Inventory? newValue) {
            if (newValue != null) {
              setState(() => _selectedInventory = newValue);
              _fetchRayons(newValue.id);
            }
          },
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Rayon>(
          value: _selectedRayon,
          hint: const Text('Choisir un emplacement'),
          isExpanded: true,
          items: _rayons.map((rayon) => DropdownMenuItem(value: rayon, child: Text(rayon.displayName))).toList(),
          onChanged: (Rayon? newValue) {
            if (newValue != null && _selectedInventory != null) {
              setState(() => _selectedRayon = newValue);
              _fetchProductsAndAnalyze(_selectedInventory!.id, newValue.id);
            }
          },
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final total = _products.length;
    final double positiveRate = total > 0 ? (_positiveCount / total) * 100 : 0;
    final double negativeRate = total > 0 ? (_negativeCount / total) * 100 : 0;
    final double correctRate = total > 0 ? (_correctCount / total) * 100 : 0;
    final Color ecartColor = _valeurEcart >= 0 ? Colors.green.shade700 : Colors.red.shade700;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView( // Permet le défilement si le contenu dépasse
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Analyse de l\'emplacement: ${_selectedRayon?.displayName ?? 'N/A'}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            'Nombre total d\'articles analysés: $total',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildValueCard('Valeur Avant', _valeurStockAvant, colorScheme.secondary)),
              const SizedBox(width: 8),
              Expanded(child: _buildValueCard('Valeur Après', _valeurStockApres, colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 8),
          _buildValueCard('Écart Total', _valeurEcart, ecartColor, isFullWidth: true),
          const Divider(height: 30, thickness: 1),
          Text(
            'Répartition des Articles par Écart',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          RepaintBoundary(
            key: _chartKey,
            child: Container( // Enveloppez le PieChart dans un Container pour lui donner un fond si nécessaire pour la capture
              color: Theme.of(context).scaffoldBackgroundColor, // ou Colors.white pour un fond blanc sur l'image
              padding: const EdgeInsets.all(8.0),
              height: 220, // Hauteur ajustée
              child: _buildPieChart(positiveRate, negativeRate, correctRate),
            ),
          ),
          const SizedBox(height: 24),
          _buildLegend('Écarts Positifs', _positiveCount, positiveRate, Colors.green.shade700),
          _buildLegend('Écarts Négatifs', _negativeCount, negativeRate, Colors.red.shade700),
          _buildLegend('Stocks Corrects', _correctCount, correctRate, Colors.blue.shade700),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildValueCard(String title, double value, Color color, {bool isFullWidth = false}) {
    return Card(
      elevation: 2,
      color: color.withAlpha((0.15 * 255).round()), // Utilisation de withAlpha
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            const SizedBox(height: 8),
            Text(
              numberFormat.format(value),
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(double pos, double neg, double correct) {
    if (pos == 0 && neg == 0 && correct == 0) { // Condition plus stricte
      return const Center(child: Text('Aucune donnée à afficher dans le graphique.'));
    }
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          if (pos > 0) PieChartSectionData( // Afficher seulement si la valeur > 0
            color: Colors.green.shade600,
            value: pos,
            title: '${pos.toStringAsFixed(1)}%',
            radius: 55, // Rayon ajusté
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(blurRadius: 2, color: Colors.black38)]),
          ),
          if (neg > 0) PieChartSectionData(
            color: Colors.red.shade600,
            value: neg,
            title: '${neg.toStringAsFixed(1)}%',
            radius: 55,
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(blurRadius: 2, color: Colors.black38)]),
          ),
          if (correct > 0) PieChartSectionData(
            color: Colors.blue.shade600,
            value: correct,
            title: '${correct.toStringAsFixed(1)}%',
            radius: 55,
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(blurRadius: 2, color: Colors.black38)]),
          ),
        ],
        pieTouchData: PieTouchData(
          touchCallback: (FlTouchEvent event, pieTouchResponse) {
            // Vous pouvez gérer les interactions ici si nécessaire
          },
        ),
      ),
    );
  }

  Widget _buildLegend(String title, int count, double percentage, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: Row(
        children: [
          Container(width: 16, height: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
          Text('$count (${percentage.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}