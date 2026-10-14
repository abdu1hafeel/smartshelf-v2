// ==============================================================================
// SmartShelf V2 - Stock Status Badge Widget
// ==============================================================================

import 'package:flutter/material.dart';

class StockBadge extends StatelessWidget {
  final double quantity;
  final double threshold;
  final bool isPackaged;

  const StockBadge({
    super.key,
    required this.quantity,
    required this.threshold,
    this.isPackaged = true,
  });

  @override
  Widget build(BuildContext context) {
    if (quantity <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFECDD3)),
        ),
        child: const Text(
          'Out of Stock',
          style: TextStyle(
            color: Color(0xFFBE123C),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (quantity <= threshold) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Text(
          'Low Stock (${isPackaged ? quantity.toInt() : quantity.toStringAsFixed(3)})',
          style: const TextStyle(
            color: Color(0xFFB45309),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Text(
        'In Stock (${isPackaged ? quantity.toInt() : quantity.toStringAsFixed(3)})',
        style: const TextStyle(
          color: Color(0xFF15803D),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
