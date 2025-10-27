// lib/screens/PaymentScreen.dart
//
// PaymentScreen: checkout entry. UI unchanged; logic adjusted so:
// - if area/restaurant has an administrative fixed delivery fee -> use it.
// - otherwise compute delivery fee by kilometers (local pricing or RPC fallback)
//   and ensure that computed fee is included in the total passed to CheckoutPaymentScreen.
//
// NOTE: this file preserves UI and existing behavior, only tightens the delivery-fee -> total flow.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:talabak_users/screens/checkout_payment_screen.dart';
import 'package:talabak_users/services/cart_service.dart';
import 'package:talabak_users/services/cart_api.dart';
import 'package:talabak_users/services/delivery_service.dart';
import 'package:talabak_users/utils/delivery_estimate.dart';
import 'package:talabak_users/utils/location_helper.dart';
import 'package:talabak_users/screens/restaurant_detail_screen.dart';
import 'package:talabak_users/screens/map_picker_screen.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

enum _StatusType { success, error, info }

class PaymentScreen extends StatefulWidget {
  final String restaurantId;
  final String restaurantName;

  const PaymentScreen({
    Key? key,
    required this.restaurantId,
    required this.restaurantName,
  }) : super(key: key);

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final Color primaryRed = const Color(0xFFFF5C01);
  final SupabaseClient _supabase = Supabase.instance.client;

  // user inputs
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _promoController = TextEditingController();

  // promo state
  String? _promoError;
  double _discountValue = 0.0;
  String? _appliedPromoCode;
  String? _appliedPromoLabel;

  // delivery estimate
  DeliveryEstimate? _estimate;
  bool _estimating = false;
  String? _estimateError;

  // selected location & address
  LatLng? _selectedLatLng;
  String? _selectedAddress;

  // override info (if admin provided fixed fee for city / area)
  double? _overrideFixedFee;
  int? _overrideCityId;
  String? _overrideCityName;

  // computed local pricing (from delivery_pricing + branch coords)
  double? _computedLocalFee;
  double? _computedChargedKm;
  double? _computedPerKmPrice;
  double? _computedBaseFee;
  double? _computedMinKm;

  // checkout progress
  bool _isCheckingOut = false;

  // global bottom error message (professional display)
  String? _lastError;

  // services
  late final DeliveryService _deliveryService;

  // simple in-memory cities cache to avoid repeated big fetches
  List<Map<String, dynamic>>? _citiesCache;

  // status message pill (professional english messages)
  String? _statusMessage;
  _StatusType? _statusType;

  // get Cart items for this restaurant
  List<CartItem> get _restaurantItems {
    final all = CartService.instance.items;
    return all.where((it) => it.restaurantId == widget.restaurantId).toList();
  }

  // bilingual helper (Arabic / English) — safe for missing AppLocalizations keys
  String _t(String ar, String en) {
    try {
      final code = Localizations.localeOf(context).languageCode;
      return code == 'ar' ? ar : en;
    } catch (_) {
      return en;
    }
  }

  double get _subtotal {
    double s = 0;
    for (final it in _restaurantItems) {
      try {
        s += (it.total ?? (it.unitPrice * it.qty));
      } catch (_) {
        s += (it.unitPrice * it.qty);
      }
    }
    return s;
  }

  // delivery fee priority: admin override -> computed local fee -> rpc estimate
  double get _deliveryFee {
    if (_overrideFixedFee != null) return _overrideFixedFee!;
    if (_computedLocalFee != null) return _computedLocalFee!;
    return _estimate?.cost ?? 0.0;
  }

  double get _total {
    final t = _subtotal - _discountValue + _deliveryFee;
    return t < 0 ? 0.0 : t;
  }

  @override
  void initState() {
    super.initState();
    _deliveryService = DeliveryService(supabase: _supabase);
    _computeDeliveryEstimate();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  // Robust _setLastError with safe fallback if AppLocalizations lacks errorMessage
  void _setLastError(Object? e) {
    String fallback(String s) => s;
    String localized(String s) {
      try {
        final loc = AppLocalizations.of(context);
        if (loc != null) {
          final dynamic dyn = loc;
          if (dyn.errorMessage is Function) {
            try {
              return (dyn.errorMessage as Function)(s).toString();
            } catch (_) {}
          }
        }
      } catch (_) {}
      return fallback(s);
    }

    final String msg;
    if (e == null) {
      msg = localized('Error');
    } else if (e is String) {
      msg = e;
    } else {
      msg = localized(e.toString());
    }

    if (!mounted) return;
    setState(() {
      _lastError = msg;
    });
  }

  void _setStatus(String message, _StatusType type) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusType = type;
    });
  }

  void _clearStatus() {
    if (!mounted) return;
    setState(() {
      _statusMessage = null;
      _statusType = null;
    });
  }

  Future<void> _computeDeliveryEstimate({double? lat, double? lng}) async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _estimating = true;
      _estimateError = null;
      _lastError = null;
      // clear previous computed local fee to re-evaluate
      _computedLocalFee = null;
      _computedChargedKm = null;
      _computedPerKmPrice = null;
      _computedBaseFee = null;
      _computedMinKm = null;
      _overrideFixedFee = null;
      _overrideCityId = null;
      _overrideCityName = null;
      _clearStatus();
    });

    try {
      double? useLat = lat;
      double? useLng = lng;

      if (useLat == null || useLng == null) {
        final pos = await determinePosition();
        if (pos != null) {
          useLat = pos.latitude;
          useLng = pos.longitude;
          _selectedLatLng = LatLng(useLat, useLng);
        }
      } else {
        _selectedLatLng = LatLng(useLat!, useLng!);
      }

      final finalLat = useLat ?? 30.0444;
      final finalLng = useLng ?? 31.2357;

      // If selectedAddress is available, first check city override and apply automatically if present
      if (_selectedAddress != null && _selectedAddress!.trim().isNotEmpty) {
        final applied = await _autoApplyOverrideFromAddress(_selectedAddress!);
        if (applied) {
          // override applied automatically
          _setStatus(
            'An administrative fixed delivery fee of ${_overrideFixedFee!.toStringAsFixed(2)} EGP has been automatically applied for ${_overrideCityName ?? 'your area'}.',
            _StatusType.success,
          );
          setState(() {
            _estimate = null;
            _estimateError = null;
          });
          return;
        }
      }

      // First try local calculation using delivery_pricing & branch coords
      final localFee = await _computeLocalFeeUsingPricing(finalLat, finalLng);
      if (localFee != null) {
        _setStatus(
          'A local delivery fee of ${localFee.toStringAsFixed(2)} EGP was calculated based on distance and pricing rules.',
          _StatusType.success,
        );
        setState(() {
          _estimate = null;
          _estimateError = null;
        });
        return;
      }

      // fallback to RPC estimate
      final est = await _deliveryService.estimateForBranchId(
        branchId: widget.restaurantId,
        userLat: finalLat,
        userLng: finalLng,
        preferRpc: true,
      );

      if (est == null) {
        setState(() {
          _estimate = null;
          _estimateError =
              loc?.errorMessage(
                'Unable to calculate delivery fee right now.',
              ) ??
                  'Unable to calculate delivery fee right now.';
        });
        _setLastError(_estimateError);
        _setStatus(
          'Failed to obtain a delivery estimate automatically; please try again or contact support.',
          _StatusType.error,
        );
      } else {
        setState(() {
          _estimate = est;
          _estimateError = null;
        });
        _setStatus(
          'A delivery estimate of ${est.cost.toStringAsFixed(2)} EGP has been fetched.',
          _StatusType.info,
        );
      }
    } catch (e) {
      debugPrint('compute delivery estimate error: $e');
      setState(() {
        _estimate = null;
        _estimateError =
            AppLocalizations.of(
              context,
            )?.errorMessage('An error occurred while calculating delivery.') ??
                'An error occurred while calculating delivery.';
      });
      _setLastError(_estimateError);
      _setStatus(
        'An internal error occurred while calculating delivery; fallback strategies were attempted.',
        _StatusType.error,
      );
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  // ---------------- Promo / coupon logic (unchanged) ----------------
  Future<void> _onSubmitPromo() async {
    final loc = AppLocalizations.of(context)!;
    final codeRaw = _promoController.text.trim();
    if (codeRaw.isEmpty) {
      setState(() {
        _promoError = loc.pleaseEnterPromo;
      });
      _setLastError(loc.pleaseEnterPromo);
      return;
    }

    final code = codeRaw.toUpperCase();

    if (_appliedPromoCode != null) {
      setState(() {
        if (_appliedPromoCode == code) {
          _promoError = loc.couponAlreadyApplied;
        } else {
          _promoError = loc.onlyOneCoupon;
        }
      });
      _setLastError(_promoError);
      return;
    }

    setState(() {
      _promoError = null;
      _lastError = null;
    });

    try {
      final q = await _supabase
          .from('coupons')
          .select(
        'id, code, discount_type, discount_value, discount_pct, min_order_amount, usage_limit, used_count, is_active, valid_from, valid_to, expires_at',
      )
          .ilike('code', code)
          .maybeSingle();

      if (q == null) {
        setState(() {
          _promoError = loc.couponNotFound;
          _appliedPromoCode = null;
          _discountValue = 0.0;
        });
        _setLastError(_promoError);
        return;
      }

      final Map<String, dynamic> row = Map<String, dynamic>.from(q as Map);

      final bool isActive = (row['is_active'] == true);
      final int usageLimit = row['usage_limit'] is int
          ? row['usage_limit'] as int
          : (row['usage_limit'] == null
          ? -1
          : int.tryParse(row['usage_limit'].toString()) ?? -1);
      final int usedCount = row['used_count'] is int
          ? row['used_count'] as int
          : int.tryParse(row['used_count']?.toString() ?? '0') ?? 0;
      final double minOrder =
          ((row['min_order_amount'] as num?)?.toDouble()) ?? 0.0;
      DateTime? validFrom;
      DateTime? validTo;
      DateTime? expiresAt;
      try {
        validFrom = row['valid_from'] != null
            ? DateTime.parse(row['valid_from'].toString())
            : null;
      } catch (_) {}
      try {
        validTo = row['valid_to'] != null
            ? DateTime.parse(row['valid_to'].toString())
            : null;
      } catch (_) {}
      try {
        expiresAt = row['expires_at'] != null
            ? DateTime.parse(row['expires_at'].toString())
            : null;
      } catch (_) {}

      if (!isActive) {
        setState(() => _promoError = loc.couponInactive);
        _setLastError(_promoError);
        return;
      }

      final now = DateTime.now().toUtc();
      if (validFrom != null && now.isBefore(validFrom.toUtc())) {
        setState(() => _promoError = loc.couponNotValidYet);
        _setLastError(_promoError);
        return;
      }
      if (validTo != null && now.isAfter(validTo.toUtc())) {
        setState(() => _promoError = loc.couponNotValidYet);
        _setLastError(_promoError);
        return;
      }
      if (expiresAt != null && now.isAfter(expiresAt.toUtc())) {
        setState(() => _promoError = loc.couponExpired);
        _setLastError(_promoError);
        return;
      }

      if (usageLimit >= 0 && usedCount >= usageLimit) {
        setState(() => _promoError = loc.couponFullyUsed);
        _setLastError(_promoError);
        return;
      }

      if (_subtotal < minOrder) {
        setState(() => _promoError = loc.couponMinOrder(minOrder));
        _setLastError(_promoError);
        return;
      }

      final double discountPct =
          ((row['discount_pct'] as num?)?.toDouble()) ?? 0.0;
      final double discountValueFixed =
          ((row['discount_value'] as num?)?.toDouble()) ?? 0.0;

      double computedDiscount = 0.0;
      String label = '';

      if (discountPct > 0) {
        computedDiscount = _subtotal * (discountPct / 100.0);
        label =
        '${discountPct.toStringAsFixed(discountPct.truncateToDouble() == discountPct ? 0 : 1)}% ${loc.off}';
      } else if (discountValueFixed > 0) {
        computedDiscount = discountValueFixed;
        label = '${discountValueFixed.toStringAsFixed(2)} EGP ${loc.off}';
      } else {
        setState(() => _promoError = loc.couponHasNoValue);
        _setLastError(_promoError);
        return;
      }

      if (computedDiscount > _subtotal) computedDiscount = _subtotal;

      final rpcRes = await _supabase
          .rpc('use_coupon_atomic', params: {'p_code': code})
          .maybeSingle();

      if (rpcRes == null) {
        setState(() {
          _promoError = loc.couponFailed;
        });
        _setLastError(_promoError);
        return;
      }

      setState(() {
        _discountValue = computedDiscount;
        _appliedPromoCode = code;
        _appliedPromoLabel = label;
        _promoError = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.couponApplied(label))));
      }
    } catch (e) {
      debugPrint('apply promo error: $e');
      setState(() {
        _promoError =
            AppLocalizations.of(context)?.couponFailed ?? 'Coupon failed';
      });
      _setLastError(_promoError);
    }
  }

  void _applyQuickPercent(double pct) {
    setState(() {
      _discountValue = (_subtotal * pct / 100.0).clamp(0.0, _subtotal);
      _appliedPromoCode = 'LOCAL_${pct.toInt()}P';
      _appliedPromoLabel =
      '${pct.toStringAsFixed(pct.truncateToDouble() == pct ? 0 : 1)}% ${AppLocalizations.of(context)?.off ?? 'off'}';
      _promoError = null;
      _promoController.clear();
      _lastError = null;
    });
    if (mounted) {
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.couponApplied(_appliedPromoLabel!))),
      );
    }
  }

  void _removeAppliedPromo() {
    setState(() {
      _appliedPromoCode = null;
      _appliedPromoLabel = null;
      _discountValue = 0.0;
      _promoController.clear();
      _promoError = null;
      _lastError = null;
    });
    final loc = AppLocalizations.of(context)!;
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.couponRemoved)));
  }

  // Navigation / actions
  Future<void> _onAddItems() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RestaurantDetailScreen(restaurantId: widget.restaurantId),
      ),
    );

    try {
      await CartApi.fetchAndSyncAllUserCarts();
    } catch (_) {}
    await _computeDeliveryEstimate();

    if (mounted) setState(() {});
  }

  Future<void> _onPickLocation() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          apiKey: 'YOUR_GOOGLE_API_KEY',
          initialLatLng: _selectedLatLng,
        ),
      ),
    );

    if (result is Map<String, dynamic>) {
      final lat = result['latitude'] as double?;
      final lng = result['longitude'] as double?;
      final addr = result['address'] as String?;

      // MapPicker قد ترجع override مباشرة — سنطبّقها تلقائياً (حسب طلبك)
      final dynamic maybeOverrideFee = result['override_fixed_fee'];
      final dynamic maybeOverrideCityId = result['override_city_id'];
      final dynamic maybeOverrideCityName = result['override_city_name'];

      if (lat != null && lng != null) {
        setState(() {
          _selectedLatLng = LatLng(lat, lng);
          if (addr != null && addr.isNotEmpty) _selectedAddress = addr;
          _estimating = true;
          _lastError = null;
          // clear previous override and local computed values until we determine new one
          _overrideFixedFee = null;
          _overrideCityId = null;
          _overrideCityName = null;
          _computedLocalFee = null;
          _computedChargedKm = null;
          _computedPerKmPrice = null;
          _computedBaseFee = null;
          _computedMinKm = null;
          _clearStatus();
        });

        // 1) إذا الـ picker رجع override مباشرة → نطبقه تلقائياً (لا نسأل المستخدم)
        if (maybeOverrideFee != null) {
          double? parsedFee;
          try {
            if (maybeOverrideFee is num)
              parsedFee = (maybeOverrideFee as num).toDouble();
            else
              parsedFee = double.tryParse(maybeOverrideFee.toString());
          } catch (_) {
            parsedFee = null;
          }

          int? parsedCityId;
          try {
            if (maybeOverrideCityId is int)
              parsedCityId = maybeOverrideCityId;
            else if (maybeOverrideCityId is String)
              parsedCityId = int.tryParse(maybeOverrideCityId) ?? null;
          } catch (_) {
            parsedCityId = null;
          }

          final cityNameStr = (maybeOverrideCityName != null)
              ? maybeOverrideCityName.toString()
              : null;

          if (parsedFee != null) {
            setState(() {
              _overrideFixedFee = parsedFee;
              _overrideCityId = parsedCityId;
              _overrideCityName = cityNameStr;
              _estimating = false;
            });
            _setStatus(
              'An administrative fixed delivery fee of ${parsedFee.toStringAsFixed(2)} EGP has been automatically applied for ${cityNameStr ?? 'your area'}.',
              _StatusType.success,
            );
            return;
          }
        }

        // 2) لو مافيش override من الـ picker → نحاول نطابق العنوان مع cities و city_delivery_overrides تلقائياً
        if (_selectedAddress != null && _selectedAddress!.trim().isNotEmpty) {
          final applied = await _autoApplyOverrideFromAddress(
            _selectedAddress!,
          );
          if (applied) {
            _setStatus(
              'An administrative fixed delivery fee of ${_overrideFixedFee!.toStringAsFixed(2)} EGP has been automatically applied for ${_overrideCityName ?? 'your area'}.',
              _StatusType.success,
            );
            setState(() {
              _estimating = false;
              _estimate = null;
            });
            return;
          }
        }

        // 3) لا override → نحاول حساب السعر محليًا من جدول delivery_pricing
        final localFee = await _computeLocalFeeUsingPricing(lat, lng);
        if (localFee != null) {
          _setStatus(
            'A local delivery fee of ${localFee.toStringAsFixed(2)} EGP was calculated based on distance and pricing rules.',
            _StatusType.success,
          );
          setState(() {
            _estimate = null;
            _estimating = false;
          });
          return;
        }

        // 4) احتياط: لا override ولا حساب محلي → نستخدم RPC estimate
        final est = await _delivery_service_estimateSafely(lat, lng);
        if (est != null) {
          _setStatus(
            'A delivery estimate of ${est.cost.toStringAsFixed(2)} EGP has been fetched.',
            _StatusType.info,
          );
        } else {
          _setStatus(
            'Failed to calculate a delivery fee; remote estimate unavailable.',
            _StatusType.error,
          );
        }
        setState(() {
          _estimate = est;
          _estimating = false;
        });
      }
    }
  }

  Future<DeliveryEstimate?> _delivery_service_estimateSafely(
      double lat,
      double lng,
      ) async {
    try {
      final est = await _deliveryService.estimateForBranchId(
        branchId: widget.restaurantId,
        userLat: lat,
        userLng: lng,
        preferRpc: true,
      );
      return est;
    } catch (e) {
      debugPrint('estimate error: $e');
      _setLastError(e);
      return null;
    }
  }

  // ------------------ البحث في جدول المدن وتطبيق override تلقائياً ------------------

  Future<bool> _autoApplyOverrideFromAddress(String address) async {
    if (address.trim().isEmpty) return false;
    final addrLower = address.toLowerCase();

    try {
      // load cities cache if needed
      if (_citiesCache == null) {
        final resp = await _supabase
            .from('cities')
            .select('id, city_name_en, city_name_ar')
            .limit(2000);
        if (resp is List) {
          _citiesCache = List<Map<String, dynamic>>.from(
            resp.map((e) => Map<String, dynamic>.from(e as Map)),
          );
        } else {
          _citiesCache = [];
        }
      }

      Map<String, dynamic>? best;
      int bestLen = 0;

      for (final c in _citiesCache!) {
        final en = (c['city_name_en'] ?? '').toString().toLowerCase();
        final ar = (c['city_name_ar'] ?? '').toString().toLowerCase();

        if (en.isNotEmpty && addrLower.contains(en) && en.length > bestLen) {
          best = c;
          bestLen = en.length;
        }
        if (ar.isNotEmpty && addrLower.contains(ar) && ar.length > bestLen) {
          best = c;
          bestLen = ar.length;
        }
      }

      if (best == null) return false;

      final cityId = (best['id'] is int)
          ? best['id'] as int
          : int.tryParse(best['id'].toString()) ?? -1;
      if (cityId == -1) return false;

      // fetch override
      final overrideResp = await _supabase
          .from('city_delivery_overrides')
          .select('id, city_id, fixed_fee, active')
          .eq('city_id', cityId)
          .eq('active', true)
          .maybeSingle();

      if (overrideResp == null) return false;

      final Map<String, dynamic> overrideRow = Map<String, dynamic>.from(
        overrideResp as Map,
      );
      final fee =
          ((overrideRow['fixed_fee'] as num?)?.toDouble()) ??
              double.tryParse(overrideRow['fixed_fee']?.toString() ?? '') ??
              0.0;

      // apply automatically (no user choice)
      final isAr = Localizations.localeOf(context).languageCode == 'ar';
      final cityName = isAr
          ? (best['city_name_ar'] ?? best['city_name_en'])
          : (best['city_name_en'] ?? best['city_name_ar']);

      setState(() {
        _overrideFixedFee = fee;
        _overrideCityId = cityId;
        _overrideCityName = cityName?.toString() ?? '';
      });

      if (kDebugMode)
        debugPrint('Auto-applied override: cityId=$cityId fee=$fee');

      return true;
    } catch (e) {
      debugPrint('autoApplyOverrideFromAddress error: $e');
      return false;
    }
  }

  // professional dialog kept for legacy but not used in auto-apply mode
  Future<bool?> _confirmOverrideDialog({
    required String address,
    String? cityName,
    required double fixedFee,
  }) {
    final loc = AppLocalizations.of(context);

    String _t(String ar, String en) {
      final isAr = Localizations.localeOf(context).languageCode == 'ar';
      return isAr ? ar : en;
    }

    final titleText =
        loc?.delivery_location ?? _t('موقع التوصيل', 'Delivery location');
    final fixedFeeExplanation = _t(
      'تم تحديد سعر توصيل ثابت لهذه المنطقة بواسطة الأدمن. يمكنك استخدام هذا السعر أو المتابعة بالسعر المحسوب عادةً.',
      'A fixed delivery fee is set for this area by the admin. You can use that fixed fee or continue with the normal calculated fee.',
    );
    final useCalculatedLabel = _t('استخدم السعر المحسوب', 'Use calculated fee');
    final useFixedLabel = _t('استخدم السعر الثابت', 'Use fixed price');
    final cancelLabel = _t('إلغاء', 'Cancel');

    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: true,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(null),
          child: Container(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 20,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // header
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titleText,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primaryRed.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${fixedFee.toStringAsFixed(2)} EGP',
                            style: const TextStyle(
                              color: Color(0xFFFF5C01),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (cityName != null && cityName.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          cityName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (cityName != null && cityName.isNotEmpty)
                      const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        address,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      fixedFeeExplanation,
                      style: const TextStyle(color: Colors.black54),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(useCalculatedLabel),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryRed,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(
                              useFixedLabel,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: Text(cancelLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------ local pricing helpers ------------------

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final cosLat1 = math.cos(_degToRad(lat1));
    final cosLat2 = math.cos(_degToRad(lat2));
    final a = sinDLat * sinDLat + cosLat1 * cosLat2 * sinDLon * sinDLon;
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double computeChargedKmFromMetersWithMin(double meters, double minKm) {
    final km = meters / 1000.0;
    if (km <= minKm) return minKm;
    return km.ceilToDouble();
  }

  double calculateDeliveryFee({
    required double chargedKm,
    double baseFee = 10.0,
    double perKmPrice = 5.0,
  }) {
    final fee = baseFee + (chargedKm * perKmPrice);
    return double.parse(fee.toStringAsFixed(2));
  }

  // Fetch delivery_pricing row (or defaults)
  Future<Map<String, double>> _fetchDeliveryPricingRow() async {
    try {
      final resp = await _supabase
          .from('delivery_pricing')
          .select('base_fee, per_km_price, min_km')
          .limit(1)
          .maybeSingle();
      if (resp != null && resp is Map) {
        final base = ((resp['base_fee'] as num?)?.toDouble()) ?? 10.0;
        final perKm = ((resp['per_km_price'] as num?)?.toDouble()) ?? 5.0;
        final minKm = ((resp['min_km'] as num?)?.toDouble()) ?? 3.0;
        return {'base_fee': base, 'per_km_price': perKm, 'min_km': minKm};
      }
    } catch (e) {
      debugPrint('fetchDeliveryPricingRow error: $e');
    }
    // fallback defaults
    return {'base_fee': 10.0, 'per_km_price': 5.0, 'min_km': 3.0};
  }

  /// Compute local fee using delivery_pricing and branch coordinates (if available).
  /// Returns computed fee or null if couldn't compute (e.g., branch coords missing).
  Future<double?> _computeLocalFeeUsingPricing(
      double userLat,
      double userLng,
      ) async {
    try {
      // 1) get branch coordinates for restaurant
      double? branchLat;
      double? branchLng;

      try {
        final branch = await _deliveryService.fetchBranchById(
          widget.restaurantId,
        );
        if (branch != null) {
          // Branch might be a data object: try properties safely
          try {
            final dynLat = (branch as dynamic).latitude;
            final dynLng = (branch as dynamic).longitude;
            branchLat = (dynLat is num)
                ? (dynLat as num).toDouble()
                : double.tryParse(dynLat?.toString() ?? '');
            branchLng = (dynLng is num)
                ? (dynLng as num).toDouble()
                : double.tryParse(dynLng?.toString() ?? '');
          } catch (e) {
            debugPrint('Branch parse error: $e');
          }
        }
      } catch (e) {
        debugPrint('fetchBranchById error (ignored): $e');
      }

      if (branchLat == null || branchLng == null) {
        // couldn't get branch coords — abort local calc
        if (kDebugMode)
          debugPrint(
            'Local fee calc aborted: branch coordinates not available.',
          );
        return null;
      }

      // 2) get pricing row
      final pricing = await _fetchDeliveryPricingRow();
      final baseFee = pricing['base_fee']!;
      final perKm = pricing['per_km_price']!;
      final minKm = pricing['min_km']!;

      // 3) compute distance and charged km
      final meters = _haversineMeters(branchLat, branchLng, userLat, userLng);
      final chargedKm = computeChargedKmFromMetersWithMin(meters, minKm);

      // 4) compute fee
      final fee = calculateDeliveryFee(
        chargedKm: chargedKm,
        baseFee: baseFee,
        perKmPrice: perKm,
      );

      // set state with additional debug info
      if (mounted) {
        setState(() {
          _computedLocalFee = fee;
          _computedChargedKm = chargedKm;
          _computedPerKmPrice = perKm;
          _computedBaseFee = baseFee;
          _computedMinKm = minKm;
        });
      }

      if (kDebugMode)
        debugPrint(
          'LocalFee calc: meters=$meters chargedKm=$chargedKm base=$baseFee perKm=$perKm fee=$fee',
        );

      return fee;
    } catch (e) {
      debugPrint('computeLocalFeeUsingPricing error: $e');
      return null;
    }
  }

  Widget _buildStatusPill() {
    if (_statusMessage == null || _statusMessage!.isEmpty)
      return const SizedBox.shrink();
    Color bg;
    Color textColor = Colors.white;
    IconData icon;
    switch (_statusType) {
      case _StatusType.success:
        bg = Colors.green.shade600;
        icon = Icons.check_circle_outline;
        break;
      case _StatusType.error:
        bg = Colors.red.shade600;
        icon = Icons.error_outline;
        break;
      case _StatusType.info:
      default:
        bg = Colors.blueGrey.shade700;
        icon = Icons.info_outline;
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(_statusMessage),
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _statusMessage ?? '',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: _clearStatus,
              icon: Icon(Icons.close, color: textColor, size: 18),
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }

  // ------------------ CHECKOUT: prepares items, ensures delivery fee computed and included in total ------------------
  Future<void> _performCheckout() async {
    if (_isCheckingOut) return;

    final LatLng initialLat = _selectedLatLng ?? const LatLng(30.0444, 31.2357);
    final String address = _selectedAddress ??
        (AppLocalizations.of(context)?.usingDeviceLocation ??
            'Using your device location (or Cairo if unavailable)');
    final String comment = _commentController.text.trim();

    setState(() => _isCheckingOut = true);

    // Resolve a sensible phone to pass to checkout (best-effort)
    String? phone;
    try {
      final supUser = _supabase.auth.currentUser ?? _supabase.auth.currentSession?.user;
      if (supUser != null) {
        final dynamic metaPhoneRaw = supUser.userMetadata?['phone'] ?? supUser.userMetadata?['mobile'];
        if (metaPhoneRaw != null && metaPhoneRaw.toString().trim().isNotEmpty) {
          phone = metaPhoneRaw.toString().trim();
        } else {
          try {
            final dynamic resp = await _supabase
                .from('customers')
                .select('id, phone')
                .eq('uid', supUser.id)
                .maybeSingle();
            if (resp is Map) {
              final dynamic phoneField = resp['phone'];
              if (phoneField != null && phoneField.toString().trim().isNotEmpty) {
                phone = phoneField.toString().trim();
              }
            }
          } catch (e) {
            if (kDebugMode) debugPrint('fetch customer phone error: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('resolve phone error: $e');
      phone = null;
    }

    // small helpers
    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int _toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    // --- NEW: check RouteSettings.arguments to see if PaymentScreen passed items/subtotals ---
    List<Map<String, dynamic>>? itemsFromArgs;
    double? argsSubtotal;
    try {
      final dynamic routeArgs = ModalRoute.of(context)?.settings.arguments;
      if (routeArgs is Map) {
        final dynamic rawItems = routeArgs['items'];
        if (rawItems is List) {
          try {
            final normalized = <Map<String, dynamic>>[];
            for (final e in rawItems) {
              if (e is Map) {
                normalized.add(Map<String, dynamic>.from(e));
              }
            }
            if (normalized.isNotEmpty) itemsFromArgs = normalized;
          } catch (_) {
            itemsFromArgs = null;
          }
        }

        // try to read subtotal if provided
        try {
          final dynamic maybeSubtotal = routeArgs['subtotal'];
          if (maybeSubtotal is num) argsSubtotal = maybeSubtotal.toDouble();
          else if (maybeSubtotal is String) argsSubtotal = double.tryParse(maybeSubtotal) ?? null;
        } catch (_) {
          argsSubtotal = null;
        }
      }
    } catch (_) {
      itemsFromArgs = null;
      argsSubtotal = null;
    }

    // Prepare items to pass: prefer itemsFromArgs if present, otherwise use CartService items for this restaurant
    List<Map<String, dynamic>> itemsToPass = [];

    try {
      if (itemsFromArgs != null && itemsFromArgs.isNotEmpty) {
        // normalize incoming map items to a consistent shape
        for (final raw in itemsFromArgs) {
          final Map<String, dynamic> m = raw;
          final String? menuItemId = (m['menu_item_id'] ?? m['menuItemId'] ?? m['offer_id'])?.toString();
          final String variantIdRaw = (m['variant_id'] ?? m['variantId'] ?? '')?.toString() ?? '';
          final String name = (m['name'] ?? m['title'] ?? '').toString();
          final double unitPrice = _toDouble(m['unit_price'] ?? m['price'] ?? m['unitPrice']);
          final int qty = (_toInt(m['qty'] ?? m['quantity'] ?? 1) == 0) ? 1 : _toInt(m['qty'] ?? m['quantity'] ?? 1);
          final String? imageUrl = (m['image_url'] ?? m['imageUrl'] ?? m['image'])?.toString();
          final dynamic rawTotal = m['total'];
          final double total = (rawTotal is num) ? rawTotal.toDouble() : (unitPrice * qty);

          itemsToPass.add({
            'menu_item_id': menuItemId ?? '',
            'variant_id': variantIdRaw.isNotEmpty ? variantIdRaw : null,
            'name': name,
            'unit_price': unitPrice,
            'qty': qty,
            'image_url': imageUrl?.isNotEmpty == true ? imageUrl : null,
            'total': total,
            // preserve original raw map too for any extra fields
            '_raw': m,
          });
        }
      } else {
        // fallback: use cart items for this restaurant (existing behaviour)
        final cartItems = CartService.instance.items.where((it) => it.restaurantId == widget.restaurantId).toList();
        itemsToPass = cartItems.map<Map<String, dynamic>>((it) {
          final String menuItemId = (it.menuItemId ?? '').toString();
          final String variantId = (it.variantId ?? '').toString();
          final String name = (it.name ?? '').toString();
          final double unitPrice = _toDouble(it.unitPrice ?? 0.0);
          final int qty = (_toInt(it.qty) == 0) ? 1 : _toInt(it.qty);
          final String imageUrl = (it.imageUrl ?? '').toString();
          final dynamic rawTotal = (it.total ?? (it.unitPrice != null ? (it.unitPrice * (it.qty ?? 1)) : null));
          final double total = rawTotal != null ? _toDouble(rawTotal) : (unitPrice * qty);

          return <String, dynamic>{
            'menu_item_id': menuItemId,
            'variant_id': variantId.isNotEmpty ? variantId : null,
            'name': name,
            'unit_price': unitPrice,
            'qty': qty,
            'image_url': imageUrl.isNotEmpty ? imageUrl : null,
            'total': total,
          };
        }).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('prepare itemsToPass error: $e');
      itemsToPass = [];
    }

    // compute passed subtotal safely (prefer argsSubtotal if provided)
    final double passedSubtotal = argsSubtotal ??
        itemsToPass.fold<double>(
          0.0,
              (double acc, Map<String, dynamic> m) {
            try {
              final dynamic t = m['total'];
              if (t is num) return acc + t.toDouble();
              final dynamic up = m['unit_price'] ?? m['price'] ?? 0;
              final dynamic qty = m['qty'] ?? m['quantity'] ?? 1;
              final double unit = (up is num) ? up.toDouble() : double.tryParse(up?.toString() ?? '') ?? 0.0;
              final int q = (qty is num) ? qty.toInt() : int.tryParse(qty?.toString() ?? '') ?? 1;
              return acc + (unit * q);
            } catch (_) {
              return acc;
            }
          },
        );

    // ------------------- Here: ensure we compute the delivery fee used and include it in the passed total -------------------
    // finalDeliveryFeeUsed respects priority: overrideFixed -> computed local -> RPC estimate cost
    // If we don't have a computed local fee yet, try to compute it here (best-effort) before falling back to estimate.
    try {
      if (_overrideFixedFee == null && _computedLocalFee == null) {
        // try compute local (best-effort, safe)
        try {
          finalLatLngSafe() {
            if (_selectedLatLng != null) return _selectedLatLng!;
            return initialLat;
          }

          final userLat = finalLatLngSafe().latitude;
          final userLng = finalLatLngSafe().longitude;
          // attempt compute but don't fail checkout if it errors
          await _computeLocalFeeUsingPricing(userLat, userLng);
        } catch (e) {
          if (kDebugMode) debugPrint('attempt local fee compute in checkout failed: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('unexpected while ensuring local fee: $e');
    }

    final double finalDeliveryFeeUsed = (_overrideFixedFee ?? _computedLocalFee ?? _estimate?.cost ?? 0.0);
    final double roundedDeliveryFee = double.parse(finalDeliveryFeeUsed.toStringAsFixed(2));
    final double finalTotal = double.parse((passedSubtotal - _discountValue + roundedDeliveryFee).toStringAsFixed(2));

    final args = <String, dynamic>{
      'items': itemsToPass,
      'subtotal': passedSubtotal,
      'deliveryFee': roundedDeliveryFee,
      'discount': _discountValue,
      // pass explicit total that includes the deliveryFee actually used
      'total': finalTotal,
    };

    // Push CheckoutPaymentScreen with args
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          settings: RouteSettings(arguments: args),
          builder: (_) => CheckoutPaymentScreen(
            initialLatLng: initialLat,
            address: address,
            subtotal: passedSubtotal,
            deliveryFee: roundedDeliveryFee,
            discount: _discountValue,
            restaurantId: widget.restaurantId,
            comment: comment,
            customerPhone: phone,
            estimate: _estimate,
            overrideFixedFee: _overrideFixedFee,
            overrideCityId: _overrideCityId,
            overrideCityName: _overrideCityName,
          ),
        ),
      );
    } catch (e) {
      _setLastError(e);
    }

    try {
      await CartApi.fetchAndSyncAllUserCarts();
    } catch (e) {
      if (kDebugMode) debugPrint('CartApi.fetchAndSyncAllUserCarts error: $e');
    }
    await _computeDeliveryEstimate();

    if (mounted) setState(() => _isCheckingOut = false);
  }

  PreferredSizeWidget _buildAppBar() {
    final loc = AppLocalizations.of(context);
    return AppBar(
      backgroundColor: primaryRed,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc?.yourCart ?? 'Cart',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 2),
          Text(
            widget.restaurantName,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemRow(CartItem it) {
    final itemTotal = (it.total ?? (it.unitPrice * it.qty));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: it.imageUrl != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(it.imageUrl!, fit: BoxFit.cover),
            )
                : Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.fastfood),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${it.unitPrice.toStringAsFixed(2)} EGP x ${it.qty}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${itemTotal.toStringAsFixed(2)} EGP',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // New helper: build a row for a Map-based passed item (safe parsing)
  Widget _buildMapItemRow(Map<String, dynamic> it) {
    String name = '';
    String? imageUrl;
    double unitPrice = 0.0;
    int qty = 1;
    double itemTotal = 0.0;

    try {
      name = (it['name'] ?? it['title'] ?? '').toString();
      imageUrl = (it['image_url'] ?? it['imageUrl'] ?? '')?.toString();
      final up = it['unit_price'] ?? it['price'] ?? it['unitPrice'];
      if (up is num) unitPrice = up.toDouble();
      else unitPrice = double.tryParse(up?.toString() ?? '') ?? 0.0;
      final q = it['qty'] ?? it['quantity'];
      if (q is num) qty = q.toInt();
      else qty = int.tryParse(q?.toString() ?? '') ?? 1;
      final t = it['total'];
      if (t is num) itemTotal = t.toDouble();
      else itemTotal = double.tryParse(t?.toString() ?? '') ?? (unitPrice * qty);
    } catch (_) {
      // ignore, keep safe defaults
      itemTotal = unitPrice * qty;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: imageUrl != null && imageUrl.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(imageUrl, fit: BoxFit.cover),
            )
                : Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.fastfood),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : 'Item',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${unitPrice.toStringAsFixed(2)} EGP x $qty',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${itemTotal.toStringAsFixed(2)} EGP',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Button styles adapt to theme
    final ButtonStyle addItemsStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      minimumSize: const Size(110, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: colorScheme.primary.withOpacity(0.16)),
      foregroundColor: theme.colorScheme.primary,
      backgroundColor: theme.cardColor,
    );

    final ButtonStyle checkoutStyle = ElevatedButton.styleFrom(
      backgroundColor: colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      minimumSize: const Size(140, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

    // Check for passed items (null-safe)
    final dynamic routeArgs = ModalRoute.of(context)?.settings.arguments;
    List<Map<String, dynamic>>? passedItems;
    if (routeArgs is Map<String, dynamic>) {
      final dynamic maybeItems = routeArgs['items'];
      if (maybeItems is List) {
        try {
          passedItems = List<Map<String, dynamic>>.from(
            maybeItems.map((e) {
              if (e is Map) return Map<String, dynamic>.from(e);
              return <String, dynamic>{};
            }),
          );
          if (passedItems.isEmpty) passedItems = null;
        } catch (_) {
          passedItems = null;
        }
      }
    }

    final bool usingPassed = passedItems != null;
    final restItems = usingPassed ? passedItems : _restaurantItems;

    // compute displayed subtotal for passed items
    double passedSubtotal = 0.0;
    if (usingPassed) {
      for (final m in passedItems!) {
        try {
          final t = m['total'];
          if (t is num) {
            passedSubtotal += t.toDouble();
          } else {
            final up = (m['unit_price'] ?? m['price']) ?? 0;
            final qty = (m['qty'] ?? m['quantity']) ?? 1;
            final double unit = (up is num) ? up.toDouble() : double.tryParse(up?.toString() ?? '') ?? 0.0;
            final int q = (qty is num) ? qty.toInt() : int.tryParse(qty?.toString() ?? '') ?? 1;
            passedSubtotal += (unit * q);
          }
        } catch (_) {}
      }
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _computeDeliveryEstimate();
                await CartApi.fetchAndSyncAllUserCarts();
              },
              color: colorScheme.primary,
              child: AnimatedBuilder(
                animation: CartService.instance,
                builder: (context, _) {
                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        loc.items,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.titleLarge?.color ?? Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (restItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              loc.noItemsInCart,
                              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                            ),
                          ),
                        )
                      else
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                          color: theme.cardColor,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: usingPassed
                                  ? (restItems as List<Map<String, dynamic>>).map((it) => _buildMapItemRow(it)).toList()
                                  : (restItems as List<CartItem>).map((it) => _buildCartItemRow(it)).toList(),
                            ),
                          ),
                        ),

                      const SizedBox(height: 14),

                      // Comments
                      Text(loc.anyComments, style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 8.0, right: 8.0),
                            child: Icon(Icons.message),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 40),
                          hintText: loc.addCommentsHint,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: theme.cardColor,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Promo code title
                      Row(children: [Expanded(child: Text(loc.doYouHaveDiscountCode, style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)))]),
                      const SizedBox(height: 8),

                      // Promo input + submit
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _promoController,
                              decoration: InputDecoration(
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.only(left: 8.0, right: 8.0),
                                  child: Icon(Icons.local_offer),
                                ),
                                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                                hintText: loc.enterYourCode,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                errorText: _promoError,
                                filled: true,
                                fillColor: theme.cardColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _onSubmitPromo,
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.primary,
                              minimumSize: const Size(80, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            child: Text(loc.submit, style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Delivery address
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(loc.deliveryAddress, style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
                                const SizedBox(height: 6),
                                Text(_selectedAddress ?? loc.usingDeviceLocation, style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                                const SizedBox(height: 6),
                                _buildStatusPill(),
                                if (_overrideFixedFee != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text('${_overrideFixedFee!.toStringAsFixed(2)} EGP (fixed)', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 8),
                                        if (_overrideCityName != null)
                                          Text(_overrideCityName!, style: TextStyle(color: theme.textTheme.bodySmall?.color)),
                                      ],
                                    ),
                                  )
                                else if (_computedLocalFee != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text('${_computedLocalFee!.toStringAsFixed(2)} EGP (local)', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 8),
                                        if (_computedChargedKm != null)
                                          Text('${_computedChargedKm!.toStringAsFixed(1)} ${loc.km_unit ?? 'km'}', style: TextStyle(color: theme.textTheme.bodySmall?.color)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          TextButton(onPressed: _onPickLocation, child: Text(loc.change)),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Payment summary
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(loc.paymentSummary, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
                          if (_estimating)
                            Row(
                              children: [
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                const SizedBox(width: 8),
                                Text(loc.calculating, style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        color: theme.cardColor,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(loc.subtotal, style: TextStyle(color: theme.textTheme.bodyLarge?.color))),
                                  Text('${(usingPassed ? passedSubtotal : _subtotal).toStringAsFixed(2)} EGP', style: TextStyle(fontWeight: FontWeight.w700, color: theme.textTheme.bodyLarge?.color)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Divider(height: 18),
                              Row(
                                children: [
                                  Expanded(child: Text(loc.total, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  Text('${_total.toStringAsFixed(2)} EGP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 80),
                    ],
                  );
                },
              ),
            ),
          ),

          // bottom area: error bar + themed fixed bottom bar
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // last error display (if present)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: _lastError != null
                      ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.colorScheme.error.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lastError!,
                            style: TextStyle(color: theme.colorScheme.error),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.close, size: 20, color: theme.colorScheme.error),
                          onPressed: () => setState(() => _lastError = null),
                          tooltip: loc.dismiss ?? 'Dismiss',
                        ),
                      ],
                    ),
                  )
                      : const SizedBox.shrink(),
                ),

                // themed fixed bottom bar with two buttons
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.bottomAppBarTheme.color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.6 : 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _onAddItems,
                          icon: Icon(Icons.add, size: 18, color: theme.iconTheme.color),
                          label: Text(
                            loc.addItems,
                            style: TextStyle(color: theme.textTheme.labelLarge?.color),
                          ),
                          style: addItemsStyle.copyWith(
                            padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 14)),
                            shape: MaterialStateProperty.all(
                              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isCheckingOut ? null : _performCheckout,
                          style: checkoutStyle.copyWith(
                            padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 14)),
                            shape: MaterialStateProperty.all(
                              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          child: _isCheckingOut
                              ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                              : Text(
                            loc.checkout,
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
