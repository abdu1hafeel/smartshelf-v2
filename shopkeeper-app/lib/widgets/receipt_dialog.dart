// ==============================================================================
// SmartShelf V2 - Confirmed Sale Receipt Dialog
// ==============================================================================

import 'package:flutter/material.dart';
import '../services/checkout_service.dart';

class ReceiptDialog extends StatelessWidget {
  final CheckoutResult result;
  final String currency;
  final VoidCallback onNewSale;

  const ReceiptDialog({
    super.key,
    required this.result,
    this.currency = 'INR',
    required this.onNewSale,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success Header Icon
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF16A34A),
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payment Confirmed',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Receipt #${result.saleNumber ?? "N/A"}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Itemized list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: result.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = result.items[index];
                  final qtyText = item.isPackaged
                      ? '${item.packagedQuantity} pcs'
                      : '${item.weightTicket?.weightKg.toStringAsFixed(3) ?? "0.000"} kg';

                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.product.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              '$qtyText × $currency ${item.inventoryItem.sellingPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$currency ${item.lineTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Total Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Paid',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  '$currency ${result.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),

            if (result.isIdempotentRetry) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'ℹ️ Safe retry: Sale was already recorded previously without double stock deduction.',
                  style: TextStyle(fontSize: 10, color: Color(0xFFB45309)),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onNewSale,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Start Next Sale',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
