// ==============================================================================
// SmartShelf V2 - Shop Model
// ==============================================================================

class Shop {
  final String id;
  final String organizationId;
  final String name;
  final String? location;
  final String currency;
  final DateTime createdAt;

  const Shop({
    required this.id,
    required this.organizationId,
    required this.name,
    this.location,
    this.currency = 'INR',
    required this.createdAt,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      name: json['name'] as String,
      location: json['location'] as String?,
      currency: (json['currency'] as String?) ?? 'INR',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'name': name,
      'location': location,
      'currency': currency,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
