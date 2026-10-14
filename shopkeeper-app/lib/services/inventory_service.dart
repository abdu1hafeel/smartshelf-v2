// ==============================================================================
// SmartShelf V2 - Shop Inventory & Catalog Service
// ==============================================================================

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/shop_inventory_item.dart';

class InventoryService {
  static const Duration _timeout = Duration(seconds: 12);
  final SupabaseClient? _client;

  InventoryService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _effectiveClient => _client ?? SupabaseConfig.client;

  /// Fetches all stocked inventory items for the selected shop location
  Future<List<ShopInventoryItem>> fetchShopInventory(String shopId) async {
    final response = await _effectiveClient
        .from('shop_inventory')
        .select('*, product:products(*, category:categories(*))')
        .eq('shop_id', shopId)
        .order('updated_at', ascending: false)
        .timeout(_timeout);

    return (response as List)
        .map((json) => ShopInventoryItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Looks up a product by barcode or SKU and returns its shop inventory record
  Future<ShopInventoryItem?> lookupByBarcode({
    required String shopId,
    required String barcodeOrSku,
  }) async {
    final code = barcodeOrSku.trim();
    if (code.isEmpty) return null;

    // 1. Find product matching barcode or SKU
    final prodRows = await _effectiveClient
        .from('products')
        .select('*, category:categories(*)')
        .or('barcode.eq.$code,sku.eq.$code')
        .eq('is_active', true)
        .limit(1)
        .timeout(_timeout);

    if (prodRows.isEmpty) {
      return null;
    }

    final product = Product.fromJson(prodRows.first);

    // 2. Fetch inventory status in active shop
    final invRows = await _effectiveClient
        .from('shop_inventory')
        .select('*')
        .eq('shop_id', shopId)
        .eq('product_id', product.id)
        .maybeSingle()
        .timeout(_timeout);

    if (invRows == null) {
      // Product exists in organization catalog but is not yet stocked in this shop
      return null;
    }

    return ShopInventoryItem.fromJson(
      invRows,
      attachedProduct: product,
    );
  }

  /// Fetches count of active IoT scale devices for the shop
  Future<int> fetchActiveScaleCount(String shopId) async {
    try {
      final res = await _effectiveClient
          .from('devices')
          .select('id')
          .eq('shop_id', shopId)
          .eq('is_active', true)
          .timeout(_timeout);

      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Fetches organization categories
  Future<List<Category>> fetchCategories(String organizationId) async {
    try {
      final res = await _effectiveClient
          .from('categories')
          .select('*')
          .eq('organization_id', organizationId)
          .order('name')
          .timeout(_timeout);

      return (res as List)
          .map((json) => Category.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (err) {
      // Non-fatal if categories fail to load
      return [];
    }
  }

  /// Looks up whether a barcode or SKU is already registered in the organization's catalog
  Future<Product?> findProductByBarcode({
    required String organizationId,
    required String barcodeOrSku,
  }) async {
    final code = barcodeOrSku.trim();
    if (code.isEmpty) return null;

    try {
      final rows = await _effectiveClient
          .from('products')
          .select('*, category:categories(*)')
          .eq('organization_id', organizationId)
          .or('barcode.eq.$code,sku.eq.$code')
          .limit(1)
          .timeout(_timeout);

      final list = rows as List;
      if (list.isEmpty) return null;
      return Product.fromJson(list.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Fetches catalog products not yet enrolled in this shop's inventory
  Future<List<Product>> fetchUnstockedCatalogProducts({
    required String organizationId,
    required String shopId,
  }) async {
    try {
      // 1. Fetch current shop inventory product IDs
      final invRows = await _effectiveClient
          .from('shop_inventory')
          .select('product_id')
          .eq('shop_id', shopId)
          .timeout(_timeout);

      final stockedIds = (invRows as List).map((r) => r['product_id'] as String).toSet();

      // 2. Fetch active catalog products
      final prodRows = await _effectiveClient
          .from('products')
          .select('*, category:categories(*)')
          .eq('organization_id', organizationId)
          .eq('is_active', true)
          .order('name')
          .timeout(_timeout);

      final unstocked = <Product>[];
      for (final r in prodRows as List) {
        final p = Product.fromJson(r as Map<String, dynamic>);
        if (!stockedIds.contains(p.id)) {
          unstocked.add(p);
        }
      }
      return unstocked;
    } catch (_) {
      return [];
    }
  }

  /// Creates a new product in the organization catalog and enrolls it into the shop's inventory
  Future<Map<String, dynamic>> createProductAndEnroll({
    required String organizationId,
    required String shopId,
    String? categoryId,
    required String name,
    String? barcode,
    String? sku,
    required String unitType,
    String? description,
    required double sellingPrice,
    required double initialQuantity,
    double lowStockThreshold = 5.0,
  }) async {
    // 1. Create product via secure RPC
    final prodRes = await _effectiveClient.rpc('create_product', params: {
      'p_organization_id': organizationId,
      'p_category_id': categoryId?.trim().isEmpty == true ? null : categoryId,
      'p_name': name.trim(),
      'p_barcode': (barcode != null && barcode.trim().isNotEmpty) ? barcode.trim() : null,
      'p_sku': (sku != null && sku.trim().isNotEmpty) ? sku.trim() : null,
      'p_unit_type': unitType,
      'p_description': (description != null && description.trim().isNotEmpty) ? description.trim() : null,
    }).timeout(_timeout);

    final productId = (prodRes as Map<String, dynamic>)['product_id'] as String;

    // 2. Enroll product into shop inventory with initial price & stock
    final invRes = await _effectiveClient.rpc('setup_shop_inventory', params: {
      'p_shop_id': shopId,
      'p_product_id': productId,
      'p_selling_price': sellingPrice,
      'p_initial_quantity': initialQuantity,
      'p_low_stock_threshold': lowStockThreshold,
    }).timeout(_timeout);

    return {
      'product_id': productId,
      'inventory': invRes,
    };
  }

  /// Enrolls an existing unstocked catalog product into shop inventory
  Future<void> enrollExistingProduct({
    required String shopId,
    required String productId,
    required double sellingPrice,
    required double initialQuantity,
    double lowStockThreshold = 5.0,
  }) async {
    await _effectiveClient.rpc('setup_shop_inventory', params: {
      'p_shop_id': shopId,
      'p_product_id': productId,
      'p_selling_price': sellingPrice,
      'p_initial_quantity': initialQuantity,
      'p_low_stock_threshold': lowStockThreshold,
    }).timeout(_timeout);
  }

  /// Increases stock for an existing product using the auditable restock_inventory RPC
  Future<Map<String, dynamic>> restockProduct({
    required String shopId,
    required String productId,
    required double quantity,
    String? reason,
  }) async {
    final res = await _effectiveClient.rpc('restock_inventory', params: {
      'p_shop_id': shopId,
      'p_product_id': productId,
      'p_quantity': quantity,
      'p_reason': (reason != null && reason.trim().isNotEmpty)
          ? reason.trim()
          : 'Stock shipment delivery',
    }).timeout(_timeout);

    return Map<String, dynamic>.from(res as Map);
  }
}
