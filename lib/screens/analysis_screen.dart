// lib/screens/analysis_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/api/api_service.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/models/inventory.dart';
import 'package:prestinv/models/product.dart';
import 'package:prestinv/models/rayon.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late ApiService _apiService;

  List<Inventory> _inventories = [];
  Inventory? _selectedInventory;

  List<Rayon> _rayons = [];
  Rayon? _selectedRayon;

  List<Product> _products = [];

  // Variables pour stocker les résultats de l'analyse
  int _positiveCount = 0;
  int _negativeCount = 0;
  int _correctCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(baseUrl: Provider.of<AppConfig>(context, listen: false).currentApiUrl);
    _fetchInventories();
  }

  Future<void> _fetchInventories() async {
    setState(() => _isLoading = true);
    try {
      _inventories = await _apiService.fetchInventories(maxResult: 100);
    } catch (e) {
      // Gérer l'erreur
    }
    setState(() => _isLoading = false);
  }

  Future<void> _fetchRayons(String inventoryId) async {
    setState(() {
      _isLoading = true;
      _rayons = [];
      _selectedRayon = null;
      _clearAnalysis();
    });
    try {
      _rayons = await _apiService.fetchRayons(inventoryId);
    } catch (e) {
      // Gérer l'erreur
    }
    setState(() => _isLoading = false);
  }

  Future<void> _fetchProductsAndAnalyze(String inventoryId, String rayonId) async {
    setState(() {
      _isLoading = true;
      _clearAnalysis();
    });
    try {
      _products = await _apiService.fetchProducts(inventoryId, rayonId);
      _performAnalysis(_products);
    } catch (e) {
      // Gérer l'erreur
    }
    setState(() => _isLoading = false);
  }

  void _clearAnalysis() {
    setState(() {
      _products = [];
      _positiveCount = 0;
      _negativeCount = 0;
      _correctCount = 0;
    });
  }

  void _performAnalysis(List<Product> products) {
    if (products.isEmpty) return;

    int pos = 0;
    int neg = 0;
    int correct = 0;

    for (final product in products) {
      final ecart = product.quantiteSaisie - product.quantiteInitiale;
      if (ecart > 0) {
        pos++;
      } else if (ecart < 0) {
        neg++;
      } else {
        correct++;
      }
    }
    setState(() {
      _positiveCount = pos;
      _negativeCount = neg;
      _correctCount = correct;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analyse des Inventaires')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- Sélecteurs ---
            _buildSelectors(),
            const SizedBox(height: 24),
            // --- Résultats ---
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

    return SingleChildScrollView(
      child: Column(
        children: [
          Text('Analyse de l\'emplacement: ${_selectedRayon?.displayName ?? ''}', style: Theme.of(context).textTheme.titleLarge),
          Text('Nombre total d\'articles: $total', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: _buildPieChart(positiveRate, negativeRate, correctRate),
          ),
          const SizedBox(height: 24),
          _buildLegend('Écarts Positifs', _positiveCount, positiveRate, Colors.green),
          _buildLegend('Écarts Négatifs', _negativeCount, negativeRate, Colors.red),
          _buildLegend('Stocks Corrects', _correctCount, correctRate, Colors.blue),
        ],
      ),
    );
  }

  Widget _buildPieChart(double pos, double neg, double correct) {
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