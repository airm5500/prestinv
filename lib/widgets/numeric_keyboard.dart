import 'package:flutter/material.dart';

class NumericKeyboard extends StatelessWidget {
  final Function(String) onKeyPressed;

  const NumericKeyboard({super.key, required this.onKeyPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[200],
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          _buildRow(['1', '2', '3']),
          _buildRow(['4', '5', '6']),
          _buildRow(['7', '8', '9']),
          _buildRow(['DEL', '0', 'OK']),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => _buildKey(key)).toList(),
    );
  }

  Widget _buildKey(String key) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(20),
            backgroundColor: (key == 'OK') ? Colors.green : (key == 'DEL' ? Colors.redAccent : Colors.white),
            foregroundColor: (key == 'OK' || key == 'DEL') ? Colors.white : Colors.black,
          ),
          onPressed: () => onKeyPressed(key),
          child: Text(key, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}