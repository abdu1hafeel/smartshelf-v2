// ==============================================================================
// SmartShelf V2 - Barcode Scanner & POS Item Addition Screen
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/product.dart';
import '../models/shop.dart';
import '../models/shop_inventory_item.dart';
import '../services/cart_service.dart';
import '../services/inventory_service.dart';
import 'loose_weight_picker_screen.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final Shop shop;
  final CartService cartService;

  const BarcodeScannerScreen({
    super.key,
    required this.shop,
    required this.cartService,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final InventoryService _inventoryService = InventoryService();
  final TextEditingController _manualInputController = TextEditingController();

  bool _isProcessingCode = false;
  String? _lastScannedCode;
  ShopInventoryItem? _lastFoundItem;
  String? _statusMessage;
  bool _isSuccessStatus = true;
  bool _torchEnabled = false;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeDetected(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _isProcessingCode) return;

    setState(() {
      _isProcessingCode = true;
      _lastScannedCode = code;
      _statusMessage = 'Looking up product catalog...';
      _isSuccessStatus = true;
    });

    try {
      final inventoryItem = await _inventoryService.lookupByBarcode(
        shopId: widget.shop.id,
        barcodeOrSku: code,
      );

      if (!mounted) return;

      if (inventoryItem == null) {
        setState(() {
          _lastFoundItem = null;
          _isProcessingCode = false;
          _statusMessage = 'Product "$code" not found or not stocked in ${widget.shop.name}.';
          _isSuccessStatus = false;
        });
        return;
      }

      final product = inventoryItem.product;
      if (product == null) {
        setState(() {
          _lastFoundItem = null;
          _isProcessingCode = false;
          _statusMessage = 'Catalog metadata missing for product.';
          _isSuccessStatus = false;
        });
        return;
      }

      setState(() {
        _lastFoundItem = inventoryItem;
      });

      if (product.isPackaged) {
        // Packaged item: add to cart or increment
        final err = widget.cartService.addPackagedProduct(
          product: product,
          inventoryItem: inventoryItem,
          quantity: 1,
        );

        if (err != null) {
          setState(() {
            _isProcessingCode = false;
            _statusMessage = err;
            _isSuccessStatus = false;
          });
        } else {
          setState(() {
            _isProcessingCode = false;
            _statusMessage = 'Added ${product.name} to cart (+1)';
            _isSuccessStatus = true;
          });
        }
      } else {
        // Loose produce: requires scale ticket
        setState(() {
          _isProcessingCode = false;
          _statusMessage = '${product.name} is loose produce. Scale reading required.';
          _isSuccessStatus = true;
        });

        // Prompt cashier to route to scale ticket view
        _promptLooseItemScale(product, inventoryItem);
      }
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isProcessingCode = false;
        _statusMessage = 'Error scanning: $err';
        _isSuccessStatus = false;
      });
    }
  }

  void _promptLooseItemScale(Product product, ShopInventoryItem inventoryItem) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.scale_rounded, color: Color(0xFF4F46E5), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Loose item • ${widget.shop.currency} ${inventoryItem.sellingPrice.toStringAsFixed(2)} / kg',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'This is a loose produce item. Please place it on the smart scale to capture an authoritative weight ticket.',
              style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LooseWeightPickerScreen(
                      shop: widget.shop,
                      cartService: widget.cartService,
                      initialProduct: product,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.speed_rounded, size: 18),
              label: const Text('Read Scale Weight Ticket'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualBarcodeDialog() {
    _manualInputController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enter Barcode / SKU', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _manualInputController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. 8901030383921 or MILK-1L',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (val) {
            Navigator.pop(ctx);
            if (val.trim().isNotEmpty) {
              _handleBarcodeDetected(val.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = _manualInputController.text.trim();
              Navigator.pop(ctx);
              if (val.isNotEmpty) {
                _handleBarcodeDetected(val);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
            ),
            child: const Text('Look Up'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Scan Product Barcode',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_torchEnabled ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Toggle Flash',
            onPressed: () {
              _scannerController.toggleTorch();
              setState(() => _torchEnabled = !_torchEnabled);
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            tooltip: 'Switch Camera',
            onPressed: () => _scannerController.switchCamera(),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_alt_outlined),
            tooltip: 'Enter Manually',
            onPressed: _showManualBarcodeDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera scanner viewport
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _handleBarcodeDetected(raw);
                  break;
                }
              }
            },
          ),

          // Viewfinder reticle overlay
          Center(
            child: Container(
              width: 280,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isProcessingCode
                      ? Colors.amber
                      : (_isSuccessStatus ? const Color(0xFF4F46E5) : const Color(0xFFE11D48)),
                  width: 2.5,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Top Instruction Badge
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Point camera at product barcode or SKU',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),

          // Bottom Feedback / Status Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_statusMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isSuccessStatus ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isSuccessStatus ? const Color(0xFFBBF7D0) : const Color(0xFFFECDD3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isSuccessStatus ? Icons.check_circle_rounded : Icons.warning_rounded,
                              size: 18,
                              color: _isSuccessStatus ? const Color(0xFF16A34A) : const Color(0xFFE11D48),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _statusMessage!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _isSuccessStatus ? const Color(0xFF15803D) : const Color(0xFFBE123C),
                                    ),
                                  ),
                                  if (_lastFoundItem != null && _lastFoundItem!.product != null)
                                    Text(
                                      '${_lastFoundItem!.product!.name} • ${widget.shop.currency} ${_lastFoundItem!.sellingPrice.toStringAsFixed(2)} (${_lastScannedCode ?? ""})',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showManualBarcodeDialog,
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text('Manual SKU'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F172A),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                            label: Text('Cart (${widget.cartService.itemCount})'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
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
}
