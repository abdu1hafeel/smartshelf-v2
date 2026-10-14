// ==============================================================================
// SmartShelf V2 - Sale and Sale Item Models
// ==============================================================================

class SaleItem {
  final String id;
  final String saleId;
  final String productId;
  final String productName;
  final String unitType;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? weightTicketId;

  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.productName,
    required this.unitType,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.weightTicketId,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      unitType: (json['unit_type'] as String?) ?? 'PACKAGED',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0.0,
      weightTicketId: json['weight_ticket_id'] as String?,
    );
  }
}

class Sale {
  final String id;
  final String shopId;
  final String saleNumber;
  final double totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final String? notes;
  final DateTime createdAt;
  final List<SaleItem> items;

  const Sale({
    required this.id,
    required this.shopId,
    required this.saleNumber,
    required this.totalAmount,
    required this.paymentMethod,
    this.paymentStatus = 'COMPLETED',
    this.notes,
    required this.createdAt,
    this.items = const [],
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    List<SaleItem> saleItems = [];
    if (json['sale_items'] != null && json['sale_items'] is List) {
      saleItems = (json['sale_items'] as List)
          .map((item) => SaleItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return Sale(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      saleNumber: json['sale_number'] as String,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: (json['payment_method'] as String?) ?? 'CASH',
      paymentStatus: (json['payment_status'] as String?) ?? 'COMPLETED',
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      items: saleItems,
    );
  }
}
