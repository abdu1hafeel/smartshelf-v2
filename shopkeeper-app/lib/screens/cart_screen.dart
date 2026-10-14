// ==============================================================================
// SmartShelf V2 - Cart & Secure Checkout POS Screen
// ==============================================================================

import 'package:flutter/material.dart';
import '../models/shop.dart';
import '../services/cart_service.dart';
import '../services/checkout_service.dart';
import '../widgets/receipt_dialog.dart';
import 'barcode_scanner_screen.dart';
import 'loose_weight_picker_screen.dart';

class CartScreen extends StatefulWidget {
  final Shop shop;
  final CartService cartService;

  const CartScreen({
    super.key,
    required this.shop,
    required this.cartService,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CheckoutService _checkoutService = CheckoutService();
  final TextEditingController _notesController = TextEditingController();

  String _selectedPaymentMethod = 'CASH'; // 'CASH', 'CARD', 'UPI', 'CREDIT'
  bool _isProcessingCheckout = false;
  String? _checkoutError;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleCheckout() async {
    final cart = widget.cartService;
    if (cart.isEmpty) return;

    setState(() {
      _isProcessingCheckout = true;
      _checkoutError = null;
    });

    final result = await _checkoutService.processCheckout(
      shopId: widget.shop.id,
      items: cart.items,
      paymentMethod: _selectedPaymentMethod,
      checkoutId: cart.checkoutId,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
    );

    if (!mounted) return;

    setState(() {
      _isProcessingCheckout = false;
    });

    if (result.success) {
      // Clear cart and prepare for next sale
      widget.cartService.clear();
      _notesController.clear();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReceiptDialog(
          result: result,
          currency: widget.shop.currency,
          onNewSale: () {
            Navigator.pop(context); // close dialog
          },
        ),
      );
    } else {
      setState(() {
        _checkoutError = result.errorMessage ?? 'Checkout transaction failed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.cartService,
      builder: (context, _) {
        final cart = widget.cartService;
        final items = cart.items;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Text(
              'POS Cart (${cart.itemCount})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0F172A),
            elevation: 0,
            actions: [
              if (cart.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFE11D48)),
                  tooltip: 'Clear Cart',
                  onPressed: () {
                    cart.clear();
                    setState(() => _checkoutError = null);
                  },
                ),
            ],
          ),
          body: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.shopping_cart_outlined, size: 40, color: Color(0xFF4F46E5)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Your Cart is Empty',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan packaged items with the camera or weigh loose produce on the scale.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BarcodeScannerScreen(
                                      shop: widget.shop,
                                      cartService: widget.cartService,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                              label: const Text('Scan Item'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LooseWeightPickerScreen(
                                      shop: widget.shop,
                                      cartService: widget.cartService,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.scale_rounded, size: 18),
                              label: const Text('Weigh Item'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF4F46E5),
                                side: const BorderSide(color: Color(0xFF4F46E5)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Cart Items List
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _buildCartItemCard(item, index);
                        },
                      ),
                    ),

                    // Checkout Sheet Panel
                    _buildCheckoutPanel(cart),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildCartItemCard(dynamic item, int index) {
    final currency = widget.shop.currency;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.isPackaged ? const Color(0xFFF1F5F9) : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.isPackaged ? Icons.inventory_2_outlined : Icons.scale_rounded,
              color: item.isPackaged ? const Color(0xFF475569) : const Color(0xFF16A34A),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (item.isPackaged)
                  Text(
                    'Unit: $currency ${item.inventoryItem.sellingPrice.toStringAsFixed(2)} • Stock: ${item.inventoryItem.quantity.toInt()} pcs',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  )
                else
                  Text(
                    'Scale Ticket: ${item.weightTicket!.weightKg.toStringAsFixed(3)} kg @ $currency ${item.inventoryItem.sellingPrice.toStringAsFixed(2)}/kg',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),

          // Stepper for Packaged or Weight display for Loose
          if (item.isPackaged)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20, color: Color(0xFF64748B)),
                  onPressed: () => widget.cartService.updatePackagedQuantity(index, -1),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '${item.packagedQuantity}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF4F46E5)),
                  onPressed: () => widget.cartService.updatePackagedQuantity(index, 1),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${item.weightTicket!.weightKg.toStringAsFixed(3)} kg',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF15803D),
                ),
              ),
            ),

          const SizedBox(width: 8),

          // Line Total
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$currency ${item.lineTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF0F172A),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                onPressed: () => widget.cartService.removeItem(index),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(top: 4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutPanel(CartService cart) {
    final currency = widget.shop.currency;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Error banner if checkout failed
            if (_checkoutError != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFBE123C)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _checkoutError!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFBE123C), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Payment Method Selector
            Row(
              children: [
                const Text(
                  'Payment:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['CASH', 'UPI', 'CARD', 'CREDIT'].map((method) {
                        final isSelected = _selectedPaymentMethod == method;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              method,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF4F46E5),
                            backgroundColor: const Color(0xFFF1F5F9),
                            onSelected: (val) {
                              if (val) setState(() => _selectedPaymentMethod = method);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Subtotal / Total Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Amount', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    Text(
                      '$currency ${cart.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Scan Barcode',
                      icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF4F46E5)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BarcodeScannerScreen(
                              shop: widget.shop,
                              cartService: widget.cartService,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Weigh Loose Item',
                      icon: const Icon(Icons.scale_rounded, color: Color(0xFF16A34A)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LooseWeightPickerScreen(
                              shop: widget.shop,
                              cartService: widget.cartService,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Checkout Button
            ElevatedButton(
              onPressed: _isProcessingCheckout ? null : _handleCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isProcessingCheckout
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Charge $currency ${cart.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
