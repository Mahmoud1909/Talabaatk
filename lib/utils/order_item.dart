// lib/utils/order_item.dart
class OrderItem {
  final String id;
  final String orderId;
  final String menuItemId;
  final String? variantId;
  final String name;
  final double unitPrice;
  final int qty;
  final String? imageUrl;
  final String? notes;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.menuItemId,
    this.variantId,
    required this.name,
    required this.unitPrice,
    required this.qty,
    this.imageUrl,
    this.notes,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      menuItemId: json['menu_item_id'] as String,
      variantId: json['variant_id'] as String?,
      name: json['name'] as String? ?? '',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      qty: (json['qty'] as int?) ?? (json['quantity'] as int?) ?? 0,
      imageUrl: json['image_url'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'menu_item_id': menuItemId,
      'variant_id': variantId,
      'name': name,
      'unit_price': unitPrice,
      'qty': qty,
      'image_url': imageUrl,
      'notes': notes,
    };
  }
}


