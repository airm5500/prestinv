// lib/widgets/numeric_keyboard.dart
import 'package:flutter/material.dart';

class NumericKeyboard extends StatelessWidget {
  final Function(String) onKeyPressed;

  const NumericKeyboard({super.key, required this.onKeyPressed});

  @override
  Widget build(BuildContext context) {
    // On récupère la hauteur de l'écran pour adapter la taille du clavier
    final screenHeight = MediaQuery.of(context).size.height;

    // On définit un écran comme "petit" si sa hauteur est inférieure à 700 pixels.
    final bool isSmallScreen = screenHeight < 700;

    // On utilise des boutons plus petits et une police réduite sur les petits écrans.
    final buttonPadding = isSmallScreen
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8) // Padding vertical réduit
        : const EdgeInsets.all(16);
    final keyFontSize = isSmallScreen ? 18.0 : 20.0;

    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
      child: Column(
        // Le clavier prend la hauteur minimale nécessaire
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(['1', '2', '3'], buttonPadding, keyFontSize),
          _buildRow(['4', '5', '6'], buttonPadding, keyFontSize),
          _buildRow(['7', '8', '9'], buttonPadding, keyFontSize),
          _buildRow(['DEL', '0', 'OK'], buttonPadding, keyFontSize),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> keys, EdgeInsets padding, double fontSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => _buildKey(key, padding, fontSize)).toList(),
    );
  }

  Widget _buildKey(String key, EdgeInsets padding, double fontSize) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: padding,
            backgroundColor: (key == 'OK') ? Colors.green : (key == 'DEL') ? Colors.redAccent : Colors.white,
            foregroundColor: (key == 'OK' || key == 'DEL') ? Colors.white : Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => onKeyPressed(key),
          child: Text(key, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
