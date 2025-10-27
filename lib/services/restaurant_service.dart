// lib/services/restaurant_service.dart
// NearestRestaurant model + getNearestRestaurants RPC wrapper.
// Depends on lib/services/supabase_client.dart which should expose `final SupabaseClient supabase = Supabase.instance.client;`

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/services/supabase_client.dart' as client_holder;
import 'package:talabak_users/utils/Restaurant_Model.dart';

final SupabaseClient _supabase = client_holder.supabase;

/// Model representing a nearby restaurant together with branch information.
class NearestRestaurant {
  final String restaurantId;
  final String restaurantName;
  final String? logoUrl;
  final double? deliveryFee;
  final int? prepMin;
  final int? prepMax;
  final String branchId;
  final String branchAddress;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;
  final String? category;

  NearestRestaurant({
    required this.restaurantId,
    required this.restaurantName,
    this.logoUrl,
    this.deliveryFee,
    this.prepMin,
    this.prepMax,
    required this.branchId,
    required this.branchAddress,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.category,
  });

  factory NearestRestaurant.fromMap(Map<String, dynamic> map) {
    return NearestRestaurant(
      restaurantId: map['restaurant_id'] as String,
      restaurantName: map['restaurant_name'] as String,
      logoUrl: map['logo_url'] as String?,
      deliveryFee: map['delivery_fee'] != null ? (map['delivery_fee'] as num).toDouble() : null,
      prepMin: map['prep_time_min'] as int?,
      prepMax: map['prep_time_max'] as int?,
      branchId: map['branch_id'] as String,
      branchAddress: map['branch_address'] as String,
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      distanceMeters: map['distance_meters'] != null ? (map['distance_meters'] as num).toDouble() : null,
      category: map['category'] as String?,
    );
  }
}

/// Fetch nearest restaurants (optionally filtered by category name).
/// - Sends `p_lat`, `p_lon`, `p_limit` and optionally `p_category` (TEXT) to the RPC.
/// - Handles PostgrestResponse.error and robustly converts returned rows to model objects.
Future<List<NearestRestaurant>> getNearestRestaurants({
  required double lat,
  required double lon,
  int limit = 20,
  String? category,
})
async {
  try {
    final params = {
      'p_lat': lat,
      'p_lon': lon,
      'p_limit': limit,
      if (category != null) 'p_category': category,
    };

    debugPrint('[getNearestRestaurants] called with params: $params');

    // RPC call - depends on your Postgres function `get_nearest_restaurants`
    final dynamic response = await _supabase.rpc('get_nearest_restaurants', params: params);

    debugPrint('[getNearestRestaurants] raw response type: ${response.runtimeType}');
    try {
      debugPrint(
        '[getNearestRestaurants] raw response (toString snippet): ${response.toString().substring(0, response.toString().length > 500 ? 500 : response.toString().length)}',
      );
    } catch (_) {}

    List<dynamic> rows = <dynamic>[];

    try {
      // If response has error/data fields (PostgrestResponse-like)
      final dynamic maybeError = response.error;
      if (maybeError != null) {
        debugPrint('getNearestRestaurants RPC returned error: ${maybeError?.message ?? maybeError}');
        return [];
      }
      final dynamic maybeData = response.data;
      if (maybeData == null) {
        debugPrint('[getNearestRestaurants] response.data is null');
        return [];
      }
      rows = maybeData is List ? maybeData : <dynamic>[maybeData];
    } catch (_) {
      // fallback: if RPC returned a plain List
      if (response is List) {
        rows = response;
      } else {
        debugPrint('getNearestRestaurants: unexpected RPC response type: ${response.runtimeType}');
        return [];
      }
    }

    debugPrint('[getNearestRestaurants] rows length (raw): ${rows.length}');
    if (rows.isNotEmpty) {
      for (var i = 0; i < (rows.length > 3 ? 3 : rows.length); i++) {
        debugPrint(
          '[getNearestRestaurants] row[$i] keys: ${(rows[i] is Map) ? (rows[i] as Map).keys.toList() : rows[i].toString()}',
        );
      }
    }

    final List<NearestRestaurant> result = <NearestRestaurant>[];
    for (final item in rows) {
      if (item is Map) {
        try {
          result.add(NearestRestaurant.fromMap(Map<String, dynamic>.from(item)));
        } catch (e) {
          debugPrint('getNearestRestaurants: failed parsing row -> $e');
        }
      } else {
        debugPrint('getNearestRestaurants: skipping non-Map row (type ${item.runtimeType})');
      }
    }

    debugPrint('[getNearestRestaurants] parsed result length: ${result.length}');
    return result;
  } catch (e, st) {
    debugPrint('getNearestRestaurants ERROR (exception): $e\n$st');
    return [];
  }
}
