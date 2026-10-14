// ==============================================================================
// SmartShelf V2 - Product Model
// ==============================================================================

class Product {
  final String id;
  final String organizationId;
  final String? categoryId;
  final String name;
  final String? barcode;
  final String? sku;
  final String unitType; // 'PACKAGED' or 'LOOSE'
  final String? description;
  final bool isActive;
  final String? categoryName;

  const Product({
    required this.id,
    required this.organizationId,
    this.categoryId,
    required this.name,
    this.barcode,
    this.sku,
    required this.unitType,
    this.description,
    this.isActive = true,
    this.categoryName,
  });

  bool get isPackaged => unitType == 'PACKAGED';
  bool get isLoose => unitType == 'LOOSE';

  factory Product.fromJson(Map<String, dynamic> json) {
    String? catName;
    if (json['category'] != null && json['category'] is Map) {
      catName = json['category']['name'] as String?;
    }

    return Product(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      categoryId: json['category_id'] as String?,
      name: json['name'] as String,
      barcode: json['barcode'] as String?,
      sku: json['sku'] as String?,
      unitType: (json['unit_type'] as String?) ?? 'PACKAGED',
      description: json['description'] as String?,
      isActive: (json['is_active'] as bool?) ?? true,
      categoryName: catName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'category_id': categoryId,
      'name': name,
      'barcode': barcode,
      'sku': sku,
      'unit_type': unitType,
      'description': description,
      'is_active': isActive,
    };
  }
}
