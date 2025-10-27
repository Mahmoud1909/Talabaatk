// lib/utils/category_model.dart
class CategoryModel {
  final String id;
  final String restaurantId;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final String? description;
  final String? imageUrl;
  final String? imagePath;
  final String? restaurantName; // new optional field

  CategoryModel({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    this.description,
    this.imageUrl,
    this.imagePath,
    this.restaurantName,
  });

  factory CategoryModel.fromMap(Map<String, dynamic> m) {
    final createdRaw = m['created_at'];
    DateTime createdAt;
    if (createdRaw == null) {
      createdAt = DateTime.now();
    } else if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now();
    } else if (createdRaw is DateTime) {
      createdAt = createdRaw;
    } else {
      createdAt = DateTime.now();
    }

    // restaurants may be returned as nested map if you requested restaurants(name)
    String? restaurantName;
    if (m['restaurants'] is Map<String, dynamic>) {
      restaurantName = (m['restaurants'] as Map<String, dynamic>)['name'] as String?;
    } else if (m['restaurant_name'] != null) {
      restaurantName = m['restaurant_name'] as String?;
    }

    return CategoryModel(
      id: (m['id'] ?? '') as String,
      restaurantId: (m['restaurant_id'] ?? '') as String,
      name: ((m['name'] ?? '') as String).trim(),
      sortOrder: (m['sort_order'] ?? 0) is int
          ? (m['sort_order'] ?? 0) as int
          : int.tryParse((m['sort_order'] ?? '0').toString()) ?? 0,
      createdAt: createdAt,
      description: m['description'] as String?,
      imageUrl: m['image_url'] as String?,
      imagePath: m['image_path'] as String?,
      restaurantName: restaurantName,
    );
  }
}
