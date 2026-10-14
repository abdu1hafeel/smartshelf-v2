// ==============================================================================
// SmartShelf V2 - Shop Inventory Browser Screen
// ==============================================================================

import 'package:flutter/material.dart';
import '../models/shop.dart';
import '../models/shop_inventory_item.dart';
import '../services/inventory_service.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/restock_dialog.dart';
import '../widgets/stock_badge.dart';

class InventoryScreen extends StatefulWidget {
  final Shop shop;

  const InventoryScreen({
    super.key,
    required this.shop,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final InventoryService _inventoryService = InventoryService();
  List<ShopInventoryItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String _selectedFilter = 'ALL'; // 'ALL', 'LOW_STOCK', 'OUT_OF_STOCK', 'LOOSE'

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _inventoryService.fetchShopInventory(widget.shop.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load inventory: $err';
      });
    }
  }

  Future<void> _openAddProductDialog() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProductDialog(
        shopId: widget.shop.id,
        organizationId: widget.shop.organizationId,
        currency: widget.shop.currency,
        inventoryService: _inventoryService,
      ),
    );

    if (created == true) {
      _loadInventory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product enrolled in store inventory successfully!'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openRestockDialog(ShopInventoryItem item) async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => RestockDialog(
        shopId: widget.shop.id,
        currency: widget.shop.currency,
        item: item,
        inventoryService: _inventoryService,
      ),
    );

    if (res != null) {
      _loadInventory();
      if (mounted) {
        final restocked = res['restocked_quantity'];
        final total = res['new_quantity'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock increased by $restocked. New total: $total'),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<ShopInventoryItem> get _filteredItems {
    return _items.where((item) {
      final prod = item.product;
      final name = prod?.name.toLowerCase() ?? '';
      final barcode = prod?.barcode?.toLowerCase() ?? '';
      final sku = prod?.sku?.toLowerCase() ?? '';
      final q = _searchQuery.toLowerCase();

      final matchesQuery = q.isEmpty || name.contains(q) || barcode.contains(q) || sku.contains(q);
      if (!matchesQuery) return false;

      switch (_selectedFilter) {
        case 'LOW_STOCK':
          return item.isLowStock;
        case 'OUT_OF_STOCK':
          return item.isOutOfStock;
        case 'LOOSE':
          return prod?.isLoose ?? false;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.shop.currency;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Inventory • ${widget.shop.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Item',
            onPressed: _openAddProductDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadInventory,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddProductDialog,
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Item',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        tooltip: 'Add Product to Store',
      ),
      body: Column(
        children: [
          // Search & Filter header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by product name, barcode, or SKU...',
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
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('ALL', 'All Items (${_items.length})'),
                      const SizedBox(width: 6),
                      _buildFilterChip('LOW_STOCK', 'Low Stock'),
                      const SizedBox(width: 6),
                      _buildFilterChip('OUT_OF_STOCK', 'Out of Stock'),
                      const SizedBox(width: 6),
                      _buildFilterChip('LOOSE', 'Loose Produce'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Inventory List
          Expanded(
            child: _isLoading
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
                                onPressed: _loadInventory,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredItems.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No products match "$_searchQuery"'
                                        : 'No inventory items found',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tap "+ Add Item" below to enroll products in this store.',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: _openAddProductDialog,
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Add Product Now'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4F46E5),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                            itemCount: _filteredItems.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = _filteredItems[index];
                              final prod = item.product;
                              final isPackaged = prod?.isPackaged ?? true;

                              return InkWell(
                                onTap: () => _openRestockDialog(item),
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
                                          color: isPackaged
                                              ? const Color(0xFFEEF2FF)
                                              : const Color(0xFFF0FDF4),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          isPackaged ? Icons.inventory_2_outlined : Icons.scale_rounded,
                                          color: isPackaged
                                              ? const Color(0xFF4F46E5)
                                              : const Color(0xFF16A34A),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              prod?.name ?? 'Unknown Product',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (prod?.categoryName != null) ...[
                                                  Text(
                                                    prod!.categoryName!,
                                                    style: TextStyle(
                                                        fontSize: 11, color: Colors.grey.shade600),
                                                  ),
                                                  Text(' • ',
                                                      style: TextStyle(color: Colors.grey.shade400)),
                                                ],
                                                Text(
                                                  prod?.barcode != null
                                                      ? 'Barcode: ${prod!.barcode}'
                                                      : (prod?.sku != null ? 'SKU: ${prod!.sku}' : ''),
                                                  style: TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 10,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '$currency ${item.sellingPrice.toStringAsFixed(2)}${isPackaged ? '' : ' /kg'}',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              StockBadge(
                                                quantity: item.quantity,
                                                threshold: item.lowStockThreshold,
                                                isPackaged: isPackaged,
                                              ),
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: () => _openRestockDialog(item),
                                                borderRadius: BorderRadius.circular(6),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF0FDF4),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border:
                                                        Border.all(color: const Color(0xFFBBF7D0)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.add,
                                                          size: 12, color: Color(0xFF16A34A)),
                                                      Text(
                                                        'Stock',
                                                        style: TextStyle(
                                                          color: Color(0xFF16A34A),
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(
        label,
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
        if (val) setState(() => _selectedFilter = key);
      },
    );
  }
}
