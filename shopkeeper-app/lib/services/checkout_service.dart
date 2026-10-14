// ==============================================================================
// SmartShelf V2 - Atomic Checkout Service (process_sale_tx RPC)
// ==============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/uuid.dart';
import '../models/cart_item.dart';

class CheckoutResult {
  final bool success;
  final String? saleId;
  final String? saleNumber;
  final double totalAmount;
  final String status;
  final bool isIdempotentRetry;
  final String checkoutId;
  final List<CartItem> items;
  final String? errorMessage;

  const CheckoutResult({
    required this.success,
    this.saleId,
    this.saleNumber,
    this.totalAmount = 0.0,
    this.status = 'PENDING',
    this.isIdempotentRetry = false,
    required this.checkoutId,
    this.items = const [],
    this.errorMessage,
  });
}

class CheckoutService {
  final SupabaseClient _client;

  CheckoutService({SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  /// Executes atomic checkout transaction via public.process_sale_tx RPC
  Future<CheckoutResult> processCheckout({
    required String shopId,
    required List<CartItem> items,
    required String paymentMethod,
    String? checkoutId,
    String? notes,
  }) async {
    if (items.isEmpty) {
      return CheckoutResult(
        success: false,
        checkoutId: checkoutId ?? '',
        errorMessage: 'Cart is empty. Add items before completing sale.',
      );
    }

    final effectiveCheckoutId = checkoutId ?? UuidUtils.generateV4();
    final itemsPayload = items.map((i) => i.toRpcPayload()).toList();

    try {
      final response = await _client.rpc('process_sale_tx', params: {
        'p_shop_id': shopId,
        'p_checkout_id': effectiveCheckoutId,
        'p_payment_method': paymentMethod,
        'p_items': itemsPayload,
        'p_notes': notes,
      });

      if (response == null || response is! Map<String, dynamic>) {
        return CheckoutResult(
          success: false,
          checkoutId: effectiveCheckoutId,
          errorMessage: 'Invalid database response received from checkout transaction.',
        );
      }

      final saleId = response['sale_id'] as String?;
      final saleNumber = response['sale_number'] as String?;
      final total = (response['total_amount'] as num?)?.toDouble() ?? 0.0;
      final status = (response['status'] as String?) ?? 'COMPLETED';
      final isRetry = (response['is_idempotent_retry'] as bool?) ?? false;

      return CheckoutResult(
        success: true,
        saleId: saleId,
        saleNumber: saleNumber,
        totalAmount: total,
        status: status,
        isIdempotentRetry: isRetry,
        checkoutId: effectiveCheckoutId,
        items: List.unmodifiable(items),
      );
    } catch (err) {
      return CheckoutResult(
        success: false,
        checkoutId: effectiveCheckoutId,
        errorMessage: _cleanError(err),
      );
    }
  }

  String _cleanError(dynamic err) {
    if (err is PostgrestException) {
      return err.message;
    }
    return err.toString().replaceFirst('Exception: ', '');
  }
}
