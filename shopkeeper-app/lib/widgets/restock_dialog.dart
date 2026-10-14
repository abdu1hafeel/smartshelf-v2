// ==============================================================================
// SmartShelf V2 - Increase Stock / Restock Dialog
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shop_inventory_item.dart';
import '../services/inventory_service.dart';

class RestockDialog extends StatefulWidget {
  final String shopId;
  final String currency;
  final ShopInventoryItem item;
  final InventoryService inventoryService;

  const RestockDialog({
    super.key,
    required this.shopId,
    required this.currency,
    required this.item,
    required this.inventoryService,
  });

  @override
  State<RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<RestockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController(text: 'Stock shipment delivery');
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final qty = double.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Please enter a valid positive quantity to add';
      });
      return;
    }

    final isPackaged = widget.item.product?.isPackaged ?? true;
    if (isPackaged && qty != qty.truncateToDouble()) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Packaged items must be restocked in whole piece integers (e.g. 5)';
      });
      return;
    }

    try {
      final res = await widget.inventoryService.restockProduct(
        shopId: widget.shopId,
        productId: widget.item.productId,
        quantity: qty,
        reason: _reasonController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(res);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = _cleanError(err);
      });
    }
  }

  String _cleanError(dynamic err) {
    if (err is PostgrestException) {
      return err.message;
    }
    final msg = err.toString().replaceFirst('Exception: ', '');
    if (msg.contains('Unauthorized')) {
      return 'Unauthorized: Only a Shop Admin or Org Admin can restock inventory.';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    final prod = widget.item.product;
    final isPackaged = prod?.isPackaged ?? true;
    final unitLabel = isPackaged ? 'pcs' : 'kg';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_box_rounded, color: Color(0xFF16A34A), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Increase Stock',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Product details banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prod?.name ?? 'Product',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Current Stock: ${widget.item.quantity.toStringAsFixed(isPackaged ? 0 : 3)} $unitLabel',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.item.isLowStock
                                ? const Color(0xFFE11D48)
                                : const Color(0xFF475569),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPackaged ? const Color(0xFFEEF2FF) : const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            prod?.unitType ?? 'PACKAGED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isPackaged ? const Color(0xFF4F46E5) : const Color(0xFF16A34A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Error display
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFE11D48), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFE11D48), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Additional quantity input
              TextFormField(
                controller: _qtyController,
                keyboardType: TextInputType.numberWithOptions(decimal: !isPackaged),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Additional Quantity to Add ($unitLabel) *',
                  hintText: isPackaged ? 'e.g. 10' : 'e.g. 5.500',
                  prefixIcon: const Icon(Icons.add, size: 20),
                  suffixText: unitLabel,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter quantity to add';
                  }
                  final parsed = double.tryParse(val.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Quantity must be greater than 0';
                  }
                  if (isPackaged && parsed != parsed.truncateToDouble()) {
                    return 'Must be an exact whole piece integer';
                  }
                  if (!isPackaged && (parsed * 1000).round() != (parsed * 1000)) {
                    return 'Max 3 decimal places (1-gram precision)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Restock reason
              TextFormField(
                controller: _reasonController,
                decoration: InputDecoration(
                  labelText: 'Restock Reason / Notes',
                  hintText: 'e.g. Morning shipment delivery',
                  prefixIcon: const Icon(Icons.edit_note, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Confirm Restock', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
