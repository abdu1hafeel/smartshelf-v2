// ==============================================================================
// SmartShelf V2 - Sales & Receipts Service
// ==============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/sale.dart';

class SalesService {
  final SupabaseClient _client;

  SalesService({SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  /// Fetches recent sales transactions with itemized details
  Future<List<Sale>> fetchRecentSales({
    required String shopId,
    int limit = 15,
  }) async {
    final response = await _client
        .from('sales')
        .select('*, sale_items(*)')
        .eq('shop_id', shopId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (response as List)
        .map((json) => Sale.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Calculates today's sales count and total revenue
  Future<Map<String, dynamic>> fetchTodayMetrics(String shopId) async {
    final now = DateTime.now().toUtc();
    final startOfToday = DateTime.utc(now.year, now.month, now.day).toIso8601String();

    try {
      final rows = await _client
          .from('sales')
          .select('total_amount')
          .eq('shop_id', shopId)
          .gte('created_at', startOfToday);

      double sum = 0.0;
      for (final r in rows) {
        sum += (r['total_amount'] as num?)?.toDouble() ?? 0.0;
      }

      return {
        'count': rows.length,
        'revenue': sum,
      };
    } catch (_) {
      return {'count': 0, 'revenue': 0.0};
    }
  }
}
