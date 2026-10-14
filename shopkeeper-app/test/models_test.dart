// ==============================================================================
// SmartShelf V2 - Data Models & Deserialization Unit Tests
// ==============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/models/product.dart';
import 'package:shopkeeper_app/models/sale.dart';
import 'package:shopkeeper_app/models/shop.dart';
import 'package:shopkeeper_app/models/shop_inventory_item.dart';
import 'package:shopkeeper_app/models/verified_weight_ticket.dart';

void main() {
  group('SmartShelf Models Tests', () {
    test('Product deserialization and unitType helpers', () {
      final json = {
        'id': 'p1',
        'organization_id': 'o1',
        'category_id': 'c1',
        'name': 'Whole Wheat Bread',
        'barcode': '1234567890123',
        'sku': 'BREAD-WW',
        'unit_type': 'PACKAGED',
        'is_active': true,
        'category': {'id': 'c1', 'name': 'Bakery'},
      };

      final product = Product.fromJson(json);
      expect(product.id, equals('p1'));
      expect(product.name, equals('Whole Wheat Bread'));
      expect(product.categoryName, equals('Bakery'));
      expect(product.isPackaged, isTrue);
      expect(product.isLoose, isFalse);
    });

    test('Shop deserialization and default currency', () {
      final json = {
        'id': 's1',
        'organization_id': 'o1',
        'name': 'Downtown Mart',
        'location': 'MG Road, Bangalore',
        'currency': 'INR',
        'created_at': '2026-10-14T10:00:00Z',
      };

      final shop = Shop.fromJson(json);
      expect(shop.id, equals('s1'));
      expect(shop.name, equals('Downtown Mart'));
      expect(shop.location, equals('MG Road, Bangalore'));
      expect(shop.currency, equals('INR'));
    });

    test('ShopInventoryItem stock thresholds and availability', () {
      final inStockJson = {
        'shop_id': 's1',
        'product_id': 'p1',
        'selling_price': 45.0,
        'quantity': 15.0,
        'low_stock_threshold': 5.0,
        'is_available': true,
        'updated_at': '2026-10-14T12:00:00Z',
      };

      final itemInStock = ShopInventoryItem.fromJson(inStockJson);
      expect(itemInStock.isOutOfStock, isFalse);
      expect(itemInStock.isLowStock, isFalse);

      final lowStockJson = {
        'shop_id': 's1',
        'product_id': 'p1',
        'selling_price': 45.0,
        'quantity': 3.0,
        'low_stock_threshold': 5.0,
        'is_available': true,
        'updated_at': '2026-10-14T12:00:00Z',
      };

      final itemLowStock = ShopInventoryItem.fromJson(lowStockJson);
      expect(itemLowStock.isOutOfStock, isFalse);
      expect(itemLowStock.isLowStock, isTrue);

      final outOfStockJson = {
        'shop_id': 's1',
        'product_id': 'p1',
        'selling_price': 45.0,
        'quantity': 0.0,
        'low_stock_threshold': 5.0,
        'is_available': true,
        'updated_at': '2026-10-14T12:00:00Z',
      };

      final itemOutOfStock = ShopInventoryItem.fromJson(outOfStockJson);
      expect(itemOutOfStock.isOutOfStock, isTrue);
      expect(itemOutOfStock.isLowStock, isFalse);
    });

    test('VerifiedWeightTicket expiration and scale telemetry parsing', () {
      final futureExpiry = DateTime.now().add(const Duration(minutes: 10)).toIso8601String();
      final validTicketJson = {
        'id': 't1',
        'shop_id': 's1',
        'device_id': 'd1',
        'product_id': 'p2',
        'weight_grams': 1850.5,
        'weight_kg': 1.851,
        'is_consumed': false,
        'expires_at': futureExpiry,
        'created_at': DateTime.now().toIso8601String(),
        'device': {
          'name': 'Produce Scale A',
          'device_identifier': 'esp32-scale-01',
        },
      };

      final validTicket = VerifiedWeightTicket.fromJson(validTicketJson);
      expect(validTicket.weightGrams, equals(1850.5));
      expect(validTicket.weightKg, equals(1.851));
      expect(validTicket.deviceName, equals('Produce Scale A'));
      expect(validTicket.isExpired, isFalse);
      expect(validTicket.isValidForCheckout, isTrue);

      // Consumed ticket
      final consumedJson = Map<String, dynamic>.from(validTicketJson)..['is_consumed'] = true;
      final consumedTicket = VerifiedWeightTicket.fromJson(consumedJson);
      expect(consumedTicket.isValidForCheckout, isFalse);
    });

    test('Sale and SaleItem deserialization', () {
      final json = {
        'id': 'sale-1',
        'shop_id': 's1',
        'sale_number': 'REC-10023',
        'total_amount': 250.0,
        'payment_method': 'UPI',
        'payment_status': 'COMPLETED',
        'notes': 'POS Checkout',
        'created_at': '2026-10-14T14:30:00Z',
        'sale_items': [
          {
            'id': 'si-1',
            'sale_id': 'sale-1',
            'product_id': 'p1',
            'product_name': 'Packaged Tea',
            'unit_type': 'PACKAGED',
            'quantity': 2.0,
            'unit_price': 125.0,
            'line_total': 250.0,
            'weight_ticket_id': null,
          }
        ],
      };

      final sale = Sale.fromJson(json);
      expect(sale.saleNumber, equals('REC-10023'));
      expect(sale.totalAmount, equals(250.0));
      expect(sale.paymentMethod, equals('UPI'));
      expect(sale.items.length, equals(1));
      expect(sale.items.first.productName, equals('Packaged Tea'));
      expect(sale.items.first.lineTotal, equals(250.0));
    });
  });
}
