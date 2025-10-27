// lib/models/branch.dart
class Branch {
  final String id;
  final String? restaurantId;
  final String address;
  final DateTime? createdAt;
  final String? name;
  final double? latitude;
  final double? longitude;
  final String? placeId;
  final DateTime? lastLocationAt;

  Branch({
    required this.id,
    this.restaurantId,
    required this.address,
    this.createdAt,
    this.name,
    this.latitude,
    this.longitude,
    this.placeId,
    this.lastLocationAt,
  });

  factory Branch.fromMap(Map<String, dynamic> m) {
    return Branch(
      id: m['id'] as String,
      restaurantId: m['restaurant_id'] as String?,
      address: m['address'] as String? ?? '',
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      name: m['name'] as String?,
      latitude: (m['latitude'] is num) ? (m['latitude'] as num).toDouble() : double.tryParse(m['latitude']?.toString() ?? ''),
      longitude: (m['longitude'] is num) ? (m['longitude'] as num).toDouble() : double.tryParse(m['longitude']?.toString() ?? ''),
      placeId: m['place_id'] as String?,
      lastLocationAt: m['last_location_at'] != null ? DateTime.tryParse(m['last_location_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'address': address,
    'created_at': createdAt?.toIso8601String(),
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'place_id': placeId,
    'last_location_at': lastLocationAt?.toIso8601String(),
  };
}
