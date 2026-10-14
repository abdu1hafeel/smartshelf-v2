// ==============================================================================
// SmartShelf V2 - Sales History & Receipt Viewer Screen
// ==============================================================================

import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../models/shop.dart';
import '../services/sales_service.dart';

class SalesHistoryScreen extends StatefulWidget {
  final Shop shop;

  const SalesHistoryScreen({
    super.key,
    required this.shop,
  });

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final SalesService _salesService = SalesService();
  List<Sale> _sales = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sales = await _salesService.fetchRecentSales(shopId: widget.shop.id, limit: 30);
      setState(() {
        _sales = sales;
        _isLoading = false;
      });
    } catch (err) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load sales history: $err';
      });
    }
  }

  void _showSaleDetailModal(Sale sale) {
    final currency = widget.shop.currency;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt #${sale.saleNumber}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${sale.createdAt.toLocal().toString().substring(0, 16)} • ${sale.paymentMethod}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'COMPLETED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Items list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: sale.items.isEmpty
                  ? Center(
                      child: Text(
                        'No line items found for this transaction.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: sale.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = sale.items[index];
                        final isLoose = item.unitType == 'LOOSE';
                        final qtyText = isLoose
                            ? '${item.quantity.toStringAsFixed(3)} kg'
                            : '${item.quantity.toInt()} pcs';

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '$qtyText × $currency ${item.unitPrice.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Confirmed',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$currency ${sale.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),

            if (sale.notes != null && sale.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Notes: ${sale.notes}',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
              ),
            ],

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.shop.currency;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Sales History • ${widget.shop.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadSales,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Color(0xFFE11D48)),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE11D48)),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadSales,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _sales.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No Sales Recorded Yet',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Completed sales and receipts for this shop will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sales.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final sale = _sales[index];
                        return InkWell(
                          onTap: () => _showSaleDetailModal(sale),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.receipt_rounded,
                                    color: Color(0xFF4F46E5),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '#${sale.saleNumber}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          fontFamily: 'monospace',
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${sale.createdAt.toLocal().toString().substring(0, 16)} • ${sale.paymentMethod}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '$currency ${sale.totalAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${sale.items.length} item(s)',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
