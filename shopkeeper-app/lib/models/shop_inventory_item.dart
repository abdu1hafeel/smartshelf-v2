// ==============================================================================
// SmartShelf V2 - Shop Inventory Item Model
// ==============================================================================

import 'product.dart';

class ShopInventoryItem {
  final String shopId;
  final String productId;
  final double sellingPrice;
  final double quantity;
  final double lowStockThreshold;
  final bool isAvailable;
  final DateTime updatedAt;
  final Product? product;

  const ShopInventoryItem({
    required this.shopId,
    required this.productId,
    required this.sellingPrice,
    required this.quantity,
    this.lowStockThreshold = 5.0,
    this.isAvailable = true,
    required this.updatedAt,
    this.product,
  });

  bool get isOutOfStock => quantity <= 0;
  bool get isLowStock => quantity <= lowStockThreshold && !isOutOfStock;

  factory ShopInventoryItem.fromJson(Map<String, dynamic> json, {Product? attachedProduct}) {
    Product? prod = attachedProduct;
    if (prod == null && json['product'] != null && json['product'] is Map<String, dynamic>) {
      prod = Product.fromJson(json['product'] as Map<String, dynamic>);
    }

    return ShopInventoryItem(
      shopId: json['shop_id'] as String,
      productId: json['product_id'] as String,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      lowStockThreshold: (json['low_stock_threshold'] as num?)?.toDouble() ?? 5.0,
      isAvailable: (json['is_available'] as bool?) ?? true,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
      product: prod,
    );
  }

  ShopInventoryItem copyWith({Product? product}) {
    return ShopInventoryItem(
      shopId: shopId,
      productId: productId,
      sellingPrice: sellingPrice,
      quantity: quantity,
      lowStockThreshold: lowStockThreshold,
      isAvailable: isAvailable,
      updatedAt: updatedAt,
      product: product ?? this.product,
    );
  }
}
