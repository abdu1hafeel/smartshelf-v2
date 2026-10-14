// ==============================================================================
// SmartShelf V2 - Add Product Barcode Scanner Modal
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScanModal extends StatefulWidget {
  const BarcodeScanModal({super.key});

  @override
  State<BarcodeScanModal> createState() => _BarcodeScanModalState();
}

class _BarcodeScanModalState extends State<BarcodeScanModal> {
  late final MobileScannerController _controller;
  bool _isScanned = false;
  bool _torchEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_isScanned) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        setState(() => _isScanned = true);
        Navigator.of(context).pop(rawValue);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Scan Product Barcode',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          IconButton(
            icon: Icon(_torchEnabled ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Toggle Flashlight',
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchEnabled = !_torchEnabled);
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            tooltip: 'Switch Camera',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Camera Viewfinder
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
            errorBuilder: (context, error) {
              final isPermissionDenied = error.errorCode == MobileScannerErrorCode.permissionDenied;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPermissionDenied ? Icons.no_photography_outlined : Icons.error_outline_rounded,
                          size: 48,
                          color: isPermissionDenied ? Colors.amber : const Color(0xFFF43F5E),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isPermissionDenied ? 'Camera Permission Required' : 'Scanner Error',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isPermissionDenied
                              ? 'Camera permission was denied. Please allow camera access in device settings to scan barcodes.'
                              : (error.errorDetails?.message ?? error.errorCode.message),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(null),
                          icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                          label: const Text('Enter Barcode Manually'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // 2. Viewfinder Reticle Box
          Center(
            child: Container(
              width: 290,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isScanned ? const Color(0xFF22C55E) : const Color(0xFF4F46E5),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: (_isScanned ? const Color(0xFF22C55E) : const Color(0xFF4F46E5)).withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // 3. Top Instruction Banner
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'Align retail barcode within the frame',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // 4. Bottom Controls & Formats Card
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Supported: EAN-13 • EAN-8 • UPC-A • UPC-E • Code 128',
                    style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancel Scan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white60),
                      backgroundColor: Colors.black45,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
