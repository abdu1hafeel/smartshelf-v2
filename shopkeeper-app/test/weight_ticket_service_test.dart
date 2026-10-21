// ==============================================================================
// SmartShelf V2 - WeightTicketService Safe Client and Subscription Tests
// ==============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/services/weight_ticket_service.dart';

void main() {
  group('WeightTicketService Safe Client Handling Tests', () {
    late WeightTicketService service;

    setUp(() {
      service = WeightTicketService();
    });

    test('fetchLatestValidTicket returns null safely when Supabase client is uninitialized', () async {
      // In a unit test environment without Supabase.initialize(), the service must not throw unhandled exceptions.
      final ticket = await service.fetchLatestValidTicket(
        shopId: 'shop-test-id',
        productId: 'prod-test-id',
      );
      expect(ticket, isNull);
    });

    test('subscribeToWeightTickets handles uninitialized client gracefully by calling onError', () {
      bool errorCalled = false;
      Object? capturedError;

      final channel = service.subscribeToWeightTickets(
        shopId: 'shop-test-id',
        productId: 'prod-test-id',
        onTicketReceived: (_) {},
        onError: (err) {
          errorCalled = true;
          capturedError = err;
        },
      );

      // Channel is null when Supabase is not initialized
      expect(channel, isNull);
      expect(errorCalled, isTrue);
      expect(capturedError, isNotNull);
    });

    test('unsubscribe with null or inactive channel does not throw exception', () {
      expect(() => service.unsubscribe(null), returnsNormally);
    });
  });
}
