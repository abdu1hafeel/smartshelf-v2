// ==============================================================================
// SmartShelf V2 - Loose Weight Picker & Scale Realtime Integration Tests
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/models/product.dart';
import 'package:shopkeeper_app/models/shop.dart';
import 'package:shopkeeper_app/models/shop_inventory_item.dart';
import 'package:shopkeeper_app/models/verified_weight_ticket.dart';
import 'package:shopkeeper_app/screens/loose_weight_picker_screen.dart';
import 'package:shopkeeper_app/services/cart_service.dart';
import 'package:shopkeeper_app/services/inventory_service.dart';
import 'package:shopkeeper_app/services/weight_ticket_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fake InventoryService returning predefined loose inventory
class FakeInventoryService extends InventoryService {
  final List<ShopInventoryItem> items;
  FakeInventoryService(this.items);

  @override
  Future<List<ShopInventoryItem>> fetchShopInventory(String shopId) async {
    return items;
  }
}

/// Fake WeightTicketService simulating Realtime events and REST fallbacks
class FakeWeightTicketService extends WeightTicketService {
  VerifiedWeightTicket? mockLatestTicket;
  void Function(VerifiedWeightTicket)? activeCallback;
  void Function(String)? activeStatusCallback;
  bool isSubscribed = false;
  String? lastSubscribedProductId;
  bool unsubscribed = false;

  FakeWeightTicketService({this.mockLatestTicket});

  @override
  Future<VerifiedWeightTicket?> fetchLatestValidTicket({
    required String shopId,
    required String productId,
  }) async {
    return mockLatestTicket;
  }

  @override
  RealtimeChannel? subscribeToWeightTickets({
    required String shopId,
    required String productId,
    required void Function(VerifiedWeightTicket ticket) onTicketReceived,
    void Function(String status)? onStatusChange,
    void Function(Object error)? onError,
  }) {
    isSubscribed = true;
    lastSubscribedProductId = productId;
    unsubscribed = false;
    activeCallback = onTicketReceived;
    activeStatusCallback = onStatusChange;
    onStatusChange?.call('Live Scale');
    return null; // Channel handle
  }

  @override
  Future<void> unsubscribe(RealtimeChannel? channel) async {
    unsubscribed = true;
    isSubscribed = false;
    activeCallback = null;
    activeStatusCallback = null;
  }

  void simulateTicketArrival(VerifiedWeightTicket ticket) {
    activeCallback?.call(ticket);
  }
}

void main() {
  group('LooseWeightPickerScreen Realtime & Safety Tests', () {
    late Shop testShop;
    late Product looseApple;
    late Product looseOnion;
    late ShopInventoryItem appleItem;
    late ShopInventoryItem onionItem;
    late CartService cartService;

    setUp(() {
      testShop = Shop(
        id: 'shop-848cabff',
        organizationId: 'org-2c17c6c2',
        name: 'SHANTHIANGADY',
        currency: 'INR',
        createdAt: DateTime.parse('2026-10-14T10:00:00Z'),
      );

      looseApple = const Product(
        id: 'prod-apple-01',
        organizationId: 'org-2c17c6c2',
        name: 'Shimla Apples',
        unitType: 'LOOSE',
      );

      looseOnion = const Product(
        id: 'prod-onion-02',
        organizationId: 'org-2c17c6c2',
        name: 'Red Onions',
        unitType: 'LOOSE',
      );

      appleItem = ShopInventoryItem(
        shopId: testShop.id,
        productId: looseApple.id,
        sellingPrice: 150.0,
        quantity: 50.0,
        lowStockThreshold: 10.0,
        updatedAt: DateTime.now(),
        product: looseApple,
      );

      onionItem = ShopInventoryItem(
        shopId: testShop.id,
        productId: looseOnion.id,
        sellingPrice: 40.0,
        quantity: 80.0,
        lowStockThreshold: 15.0,
        updatedAt: DateTime.now(),
        product: looseOnion,
      );

      cartService = CartService();
    });

    testWidgets('Displays Live Scale status badge and subscribes for active loose product',
        (WidgetTester tester) async {
      final fakeInventory = FakeInventoryService([appleItem, onionItem]);
      final fakeTicketService = FakeWeightTicketService();

      await tester.pumpWidget(
        MaterialApp(
          home: LooseWeightPickerScreen(
            shop: testShop,
            cartService: cartService,
            inventoryService: fakeInventory,
            ticketService: fakeTicketService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify screen title and items loaded
      expect(find.text('Weigh Loose Produce'), findsOneWidget);
      expect(find.text('Shimla Apples'), findsWidgets);

      // Verify Live Scale status badge is displayed
      expect(find.text('Live Scale'), findsOneWidget);
      expect(fakeTicketService.isSubscribed, isTrue);
      expect(fakeTicketService.lastSubscribedProductId, equals(looseApple.id));
    });

    testWidgets('Updates UI when a verified scale ticket arrives via Realtime without deducting inventory',
        (WidgetTester tester) async {
      final fakeInventory = FakeInventoryService([appleItem]);
      final fakeTicketService = FakeWeightTicketService();

      await tester.pumpWidget(
        MaterialApp(
          home: LooseWeightPickerScreen(
            shop: testShop,
            cartService: cartService,
            inventoryService: fakeInventory,
            ticketService: fakeTicketService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially no ticket: Add to Cart button disabled
      expect(find.text('Awaiting Valid Scale Ticket'), findsOneWidget);
      expect(appleItem.quantity, equals(50.0)); // Inventory unchanged

      // Simulate ESP32 sending a stable reading resulting in a verified ticket
      final verifiedTicket = VerifiedWeightTicket(
        id: 'ticket-esp32-001',
        shopId: testShop.id,
        deviceId: 'esp32-scale-01',
        productId: looseApple.id,
        weightGrams: 2350.0,
        weightKg: 2.350,
        isConsumed: false,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );

      fakeTicketService.simulateTicketArrival(verifiedTicket);
      await tester.pumpAndSettle();

      // Verify authoritative weight is displayed
      expect(find.text('2.350 kg'), findsOneWidget);
      expect(find.text('VERIFIED SCALE READING'), findsOneWidget);

      // Verify inventory has NOT been deducted merely because weight arrived
      expect(appleItem.quantity, equals(50.0));
      expect(cartService.items, isEmpty);

      // Verify Add to Cart button is now enabled with calculated price
      // Rate: 150/kg * 2.350 kg = 352.50
      expect(find.textContaining('Add 2.350 kg to Cart (INR 352.50)'), findsOneWidget);
    });

    testWidgets('Switching product un-subscribes previous channel and subscribes for new product',
        (WidgetTester tester) async {
      final fakeInventory = FakeInventoryService([appleItem, onionItem]);
      final fakeTicketService = FakeWeightTicketService();

      await tester.pumpWidget(
        MaterialApp(
          home: LooseWeightPickerScreen(
            shop: testShop,
            cartService: cartService,
            inventoryService: fakeInventory,
            ticketService: fakeTicketService,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(fakeTicketService.lastSubscribedProductId, equals(looseApple.id));

      // Tap on Red Onions chip
      await tester.tap(find.textContaining('Red Onions'));
      await tester.pumpAndSettle();

      // Verified previous subscription was replaced with Red Onions
      expect(fakeTicketService.lastSubscribedProductId, equals(looseOnion.id));
      expect(fakeTicketService.isSubscribed, isTrue);
    });

    testWidgets('Disposing screen cancels and un-subscribes Realtime channel',
        (WidgetTester tester) async {
      final fakeInventory = FakeInventoryService([appleItem]);
      final fakeTicketService = FakeWeightTicketService();

      await tester.pumpWidget(
        MaterialApp(
          home: LooseWeightPickerScreen(
            shop: testShop,
            cartService: cartService,
            inventoryService: fakeInventory,
            ticketService: fakeTicketService,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(fakeTicketService.isSubscribed, isTrue);

      // Navigate away / replace screen
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Other Screen')),
        ),
      );
      await tester.pumpAndSettle();

      // Verify unsubscription occurred
      expect(fakeTicketService.unsubscribed, isTrue);
    });

    testWidgets('Expired or consumed tickets do not allow checkout',
        (WidgetTester tester) async {
      final expiredTicket = VerifiedWeightTicket(
        id: 'ticket-expired-01',
        shopId: testShop.id,
        deviceId: 'esp32-scale-01',
        productId: looseApple.id,
        weightGrams: 1000.0,
        weightKg: 1.000,
        isConsumed: false,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      );

      final fakeInventory = FakeInventoryService([appleItem]);
      final fakeTicketService = FakeWeightTicketService(mockLatestTicket: expiredTicket);

      await tester.pumpWidget(
        MaterialApp(
          home: LooseWeightPickerScreen(
            shop: testShop,
            cartService: cartService,
            inventoryService: fakeInventory,
            ticketService: fakeTicketService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // UI should show ticket expired / invalid
      expect(find.text('Awaiting Valid Scale Ticket'), findsOneWidget);
    });
  });
}
