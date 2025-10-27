// lib/models/menu_item_model.dart
class MenuItemModel {
  final String id;
  final String restaurantId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool hasDiscount;
  final double discountPercent;
  final String? categoryId;

  MenuItemModel({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    this.hasDiscount = false,
    this.discountPercent = 0.0,
    this.categoryId,
  });

  factory MenuItemModel.fromMap(Map<String, dynamic> m) {
    return MenuItemModel(
      id: (m['id'] as String),
      restaurantId: (m['restaurant_id'] as String),
      name: (m['name'] ?? '') as String,
      description: m['description'] as String?,
      price: m['price'] != null ? (m['price'] as num).toDouble() : 0.0,
      imageUrl: m['image_url'] as String?,
      hasDiscount: (m['has_discount'] as bool?) ?? false,
      discountPercent: m['discount_percent'] != null ? (m['discount_percent'] as num).toDouble() : 0.0,
      categoryId: m['category_id'] as String?,
    );
  }

  double effectivePrice() {
    if (!hasDiscount || discountPercent <= 0) return price;
    return (price * (1.0 - (discountPercent / 100.0)));
  }
}

class MenuItemVariant {
  final String id;
  final String menuItemId;
  final String name;
  final double extraPrice;
  final int sortOrder;

  MenuItemVariant({
    required this.id,
    required this.menuItemId,
    required this.name,
    required this.extraPrice,
    this.sortOrder = 0,
  });

  factory MenuItemVariant.fromMap(Map<String, dynamic> m) {
    return MenuItemVariant(
      id: m['id'] as String,
      menuItemId: m['menu_item_id'] as String,
      name: (m['name'] ?? '') as String,
      extraPrice: m['extra_price'] != null ? (m['extra_price'] as num).toDouble() : 0.0,
      sortOrder: (m['sort_order'] as int?) ?? 0,
    );
  }
}

class MenuItemWithVariants {
  final MenuItemModel item;
  final List<MenuItemVariant> variants;

  MenuItemWithVariants({required this.item, required this.variants});
}
