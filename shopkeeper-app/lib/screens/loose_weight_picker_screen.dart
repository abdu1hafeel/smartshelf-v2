// ==============================================================================
// SmartShelf V2 - Loose Weight Produce Scale Integration Screen
// ==============================================================================

import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/shop.dart';
import '../models/shop_inventory_item.dart';
import '../models/verified_weight_ticket.dart';
import '../services/cart_service.dart';
import '../services/inventory_service.dart';
import '../services/weight_ticket_service.dart';

class LooseWeightPickerScreen extends StatefulWidget {
  final Shop shop;
  final CartService cartService;
  final Product? initialProduct;

  const LooseWeightPickerScreen({
    super.key,
    required this.shop,
    required this.cartService,
    this.initialProduct,
  });

  @override
  State<LooseWeightPickerScreen> createState() => _LooseWeightPickerScreenState();
}

class _LooseWeightPickerScreenState extends State<LooseWeightPickerScreen> {
  final _inventoryService = InventoryService();
  final _ticketService = WeightTicketService();

  List<ShopInventoryItem> _looseItems = [];
  ShopInventoryItem? _selectedItem;
  VerifiedWeightTicket? _latestTicket;
  bool _isLoadingInventory = true;
  bool _isLoadingTicket = false;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLooseInventory();
  }

  Future<void> _loadLooseInventory() async {
    setState(() {
      _isLoadingInventory = true;
      _errorMessage = null;
    });

    try {
      final items = await _inventoryService.fetchShopInventory(widget.shop.id);
      final loose = items.where((i) => i.product != null && i.product!.isLoose).toList();

      setState(() {
        _looseItems = loose;
        _isLoadingInventory = false;

        if (widget.initialProduct != null) {
          final match = loose.where((i) => i.productId == widget.initialProduct!.id).firstOrNull;
          if (match != null) {
            _selectedItem = match;
            _fetchTicketForSelectedItem(match);
          }
        } else if (loose.isNotEmpty) {
          _selectedItem = loose.first;
          _fetchTicketForSelectedItem(loose.first);
        }
      });
    } catch (err) {
      setState(() {
        _isLoadingInventory = false;
        _errorMessage = 'Failed to load loose inventory: $err';
      });
    }
  }

  Future<void> _fetchTicketForSelectedItem(ShopInventoryItem item) async {
    setState(() {
      _isLoadingTicket = true;
      _errorMessage = null;
    });

    try {
      final ticket = await _ticketService.fetchLatestValidTicket(
        shopId: widget.shop.id,
        productId: item.productId,
      );

      setState(() {
        _latestTicket = ticket;
        _isLoadingTicket = false;
      });
    } catch (err) {
      setState(() {
        _latestTicket = null;
        _isLoadingTicket = false;
        _errorMessage = 'Error reading scale ticket: $err';
      });
    }
  }

  void _handleAddToCart() {
    final item = _selectedItem;
    final ticket = _latestTicket;

    if (item == null || item.product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a loose produce item.')),
      );
      return;
    }

    if (ticket == null || !ticket.isValidForCheckout) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid unexpired scale ticket found. Please weigh the item again on the scale.'),
          backgroundColor: Color(0xFFE11D48),
        ),
      );
      return;
    }

    final error = widget.cartService.addLooseProduct(
      product: item.product!,
      inventoryItem: item,
      ticket: ticket,
    );

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFE11D48),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${ticket.weightKg.toStringAsFixed(3)} kg ${item.product!.name} to cart!'),
          backgroundColor: const Color(0xFF16A34A),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _looseItems.where((i) {
      final name = i.product?.name.toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Weigh Loose Produce',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Scale Ticket',
            onPressed: _selectedItem != null ? () => _fetchTicketForSelectedItem(_selectedItem!) : null,
          ),
        ],
      ),
      body: _isLoadingInventory
          ? const Center(child: CircularProgressIndicator())
          : _looseItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.scale_rounded, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'No Loose Items Configured',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Configure loose products (produce, grains, fruits) in the admin console and assign them to ${widget.shop.name}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Product Selection Chips / List
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search loose produce (e.g. Apples, Rice)...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),

                    // Horizontal Item Selector
                    Container(
                      height: 52,
                      color: Colors.white,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isSelected = _selectedItem?.productId == item.productId;

                          return FilterChip(
                            selected: isSelected,
                            showCheckmark: false,
                            label: Text(
                              '${item.product?.name ?? "Item"} (${widget.shop.currency} ${item.sellingPrice.toStringAsFixed(2)}/kg)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                            selectedColor: const Color(0xFF4F46E5),
                            backgroundColor: const Color(0xFFF8FAFC),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF4F46E5) : Colors.grey.shade300,
                              ),
                            ),
                            onSelected: (_) {
                              setState(() => _selectedItem = item);
                              _fetchTicketForSelectedItem(item);
                            },
                          );
                        },
                      ),
                    ),

                    const Divider(height: 1),

                    // Main Scale Telemetry Card
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _selectedItem == null
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildScaleStatusCard(),
                                  const SizedBox(height: 16),
                                  _buildHardwareHelpNotice(),
                                ],
                              ),
                      ),
                    ),

                    // Bottom Action Bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: ElevatedButton(
                          onPressed: (_latestTicket != null && _latestTicket!.isValidForCheckout && !_isLoadingTicket)
                              ? _handleAddToCart
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_shopping_cart_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _latestTicket != null && _latestTicket!.isValidForCheckout
                                    ? 'Add ${_latestTicket!.weightKg.toStringAsFixed(3)} kg to Cart (${widget.shop.currency} ${((_selectedItem?.sellingPrice ?? 0.0) * _latestTicket!.weightKg).toStringAsFixed(2)})'
                                    : 'Awaiting Valid Scale Ticket',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildScaleStatusCard() {
    final item = _selectedItem!;
    final ticket = _latestTicket;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Product & Price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product?.name ?? 'Loose Produce',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Rate: ${widget.shop.currency} ${item.sellingPrice.toStringAsFixed(2)} / kg',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'LOOSE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),

          // Central Weight Readout Display
          if (_isLoadingTicket)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: const Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(height: 16),
                  Text(
                    'Listening for ESP32 scale weight ticket...',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            )
          else if (ticket != null && ticket.isValidForCheckout)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'VERIFIED SCALE READING',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Authoritative Weight in kg with 3 decimal places
                  Text(
                    '${ticket.weightKg.toStringAsFixed(3)} kg',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                    ),
                  ),
                  Text(
                    '(${ticket.weightGrams.toStringAsFixed(1)} grams)',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFDCFCE7), height: 1),
                  const SizedBox(height: 12),
                  // Line calculation breakdown
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Authoritative Line Price:',
                        style: TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                      ),
                      Text(
                        '${widget.shop.currency} ${(item.sellingPrice * ticket.weightKg).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Scale: ${ticket.deviceName ?? ticket.deviceIdentifier ?? "ESP32 Scale"}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      Text(
                        'Expires in: ${ticket.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 3600)}s',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                children: [
                  Icon(Icons.scale_rounded, size: 48, color: Colors.amber.shade700),
                  const SizedBox(height: 12),
                  const Text(
                    'No Valid Weight Ticket Found',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please place ${item.product?.name ?? "the produce"} on the physical ESP32 load-cell scale. Once the weight stabilizes, tap the button below.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _fetchTicketForSelectedItem(item),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Check Scale Ticket Again'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF92400E),
                      side: BorderSide(color: Colors.amber.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE11D48)),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHardwareHelpNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF64748B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hardware Integrity Notice',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Weight tickets are signed and cryptographically verified by the smart scale firmware. Weight cannot be manually typed or falsified on the mobile terminal.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
