// ==============================================================================
// SmartShelf V2 - Add Product / Enroll Inventory Dialog
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/inventory_service.dart';
import 'barcode_scan_modal.dart';

class AddProductDialog extends StatefulWidget {
  final String shopId;
  final String organizationId;
  final String currency;
  final InventoryService inventoryService;

  const AddProductDialog({
    super.key,
    required this.shopId,
    required this.organizationId,
    required this.currency,
    required this.inventoryService,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _newFormKey = GlobalKey<FormState>();
  final _enrollFormKey = GlobalKey<FormState>();

  // New Product Form Controllers
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _skuController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _initialQtyController = TextEditingController(text: '0');
  final _thresholdController = TextEditingController(text: '5');
  String _unitType = 'PACKAGED'; // 'PACKAGED' or 'LOOSE'
  String? _selectedCategoryId;

  // Existing Product Enrollment Controllers
  Product? _selectedCatalogProduct;
  final _enrollPriceController = TextEditingController();
  final _enrollQtyController = TextEditingController(text: '0');
  final _enrollThresholdController = TextEditingController(text: '5');

  List<Category> _categories = [];
  List<Product> _unstockedProducts = [];
  Product? _duplicateProduct;
  bool _isLoadingData = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMetadata();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _initialQtyController.dispose();
    _thresholdController.dispose();
    _enrollPriceController.dispose();
    _enrollQtyController.dispose();
    _enrollThresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    try {
      final cats = await widget.inventoryService.fetchCategories(widget.organizationId);
      final unstocked = await widget.inventoryService.fetchUnstockedCatalogProducts(
        organizationId: widget.organizationId,
        shopId: widget.shopId,
      );

      if (!mounted) return;
      setState(() {
        _categories = cats;
        _unstockedProducts = unstocked;
        if (unstocked.isNotEmpty) {
          _selectedCatalogProduct = unstocked.first;
        }
        _isLoadingData = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingData = false);
    }
  }

  Future<void> _checkBarcodeDuplicate(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      if (_duplicateProduct != null) {
        setState(() => _duplicateProduct = null);
      }
      return;
    }

    try {
      final existing = await widget.inventoryService.findProductByBarcode(
        organizationId: widget.organizationId,
        barcodeOrSku: trimmed,
      );
      if (!mounted) return;
      setState(() {
        _duplicateProduct = existing;
      });
    } catch (_) {}
  }

  Future<void> _openBarcodeScanner() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScanModal(),
      ),
    );

    if (scanned != null && scanned.trim().isNotEmpty) {
      final cleanCode = scanned.trim();
      setState(() {
        _barcodeController.text = cleanCode;
      });
      await _checkBarcodeDuplicate(cleanCode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Scanned barcode: $cleanCode')),
              ],
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleCreateNewProduct() async {
    if (!_newFormKey.currentState!.validate()) return;

    final barcodeText = _barcodeController.text.trim();
    if (barcodeText.isNotEmpty) {
      final existing = await widget.inventoryService.findProductByBarcode(
        organizationId: widget.organizationId,
        barcodeOrSku: barcodeText,
      );
      if (existing != null) {
        setState(() {
          _duplicateProduct = existing;
          _errorMessage =
              'Barcode "$barcodeText" already exists in catalog for "${existing.name}". Switch to "From Catalog" tab to stock it.';
        });
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final price = double.parse(_priceController.text.trim());
    final qty = double.parse(_initialQtyController.text.trim());
    final threshold = double.tryParse(_thresholdController.text.trim()) ?? 5.0;

    try {
      await widget.inventoryService.createProductAndEnroll(
        organizationId: widget.organizationId,
        shopId: widget.shopId,
        categoryId: _selectedCategoryId,
        name: _nameController.text.trim(),
        barcode: _barcodeController.text.trim(),
        sku: _skuController.text.trim(),
        unitType: _unitType,
        description: _descController.text.trim(),
        sellingPrice: price,
        initialQuantity: qty,
        lowStockThreshold: threshold,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = _cleanError(err);
      });
    }
  }

  Future<void> _handleEnrollExistingProduct() async {
    if (_selectedCatalogProduct == null) return;
    if (!_enrollFormKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final price = double.parse(_enrollPriceController.text.trim());
    final qty = double.parse(_enrollQtyController.text.trim());
    final threshold = double.tryParse(_enrollThresholdController.text.trim()) ?? 5.0;

    try {
      await widget.inventoryService.enrollExistingProduct(
        shopId: widget.shopId,
        productId: _selectedCatalogProduct!.id,
        sellingPrice: price,
        initialQuantity: qty,
        lowStockThreshold: threshold,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      if (err.message.contains('uq_products_org_barcode')) {
        return 'A product with this barcode already exists in the catalog.';
      }
      return err.message;
    }
    final msg = err.toString().replaceFirst('Exception: ', '');
    if (msg.contains('Only an ORG_ADMIN')) {
      return 'Unauthorized: Only an Org Admin can create catalog products. If you are a store keeper, enroll existing catalog items or use Admin Console.';
    }
    if (msg.contains('Only a Shop/Org Admin')) {
      return 'Unauthorized: Only a Shop/Org Admin can configure shop inventory.';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_shopping_cart_rounded, color: Color(0xFF4F46E5), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Add Product to Store',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                labelColor: const Color(0xFF4F46E5),
                unselectedLabelColor: const Color(0xFF64748B),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                tabs: [
                  const Tab(text: 'New Product'),
                  Tab(text: 'From Catalog (${_unstockedProducts.length})'),
                ],
              ),
            ),

            // Error display
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
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
              ),

            // Tab Views
            Expanded(
              child: _isLoadingData
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildNewProductForm(),
                        _buildEnrollExistingForm(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewProductForm() {
    final isPackaged = _unitType == 'PACKAGED';
    final qtyUnit = isPackaged ? 'pcs' : 'kg';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _newFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Unit Type Switcher
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    avatar: Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: _unitType == 'PACKAGED' ? Colors.white : const Color(0xFF4F46E5),
                    ),
                    label: const Text('Packaged (pcs)'),
                    selected: _unitType == 'PACKAGED',
                    selectedColor: const Color(0xFF4F46E5),
                    labelStyle: TextStyle(
                      color: _unitType == 'PACKAGED' ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _unitType = 'PACKAGED');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    avatar: Icon(
                      Icons.scale_rounded,
                      size: 16,
                      color: _unitType == 'LOOSE' ? Colors.white : const Color(0xFF16A34A),
                    ),
                    label: const Text('Loose (kg)'),
                    selected: _unitType == 'LOOSE',
                    selectedColor: const Color(0xFF16A34A),
                    labelStyle: TextStyle(
                      color: _unitType == 'LOOSE' ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _unitType = 'LOOSE');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Product Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Product Name *',
                hintText: 'e.g. Masala Tea 250g or Fresh Onions',
                prefixIcon: Icon(Icons.label_outline, size: 20),
                filled: true,
                isDense: true,
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Product name is required';
                if (val.trim().length < 2) return 'Must be at least 2 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Barcode & SKU Row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _barcodeController,
                    onChanged: (val) => _checkBarcodeDuplicate(val),
                    decoration: InputDecoration(
                      labelText: 'Barcode (EAN/UPC)',
                      hintText: '890...',
                      prefixIcon: const Icon(Icons.qr_code_scanner, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF4F46E5), size: 20),
                        tooltip: 'Scan Barcode',
                        onPressed: _openBarcodeScanner,
                      ),
                      filled: true,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _skuController,
                    decoration: const InputDecoration(
                      labelText: 'SKU / Code',
                      hintText: 'SKU-001',
                      prefixIcon: Icon(Icons.tag, size: 20),
                      filled: true,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Scan Barcode Button
            OutlinedButton.icon(
              onPressed: _openBarcodeScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text(
                'Scan Barcode',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F46E5),
                side: const BorderSide(color: Color(0xFFC7D2FE), width: 1.5),
                backgroundColor: const Color(0xFFEEF2FF),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (_duplicateProduct != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Warning: Barcode already registered to "${_duplicateProduct!.name}" in catalog.',
                            style: const TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Switch to the "From Catalog" tab to stock this existing product in this store.',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Category Dropdown (if available)
            if (_categories.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Category (Optional)',
                  prefixIcon: Icon(Icons.category_outlined, size: 20),
                  filled: true,
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('No Category')),
                  ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (val) => setState(() => _selectedCategoryId = val),
              ),
              const SizedBox(height: 12),
            ],

            // Selling Price & Initial Stock Row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Selling Price (${widget.currency}) *',
                      hintText: '49.50',
                      prefixText: '${widget.currency} ',
                      filled: true,
                      isDense: true,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Price required';
                      final parsed = double.tryParse(val.trim());
                      if (parsed == null || parsed < 0) return 'Invalid price';
                      if ((parsed * 100).round() != (parsed * 100)) return 'Max 2 decimals';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _initialQtyController,
                    keyboardType: TextInputType.numberWithOptions(decimal: !isPackaged),
                    decoration: InputDecoration(
                      labelText: 'Initial Stock ($qtyUnit) *',
                      hintText: isPackaged ? '20' : '20.000',
                      suffixText: qtyUnit,
                      filled: true,
                      isDense: true,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Stock required';
                      final parsed = double.tryParse(val.trim());
                      if (parsed == null || parsed < 0) return 'Invalid stock';
                      if (isPackaged && parsed != parsed.truncateToDouble()) return 'Must be whole piece';
                      if (!isPackaged && (parsed * 1000).round() != (parsed * 1000)) {
                        return 'Max 3 decimals';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Low Stock Threshold
            TextFormField(
              controller: _thresholdController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Low Stock Alert Threshold ($qtyUnit)',
                hintText: '5',
                prefixIcon: const Icon(Icons.warning_amber_rounded, size: 20),
                filled: true,
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),

            // Submit Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleCreateNewProduct,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Enroll & Stock in Store', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnrollExistingForm() {
    if (_unstockedProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'All Catalog Products Are Stocked',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Switch to the "New Product" tab to create a brand new item.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final isPackaged = _selectedCatalogProduct?.isPackaged ?? true;
    final qtyUnit = isPackaged ? 'pcs' : 'kg';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _enrollFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Catalog Product Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedCatalogProduct?.id,
              decoration: const InputDecoration(
                labelText: 'Select Catalog Product *',
                prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                filled: true,
                isDense: true,
              ),
              items: _unstockedProducts
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.name} (${p.unitType})'),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedCatalogProduct = _unstockedProducts.firstWhere((p) => p.id == val);
                  });
                }
              },
            ),
            const SizedBox(height: 14),

            // Selling Price & Initial Stock Row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _enrollPriceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Selling Price (${widget.currency}) *',
                      hintText: '49.50',
                      prefixText: '${widget.currency} ',
                      filled: true,
                      isDense: true,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Price required';
                      final parsed = double.tryParse(val.trim());
                      if (parsed == null || parsed < 0) return 'Invalid price';
                      if ((parsed * 100).round() != (parsed * 100)) return 'Max 2 decimals';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _enrollQtyController,
                    keyboardType: TextInputType.numberWithOptions(decimal: !isPackaged),
                    decoration: InputDecoration(
                      labelText: 'Initial Stock ($qtyUnit) *',
                      hintText: isPackaged ? '20' : '20.000',
                      suffixText: qtyUnit,
                      filled: true,
                      isDense: true,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Stock required';
                      final parsed = double.tryParse(val.trim());
                      if (parsed == null || parsed < 0) return 'Invalid stock';
                      if (isPackaged && parsed != parsed.truncateToDouble()) return 'Must be whole piece';
                      if (!isPackaged && (parsed * 1000).round() != (parsed * 1000)) {
                        return 'Max 3 decimals';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Low Stock Threshold
            TextFormField(
              controller: _enrollThresholdController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Low Stock Alert Threshold ($qtyUnit)',
                hintText: '5',
                prefixIcon: const Icon(Icons.warning_amber_rounded, size: 20),
                filled: true,
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),

            // Submit Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleEnrollExistingProduct,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Add to Store Stock', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
