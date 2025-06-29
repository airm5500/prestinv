// lib/screens/analysis_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

// Imports pour la génération PDF et l'impression
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late ApiService _apiService;
  final numberFormat = NumberFormat.currency(locale: 'fr_FR', symbol: 'F', decimalDigits: 0);

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
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur de chargement des inventaires: $e"), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchRayons(String inventoryId) async {
    setState(() { _isLoading = true; _rayons = []; _selectedRayon = null; _clearAnalysis(); });
    try {
      _rayons = await _apiService.fetchRayons(inventoryId);
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur de chargement des emplacements: $e"), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchProductsAndAnalyze(String inventoryId, String rayonId) async {
    setState(() { _isLoading = true; _clearAnalysis(); });
    try {
      _products = await _apiService.fetchProducts(inventoryId, rayonId);
      _performAnalysis(_products);
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur de chargement des produits: $e"), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _isLoading = false);
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
    if (products.isEmpty) return;

    int pos = 0, neg = 0, correct = 0;
    double valAvant = 0, valApres = 0;

    for (final product in products) {
      final ecart = product.quantiteSaisie - product.quantiteInitiale;
      if (ecart > 0) pos++;
      else if (ecart < 0) neg++;
      else correct++;

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
    // 1. Capturer le graphique en tant qu'image
    final boundary = _chartKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if(byteData == null) return;
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
              pw.Header(level: 0, text: 'Rapport d\'Analyse'),
              pw.Text('Inventaire: ${_selectedInventory?.libelle ?? 'N/A'}'),
              pw.Text('Emplacement: ${_selectedRayon?.displayName ?? 'N/A'}'),
              pw.Divider(height: 20),

              pw.Header(level: 1, text: 'Valorisation de l\'inventaire'),
              pw.Text('Valeur Avant: ${numberFormat.format(_valeurStockAvant)}'),
              pw.Text('Valeur Après: ${numberFormat.format(_valeurStockApres)}'),
              pw.Text('Écart Total: ${numberFormat.format(_valeurEcart)}',
                  style: pw.TextStyle(color: _valeurEcart >= 0 ? PdfColors.green : PdfColors.red, fontWeight: pw.FontWeight.bold)
              ),
              pw.SizedBox(height: 20),

              pw.Header(level: 1, text: 'Répartition des Écarts'),
              pw.Center(
                child: pw.SizedBox(
                  width: 250,
                  height: 250,
                  child: pw.Image(chartImage),
                ),
              ),
              pw.SizedBox(height: 20),

              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                data: [
                  ['Catégorie', 'Nombre d\'articles', 'Pourcentage'],
                  ['Écarts Positifs', '$_positiveCount', '${positiveRate.toStringAsFixed(1)}%'],
                  ['Écarts Négatifs', '$_negativeCount', '${negativeRate.toStringAsFixed(1)}%'],
                  ['Stocks Corrects', '$_correctCount', '${correctRate.toStringAsFixed(1)}%'],
                ],
              ),
            ],
          );
        },
      ),
    );

    // 3. Lancer l'impression
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyse des Inventaires'),
        actions: [
          if (_products.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimer l\'analyse',
              onPressed: _printAnalysis,
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
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
        ),
      ],
    );
  }

  Widget _buildResults() {
    final total = _products.length;
    final double positiveRate = total > 0 ? (_positiveCount / total) * 100 : 0;
    final double negativeRate = total > 0 ? (_negativeCount / total) * 100 : 0;
    final double correctRate = total > 0 ? (_correctCount / total) * 100 : 0;
    final ecartColor = _valeurEcart >= 0 ? Colors.green : Colors.red;

    return SingleChildScrollView(
      child: Column(
        children: [
          Text('Analyse de l\'emplacement: ${_selectedRayon?.displayName ?? ''}', style: Theme.of(context).textTheme.titleLarge),
          Text('Nombre total d\'articles: $total', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildValueCard('Valeur Avant', _valeurStockAvant, Colors.blueGrey)),
              const SizedBox(width: 8),
              Expanded(child: _buildValueCard('Valeur Après', _valeurStockApres, Colors.blue)),
            ],
          ),
          const SizedBox(height: 8),
          _buildValueCard('Écart Total', _valeurEcart, ecartColor, isFullWidth: true),
          const Divider(height: 40),
          RepaintBoundary(
            key: _chartKey,
            child: SizedBox(
              height: 200,
              child: _buildPieChart(positiveRate, negativeRate, correctRate),
            ),
          ),
          const SizedBox(height: 24),
          _buildLegend('Écarts Positifs', _positiveCount, positiveRate, Colors.green),
          _buildLegend('Écarts Négatifs', _negativeCount, negativeRate, Colors.red),
          _buildLegend('Stocks Corrects', _correctCount, correctRate, Colors.blue),
        ],
      ),
    );
  }

  Widget _buildValueCard(String title, double value, Color color, {bool isFullWidth = false}) {
    return Card(
      // ignore: deprecated_member_use
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    if (pos + neg + correct == 0) {
      return const Center(child: Text('Aucune donnée à afficher dans le graphique.'));
    }
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(
            color: Colors.green,
            value: pos,
            title: '${pos.toStringAsFixed(1)}%',
            radius: 50,
            titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          PieChartSectionData(
            color: Colors.red,
            value: neg,
            title: '${neg.toStringAsFixed(1)}%',
            radius: 50,
            titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          PieChartSectionData(
            color: Colors.blue,
            value: correct,
            title: '${correct.toStringAsFixed(1)}%',
            radius: 50,
            titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String title, int count, double rate, Color color) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, radius: 10),
        title: Text(title),
        trailing: Text('$count articles (${rate.toStringAsFixed(1)}%)'),
      ),
    );
  }
}
