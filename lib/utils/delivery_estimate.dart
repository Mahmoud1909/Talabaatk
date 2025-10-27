// lib/utils/delivery_estimate.dart
class DeliveryEstimate {
  final double distanceMeters; // عدد أمتار (مثلاً 1523.45)
  final double distanceKm;     // كم مكافئ (مثلاً 1.523)
  final int chargedKm;         // الكيلومترات المحتسبة (قيمة integer حسب القاعدة)
  final double cost;           // المبلغ النهائي
  final int durationSeconds;   // زمن الرحلة بتانيه (تقديري)
  final double perKmPrice;     // سعر الكيلو المستخدم في الحساب
  final String? pricingId;     // id لصف التّسعير إن وجد (nullable)

  DeliveryEstimate({
    required this.distanceMeters,
    required this.distanceKm,
    required this.chargedKm,
    required this.cost,
    required this.durationSeconds,
    required this.perKmPrice,
    this.pricingId,
  });

  // مَصنَع من Map (مناسب لنتيجة RPC أو DB)
  factory DeliveryEstimate.fromMap(Map<String, dynamic> m) {
    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    int _toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.round();
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? (double.tryParse(v)?.round() ?? 0);
      return 0;
    }

    return DeliveryEstimate(
      distanceMeters: _toDouble(m['distance_meters'] ?? m['distanceMeters'] ?? 0),
      distanceKm: _toDouble(m['distance_km'] ?? m['distanceKm'] ?? 0),
      chargedKm: _toInt(m['charged_km'] ?? m['chargedKm'] ?? m['chargedKmRounded'] ?? 0),
      cost: _toDouble(m['delivery_fee'] ?? m['cost'] ?? 0),
      durationSeconds: _toInt(m['duration_seconds'] ?? m['durationSeconds'] ?? 0),
      perKmPrice: _toDouble(m['per_km_price'] ?? m['perKmPrice'] ?? 0),
      pricingId: (m['pricing_id'] ?? m['pricingId'])?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'distance_meters': distanceMeters,
    'distance_km': distanceKm,
    'charged_km': chargedKm,
    'delivery_fee': cost,
    'duration_seconds': durationSeconds,
    'per_km_price': perKmPrice,
    'pricing_id': pricingId,
  };
}
