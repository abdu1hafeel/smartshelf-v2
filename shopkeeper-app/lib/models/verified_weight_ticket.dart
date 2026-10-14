// ==============================================================================
// SmartShelf V2 - Verified Weight Ticket Model (Scale Telemetry)
// ==============================================================================

class VerifiedWeightTicket {
  final String id;
  final String shopId;
  final String deviceId;
  final String productId;
  final double weightGrams;
  final double weightKg;
  final bool isConsumed;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String? deviceName;
  final String? deviceIdentifier;

  const VerifiedWeightTicket({
    required this.id,
    required this.shopId,
    required this.deviceId,
    required this.productId,
    required this.weightGrams,
    required this.weightKg,
    required this.isConsumed,
    required this.expiresAt,
    required this.createdAt,
    this.deviceName,
    this.deviceIdentifier,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isValidForCheckout => !isConsumed && !isExpired;

  factory VerifiedWeightTicket.fromJson(Map<String, dynamic> json) {
    String? devName;
    String? devIdStr;
    if (json['device'] != null && json['device'] is Map) {
      devName = json['device']['name'] as String?;
      devIdStr = json['device']['device_identifier'] as String?;
    }

    final grams = (json['weight_grams'] as num?)?.toDouble() ?? 0.0;
    final kg = (json['weight_kg'] as num?)?.toDouble() ?? (grams / 1000.0);

    return VerifiedWeightTicket(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      deviceId: json['device_id'] as String,
      productId: json['product_id'] as String,
      weightGrams: grams,
      weightKg: kg,
      isConsumed: (json['is_consumed'] as bool?) ?? false,
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      deviceName: devName,
      deviceIdentifier: devIdStr,
    );
  }
}
