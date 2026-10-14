// ==============================================================================
// SmartShelf V2 - Shopkeeper App Widget Tests
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/models/cart_item.dart';
import 'package:shopkeeper_app/models/product.dart';
import 'package:shopkeeper_app/models/shop_inventory_item.dart';
import 'package:shopkeeper_app/services/checkout_service.dart';
import 'package:shopkeeper_app/services/inventory_service.dart';
import 'package:shopkeeper_app/widgets/add_product_dialog.dart';
import 'package:shopkeeper_app/widgets/receipt_dialog.dart';
import 'package:shopkeeper_app/widgets/restock_dialog.dart';
import 'package:shopkeeper_app/widgets/stat_card.dart';
import 'package:shopkeeper_app/widgets/stock_badge.dart';

void main() {
  group('Shopkeeper UI Widgets', () {
    testWidgets('StockBadge renders correct status text and style', (WidgetTester tester) async {
      // 1. In Stock
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StockBadge(quantity: 20, threshold: 5, isPackaged: true),
          ),
        ),
      );
      expect(find.text('In Stock (20)'), findsOneWidget);

      // 2. Low Stock
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StockBadge(quantity: 3, threshold: 5, isPackaged: true),
          ),
        ),
      );
      expect(find.text('Low Stock (3)'), findsOneWidget);

      // 3. Out of Stock
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StockBadge(quantity: 0, threshold: 5, isPackaged: true),
          ),
        ),
      );
      expect(find.text('Out of Stock'), findsOneWidget);
    });

    testWidgets('StatCard displays title, value, and triggers onTap callback', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatCard(
              title: "Today's Revenue",
              value: 'INR 4,500.00',
              icon: Icons.currency_rupee,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text("Today's Revenue"), findsOneWidget);
      expect(find.text('INR 4,500.00'), findsOneWidget);
      expect(find.byIcon(Icons.currency_rupee), findsOneWidget);

      await tester.tap(find.text("Today's Revenue"));
      expect(tapped, isTrue);
    });

    testWidgets('ReceiptDialog displays confirmed receipt breakdown', (WidgetTester tester) async {
      const prod = Product(
        id: 'p1',
        organizationId: 'o1',
        name: 'Packaged Biscuits',
        unitType: 'PACKAGED',
      );

      final inv = ShopInventoryItem(
        shopId: 's1',
        productId: 'p1',
        sellingPrice: 30.0,
        quantity: 10,
        updatedAt: DateTime.now(),
      );

      final cartItem = CartItem(
        product: prod,
        inventoryItem: inv,
        packagedQuantity: 2,
      );

      final checkoutResult = CheckoutResult(
        success: true,
        saleId: 'sale-999',
        saleNumber: 'REC-00042',
        totalAmount: 60.0,
        status: 'COMPLETED',
        checkoutId: 'test-uuid-checkout',
        items: [cartItem],
      );

      bool newSaleTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptDialog(
              result: checkoutResult,
              currency: 'INR',
              onNewSale: () => newSaleTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('Payment Confirmed'), findsOneWidget);
      expect(find.text('Receipt #REC-00042'), findsOneWidget);
      expect(find.text('Packaged Biscuits'), findsOneWidget);
      expect(find.text('INR 60.00'), findsNWidgets(2)); // line item & total

      // Tap 'Start Next Sale'
      await tester.tap(find.text('Start Next Sale'));
      expect(newSaleTriggered, isTrue);
    });

    testWidgets('RestockDialog renders product info and validates whole number for packaged goods', (WidgetTester tester) async {
      const prod = Product(
        id: 'p-pkg-1',
        organizationId: 'o1',
        name: 'Packaged Biscuits 200g',
        unitType: 'PACKAGED',
      );

      final inv = ShopInventoryItem(
        shopId: 's1',
        productId: 'p-pkg-1',
        sellingPrice: 30.0,
        quantity: 12.0,
        updatedAt: DateTime.now(),
        product: prod,
      );

      final invService = InventoryService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestockDialog(
              shopId: 's1',
              currency: 'INR',
              item: inv,
              inventoryService: invService,
            ),
          ),
        ),
      );

      expect(find.text('Increase Stock'), findsOneWidget);
      expect(find.text('Packaged Biscuits 200g'), findsOneWidget);
      expect(find.text('Current Stock: 12 pcs'), findsOneWidget);
      expect(find.text('PACKAGED'), findsOneWidget);

      // Enter fractional quantity for packaged goods (invalid)
      await tester.enterText(find.byType(TextFormField).first, '3.5');
      await tester.tap(find.text('Confirm Restock'));
      await tester.pump();

      expect(find.text('Must be an exact whole piece integer'), findsOneWidget);
    });

    testWidgets('RestockDialog renders loose unit label and validates positive quantity', (WidgetTester tester) async {
      const looseProd = Product(
        id: 'p-loose-1',
        organizationId: 'o1',
        name: 'Loose Farm Tomatoes',
        unitType: 'LOOSE',
      );

      final looseInv = ShopInventoryItem(
        shopId: 's1',
        productId: 'p-loose-1',
        sellingPrice: 35.0,
        quantity: 25.500,
        updatedAt: DateTime.now(),
        product: looseProd,
      );

      final invService = InventoryService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestockDialog(
              shopId: 's1',
              currency: 'INR',
              item: looseInv,
              inventoryService: invService,
            ),
          ),
        ),
      );

      expect(find.text('Current Stock: 25.500 kg'), findsOneWidget);
      expect(find.text('LOOSE'), findsOneWidget);

      // Enter negative quantity
      await tester.enterText(find.byType(TextFormField).first, '-5');
      await tester.tap(find.text('Confirm Restock'));
      await tester.pump();

      expect(find.text('Quantity must be greater than 0'), findsOneWidget);
    });

    testWidgets('AddProductDialog renders form fields and switches between Packaged and Loose', (WidgetTester tester) async {
      final invService = InventoryService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddProductDialog(
              shopId: 's1',
              organizationId: 'o1',
              currency: 'INR',
              inventoryService: invService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add Product to Store'), findsOneWidget);
      expect(find.text('New Product'), findsOneWidget);
      expect(find.text('Packaged (pcs)'), findsOneWidget);
      expect(find.text('Loose (kg)'), findsOneWidget);

      // Switch to Loose Produce
      await tester.tap(find.text('Loose (kg)'));
      await tester.pumpAndSettle();

      expect(find.text('Initial Stock (kg) *'), findsOneWidget);
    });

    testWidgets('AddProductDialog renders Scan Barcode button and manual entry field', (WidgetTester tester) async {
      final invService = InventoryService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddProductDialog(
              shopId: 's1',
              organizationId: 'o1',
              currency: 'INR',
              inventoryService: invService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Barcode (EAN/UPC)'), findsOneWidget);
      expect(find.text('Scan Barcode'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    });
  });
}
