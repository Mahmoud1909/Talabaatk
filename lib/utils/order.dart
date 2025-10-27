// lib/utils/order.dart
import 'order_item.dart';

class Order {
  final String id;
  final String customerId;
  final String restaurantId;
  final String? branchId;
  final String? driverId;
  final double total;
  final String status;
  final DateTime createdAt;

  // 🛵 بيانات التوصيل
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? deliveryPlaceId;
  final String? deliveryAddress;
  final double? deliveryFee;       // ✅ جديد
  final double? perKmPrice;        // ✅ جديد
  final double? distanceMeters;    // كان موجود (احتفظنا به)
  final int? durationSeconds;      // كان موجود (احتفظنا به)

  // 📝 إضافات المستخدم
  final String? comment;
  final String? customerPhone;

  final double? branchLatitude;    // ✅ جديد
  final double? branchLongitude;   // ✅ جديد

  final List<OrderItem> items;
  final int? chargedKm;   // ← غيرناها من double? إلى int?


  Order({
    required this.id,
    required this.customerId,
    required this.restaurantId,
    this.branchId,
    this.driverId,
    required this.total,
    required this.status,
    required this.createdAt,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryPlaceId,
    this.deliveryAddress,
    this.deliveryFee,
    this.chargedKm,
    this.perKmPrice,
    this.distanceMeters,
    this.durationSeconds,
    this.comment,
    this.customerPhone,
    this.branchLatitude,
    this.branchLongitude,
    this.items = const [],
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      restaurantId: json['restaurant_id'] as String,
      branchId: json['branch_id'] as String?,
      driverId: json['driver_id'] as String?,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      deliveryLatitude: (json['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (json['delivery_longitude'] as num?)?.toDouble(),
      deliveryPlaceId: json['delivery_place_id'] as String?,
      deliveryAddress: json['delivery_address'] as String?,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble(),
      chargedKm: (json['charged_km'] as num?)?.toInt(),

      perKmPrice: (json['per_km_price'] as num?)?.toDouble(),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      durationSeconds: json['duration_seconds'] as int?,
      comment: json['comment'] as String?,
      customerPhone: json['customer_phone'] as String?,
      branchLatitude: (json['branch_latitude'] as num?)?.toDouble(),
      branchLongitude: (json['branch_longitude'] as num?)?.toDouble(),
      items: (json['order_items'] != null && json['order_items'] is List)
          ? (json['order_items'] as List)
          .map((i) => OrderItem.fromJson(Map<String, dynamic>.from(i as Map)))
          .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'restaurant_id': restaurantId,
      'total': total,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'branch_id': branchId,
      'delivery_latitude': deliveryLatitude,
      'delivery_longitude': deliveryLongitude,
      'delivery_address': deliveryAddress,
      'comment': comment,
      'customer_phone': customerPhone,
      'delivery_fee': deliveryFee,
      'charged_km': chargedKm,
      'per_km_price': perKmPrice,
      'order_items': items.map((i) => i.toJson()).toList(),
    };
  }


}
