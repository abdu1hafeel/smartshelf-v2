// ==============================================================================
// SmartShelf V2 - Cart & RPC Payload Unit Tests
// ==============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/models/cart_item.dart';
import 'package:shopkeeper_app/models/product.dart';
import 'package:shopkeeper_app/models/shop_inventory_item.dart';
import 'package:shopkeeper_app/models/verified_weight_ticket.dart';
import 'package:shopkeeper_app/services/cart_service.dart';

void main() {
  group('CartService & CartItem Tests', () {
    late Product packagedProd;
    late Product looseProd;
    late ShopInventoryItem packagedInv;
    late ShopInventoryItem looseInv;

    setUp(() {
      packagedProd = const Product(
        id: 'prod-pkg-001',
        organizationId: 'org-001',
        name: 'Organic Milk 1L',
        barcode: '8901030000001',
        sku: 'MILK-1L',
        unitType: 'PACKAGED',
      );

      packagedInv = ShopInventoryItem(
        shopId: 'shop-001',
        productId: 'prod-pkg-001',
        sellingPrice: 65.0,
        quantity: 10.0,
        lowStockThreshold: 3.0,
        updatedAt: DateTime.now(),
        product: packagedProd,
      );

      looseProd = const Product(
        id: 'prod-loose-002',
        organizationId: 'org-001',
        name: 'Fresh Royal Gala Apples',
        barcode: null,
        sku: 'APPLE-GALA',
        unitType: 'LOOSE',
      );

      looseInv = ShopInventoryItem(
        shopId: 'shop-001',
        productId: 'prod-loose-002',
        sellingPrice: 120.0, // Rs 120 per kg
        quantity: 25.5,
        lowStockThreshold: 5.0,
        updatedAt: DateTime.now(),
        product: looseProd,
      );
    });

    test('Packaged item line total and quantity calculations', () {
      final item = CartItem(
        product: packagedProd,
        inventoryItem: packagedInv,
        packagedQuantity: 3,
      );

      expect(item.isPackaged, isTrue);
      expect(item.isLoose, isFalse);
      expect(item.quantity, equals(3.0));
      expect(item.lineTotal, equals(195.0)); // 3 * 65.0
    });

    test('Loose produce line total with 3-decimal kg precision', () {
      final ticket = VerifiedWeightTicket(
        id: 'ticket-001',
        shopId: 'shop-001',
        deviceId: 'device-001',
        productId: 'prod-loose-002',
        weightGrams: 1450.0,
        weightKg: 1.450,
        isConsumed: false,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );

      final item = CartItem(
        product: looseProd,
        inventoryItem: looseInv,
        weightTicket: ticket,
      );

      expect(item.isPackaged, isFalse);
      expect(item.isLoose, isTrue);
      expect(item.quantity, equals(1.450));
      expect(item.lineTotal, closeTo(174.0, 0.001)); // 1.450 * 120.0
    });

    test('Generates canonical process_sale_tx RPC payload for packaged item', () {
      final item = CartItem(
        product: packagedProd,
        inventoryItem: packagedInv,
        packagedQuantity: 2,
      );

      final payload = item.toRpcPayload();
      expect(payload['product_id'], equals('prod-pkg-001'));
      expect(payload['quantity'], equals(2));
      expect(payload.containsKey('weight_ticket_id'), isFalse);
    });

    test('Generates canonical process_sale_tx RPC payload for loose goods with ticket', () {
      final ticket = VerifiedWeightTicket(
        id: 'ticket-abc-123',
        shopId: 'shop-001',
        deviceId: 'dev-01',
        productId: 'prod-loose-002',
        weightGrams: 750.0,
        weightKg: 0.750,
        isConsumed: false,
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        createdAt: DateTime.now(),
      );

      final item = CartItem(
        product: looseProd,
        inventoryItem: looseInv,
        weightTicket: ticket,
      );

      final payload = item.toRpcPayload();
      expect(payload['product_id'], equals('prod-loose-002'));
      expect(payload['weight_ticket_id'], equals('ticket-abc-123'));
      expect(payload.containsKey('quantity'), isFalse);
    });

    test('CartService accumulates items and calculates total amount correctly', () {
      final cart = CartService();

      expect(cart.isEmpty, isTrue);
      expect(cart.totalAmount, equals(0.0));

      // Add 2 packaged milk
      final err1 = cart.addPackagedProduct(
        product: packagedProd,
        inventoryItem: packagedInv,
        quantity: 2,
      );
      expect(err1, isNull);
      expect(cart.itemCount, equals(1));
      expect(cart.totalAmount, equals(130.0)); // 2 * 65

      // Repeated scan increments quantity
      final err2 = cart.addPackagedProduct(
        product: packagedProd,
        inventoryItem: packagedInv,
        quantity: 1,
      );
      expect(err2, isNull);
      expect(cart.itemCount, equals(1));
      expect(cart.items.first.packagedQuantity, equals(3));
      expect(cart.totalAmount, equals(195.0)); // 3 * 65

      // Add loose apples with valid scale ticket
      final ticket = VerifiedWeightTicket(
        id: 'ticket-999',
        shopId: 'shop-001',
        deviceId: 'scale-01',
        productId: 'prod-loose-002',
        weightGrams: 2000.0,
        weightKg: 2.000,
        isConsumed: false,
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        createdAt: DateTime.now(),
      );

      final err3 = cart.addLooseProduct(
        product: looseProd,
        inventoryItem: looseInv,
        ticket: ticket,
      );
      expect(err3, isNull);
      expect(cart.itemCount, equals(2));
      // 195 (milk) + 240 (2kg apples @ 120/kg) = 435.0
      expect(cart.totalAmount, closeTo(435.0, 0.001));
    });

    test('Prevents exceeding available inventory stock for packaged goods', () {
      final cart = CartService();

      // Inventory only has 10 pcs
      final err = cart.addPackagedProduct(
        product: packagedProd,
        inventoryItem: packagedInv,
        quantity: 15, // Exceeds 10
      );

      expect(err, isNotNull);
      expect(err, contains('exceeds available stock'));
      expect(cart.isEmpty, isTrue);
    });

    test('Prevents adding loose item if scale ticket is expired or consumed', () {
      final cart = CartService();

      final expiredTicket = VerifiedWeightTicket(
        id: 'ticket-expired',
        shopId: 'shop-001',
        deviceId: 'scale-01',
        productId: 'prod-loose-002',
        weightGrams: 1000.0,
        weightKg: 1.000,
        isConsumed: false,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 10)), // EXPIRED
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final errExpired = cart.addLooseProduct(
        product: looseProd,
        inventoryItem: looseInv,
        ticket: expiredTicket,
      );
      expect(errExpired, isNotNull);
      expect(errExpired, contains('expired or already consumed'));

      final consumedTicket = VerifiedWeightTicket(
        id: 'ticket-consumed',
        shopId: 'shop-001',
        deviceId: 'scale-01',
        productId: 'prod-loose-002',
        weightGrams: 1000.0,
        weightKg: 1.000,
        isConsumed: true, // ALREADY CONSUMED
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );

      final errConsumed = cart.addLooseProduct(
        product: looseProd,
        inventoryItem: looseInv,
        ticket: consumedTicket,
      );
      expect(errConsumed, isNotNull);
      expect(errConsumed, contains('expired or already consumed'));
    });

    test('Prevents duplicate addition of the exact same weight ticket ID', () {
      final cart = CartService();

      final ticket = VerifiedWeightTicket(
        id: 'ticket-unique-123',
        shopId: 'shop-001',
        deviceId: 'scale-01',
        productId: 'prod-loose-002',
        weightGrams: 1200.0,
        weightKg: 1.200,
        isConsumed: false,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );

      final err1 = cart.addLooseProduct(
        product: looseProd,
        inventoryItem: looseInv,
        ticket: ticket,
      );
      expect(err1, isNull);

      // Attempt to add same ticket again
      final err2 = cart.addLooseProduct(
        product: looseProd,
        inventoryItem: looseInv,
        ticket: ticket,
      );
      expect(err2, isNotNull);
      expect(err2, contains('already been added to the cart'));
    });

    test('Checkout UUID remains constant across retry until cart is cleared', () {
      final cart = CartService();
      final initialCheckoutId = cart.checkoutId;

      expect(initialCheckoutId, isNotEmpty);
      expect(initialCheckoutId.length, equals(36)); // standard uuid length

      // Adding item does not alter current checkout UUID
      cart.addPackagedProduct(product: packagedProd, inventoryItem: packagedInv);
      expect(cart.checkoutId, equals(initialCheckoutId));

      // Clearing cart after successful transaction generates a new checkout UUID
      cart.clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.checkoutId, isNot(equals(initialCheckoutId)));
    });
  });
}
