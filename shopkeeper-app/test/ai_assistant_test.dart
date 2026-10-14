// ==============================================================================
// SmartShelf V2 - AI Shopkeeper Assistant Unit & Widget Tests
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/models/ai_message.dart';
import 'package:shopkeeper_app/models/shop.dart';
import 'package:shopkeeper_app/screens/ai_assistant_screen.dart';
import 'package:shopkeeper_app/services/ai_assistant_service.dart';

void main() {
  group('AiMessage Model Tests', () {
    test('User message creation', () {
      final now = DateTime.now();
      final msg = AiMessage(
        id: 'msg-1',
        text: 'How much revenue did my shop generate today?',
        isUser: true,
        timestamp: now,
      );

      expect(msg.id, equals('msg-1'));
      expect(msg.text, equals('How much revenue did my shop generate today?'));
      expect(msg.isUser, isTrue);
      expect(msg.isError, isFalse);
      expect(msg.intent, isNull);
    });

    test('Assistant message with intent and raw analytics data', () {
      final now = DateTime.now();
      final rawData = {
        'total_revenue': 12500.50,
        'sales_count': 42,
        'units_sold': 118,
      };

      final msg = AiMessage(
        id: 'msg-2',
        text: 'Today your shop has generated ₹12,500.50 across 42 transactions.',
        isUser: false,
        timestamp: now,
        intent: 'TODAY_SALES',
        rawData: rawData,
      );

      expect(msg.isUser, isFalse);
      expect(msg.isError, isFalse);
      expect(msg.intent, equals('TODAY_SALES'));
      expect(msg.rawData?['total_revenue'], equals(12500.50));
      expect(msg.rawData?['sales_count'], equals(42));
    });

    test('Error message creation', () {
      final msg = AiMessage(
        id: 'msg-err',
        text: 'Network timeout',
        isUser: false,
        timestamp: DateTime.now(),
        isError: true,
      );

      expect(msg.isError, isTrue);
    });
  });

  group('AiAssistantService Intent Classification Tests', () {
    final service = AiAssistantService();

    test('Classifies today revenue and sales questions', () {
      expect(service.classifyIntent('How much revenue did my shop generate today?'), equals('TODAY_SALES'));
      expect(service.classifyIntent('What are today sales?'), equals('TODAY_SALES'));
      expect(service.classifyIntent('How much did we sell today?'), equals('TODAY_SALES'));
    });

    test('Classifies month and monthly comparison questions', () {
      expect(service.classifyIntent('How is this month performing compared to last month?'), equals('PERIOD_COMPARE'));
      expect(service.classifyIntent('Compare this month sales with last month'), equals('PERIOD_COMPARE'));
      expect(service.classifyIntent('Total revenue for this month so far'), equals('MONTH_SALES'));
    });

    test('Classifies low stock and inventory alerts', () {
      expect(service.classifyIntent('Which items are running low on stock?'), equals('LOW_STOCK'));
      expect(service.classifyIntent('Show out of stock items'), equals('LOW_STOCK'));
      expect(service.classifyIntent('What items are almost finished?'), equals('LOW_STOCK'));
    });

    test('Classifies restock recommendations', () {
      expect(service.classifyIntent('What should I restock today?'), equals('RESTOCK'));
      expect(service.classifyIntent('Reorder recommendation list'), equals('RESTOCK'));
      expect(service.classifyIntent('How much inventory should I buy?'), equals('RESTOCK'));
    });

    test('Classifies top selling products', () {
      expect(service.classifyIntent('What are my top-selling products this week?'), equals('TOP_SELLING'));
      expect(service.classifyIntent('Best selling items today'), equals('TOP_SELLING'));
      expect(service.classifyIntent('Most popular goods'), equals('TOP_SELLING'));
    });

    test('Classifies slow-moving or zero-sales products', () {
      expect(service.classifyIntent('Which products have had no sales in the last 14 days?'), equals('SLOW_MOVING'));
      expect(service.classifyIntent('Dead stock list'), equals('SLOW_MOVING'));
      expect(service.classifyIntent('Slow moving inventory'), equals('SLOW_MOVING'));
    });

    test('Classifies cross-shop queries', () {
      expect(service.classifyIntent('How much did the other shop sell?'), equals('CROSS_SHOP'));
      expect(service.classifyIntent('Show sales from branch 2'), equals('CROSS_SHOP'));
      expect(service.classifyIntent('Can I see another store inventory?'), equals('CROSS_SHOP'));
    });

    test('Classifies general store overview by default', () {
      expect(service.classifyIntent('Tell me about the store status'), equals('GENERAL_OVERVIEW'));
    });
  });

  group('AiAssistantService Deterministic Synthesis Tests', () {
    final service = AiAssistantService();

    test('Synthesizes TODAY_SALES with revenue and transactions', () {
      final text = service.synthesizeDeterministicNarrative('TODAY_SALES', {
        'total_revenue': 328.5,
        'total_transactions': 2,
        'packaged_units_sold': 2,
        'loose_weight_sold_kg': 0.0,
        'top_product_name': 'Packaged Biscuits 200g',
        'top_product_revenue': 60.0,
      });

      expect(text, contains('₹328.50'));
      expect(text, contains('2 customer transactions'));
      expect(text, contains('Packaged Biscuits 200g'));
    });

    test('Synthesizes LOW_STOCK with item listings', () {
      final text = service.synthesizeDeterministicNarrative('LOW_STOCK', {
        'low_stock_count': 1,
        'out_of_stock_count': 0,
        'low_stock_items': [
          {
            'product_name': 'Tata Tea Gold 250g',
            'current_stock': 15,
            'low_stock_threshold': 55,
            'unit_type': 'PACKAGED',
          }
        ],
      });

      expect(text, contains('Tata Tea Gold 250g'));
      expect(text, contains('15 / 55 pcs'));
    });

    test('Synthesizes RESTOCK with recommended purchase orders', () {
      final text = service.synthesizeDeterministicNarrative('RESTOCK', {
        'recommended_restock_count': 1,
        'restock_recommendations': [
          {
            'product_name': 'Tata Tea Gold 250g',
            'current_stock': 15,
            'low_stock_threshold': 55,
            'recommended_order_quantity': 95,
            'unit_type': 'PACKAGED',
            'urgency': 'NORMAL',
          }
        ],
      });

      expect(text, contains('Tata Tea Gold 250g'));
      expect(text, contains('+95 pcs'));
    });

    test('Synthesizes CROSS_SHOP privacy protection message', () {
      final text = service.synthesizeDeterministicNarrative('CROSS_SHOP', {
        'is_org_admin': false,
        'privacy_message': 'Cross-shop metrics are restricted to Organization Administrators.',
      });

      expect(text, contains('restricted'));
      expect(text, contains('Organization Administrator'));
    });
  });

  group('AiAssistantScreen Widget Tests', () {
    final testShop = Shop(
      id: 'shop-test-123',
      organizationId: 'org-test-456',
      name: 'Downtown Mart',
      location: '123 Main Street',
      currency: 'INR',
      createdAt: DateTime.now(),
    );

    testWidgets('Renders AppBar, welcome message, suggestion chips, and input field',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiAssistantScreen(shop: testShop),
        ),
      );

      // Verify title & shop name
      expect(find.text('AI Shopkeeper Assistant'), findsOneWidget);
      expect(find.textContaining('Downtown Mart'), findsWidgets);

      // Verify welcome message is present
      expect(find.textContaining('SmartShelf AI Assistant'), findsOneWidget);
      expect(find.textContaining('Ask me anything about today’s revenue'), findsOneWidget);

      // Verify suggested prompt chips
      expect(find.text('How much revenue did my shop generate today?'), findsOneWidget);
      expect(find.text('Which items are running low on stock?'), findsOneWidget);
      expect(find.byType(ActionChip), findsWidgets);

      // Verify input bar and send button
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('Tapping a suggested prompt chip puts the prompt into chat flow',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiAssistantScreen(shop: testShop),
        ),
      );

      // Find first visible prompt chip and tap it
      final chip = find.text('How much revenue did my shop generate today?');
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();

      // Verify the user bubble was created with that text
      expect(find.text('How much revenue did my shop generate today?'), findsWidgets);
    });
  });
}
