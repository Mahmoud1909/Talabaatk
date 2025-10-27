// lib/screens/checkout_payment_screen.dart
// Checkout screen — fixed: only honor passed `total` when it is explicitly provided.
// Otherwise compute total as (subtotal - discount) + deliveryFee (which may be km-based).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as ll;
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:talabak_users/l10n/app_localizations.dart';
import 'package:talabak_users/services/cart_api.dart';
import 'package:talabak_users/services/cart_service.dart';
import 'package:talabak_users/services/order_service.dart';
import 'package:talabak_users/services/delivery_service.dart';
import 'package:talabak_users/services/supabase_service.dart' as userService;
import 'package:talabak_users/services/supabase_client.dart' as client;
import 'package:talabak_users/utils/delivery_estimate.dart';
import 'package:talabak_users/utils/order.dart';
import 'package:talabak_users/utils/order_item.dart';
import 'package:talabak_users/utils/Branch_Model.dart';
import 'package:talabak_users/screens/main_screen.dart';

enum PaymentMethod { mobileWallet, cash }

const Color kPrimaryColor = Color(0xFFFF5C01); // never changes across light/dark

double _degToRad(double deg) => deg * (math.pi / 180.0);

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0; // meters
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
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


class BannerService {
  static OverlayEntry? _currentEntry;

  static void show(
      BuildContext context, {
        required String message,
        String variant = 'info',
        Duration duration = const Duration(milliseconds: 2600),
      }) {
    _hide();
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (ctx) {
        return BannerWidget(
          message: message,
          variant: variant,
          onFinish: () => _hide(),
          duration: duration,
        );
      },
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }

  static void _hide() {
    try {
      _currentEntry?.remove();
      _currentEntry = null;
    } catch (_) {}
  }
}

class BannerWidget extends StatefulWidget {
  final String message;
  final String variant; // 'success' | 'error' | 'info'
  final VoidCallback onFinish;
  final Duration duration;

  const BannerWidget({
    Key? key,
    required this.message,
    required this.variant,
    required this.onFinish,
    this.duration = const Duration(milliseconds: 2600),
  }) : super(key: key);

  @override
  State<BannerWidget> createState() => _BannerWidgetState();
}

class _BannerWidgetState extends State<BannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offsetAnim;
  late final Animation<double> _fadeAnim;

  Color get _bgColor {
    switch (widget.variant) {
      case 'success':
        return Colors.green.shade700;
      case 'error':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade900;
    }
  }

  Color get _glowColor {
    switch (widget.variant) {
      case 'success':
        return Colors.greenAccent;
      case 'error':
        return Colors.redAccent;
      default:
        return Colors.blueAccent;
    }
  }

  IconData get _icon {
    switch (widget.variant) {
      case 'success':
        return Icons.check_circle;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.info_outline;
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _offsetAnim = Tween<Offset>(begin: const Offset(0, -0.25), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    _ctrl.forward();

    Future.delayed(widget.duration, () async {
      if (mounted) {
        await _ctrl.reverse();
        widget.onFinish();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPadding = media.padding.top + 12.0;
    return Positioned(
      top: 0,
      left: 16,
      right: 16,
      child: SafeArea(
        minimum: EdgeInsets.only(top: 8),
        child: SlideTransition(
          position: _offsetAnim,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: Container(
                  margin: EdgeInsets.only(top: topPadding - media.padding.top),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  constraints: const BoxConstraints(maxWidth: 920),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: _glowColor.withOpacity(0.18), blurRadius: 28, spreadRadius: 2),
                      BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 6)),
                    ],
                    border: Border.all(color: _bgColor.withOpacity(0.12), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [_bgColor, _bgColor.withOpacity(0.85)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [BoxShadow(color: _bgColor.withOpacity(0.22), blurRadius: 18, spreadRadius: 1)],
                        ),
                        child: Icon(_icon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------
/// Checkout screen
/// ---------------------
class CheckoutPaymentScreen extends StatefulWidget {
  final gmap.LatLng? initialLatLng;
  final String? address;
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final String? restaurantId;
  final String? comment;
  final String? customerPhone;
  final DeliveryEstimate? estimate;

  final double? overrideFixedFee;
  final int? overrideCityId;
  final String? overrideCityName;

  const CheckoutPaymentScreen({
    Key? key,
    this.initialLatLng,
    this.address,
    this.subtotal = 0.0,
    this.deliveryFee = 0.0,
    this.discount = 0.0,
    this.restaurantId,
    this.comment,
    this.customerPhone,
    this.estimate,
    this.overrideFixedFee,
    this.overrideCityId,
    this.overrideCityName,
  }) : super(key: key);

  @override
  State<CheckoutPaymentScreen> createState() => _CheckoutPaymentScreenState();
}

class _CheckoutPaymentScreenState extends State<CheckoutPaymentScreen>
    with SingleTickerProviderStateMixin {
  PaymentMethod _method = PaymentMethod.cash;
  final TextEditingController _phoneController = TextEditingController();
  bool _agreeTerms = false;
  bool _isProcessing = false;

  gmap.GoogleMapController? _gmapController;
  final fmap.MapController _fmapController = fmap.MapController();

  double _pickedLat = 30.0444;
  double _pickedLng = 31.2357;
  String? _pickedAddress;

  String? _phoneError;
  String? _lastErrorKey;

  final OrderService _orderService = OrderService();
  final Uuid _uuid = const Uuid();

  double? _computedDeliveryFee;
  double? _computedChargedKm;
  double? _computedPerKmPrice;
  double? _computedBaseFee;
  double? _computedMinKm;
  bool _estimating = false;

  List<Map<String, dynamic>>? _passedItems;
  double? _passedSubtotal;
  double? _passedDeliveryFee;
  double? _passedDiscount;
  double? _passedTotal;
  bool _argsProcessed = false;

  final SupabaseClient _supabase = Supabase.instance.client;

  /// total getter: if previous screen passed a total, keep it exactly as passed.
  /// Otherwise compute it as (subtotal - discount) + deliveryFee (deliveryFee may be computed via km).
  double get total => _passedTotal ??
      (((_passedSubtotal ?? widget.subtotal) - (_passedDiscount ?? widget.discount)) + (_computedDeliveryFee ?? _passedDeliveryFee ?? widget.deliveryFee));

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: kPrimaryColor,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    if (widget.initialLatLng != null) {
      _pickedLat = widget.initialLatLng!.latitude;
      _pickedLng = widget.initialLatLng!.longitude;
    }
    if (widget.address != null && widget.address!.isNotEmpty) {
      _pickedAddress = widget.address;
    }
    if (widget.customerPhone != null && widget.customerPhone!.isNotEmpty) {
      _phoneController.text = widget.customerPhone!;
    }

    if (widget.overrideFixedFee != null) {
      _computedDeliveryFee = widget.overrideFixedFee;
    }

    if (widget.estimate != null) {
      final est = widget.estimate!;
      _computedChargedKm = est.chargedKm?.toDouble();
      _computedPerKmPrice = est.perKmPrice;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePricingLoaded());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _computeDeliveryLocallyIfPossible());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsProcessed) {
      final dynamic routeArgs = ModalRoute.of(context)?.settings.arguments;
      if (routeArgs is Map) {
        try {
          final dynamic rawItems = routeArgs['items'];
          if (rawItems is List) {
            try {
              _passedItems = rawItems.map<Map<String, dynamic>>((e) {
                if (e is Map) return Map<String, dynamic>.from(e as Map);
                return <String, dynamic>{};
              }).toList();
              if (_passedItems != null && _passedItems!.isEmpty) _passedItems = null;
            } catch (_) {
              _passedItems = null;
            }
          }
        } catch (_) {
          _passedItems = null;
        }

        try {
          final dynamic maybeSubtotal = routeArgs['subtotal'];
          if (maybeSubtotal is num) _passedSubtotal = maybeSubtotal.toDouble();
          else if (maybeSubtotal is String) _passedSubtotal = double.tryParse(maybeSubtotal) ?? widget.subtotal;
          else _passedSubtotal = widget.subtotal;
        } catch (_) {
          _passedSubtotal = widget.subtotal;
        }

        try {
          final dynamic maybeDeliveryFee = routeArgs['deliveryFee'];
          if (maybeDeliveryFee is num) _passedDeliveryFee = maybeDeliveryFee.toDouble();
          else if (maybeDeliveryFee is String) _passedDeliveryFee = double.tryParse(maybeDeliveryFee) ?? widget.deliveryFee;
          else _passedDeliveryFee = widget.deliveryFee;
        } catch (_) {
          _passedDeliveryFee = widget.deliveryFee;
        }

        try {
          final dynamic maybeDiscount = routeArgs['discount'];
          if (maybeDiscount is num) _passedDiscount = maybeDiscount.toDouble();
          else if (maybeDiscount is String) _passedDiscount = double.tryParse(maybeDiscount) ?? widget.discount;
          else _passedDiscount = widget.discount;
        } catch (_) {
          _passedDiscount = widget.discount;
        }

        // IMPORTANT FIX:
        // Only set _passedTotal if the previous screen explicitly provided 'total' in routeArgs.
        // We'll keep it, but later after computing delivery fee we will validate whether the passed total included delivery.
        try {
          if (routeArgs.containsKey('total')) {
            final dynamic maybeTotal = routeArgs['total'];
            if (maybeTotal is num) {
              _passedTotal = maybeTotal.toDouble();
            } else if (maybeTotal is String) {
              final parsed = double.tryParse(maybeTotal);
              if (parsed != null) _passedTotal = parsed;
              // if parsing fails, we intentionally leave _passedTotal null so the screen computes it.
            } else {
              // if key exists but not numeric/string, ignore and let computed flow handle it
            }
          } else {
            // no total passed explicitly -> keep _passedTotal null
          }
        } catch (_) {
          // on any error, prefer to leave _passedTotal null
          _passedTotal = null;
        }

        if (_passedDeliveryFee != null && widget.overrideFixedFee == null && _computedDeliveryFee == null) {
          _computedDeliveryFee = _passedDeliveryFee;
        }
      }
      _argsProcessed = true;
    }
  }

  @override
  void dispose() {
    _gmapController?.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showMessageLocalized(String key, {String variant = 'info'}) {
    final loc = AppLocalizations.of(context);
    final text = (loc == null) ? key : (loc.getStringOrNull(key) ?? key);
    BannerService.show(context, message: text, variant: variant);
  }

  void _showMessageText(String text, {String variant = 'info'}) {
    BannerService.show(context, message: text, variant: variant);
  }

  void _setUserErrorKey(String key) {
    if (kDebugMode) debugPrint('User error set (key): $key');
    _lastErrorKey = key;
    _showMessageLocalized(key, variant: 'error');
  }

  void _clearUserErrorKey() {
    _lastErrorKey = null;
  }

  bool _validatePhone() {
    final txt = _phoneController.text.trim();
    if (txt.isEmpty) {
      setState(() => _phoneError = null);
      _clearUserErrorKey();
      return true;
    }
    if (txt.length != 11) {
      setState(() => _phoneError = AppLocalizations.of(context)!.enter_valid_phone);
      _setUserErrorKey('enter_valid_phone');
      return false;
    }
    setState(() => _phoneError = null);
    _clearUserErrorKey();
    return true;
  }

  Future<void> _ensurePricingLoaded() async {
    if (_computedBaseFee != null && _computedPerKmPrice != null && _computedMinKm != null) return;

    try {
      final dynamic resp = await client.supabase.from('delivery_pricing').select().limit(1).maybeSingle();
      if (resp != null && resp is Map) {
        final base = (resp['base_fee'] as num?)?.toDouble() ?? 10.0;
        final perKm = (resp['per_km_price'] as num?)?.toDouble() ?? 5.0;
        final minKm = (resp['min_km'] as num?)?.toDouble() ?? 3.0;
        _computedBaseFee ??= base;
        _computedPerKmPrice ??= perKm;
        _computedMinKm ??= minKm;
      } else {
        _computedBaseFee ??= 10.0;
        _computedPerKmPrice ??= 5.0;
        _computedMinKm ??= 3.0;
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to load pricing: $e\n$st — falling back to defaults');
      _computedBaseFee ??= 10.0;
      _computedPerKmPrice ??= 5.0;
      _computedMinKm ??= 3.0;
    }
  }

  /// This function now:
  /// - computes local fee (base + chargedKm * perKm) when no overrideFixedFee.
  /// - after computing, if a total was passed but it seems to not include delivery (i.e. equals subtotal - discount),
  ///   we clear the passed total so the computed total will be used (subtotal - discount + delivery).
  Future<void> _computeDeliveryLocallyIfPossible() async {
    if (widget.overrideFixedFee != null) {
      // if admin override provided, prefer it and nothing else to do
      setState(() {
        _computedDeliveryFee = widget.overrideFixedFee;
      });
      return;
    }

    setState(() {
      _estimating = true;
      _clearUserErrorKey();
    });

    try {
      await _ensurePricingLoaded();
      _computedPerKmPrice ??= widget.estimate?.perKmPrice ?? 5.0;
      _computedBaseFee ??= 10.0;
      _computedMinKm ??= 3.0;

      double? branchLat;
      double? branchLng;

      if (widget.restaurantId != null && widget.restaurantId!.isNotEmpty) {
        try {
          final ds = DeliveryService(supabase: Supabase.instance.client);
          final branch = await ds.fetchBranchById(widget.restaurantId!);
          if (branch != null && branch.latitude != null && branch.longitude != null) {
            branchLat = branch.latitude;
            branchLng = branch.longitude;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('DeliveryService.fetchBranchById failed (ignored): $e');
        }
      }

      if (branchLat == null || branchLng == null) {
        try {
          final ds = DeliveryService(supabase: Supabase.instance.client);
          final nearest = await ds.getNearestBranches(lat: _pickedLat, lon: _pickedLng, limit: 1);
          if (nearest.isNotEmpty) {
            final nb = nearest.first;
            branchLat = nb.latitude;
            branchLng = nb.longitude;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('getNearestBranches failed (ignored): $e');
        }
      }

      if (branchLat != null && branchLng != null) {
        // compute charged km + fee using pricing values
        final meters = _haversineMeters(branchLat, branchLng, _pickedLat, _pickedLng);
        final chargedKm = computeChargedKmFromMetersWithMin(meters, _computedMinKm ?? 3.0);
        final fee = calculateDeliveryFee(
          chargedKm: chargedKm,
          baseFee: _computedBaseFee ?? 10.0,
          perKmPrice: _computedPerKmPrice ?? 5.0,
        );
        setState(() {
          _computedChargedKm = chargedKm;
          _computedDeliveryFee = fee;
        });
      } else {
        // fallback: use whatever was passed or widget deliveryFee
        setState(() {
          _computedDeliveryFee ??= _passedDeliveryFee ?? widget.deliveryFee;
        });
      }

      // --- New logic: validate whether passed total omitted delivery fee ---
      if (_passedTotal != null) {
        final double finalDelivery = _computedDeliveryFee ?? _passedDeliveryFee ?? widget.deliveryFee;
        final double subtotal = _passedSubtotal ?? widget.subtotal;
        final double discount = _passedDiscount ?? widget.discount;
        final double expectedWithoutDelivery = subtotal - discount;

        // If the passed total equals subtotal-discount (i.e. delivery not included) but we now have a positive delivery,
        // ignore the passed total so UI and order creation will use computed total including delivery.
        if (( (_passedTotal! - expectedWithoutDelivery).abs() < 0.01 ) && (finalDelivery > 0.0)) {
          if (kDebugMode) debugPrint('Passed total appears to omit delivery — clearing _passedTotal to compute final total including delivery.');
          setState(() {
            _passedTotal = null;
          });
        }
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('computeDeliveryLocally ERROR: $e\n$st');
      _setUserErrorKey('error_loading_restaurants');
      setState(() {
        _computedDeliveryFee ??= _passedDeliveryFee ?? widget.deliveryFee;
      });
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _clearAndEnsureLocalRemoval(String restaurantId, {String? customerId}) async {
    if (restaurantId.isEmpty) return;
    CartService.instance.startClearingRestaurant(restaurantId);

    try {
      await CartApi.clearCartForRestaurant(restaurantId);
    } catch (e) {
      if (kDebugMode) debugPrint('Server-side clear failed (best-effort): $e');
    }

    try {
      CartService.instance.removeItemsForRestaurant(restaurantId);
      await CartService.instance.persistNow();
    } catch (e) {
      if (kDebugMode) debugPrint('Local remove/persist error: $e');
    }

    try {
      await CartApi.fetchAndSyncAllUserCarts();
    } catch (e) {
      if (kDebugMode) debugPrint('fetchAndSyncAllUserCarts failed: $e');
    }

    CartService.instance.stopClearingRestaurant(restaurantId);
  }

  Future<String> _resolveCustomerIdForOrderCreation() async {
    final cid = await CartApi.currentCustomerId();
    if (cid != null && cid.isNotEmpty) return cid;

    final supUser = client.supabase.auth.currentUser ?? client.supabase.auth.currentSession?.user;
    if (supUser != null) {
      try {
        var row = await userService.fetchCustomerByUid(supUser.id);
        if (row == null) {
          final upserted = await userService.insertOrUpdateUser(
            uid: supUser.id,
            firstName: supUser.userMetadata?['first_name'] ?? (supUser.email ?? 'User'),
            email: supUser.email,
          );
          if (upserted) row = await userService.fetchCustomerByUid(supUser.id);
        }
        if (row != null && row['id'] != null) return row['id'] as String;
      } catch (e, st) {
        if (kDebugMode) debugPrint('resolveCustomerId async error: $e\n$st');
      }
    }

    final fallback = _uuid.v4();
    if (kDebugMode) debugPrint('resolveCustomerId: falling back to generated UUID $fallback');
    return fallback;
  }

  void _sanitizeAndShowError(dynamic e, StackTrace? st, {String? friendlyKey}) {
    final loc = AppLocalizations.of(context);
    final friendly = friendlyKey != null ? (loc?.getStringOrNull(friendlyKey) ?? friendlyKey) : (loc?.checkout_failed ?? 'Failed to place order. Please try again later.');
    _setUserErrorKey(friendlyKey ?? 'checkout_failed');
    _showMessageText(friendly, variant: 'error');
    if (kDebugMode) {
      debugPrint('Sanitized error shown to user: $friendly');
      debugPrint('Full error: $e\n$st');
    }
  }

  Future<void> _onConfirmPressed() async {
    _clearUserErrorKey();

    final loc = AppLocalizations.of(context)!;

    if (!_agreeTerms) {
      _setUserErrorKey('please_accept_terms');
      _showMessageLocalized('please_accept_terms', variant: 'error');
      return;
    }
    if (!_validatePhone()) return;

    setState(() => _isProcessing = true);

    try {
      // ensure pricing loaded
      await _ensurePricingLoaded();
      _computedPerKmPrice ??= widget.estimate?.perKmPrice ?? 5.0;
      _computedBaseFee ??= 10.0;
      _computedMinKm ??= 3.0;

      // If we don't yet have a computed delivery fee (and no override), try compute it now (best-effort)
      if (_computedDeliveryFee == null && widget.overrideFixedFee == null) {
        await _computeDeliveryLocallyIfPossible();
      }

      String? restId = widget.restaurantId;
      Branch? nearestBranch;

      if (restId == null || restId.isEmpty) {
        final ds = DeliveryService(supabase: Supabase.instance.client);
        final nearest = await ds.getNearestBranches(lat: _pickedLat, lon: _pickedLng, limit: 1);
        if (nearest.isEmpty) {
          _setUserErrorKey('no_nearby_restaurant');
          _showMessageLocalized('no_nearby_restaurant', variant: 'error');
          if (mounted) setState(() => _isProcessing = false);
          return;
        }
        nearestBranch = nearest.first;
        restId = nearestBranch.restaurantId;
        if (restId == null || restId.isEmpty) {
          restId = nearestBranch.id;
        }
      } else {
        try {
          final ds = DeliveryService(supabase: Supabase.instance.client);
          final nearest = await ds.getNearestBranches(lat: _pickedLat, lon: _pickedLng, limit: 1);
          if (nearest.isNotEmpty) nearestBranch = nearest.first;
        } catch (_) {}
      }

      if (restId == null || restId.isEmpty) {
        _setUserErrorKey('could_not_determine_restaurant');
        _showMessageLocalized('could_not_determine_restaurant', variant: 'error');
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      final customerId = await _resolveCustomerIdForOrderCreation();

      final List<dynamic> cartItemsSource;
      if (_passedItems != null && _passedItems!.isNotEmpty) {
        cartItemsSource = _passedItems!;
      } else {
        cartItemsSource = CartService.instance.items.where((it) => it.restaurantId == restId).toList();
      }

      final itemsPayload = cartItemsSource.map((ci) {
        if (ci is Map<String, dynamic>) {
          return {
            'menu_item_id': ci['menu_item_id'],
            'variant_id': ci['variant_id'] ?? '',
            'name': ci['name'],
            'unit_price': ci['unit_price'],
            'qty': ci['qty'],
            'image_url': ci['image_url'] ?? ''
          };
        } else {
          try {
            return {
              'menu_item_id': (ci as dynamic).menuItemId,
              'variant_id': (ci as dynamic).variantId ?? '',
              'name': (ci as dynamic).name,
              'unit_price': (ci as dynamic).unitPrice,
              'qty': (ci as dynamic).qty,
              'image_url': (ci as dynamic).imageUrl ?? ''
            };
          } catch (_) {
            return <String, dynamic>{};
          }
        }
      }).toList();

      // ensure computed delivery fee is set (honor passed delivery fee, overrideFixedFee, or computed)
      _computedDeliveryFee ??= _passedDeliveryFee ?? widget.deliveryFee;
      _computedPerKmPrice ??= widget.estimate?.perKmPrice ?? 5.0;
      _computedBaseFee ??= 10.0;
      _computedMinKm ??= 3.0;

      final orderId = _uuid.v4();
      final items = <OrderItem>[];
      final uuid = Uuid();

      for (final ci in cartItemsSource) {
        if (ci is Map<String, dynamic>) {
          final menuItemId = ci['menu_item_id']?.toString() ?? uuid.v4();
          final variantIdRaw = ci['variant_id'];
          final variantId = (variantIdRaw is String && variantIdRaw.isNotEmpty) ? variantIdRaw : null;
          final name = ci['name']?.toString() ?? 'Item';
          final unitPrice = (ci['unit_price'] is num) ? (ci['unit_price'] as num).toDouble() : double.tryParse(ci['unit_price']?.toString() ?? '') ?? 0.0;
          final qty = (ci['qty'] is int) ? ci['qty'] as int : int.tryParse(ci['qty']?.toString() ?? '') ?? 1;
          final imageUrl = ci['image_url']?.toString();
          items.add(OrderItem(
            id: uuid.v4(),
            orderId: orderId,
            menuItemId: menuItemId,
            variantId: variantId,
            name: name,
            unitPrice: unitPrice,
            qty: qty,
            imageUrl: imageUrl,
          ));
        } else {
          try {
            items.add(OrderItem(
              id: uuid.v4(),
              orderId: orderId,
              menuItemId: (ci as dynamic).menuItemId,
              variantId: (ci as dynamic).variantId,
              name: (ci as dynamic).name,
              unitPrice: (ci as dynamic).unitPrice,
              qty: (ci as dynamic).qty,
              imageUrl: (ci as dynamic).imageUrl,
            ));
          } catch (e) {
            if (kDebugMode) debugPrint('Failed to parse cart item into OrderItem: $e');
          }
        }
      }

      if (items.isEmpty) {
        items.add(OrderItem(
          id: uuid.v4(),
          orderId: orderId,
          menuItemId: uuid.v4(),
          name: "Item",
          unitPrice: widget.subtotal > 0 ? widget.subtotal : 0.0,
          qty: 1,
        ));
      }

      String? branchId = nearestBranch?.id;

      // ORDER TOTAL logic:
      // - If previous screen provided a total (_passedTotal) AND it seems to already include delivery -> use it exactly.
      // - Otherwise compute total as (subtotal - discount) + deliveryFee (deliveryFee may be _computedDeliveryFee which is based on km).
      double orderTotal;
      final double effectiveDelivery = _computedDeliveryFee ?? _passedDeliveryFee ?? widget.deliveryFee;
      if (_passedTotal != null) {
        // validate that _passedTotal likely includes delivery: difference between passedTotal and (subtotal-discount) should be >= effectiveDelivery - epsilon
        final double subtotal = _passedSubtotal ?? widget.subtotal;
        final double discount = _passedDiscount ?? widget.discount;
        final double includedDeliveryInPassedTotal = _passedTotal! - (subtotal - discount);
        if (includedDeliveryInPassedTotal >= (effectiveDelivery - 0.01)) {
          // passed total seems to include delivery -> honor it
          orderTotal = _passedTotal!;
        } else {
          // passed total likely omitted delivery -> compute ourselves
          orderTotal = ((subtotal - discount) + effectiveDelivery);
        }
      } else {
        orderTotal = (((_passedSubtotal ?? widget.subtotal) - (_passedDiscount ?? widget.discount)) + effectiveDelivery);
      }

      final order = Order(
        id: orderId,
        customerId: customerId,
        restaurantId: restId,
        total: double.parse(orderTotal.toStringAsFixed(2)),
        status: "delivering",
        createdAt: DateTime.now(),
        branchId: branchId,
        deliveryLatitude: _pickedLat,
        deliveryLongitude: _pickedLng,
        deliveryAddress: _pickedAddress,
        comment: widget.comment,
        customerPhone: _phoneController.text.isNotEmpty ? _phoneController.text : widget.customerPhone,
        items: items,
        // ensure deliveryFee stored explicitly (rounded two decimals)
        deliveryFee: double.parse(effectiveDelivery.toStringAsFixed(2)),
        chargedKm: _computedChargedKm?.toInt(),
        perKmPrice: _computedPerKmPrice,
        distanceMeters: (_computedChargedKm != null) ? (_computedChargedKm! * 1000.0) : null,
      );

      if (kDebugMode) debugPrint('Checkout: creating order via OrderService.createOrder (orderId=$orderId) with auto_assign_driver=false');

      dynamic savedOrder;
      try {
        savedOrder = await _orderService.createOrder(order, items, autoAssignDriver: false);
      } catch (e, st) {
        _sanitizeAndShowError(e, st, friendlyKey: 'checkout_failed');
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      if (savedOrder != null) {
        if (kDebugMode) debugPrint('Checkout: save succeeded (orderId=$orderId). Cleaning up cart.');

        try {
          await _clearAndEnsureLocalRemoval(restId, customerId: customerId);
        } catch (e) {
          if (kDebugMode) debugPrint('Fallback cleanup failed: $e');
        }

        try {
          await CartApi.fetchAndSyncAllUserCarts();
        } catch (e) {
          if (kDebugMode) debugPrint('Cart sync after fallback failed: $e');
        }

        _clearUserErrorKey();
        _showMessageLocalized('order_success', variant: 'success');

        if (mounted) {
          Future.delayed(const Duration(milliseconds: 700), () {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
          });
        }
      } else {
        _setUserErrorKey('order_failed');
        _showMessageLocalized('order_failed', variant: 'error');
      }
    } catch (e, st) {
      _sanitizeAndShowError(e, st, friendlyKey: 'checkout_failed');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openMapPickerInline() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _MapPickerBottomSheet(
          initialLat: _pickedLat,
          initialLng: _pickedLng,
          primaryColor: kPrimaryColor,
        );
      },
    );

    if (result != null && mounted) {
      final lat = result['latitude'] as double?;
      final lng = result['longitude'] as double?;
      final addr = result['address'] as String?;
      final maybeOverrideFee = result['override_fixed_fee'];

      if (lat != null && lng != null) {
        setState(() {
          _pickedLat = lat;
          _pickedLng = lng;
          if (addr != null && addr.isNotEmpty) _pickedAddress = addr;
          _clearUserErrorKey();
        });

        if (maybeOverrideFee != null) {
          double? parsedFee;
          try {
            if (maybeOverrideFee is num) parsedFee = (maybeOverrideFee as num).toDouble();
            else parsedFee = double.tryParse(maybeOverrideFee.toString());
          } catch (_) {
            parsedFee = null;
          }

          if (parsedFee != null) {
            setState(() {
              _computedDeliveryFee = parsedFee;
            });
            _showMessageLocalized('fixed_delivery_price_applied', variant: 'info');
            return;
          }
        }

        _computedDeliveryFee = null;
        _computedChargedKm = null;
        await _computeDeliveryLocallyIfPossible();
      }
    }
  }

  String _t(String ar, String en) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'ar' ? ar : en;
  }

  Widget _buildSmallMapPreview(double height, {double? lat, double? lng}) {
    final borderRadius = BorderRadius.circular(12.0);
    const double fallbackLat = 30.0444;
    const double fallbackLng = 31.2357;
    final bool hasPicked = lat != null && lng != null;
    final double defaultLat = lat ?? fallbackLat;
    final double defaultLng = lng ?? fallbackLng;
    final theme = Theme.of(context);
    final previewBg = theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[200];

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: previewBg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AbsorbPointer(
              absorbing: true,
              child: Builder(builder: (context) {
                if (kIsWeb) {
                  final center = ll.LatLng(defaultLat, defaultLng);
                  return fmap.FlutterMap(
                    mapController: _fmapController,
                    options: fmap.MapOptions(initialCenter: center, initialZoom: 14),
                    children: [
                      fmap.TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.app',
                      ),
                      fmap.MarkerLayer(
                        markers: [
                          fmap.Marker(
                            point: center,
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_on,
                              color: hasPicked ? Colors.red : Colors.grey,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                } else {
                  final cameraPos = gmap.CameraPosition(target: gmap.LatLng(defaultLat, defaultLng), zoom: 14);
                  return gmap.GoogleMap(
                    initialCameraPosition: cameraPos,
                    onMapCreated: (c) => _gmapController = c,
                    markers: {
                      gmap.Marker(
                        markerId: const gmap.MarkerId('picked'),
                        position: gmap.LatLng(defaultLat, defaultLng),
                        icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                          hasPicked ? gmap.BitmapDescriptor.hueRed : gmap.BitmapDescriptor.hueAzure,
                        ),
                      ),
                    },
                    myLocationEnabled: false,
                    zoomControlsEnabled: false,
                    liteModeEnabled: true,
                  );
                }
              }),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                decoration: BoxDecoration(color: Theme.of(context).cardColor.withOpacity(0.95), borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit, size: 16),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.of(context)!.change, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTermsInline() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return Padding(
          padding: MediaQuery.of(ctx).viewInsets,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(loc.terms_title ?? 'Terms & Conditions', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    loc.terms_paragraph1 ?? '1. Availability: The delivery service is subject to availability in your area. We will notify you if your order cannot be fulfilled.',
                    style: const TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loc.terms_paragraph2 ?? '2. Accuracy of information: You confirm that the phone number and address you provide are accurate. Incorrect details may delay or cancel your order.',
                    style: const TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loc.terms_paragraph3 ?? '3. Payment: Cash on delivery is accepted. Mobile wallet payments will be supported soon.',
                    style: const TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loc.terms_paragraph4 ?? '4. Cancellations and refunds: Orders can be cancelled according to the restaurant policy.',
                    style: const TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Text(loc.thank_you ?? 'Thank you for using our service — we appreciate your trust!', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final displaySubtotal = _passedSubtotal ?? widget.subtotal;
    final displayDeliveryFee = _computedDeliveryFee ?? _passedDeliveryFee ?? widget.deliveryFee;
    final displayDiscount = _passedDiscount ?? widget.discount;
    final displayTotal = _passedTotal ?? ((displaySubtotal - displayDiscount) + displayDeliveryFee);

    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black87;
    final subtitleColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: kPrimaryColor,
        statusBarIconBrightness: Brightness.light,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        color: scaffoldBg,
        child: SafeArea(
          bottom: false,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(loc.checkout_title),
              backgroundColor: kPrimaryColor,
              elevation: 0,
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: GestureDetector(
                    onTap: _openMapPickerInline,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      child: Column(
                        key: ValueKey<int>(theme.brightness == Brightness.dark ? 1 : 0),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(loc.delivery_location, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(height: 8),
                          _buildSmallMapPreview(180, lat: _pickedLat, lng: _pickedLng),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 16, color: theme.brightness == Brightness.dark ? Colors.orangeAccent : Colors.redAccent),
                              const SizedBox(width: 6),
                              Expanded(child: Text(_pickedAddress ?? loc.choose_address, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: subtitleColor))),
                              TextButton(onPressed: _openMapPickerInline, child: Text(loc.change)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeInOut,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(loc.pay_with, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(height: 8),

                          Card(
                            color: cardColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            child: Column(
                              children: [
                                RadioListTile<PaymentMethod>(
                                  value: PaymentMethod.mobileWallet,
                                  groupValue: _method,
                                  onChanged: (v) => setState(() => _method = v ?? PaymentMethod.cash),
                                  title: Text('Mobile wallet (Vodafone / Etisalat / Orange)', style: TextStyle(color: textColor)),
                                  subtitle: Text('Pay using your mobile wallet account', style: TextStyle(color: subtitleColor)),
                                ),
                                RadioListTile<PaymentMethod>(
                                  value: PaymentMethod.cash,
                                  groupValue: _method,
                                  onChanged: (v) => setState(() => _method = v ?? PaymentMethod.cash),
                                  title: Text('Cash (on delivery)', style: TextStyle(color: textColor)),
                                  subtitle: Text('Pay in cash when the courier arrives', style: TextStyle(color: subtitleColor)),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),
                          Text(loc.enter_valid_phone, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                            decoration: InputDecoration(
                              hintText: '01xxxxxxxxx',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              errorText: _phoneError,
                              prefixIcon: const Icon(Icons.phone),
                              fillColor: cardColor,
                              filled: false,
                            ),
                            style: TextStyle(color: textColor),
                            onChanged: (_) {
                              if (_phoneError != null) _validatePhone();
                            },
                          ),

                          const SizedBox(height: 16),
                          if (widget.comment != null && widget.comment!.isNotEmpty) ...[
                            Text(loc.comment, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                            const SizedBox(height: 8),
                            Card(
                              color: cardColor,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              child: Padding(padding: const EdgeInsets.all(12.0), child: Text(widget.comment!, style: TextStyle(color: textColor))),
                            ),
                            const SizedBox(height: 12),
                          ],

                          Text(loc.paymentSummary, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(height: 8),
                          Card(
                            color: cardColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Column(
                                children: [
                                  Row(children: [Expanded(child: Text(loc.subtotal, style: TextStyle(color: textColor))), Text('${displaySubtotal.toStringAsFixed(2)} EGP', style: TextStyle(color: textColor))]),
                                  const SizedBox(height: 6),
                                  if (displayDiscount > 0) ...[
                                    Row(children: [Expanded(child: Text(loc.discount, style: TextStyle(color: textColor))), Text('- ${displayDiscount.toStringAsFixed(2)} EGP', style: TextStyle(color: textColor))]),
                                    const SizedBox(height: 6),
                                  ],
                                  Row(children: [
                                    Expanded(child: Text(loc.delivery_fee, style: TextStyle(color: textColor))),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 360),
                                      child: _estimating
                                          ? Row(
                                        key: const ValueKey('estimating'),
                                        children: [const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Text(loc.calculating, style: TextStyle(color: subtitleColor))],
                                      )
                                          : Text('${displayDeliveryFee.toStringAsFixed(2)} EGP', key: const ValueKey('fee'), style: TextStyle(color: textColor)),
                                    ),
                                  ]),
                                  if (_computedChargedKm != null) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            AppLocalizations.of(context)!.distance(_computedChargedKm!.toStringAsFixed(1)),
                                            style: TextStyle(color: textColor),
                                          ),
                                        ),
                                        Text('${_computedChargedKm!.toStringAsFixed(1)} ${AppLocalizations.of(context)!.km_unit}', style: TextStyle(color: textColor))
                                      ],
                                    )
                                  ],
                                  if (_computedPerKmPrice != null) ...[
                                    const SizedBox(height: 6),
                                    Row(children: [Expanded(child: Text('Per km price', style: TextStyle(color: textColor))), Text('${_computedPerKmPrice!.toStringAsFixed(2)} EGP', style: TextStyle(color: textColor))]),
                                  ],
                                  const Divider(height: 18),
                                  Row(children: [Expanded(child: Text(loc.total, style: TextStyle(fontWeight: FontWeight.bold, color: textColor))), Text('${displayTotal.toStringAsFixed(2)} EGP', style: const TextStyle(fontWeight: FontWeight.bold))]),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(value: _agreeTerms, onChanged: (v) => setState(() => _agreeTerms = v ?? false)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Wrap(
                                  children: [
                                    Text(loc.please_accept_terms, style: TextStyle(color: textColor)),
                                    const SizedBox(width: 6),
                                    GestureDetector(onTap: _openTermsInline, child: Text('terms and conditions', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, decoration: TextDecoration.underline))),
                                    const Text('.'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (_agreeTerms && !_isProcessing) ? _onConfirmPressed : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _isProcessing
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text(loc.checkout, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper bottom sheet map picker widget (simple inline picker).
class _MapPickerBottomSheet extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final Color primaryColor;

  const _MapPickerBottomSheet({
    Key? key,
    required this.initialLat,
    required this.initialLng,
    required this.primaryColor,
  }) : super(key: key);

  @override
  State<_MapPickerBottomSheet> createState() => _MapPickerBottomSheetState();
}

class _MapPickerBottomSheetState extends State<_MapPickerBottomSheet> {
  double _lat = 30.0444;
  double _lng = 31.2357;
  String? _address;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.78;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(6))),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: Text(
                      'Map preview here',
                      style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              children: [
                Text(_address ?? '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(AppLocalizations.of(context)!.no),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: widget.primaryColor),
                        onPressed: () {
                          Navigator.of(context).pop({
                            'latitude': _lat,
                            'longitude': _lng,
                            'address': _address,
                          });
                        },
                        child: Text(AppLocalizations.of(context)!.yes),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// --------------------------------------------
/// NOTE: AppLocalizations helper (extension)
/// --------------------------------------------
extension _LocExt on AppLocalizations {
  String? getStringOrNull(String key) {
    switch (key) {
      case 'order_success':
        return order_success;
      case 'checkout_failed':
        return checkout_failed;
      case 'order_failed':
        return order_failed;
      case 'please_accept_terms':
        return please_accept_terms;
      case 'fixed_delivery_price_applied':
        return fixed_delivery_price_applied ?? 'Fixed delivery price applied';
      case 'no_nearby_restaurant':
        return no_nearby_restaurant ?? 'No nearby restaurant';
      case 'could_not_determine_restaurant':
        return could_not_determine_restaurant ?? 'Could not determine the restaurant';
      case 'error_loading_restaurants':
        return error_loading_restaurants ?? 'Error loading restaurants';
      case 'enter_valid_phone':
        return enter_valid_phone;
      default:
        return null;
    }
  }
}
