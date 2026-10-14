// ==============================================================================
// SmartShelf V2 - AI Shopkeeper Assistant Service
// ==============================================================================

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/ai_message.dart';

class AiAssistantService {
  static const Duration _timeout = Duration(seconds: 15);
  final SupabaseClient? _client;

  AiAssistantService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _effectiveClient => _client ?? SupabaseConfig.client;

  /// Classifies a natural language query into an approved analytics intent
  String classifyIntent(String query) {
    final q = query.toLowerCase().trim();

    if (q.contains('other shop') ||
        q.contains('other store') ||
        q.contains('network') ||
        q.contains('cross shop') ||
        q.contains('all branch') ||
        q.contains('all stores') ||
        q.contains('branch 2') ||
        q.contains('another store')) {
      return 'CROSS_SHOP';
    }

    if (q.contains('restock') ||
        q.contains('reorder') ||
        q.contains('buy more') ||
        q.contains('what should i order') ||
        q.contains('should i restock') ||
        q.contains('inventory should i buy')) {
      return 'RESTOCK';
    }

    if (q.contains('low stock') ||
        q.contains('out of stock') ||
        q.contains('running low') ||
        q.contains('depleted') ||
        q.contains('stock level') ||
        q.contains('items are low') ||
        q.contains('shortage') ||
        q.contains('almost finished')) {
      return 'LOW_STOCK';
    }

    if (q.contains('slow') ||
        q.contains('not selling') ||
        q.contains('selling slowly') ||
        q.contains('dead stock') ||
        q.contains('least sold') ||
        q.contains('slow-moving') ||
        q.contains('no sales')) {
      return 'SLOW_MOVING';
    }

    if (q.contains('top') ||
        q.contains('best selling') ||
        q.contains('most sold') ||
        q.contains('highest selling') ||
        q.contains('popular') ||
        q.contains('sold the most') ||
        q.contains('fast-selling') ||
        q.contains('fast selling')) {
      return 'TOP_SELLING';
    }

    if (q.contains('compare') ||
        q.contains('comparison') ||
        q.contains('versus') ||
        q.contains('vs') ||
        (q.contains('this month') && q.contains('last month')) ||
        (q.contains('this week') && q.contains('last week'))) {
      return 'PERIOD_COMPARE';
    }

    if (q.contains('today') ||
        q.contains("day's revenue") ||
        q.contains('todays sales') ||
        q.contains('revenue today') ||
        (q.contains('how much') && q.contains('today')) ||
        q.contains('today generate') ||
        q.contains('today sales')) {
      return 'TODAY_SALES';
    }

    if (q.contains('month') ||
        q.contains('monthly') ||
        q.contains('this month')) {
      return 'MONTH_SALES';
    }

    return 'GENERAL_OVERVIEW';
  }

  /// Alias for askQuestion
  Future<AiMessage> askAssistant({
    required String shopId,
    required String question,
  }) =>
      askQuestion(shopId: shopId, question: question);

  /// Queries real Supabase records via verified server-side RPC and generates a structured business answer
  Future<AiMessage> askQuestion({
    required String shopId,
    required String question,
  }) async {
    final cleanQuestion = question.trim();
    if (cleanQuestion.isEmpty) {
      return AiMessage.error('Please enter a question about your store.');
    }

    final intent = classifyIntent(cleanQuestion);

    try {
      final res = await _effectiveClient.rpc(
        'get_shopkeeper_assistant_analytics',
        params: {
          'p_shop_id': shopId,
          'p_intent': intent,
        },
      ).timeout(_timeout);

      final Map<String, dynamic> data = Map<String, dynamic>.from(res as Map);
      final narrative = synthesizeDeterministicNarrative(intent, data);

      return AiMessage.assistant(
        text: narrative,
        intent: intent,
        metrics: data,
      );
    } catch (err) {
      return AiMessage.error(_cleanError(err));
    }
  }

  /// Deterministically formats business narrative from verified database figures
  String synthesizeDeterministicNarrative(String intent, Map<String, dynamic> data) {
    final shopName = data['shop_name'] as String? ?? 'Your Store';
    final currency = data['currency'] as String? ?? 'INR';
    final sym = currency == 'INR' ? '₹' : '$currency ';

    switch (intent) {
      case 'TODAY_SALES': {
        final rev = (data['total_revenue'] as num?)?.toDouble() ?? 0.0;
        final count = (data['transaction_count'] as num?)?.toInt() ??
            (data['sales_count'] as num?)?.toInt() ??
            (data['total_transactions'] as num?)?.toInt() ??
            0;
        final aov = (data['average_order_value'] as num?)?.toDouble() ??
            (count > 0 ? (rev / count) : 0.0);
        final date = data['date'] as String? ?? 'today';
        final top = data['top_product_today'] as Map<String, dynamic>?;
        final topNameAlt = data['top_product_name'] as String?;

        if (count == 0) {
          return 'Your store has not recorded any completed sales transactions yet today ($date). New bills will update this summary automatically.';
        }

        String topSummary = '';
        if (top != null) {
          final topName = top['name'] as String? ?? 'Product';
          final topQty = (top['quantity'] as num?)?.toDouble() ?? 0.0;
          final topUnit = top['unit_type'] == 'LOOSE' ? 'kg' : 'pcs';
          final qtyFormatted = topUnit == 'kg' ? topQty.toStringAsFixed(3) : topQty.toInt().toString();
          topSummary = '\n\nHighest-selling item: $topName ($qtyFormatted $topUnit sold).';
        } else if (topNameAlt != null && topNameAlt.isNotEmpty) {
          topSummary = '\n\nHighest-selling item: $topNameAlt.';
        }

        return 'Today ($date), $shopName generated $sym${rev.toStringAsFixed(2)} in revenue across $count customer transaction${count == 1 ? '' : 's'}, with an average basket value of $sym${aov.toStringAsFixed(2)}.$topSummary';
      }

      case 'MONTH_SALES': {
        final rev = (data['total_revenue'] as num?)?.toDouble() ?? 0.0;
        final count = (data['transaction_count'] as num?)?.toInt() ??
            (data['sales_count'] as num?)?.toInt() ??
            0;
        final avg = (data['daily_average'] as num?)?.toDouble() ?? 0.0;
        final month = data['month'] as String? ?? 'the current month';

        if (count == 0) {
          return 'No sales transactions have been recorded for $month yet.';
        }

        return 'For $month, $shopName has generated $sym${rev.toStringAsFixed(2)} in total revenue across $count sales transactions, averaging $sym${avg.toStringAsFixed(2)} per day.';
      }

      case 'PERIOD_COMPARE': {
        final thisWeek = (data['this_week_revenue'] as num?)?.toDouble() ?? 0.0;
        final lastWeek = (data['last_week_revenue'] as num?)?.toDouble() ?? 0.0;
        final thisOrders = (data['this_week_orders'] as num?)?.toInt() ?? 0;
        final lastOrders = (data['last_week_orders'] as num?)?.toInt() ?? 0;
        final pct = (data['percentage_change'] as num?)?.toDouble() ?? 0.0;
        final diff = (data['revenue_difference'] as num?)?.toDouble() ?? (thisWeek - lastWeek);
        final isGrowth = diff >= 0;

        return 'Sales Comparison (Last 7 Days vs Prior 7 Days):\n\n'
            '• This Week: $sym${thisWeek.toStringAsFixed(2)} ($thisOrders bills)\n'
            '• Last Week: $sym${lastWeek.toStringAsFixed(2)} ($lastOrders bills)\n'
            '• Trend: ${isGrowth ? '+' : ''}${pct.toStringAsFixed(1)}% (${isGrowth ? 'Growth' : 'Decline'} of $sym${diff.abs().toStringAsFixed(2)})';
      }

      case 'TOP_SELLING': {
        final items = (data['items'] as List?) ?? [];
        if (items.isEmpty) {
          return 'There are no recorded sales over the past 30 days to rank top-selling products.';
        }

        final buffer = StringBuffer('Top-selling products over the last 30 days by quantity:\n\n');
        for (int i = 0; i < items.length; i++) {
          final it = items[i] as Map<String, dynamic>;
          final name = it['name'] as String? ?? it['product_name'] as String? ?? 'Item';
          final qty = (it['total_quantity'] as num?)?.toDouble() ?? (it['quantity'] as num?)?.toDouble() ?? 0.0;
          final rev = (it['total_revenue'] as num?)?.toDouble() ?? 0.0;
          final unit = (it['unit_type'] == 'LOOSE' || it['unit_type'] == 'kg') ? 'kg' : 'pcs';
          final qtyStr = unit == 'kg' ? qty.toStringAsFixed(3) : qty.toInt().toString();

          buffer.writeln('${i + 1}. $name: $qtyStr $unit ($sym${rev.toStringAsFixed(2)})');
        }

        return buffer.toString().trim();
      }

      case 'LOW_STOCK': {
        final total = (data['total_products'] as num?)?.toInt() ?? 0;
        final outList = (data['out_of_stock_items'] as List?) ?? [];
        final lowList = (data['low_stock_items'] as List?) ?? [];

        if (outList.isEmpty && lowList.isEmpty) {
          return 'All $total tracked products in $shopName are currently in stock and above their safety thresholds.';
        }

        final buffer = StringBuffer();
        if (outList.isNotEmpty) {
          buffer.writeln('⚠️ Out of Stock (${outList.length}):');
          for (final it in outList) {
            final m = it as Map<String, dynamic>;
            final name = m['name'] ?? m['product_name'] ?? 'Item';
            final unit = (m['unit_type'] == 'LOOSE' || m['unit_type'] == 'kg') ? 'kg' : 'pcs';
            buffer.writeln('• $name (0 $unit)');
          }
          buffer.writeln();
        }

        if (lowList.isNotEmpty) {
          buffer.writeln('⚡ Running Low (${lowList.length}):');
          for (final it in lowList) {
            final m = it as Map<String, dynamic>;
            final name = m['name'] ?? m['product_name'] ?? 'Item';
            final qty = (m['quantity'] as num?)?.toDouble() ?? (m['current_stock'] as num?)?.toDouble() ?? 0.0;
            final th = (m['threshold'] as num?)?.toDouble() ?? (m['low_stock_threshold'] as num?)?.toDouble() ?? 5.0;
            final unit = (m['unit_type'] == 'LOOSE' || m['unit_type'] == 'kg') ? 'kg' : 'pcs';
            final qtyStr = unit == 'kg' ? qty.toStringAsFixed(3) : qty.toInt().toString();
            final thStr = unit == 'kg' ? th.toStringAsFixed(3) : th.toInt().toString();
            buffer.writeln('• $name: $qtyStr / $thStr $unit');
          }
        }

        return buffer.toString().trim();
      }

      case 'RESTOCK': {
        final recs = (data['recommendations'] as List?) ?? (data['restock_recommendations'] as List?) ?? [];
        if (recs.isEmpty) {
          return 'No products currently require restocking. All catalog items have sufficient inventory buffer.';
        }

        final buffer = StringBuffer('Recommended Restock Plan (based on stock levels and velocity):\n\n');
        for (int i = 0; i < recs.length; i++) {
          final r = recs[i] as Map<String, dynamic>;
          final name = r['name'] as String? ?? r['product_name'] as String? ?? 'Item';
          final curr = (r['current_stock'] as num?)?.toDouble() ?? 0.0;
          final th = (r['threshold'] as num?)?.toDouble() ?? (r['low_stock_threshold'] as num?)?.toDouble() ?? 5.0;
          final suggested = (r['suggested_restock'] as num?)?.toInt() ??
              (r['recommended_order_quantity'] as num?)?.toInt() ??
              5;
          final urgency = r['urgency'] as String? ?? 'NORMAL';
          final unit = (r['unit_type'] == 'LOOSE' || r['unit_type'] == 'kg') ? 'kg' : 'pcs';
          final currStr = unit == 'kg' ? curr.toStringAsFixed(3) : curr.toInt().toString();
          final thStr = unit == 'kg' ? th.toStringAsFixed(3) : th.toInt().toString();

          buffer.writeln('${i + 1}. $name [$urgency]');
          buffer.writeln('   Current stock: $currStr $unit (Safety threshold: $thStr $unit)');
          buffer.writeln('   Suggested restock: +$suggested $unit');
          if (i < recs.length - 1) buffer.writeln();
        }

        return buffer.toString().trim();
      }

      case 'SLOW_MOVING': {
        final items = (data['items'] as List?) ?? [];
        if (items.isEmpty) {
          return 'No slow-moving products were detected over the past 30 days. All active items show consistent movement.';
        }

        final buffer = StringBuffer('Slow-Moving Products (last 30 days):\n\n');
        for (int i = 0; i < items.length; i++) {
          final it = items[i] as Map<String, dynamic>;
          final name = it['name'] as String? ?? it['product_name'] as String? ?? 'Item';
          final curr = (it['current_stock'] as num?)?.toDouble() ?? 0.0;
          final sold = (it['units_sold_30d'] as num?)?.toDouble() ?? 0.0;
          final days = (it['days_stocked'] as num?)?.toInt() ?? 0;
          final unit = (it['unit_type'] == 'LOOSE' || it['unit_type'] == 'kg') ? 'kg' : 'pcs';
          final currStr = unit == 'kg' ? curr.toStringAsFixed(3) : curr.toInt().toString();

          buffer.writeln('${i + 1}. $name: $sold $unit sold (Stock: $currStr $unit, stocked for $days days)');
        }

        buffer.writeln('\nTip: Consider repositioning these items or running an in-store promotion.');
        return buffer.toString().trim();
      }

      case 'CROSS_SHOP': {
        final authorized = (data['authorized'] as bool?) ?? (data['is_org_admin'] as bool?) ?? false;
        if (!authorized) {
          return data['privacy_message'] as String? ??
              data['message'] as String? ??
              'Cross-shop trends and multi-branch network analytics are restricted to organization administrators to protect store data privacy.';
        }

        final branches = (data['total_organization_branches'] as num?)?.toInt() ?? 0;
        final rev = (data['total_network_today_revenue'] as num?)?.toDouble() ?? 0.0;

        return 'Organization Overview:\n\n'
            '• Active Branches: $branches\n'
            '• Total Network Revenue Today: $sym${rev.toStringAsFixed(2)}\n\n'
            'Individual branch records remain strictly isolated for privacy.';
      }

      case 'GENERAL_OVERVIEW':
      default: {
        final rev = (data['today_revenue'] as num?)?.toDouble() ?? 0.0;
        final orders = (data['today_orders'] as num?)?.toInt() ?? 0;
        final total = (data['total_items'] as num?)?.toInt() ?? 0;
        final low = (data['low_stock_count'] as num?)?.toInt() ?? 0;
        final out = (data['out_of_stock_count'] as num?)?.toInt() ?? 0;

        return 'Here is your store snapshot for $shopName:\n\n'
            '• Today\'s Revenue: $sym${rev.toStringAsFixed(2)} ($orders customer bills)\n'
            '• Inventory: $total items tracked ($low low-stock alert${low == 1 ? '' : 's'}, $out out-of-stock)\n\n'
            'You can ask me about top-selling items, restocking advice, or weekly comparisons.';
      }
    }
  }

  String _cleanError(dynamic err) {
    if (err is PostgrestException) {
      if (err.message.contains('Unauthorized')) {
        return 'Access Denied: You are not authorized to view analytics for this shop.';
      }
      return err.message;
    }
    final msg = err.toString().replaceFirst('Exception: ', '');
    if (msg.contains('TimeoutException')) {
      return 'The request timed out. Please check your network connection and try again.';
    }
    return msg;
  }
}
