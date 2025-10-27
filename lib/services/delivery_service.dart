import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/utils/Branch_Model.dart';
import 'package:talabak_users/utils/delivery_estimate.dart';

class DeliveryService {
  final SupabaseClient supabase;
  final double defaultPricePerKm;
  final double defaultBaseFee;
  final double defaultMinKm;
  final Duration rpcTimeout;
  final int rpcRetries;

  DeliveryService({
    required this.supabase,
    this.defaultPricePerKm = 5.0, // note: per-km default in EGP (adjust if you used different unit)
    this.defaultBaseFee = 10.0,
    this.defaultMinKm = 3.0,
    this.rpcTimeout = const Duration(seconds: 8),
    this.rpcRetries = 2,
  });

  // ---------- helpers ----------
  double _degToRad(double deg) => deg * (pi / 180.0);

  /// Haversine -> meters
  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  int _computeChargedKm(double distanceKm, double minKm) {
    // rule: if km <= minKm -> charge minKm (as integer)
    if (distanceKm <= minKm) return minKm.ceil();
    return distanceKm.ceil();
  }

  double _roundTo(double value, int digits) {
    final factor = pow(10, digits);
    return ((value * factor).round()) / factor;
  }

  double _roundCost(double value) => _roundTo(value, 2);

  // ---------- local estimate ----------
  /// Now includes baseFee and minKm so local and pricing-based calculations remain consistent.
  /// pricePerKm = per-km price (EGP/km), baseFee = flat base fee (EGP), minKm = minimum charged km
  DeliveryEstimate estimateLocal({
    required double branchLat,
    required double branchLng,
    required double userLat,
    required double userLng,
    double? pricePerKm,
    double? baseFee,
    double? minKm,
  }) {
    final perKm = pricePerKm ?? defaultPricePerKm;
    final bFee = baseFee ?? defaultBaseFee;
    final mKm = minKm ?? defaultMinKm;

    final distM = _haversineMeters(branchLat, branchLng, userLat, userLng);
    final distKm = distM / 1000.0;
    final charged = _computeChargedKm(distKm, mKm); // int
    final cost = _roundCost(bFee + (charged * perKm));

    // crude duration estimate (assume average 30 km/h -> 30000 m/h)
    final durationSeconds = (distM / (30000.0 / 3600.0)).ceil();

    return DeliveryEstimate(
      distanceMeters: distM,
      distanceKm: _roundTo(distKm, 3),
      chargedKm: charged,
      cost: cost,
      durationSeconds: durationSeconds,
      perKmPrice: perKm,
      pricingId: null, // local calc - no pricing id
      // If your DeliveryEstimate model has fields for baseFee/minKm, you can set them too.
    );
  }

  // ---------- fetch branch ----------
  Future<Branch?> fetchBranchById(String branchId) async {
    try {
      final res = await supabase
          .from('branches')
          .select('id, restaurant_id, name, latitude, longitude, address, place_id, created_at, last_location_at')
          .eq('id', branchId)
          .maybeSingle();

      if (res == null) return null;

      // support different SDK shapes
      try {
        final dynamic maybeError = res is Map && res.containsKey('error') ? res['error'] : null;
        final dynamic maybeData = res is Map && res.containsKey('data') ? res['data'] : null;
        if (maybeData != null) {
          if (maybeData is Map) return Branch.fromMap(Map<String, dynamic>.from(maybeData));
          if (maybeData is List && maybeData.isNotEmpty) return Branch.fromMap(Map<String, dynamic>.from(maybeData[0] as Map));
        }
      } catch (_) {
        // ignore
      }

      if (res is Map) {
        return Branch.fromMap(Map<String, dynamic>.from(res));
      }

      if (res is List && res.isNotEmpty) {
        return Branch.fromMap(Map<String, dynamic>.from(res[0] as Map));
      }

      if (res is dynamic) {
        try {
          final map = Map<String, dynamic>.from(res as Map);
          return Branch.fromMap(map);
        } catch (_) {}
      }

      return null;
    } catch (e, st) {
      debugPrint('fetchBranchById error: $e\n$st');
      return null;
    }
  }

  // ---------- RPC estimate ----------
  Future<DeliveryEstimate?> estimateViaRpc({
    required String branchId,
    required double userLat,
    required double userLng,
    double? pricePerKm,
    double? baseFee,
    double? minKm,
    bool validateBranchExists = true,
  }) async {
    final p = pricePerKm ?? defaultPricePerKm;

    if (validateBranchExists) {
      final b = await fetchBranchById(branchId);
      if (b == null) {
        debugPrint('estimateViaRpc: branch not found -> skipping RPC (fallback will be used)');
        return null;
      }
    }

    int attempt = 0;
    while (attempt <= rpcRetries) {
      attempt++;
      try {
        final future = supabase.rpc(
          'compute_delivery_for_branch',
          params: {
            'branch_uuid': branchId,
            'user_lat': userLat,
            'user_lng': userLng,
            'price_per_km': p,
            // pass base/min if your RPC supports them (safe to include even if ignored)
            'base_fee': baseFee ?? defaultBaseFee,
            'min_km': minKm ?? defaultMinKm,
          },
        );

        final res = await future.timeout(rpcTimeout);

        dynamic data;
        dynamic error;
        try {
          error = (res as dynamic).error;
          data = (res as dynamic).data;
        } catch (_) {
          data = res;
          error = null;
        }

        if (error != null) {
          debugPrint('estimateViaRpc RPC error (attempt $attempt): $error');
          if (attempt > rpcRetries) return null;
          await Future.delayed(Duration(milliseconds: 120 * attempt));
          continue;
        }

        if (data == null) {
          debugPrint('estimateViaRpc - empty data (attempt $attempt)');
          if (attempt > rpcRetries) return null;
          await Future.delayed(Duration(milliseconds: 120 * attempt));
          continue;
        }

        Map<String, dynamic> row;
        if (data is List && data.isNotEmpty) {
          row = Map<String, dynamic>.from(data[0] as Map);
        } else if (data is Map) {
          row = Map<String, dynamic>.from(data);
        } else {
          debugPrint('estimateViaRpc - unexpected data shape: ${data.runtimeType}');
          return null;
        }

        final estimate = DeliveryEstimate.fromMap(row);

        final normalized = DeliveryEstimate(
          distanceMeters: (estimate.distanceMeters),
          distanceKm: _roundTo(estimate.distanceKm, 3),
          chargedKm: estimate.chargedKm,
          cost: _roundCost(estimate.cost),
          durationSeconds: estimate.durationSeconds,
          perKmPrice: estimate.perKmPrice ?? p,
          pricingId: estimate.pricingId,
        );

        return normalized;
      } on TimeoutException catch (te) {
        debugPrint('estimateViaRpc - timeout (attempt $attempt): $te');
        if (attempt > rpcRetries) return null;
        await Future.delayed(Duration(milliseconds: 120 * attempt));
        continue;
      } catch (e, st) {
        debugPrint('estimateViaRpc - unexpected error (attempt $attempt): $e\n$st');
        if (attempt > rpcRetries) return null;
        await Future.delayed(Duration(milliseconds: 120 * attempt));
        continue;
      }
    }

    return null;
  }

  // ---------- convenience flow ----------
  Future<DeliveryEstimate?> estimateForBranchId({
    required String branchId,
    required double userLat,
    required double userLng,
    double? pricePerKm,
    double? baseFee,
    double? minKm,
    bool preferRpc = true,
  }) async {
    final p = pricePerKm ?? defaultPricePerKm;
    final bFee = baseFee ?? defaultBaseFee;
    final mKm = minKm ?? defaultMinKm;

    Branch? branch = await fetchBranchById(branchId);

    if (branch == null || branch.latitude == null || branch.longitude == null) {
      // if branch has no coords, try RPC (it might use geog stored in DB)
      final rpc = await estimateViaRpc(
        branchId: branchId,
        userLat: userLat,
        userLng: userLng,
        pricePerKm: p,
        baseFee: bFee,
        minKm: mKm,
        validateBranchExists: false,
      );
      return rpc;
    }

    if (preferRpc) {
      final rpc = await estimateViaRpc(
        branchId: branchId,
        userLat: userLat,
        userLng: userLng,
        pricePerKm: p,
        baseFee: bFee,
        minKm: mKm,
        validateBranchExists: false,
      );
      if (rpc != null) return rpc;
    }

    // fallback local (now uses baseFee & minKm)
    return estimateLocal(
      branchLat: branch.latitude!,
      branchLng: branch.longitude!,
      userLat: userLat,
      userLng: userLng,
      pricePerKm: p,
      baseFee: bFee,
      minKm: mKm,
    );
  }

  // ---------- nearest branches (client-side computation) ----------
  /// Returns a list of nearest Branch objects to (lat, lon).
  /// This fetches branches that have non-null lat/lng from the DB
  /// and computes distances locally (Haversine). The result is sorted by distance.
  Future<List<Branch>> getNearestBranches({
    required double lat,
    required double lon,
    int limit = 5,
    int fetchLimit = 500, // safety: how many rows to fetch from DB (tweak as needed)
  }) async {
    try {
      final resp = await supabase
          .from('branches')
          .select('id, restaurant_id, name, latitude, longitude, address, place_id')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .limit(fetchLimit);

      final data = resp as List<dynamic>?; // SDK returns list of maps

      if (data == null || data.isEmpty) return [];

      final List<Map<String, dynamic>> rows = data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final List<Map<String, dynamic>> withDistance = [];

      for (final row in rows) {
        final latVal = row['latitude'];
        final lonVal = row['longitude'];
        if (latVal == null || lonVal == null) continue;
        try {
          final double bLat = (latVal is num) ? latVal.toDouble() : double.parse(latVal.toString());
          final double bLon = (lonVal is num)
              ? lonVal.toDouble()
              : double.parse(lonVal.toString());
          final dist = _haversineMeters(lat, lon, bLat, bLon);
          final copy = Map<String, dynamic>.from(row);
          copy['__distance_m'] = dist;
          withDistance.add(copy);
        } catch (_) {
          continue;
        }
      }

      withDistance.sort((a, b) {
        final da = (a['__distance_m'] as num?)?.toDouble() ?? double.infinity;
        final db = (b['__distance_m'] as num?)?.toDouble() ?? double.infinity;
        return da.compareTo(db);
      });

      final sliced = withDistance.take(limit).toList();

      final List<Branch> result = sliced.map((r) {
        return Branch.fromMap(r);
      }).toList();

      return result;
    } catch (e, st) {
      debugPrint('getNearestBranches error: $e\n$st');
      return [];
    }
  }
}
