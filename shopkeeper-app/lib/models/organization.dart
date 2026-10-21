// ==============================================================================
// SmartShelf V2 - Organization Model
// ==============================================================================

class Organization {
  final String id;
  final String name;
  final DateTime createdAt;

  const Organization({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Returns 8-character prefix of UUID for disambiguating duplicate organization names
  String get shortId => id.length >= 8 ? id.substring(0, 8) : id;

  /// Returns user-facing label, appending short ID if multiple organizations share the same name
  String displayName({bool isDuplicate = false}) {
    return isDuplicate ? '$name ($shortId)' : name;
  }
}
