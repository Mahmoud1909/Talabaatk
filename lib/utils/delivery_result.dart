// lib/models/delivery_result.dart
class DeliveryResult {
  final int distanceMeters;
  final double distanceKm;
  final double chargedKm;
  final double cost;

  DeliveryResult({
    required this.distanceMeters,
    required this.distanceKm,
    required this.chargedKm,
    required this.cost,
  });

  factory DeliveryResult.fromJson(Map<String, dynamic> j) {
    return DeliveryResult(
      distanceMeters: j['distance_m'] as int,
      distanceKm: (j['distance_km'] as num).toDouble(),
      chargedKm: (j['charged_km'] as num).toDouble(),
      cost: (j['cost'] as num).toDouble(),
    );
  }
}
