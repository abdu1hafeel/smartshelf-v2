// ==============================================================================
// SmartShelf V2 - Category Model
// ==============================================================================

class Category {
  final String id;
  final String organizationId;
  final String name;
  final String? description;

  const Category({
    required this.id,
    required this.organizationId,
    required this.name,
    this.description,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'name': name,
      'description': description,
    };
  }
}
