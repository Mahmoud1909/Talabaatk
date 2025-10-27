// lib/screens/cart_screen.dart
import 'dart:async';
import 'dart:math' show min;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/screens/PaymentScreen.dart';
import 'package:talabak_users/services/cart_service.dart';
import 'package:talabak_users/services/cart_api.dart';
import 'package:talabak_users/screens/item_detail_screen.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

const Color kPrimaryColor = Color(0xFFFF5C01);

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with TickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  final Map<String, String> _restaurantNames = {}; // restaurantId -> name
  final Set<String> _loadingItemIds = {};
  final Map<String, Timer?> _loadingDelayTimers = {};
  final Set<String> _removingItemIds = {};
  final Map<String, bool> _isAnimatingRemoval = {};

  bool _isSyncing = false;
  Timer? _syncDebounceTimer;
  List<CartItem> _lastKnownItems = [];

  static const int _syncDebounceMs = 600;
  static const int _spinnerDelayMs = 180;

  // Stagger controller for entrance animations (kept for cards)
  late final AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _staggerController.forward();
    _initCartFlow();
  }

  @override
  void dispose() {
    for (final t in _loadingDelayTimers.values) {
      t?.cancel();
    }
    _loadingDelayTimers.clear();
    _syncDebounceTimer?.cancel();
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _initCartFlow() async {
    await CartService.instance.loadFromLocal();
    await _loadRestaurantNames();

    final local = CartService.instance.items;
    if (local.isNotEmpty) _lastKnownItems = local;

    try {
      final session = _supabase.auth.currentSession;
      if (session != null) {
        final customerId = await CartApi.currentCustomerId();
        if (customerId != null) {
          await _reconcileLocalProvisionalItemsWithServer(customerId);
          await _runFullSync(immediate: true);
        }
      }
    } catch (_) {
      // silent - user-visible errors use MessageOverlay
    }
  }

  Future<void> _reconcileLocalProvisionalItemsWithServer(String customerId) async {
    final provisional = CartService.instance.items.where((it) => _isProvisionalId(it.id)).toList();
    for (final it in provisional) {
      try {
        await CartApi.addToCart(
          customerId: customerId,
          restaurantId: it.restaurantId ?? '',
          menuItemId: it.menuItemId,
          variantId: it.variantId,
          name: it.name,
          clientUnitPrice: it.unitPrice,
          qty: it.qty,
          imageUrl: it.imageUrl,
          localCartItemId: it.id,
        );
      } catch (_) {
        // silent fallback; sync later
      }
    }
  }

  Future<void> _loadRestaurantNames() async {
    final ids = CartService.instance.items.map((e) => e.restaurantId).whereType<String>().toSet().toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _restaurantNames.clear());
      return;
    }

    try {
      final response = await _supabase.from('restaurants').select('id, name').inFilter('id', ids);
      final map = <String, String>{};
      if (response is List) {
        for (final r in response) {
          final m = Map<String, dynamic>.from(r as Map);
          map[m['id'] as String] = (m['name'] as String?) ?? '';
        }
      }
      if (mounted) setState(() {
        _restaurantNames
          ..clear()
          ..addAll(map);
      });
    } catch (_) {
      // silent - names are non-critical
    }
  }

  bool _isProvisionalId(String id) => id.contains('-local');

  void _startLoadingWithDelay(String itemId, {int delayMs = _spinnerDelayMs}) {
    _loadingDelayTimers[itemId]?.cancel();
    _loadingDelayTimers[itemId] = Timer(Duration(milliseconds: delayMs), () {
      if (mounted) setState(() => _loadingItemIds.add(itemId));
    });
  }

  void _stopLoadingAndCancelDelay(String itemId) {
    _loadingDelayTimers[itemId]?.cancel();
    _loadingDelayTimers.remove(itemId);
    if (mounted) setState(() => _loadingItemIds.remove(itemId));
  }

  void _scheduleFullSync({int debounceMs = _syncDebounceMs, bool immediate = false}) {
    if (immediate) {
      _syncDebounceTimer?.cancel();
      _runFullSync(immediate: true);
      return;
    }
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(Duration(milliseconds: debounceMs), () {
      _runFullSync();
    });
  }

  Future<void> _runFullSync({bool immediate = false}) async {
    if (mounted) setState(() => _isSyncing = true);
    try {
      await CartApi.fetchAndSyncAllUserCarts();
      await _loadRestaurantNames();

      final fresh = CartService.instance.items;
      if (fresh.isNotEmpty) _lastKnownItems = fresh;
    } catch (_) {
      // silent; user-visible errors handled locally
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _incQty(CartItem it) async {
    final backup = CartService.instance.items.toList();
    final newQty = it.qty + 1;
    CartService.instance.updateQty(it.id, newQty);
    _startLoadingWithDelay(it.id);

    try {
      if (_isProvisionalId(it.id)) {
        final customerId = await CartApi.currentCustomerId();
        if (customerId == null) throw Exception('not_authenticated');
        await CartApi.addToCart(
          customerId: customerId,
          restaurantId: it.restaurantId ?? '',
          menuItemId: it.menuItemId,
          variantId: it.variantId,
          name: it.name,
          clientUnitPrice: it.unitPrice,
          qty: 1,
          imageUrl: it.imageUrl,
          localCartItemId: it.id,
        );
      } else {
        await CartApi.setItemQty(it.id, newQty, restaurantId: it.restaurantId);
      }

      _scheduleFullSync();
      final cached = CartService.instance.items;
      if (cached.isNotEmpty) _lastKnownItems = cached;

      // **Plain / non-animated** acknowledgement for quantity change:
      MessageOverlay.showPositive(context, AppLocalizations.of(context)!.qtyUpdated, animated: false);
    } catch (e) {
      // rollback
      CartService.instance.replaceAll(backup);
      if (mounted) MessageOverlay.showNegative(context, AppLocalizations.of(context)!.failedToUpdateQty(e.toString()));
    } finally {
      _stopLoadingAndCancelDelay(it.id);
    }
  }

  Future<void> _decQty(CartItem it) async {
    final backup = CartService.instance.items.toList();
    final newQty = it.qty - 1;
    if (newQty <= 0) {
      await _animateAndRemove(it, backup: backup);
      return;
    }

    CartService.instance.updateQty(it.id, newQty);
    _startLoadingWithDelay(it.id);

    try {
      if (_isProvisionalId(it.id)) {
        final customerId = await CartApi.currentCustomerId();
        if (customerId == null) throw Exception('not_authenticated');
        await CartApi.addToCart(
          customerId: customerId,
          restaurantId: it.restaurantId ?? '',
          menuItemId: it.menuItemId,
          variantId: it.variantId,
          name: it.name,
          clientUnitPrice: it.unitPrice,
          qty: newQty,
          imageUrl: it.imageUrl,
          localCartItemId: it.id,
        );
      } else {
        await CartApi.setItemQty(it.id, newQty, restaurantId: it.restaurantId);
      }

      _scheduleFullSync();
      final cached = CartService.instance.items;
      if (cached.isNotEmpty) _lastKnownItems = cached;

      // **Plain / non-animated** acknowledgement for quantity change:
      MessageOverlay.showPositive(context, AppLocalizations.of(context)!.qtyUpdated, animated: false);
    } catch (e) {
      CartService.instance.replaceAll(backup);
      if (mounted) MessageOverlay.showNegative(context, AppLocalizations.of(context)!.failedToUpdateQty(e.toString()));
    } finally {
      _stopLoadingAndCancelDelay(it.id);
    }
  }

  Future<void> _animateAndRemove(CartItem it, {List<CartItem>? backup}) async {
    final backupList = backup ?? CartService.instance.items.toList();
    final itemId = it.id;

    if (_isAnimatingRemoval[itemId] == true) return;

    if (mounted) setState(() => _isAnimatingRemoval[itemId] = true);

    // short animation for visual feedback (kept)
    const animationDuration = Duration(milliseconds: 340);
    await Future.delayed(animationDuration);

    if (mounted) setState(() => _removingItemIds.add(itemId));

    // optimistic local remove
    try {
      CartService.instance.removeItem(itemId);
      await CartService.instance.persistNow();
    } catch (_) {
      // ignore local persistence errors
    }

    try {
      if (_isProvisionalId(itemId)) {
        _scheduleFullSync(immediate: true);
      } else {
        await CartApi.removeFromCart(itemId, restaurantId: it.restaurantId);
        _scheduleFullSync(immediate: true);
      }
      MessageOverlay.showPositive(context, AppLocalizations.of(context)!.itemRemoved);
    } catch (e) {
      // restore on failure
      try {
        CartService.instance.replaceAll(backupList);
        await CartService.instance.persistNow();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isAnimatingRemoval[itemId] = false;
          _removingItemIds.remove(itemId);
        });
        MessageOverlay.showNegative(context, AppLocalizations.of(context)!.failedToRemoveItem(e.toString()));
      }
      return;
    } finally {
      if (mounted) setState(() => _removingItemIds.remove(itemId));
    }

    if (mounted) setState(() => _isAnimatingRemoval.remove(itemId));
  }

  Future<void> _clearCartForRestaurant(String restaurantId) async {
    CartService.instance.startClearingRestaurant(restaurantId);
    try {
      await CartApi.clearCartForRestaurant(restaurantId);
      _scheduleFullSync(immediate: true);
      MessageOverlay.showPositive(context, AppLocalizations.of(context)!.cartCleared);
    } catch (e) {
      MessageOverlay.showNegative(context, AppLocalizations.of(context)!.failedToClearCart(e.toString()));
    } finally {
      CartService.instance.stopClearingRestaurant(restaurantId);
    }
  }

  Future<void> _checkout(String restaurantId) async {
    try {
      final restName = _restaurantNames[restaurantId] ?? AppLocalizations.of(context)!.restaurant;
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentScreen(restaurantId: restaurantId, restaurantName: restName),
          ),
        );
      }
      _scheduleFullSync(immediate: true);
    } catch (e) {
      MessageOverlay.showNegative(context, AppLocalizations.of(context)!.failedToNavigatePayment(e.toString()));
    }
  }

  Widget _itemImage(String? url) {
    const double size = 56;
    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.fastfood),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(width: size, height: size, color: Colors.grey[200]);
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(width: size, height: size, color: Colors.grey[200], child: const Icon(Icons.broken_image));
        },
      ),
    );
  }

  Widget _qtyControl(BuildContext context, CartItem it) {
    final isUpdating = _loadingItemIds.contains(it.id);
    final isRemoving = _removingItemIds.contains(it.id);
    final isAnimating = _isAnimatingRemoval[it.id] == true;

    const double controlSize = 40;
    const double qtyWidth = 44;

    Widget leftControl() {
      if (isRemoving) {
        return const SizedBox(
          width: controlSize,
          height: controlSize,
          child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      }

      return SizedBox(
        width: controlSize,
        height: controlSize,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: controlSize, height: controlSize),
          onPressed: (isUpdating || isRemoving || isAnimating)
              ? null
              : () {
            if (it.qty == 1) {
              _animateAndRemove(it);
            } else {
              _decQty(it);
            }
          },
          icon: Icon(it.qty == 1 ? Icons.delete_outline : Icons.remove),
          splashRadius: 20,
        ),
      );
    }

    // >>> REMOVED the quantity change animation (AnimatedSwitcher) as requested.
    // The number is shown plainly.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final qtyWidget = Text(
      '${it.qty}',
      key: ValueKey<int>(it.qty),
      style: TextStyle(
        fontWeight: FontWeight.w600,
        // When theme is dark the user asked the number to be black.
        color: isDark ? Colors.black : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
      ),
    );

    Widget rightControl() {
      return SizedBox(
        width: controlSize,
        height: controlSize,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: controlSize, height: controlSize),
          onPressed: (isUpdating || isRemoving || isAnimating) ? null : () => _incQty(it),
          icon: const Icon(Icons.add),
          splashRadius: 20,
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      leftControl(),
      const SizedBox(width: 6),
      Container(
        width: qtyWidth,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
        child: Center(child: qtyWidget),
      ),
      const SizedBox(width: 6),
      rightControl(),
    ]);
  }

  Widget _restaurantCard(BuildContext context, String restId, List<CartItem> restItems, int index) {
    // staggered animation based on index
    final double start = (index * 0.06).clamp(0.0, 0.6);
    final double end = (start + 0.6).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, child) {
        final t = (_staggerController.value - start) / (end - start);
        final eased = Curves.easeOut.transform(t.clamp(0.0, 1.0));
        return Opacity(opacity: eased, child: Transform.translate(offset: Offset(0, 12 * (1 - eased)), child: child));
      },
      child: _buildRestaurantCardBody(context, restId, restItems),
    );
  }

  Widget _buildRestaurantCardBody(BuildContext context, String restId, List<CartItem> restItems) {
    final t = AppLocalizations.of(context)!;
    final restName = _restaurantNames[restId] ?? restId;
    final restTotal = restItems.fold<double>(0.0, (s, it) => s + it.total);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(restName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            Text(t.currency(restTotal.toStringAsFixed(2)), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Column(children: restItems.map((it) {
            final animating = _isAnimatingRemoval[it.id] == true;
            return ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  opacity: animating ? 0.0 : 1.0,
                  child: animating
                      ? const SizedBox.shrink()
                      : InkWell(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: it.menuItemId, cartItemId: it.id, restaurantId: it.restaurantId)));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        _itemImage(it.imageUrl),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(t.currency(it.unitPrice.toStringAsFixed(2)), style: TextStyle(color: Colors.grey[700])),
                            ])),
                        const SizedBox(width: 8),
                        _qtyControl(context, it),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          }).toList()),
          const SizedBox(height: 10),
          Row(children: [
            ValueListenableBuilder<Set<String>>(
              valueListenable: CartService.instance.clearingRestaurants,
              builder: (context, clearingSet, _) {
                final isClearing = clearingSet.contains(restId);
                return ElevatedButton(
                  onPressed: isClearing ? null : () => _clearCartForRestaurant(restId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: kPrimaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: kPrimaryColor)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    elevation: 0,
                  ),
                  child: isClearing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t.clear, style: const TextStyle(fontWeight: FontWeight.w700)),
                );
              },
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () => _checkout(restId),
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              child: Text(AppLocalizations.of(context)!.checkout, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // keep status bar color same as app bar / primary color
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: kPrimaryColor, statusBarIconBrightness: Brightness.light));

    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.yourCart),
        backgroundColor: kPrimaryColor,
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: _isSyncing
                ? Padding(
              key: const ValueKey('syncing'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: 8),
                Text(t.syncing, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ]),
            )
                : const SizedBox(key: ValueKey('idle'), width: 0),
          )
        ],
      ),
      body: AnimatedBuilder(
        animation: CartService.instance,
        builder: (context, _) {
          List<CartItem> displayItems = CartService.instance.items;
          if (displayItems.isNotEmpty) _lastKnownItems = displayItems;
          else if (displayItems.isEmpty && _isSyncing && _lastKnownItems.isNotEmpty) displayItems = _lastKnownItems;

          if (displayItems.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(t.emptyCart, style: TextStyle(color: Colors.grey[700])),
              ]),
            );
          }

          final Map<String, List<CartItem>> byRest = {};
          for (final it in displayItems) {
            final r = it.restaurantId ?? 'unknown';
            byRest.putIfAbsent(r, () => []).add(it);
          }

          final restIds = byRest.keys.toList()
            ..sort((a, b) {
              final aName = _restaurantNames[a] ?? a;
              final bName = _restaurantNames[b] ?? b;
              return aName.compareTo(bName);
            });

          return RefreshIndicator(
            onRefresh: () async {
              _scheduleFullSync(immediate: true);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: restIds.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, sectionIndex) {
                final restId = restIds[sectionIndex];
                final restItems = byRest[restId]!;
                return _restaurantCard(context, restId, restItems, sectionIndex);
              },
            ),
          );
        },
      ),
    );
  }
}

/// ---------- Message overlay (distinctive rectangle messages) ----------
/// positive = sweet (green), negative = bitter (red)
class MessageOverlay {
  static void _show(BuildContext context, String message, {required bool positive, bool animated = true}) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final Color good = Colors.green.shade600;
    final Color bad = Colors.red.shade600;
    final color = positive ? good : bad;
    final bg = positive ? good.withOpacity(0.08) : bad.withOpacity(0.08);
    final border = positive ? good.withOpacity(0.16) : bad.withOpacity(0.16);
    final icon = positive ? Icons.check_circle_outline : Icons.error_outline;

    late OverlayEntry entry;

    if (!animated) {
      // Plain (no animation) overlay: appears immediately and auto-removes.
      entry = OverlayEntry(
        builder: (context) {
          return Positioned(
            top: 84,
            left: 18,
            right: 18,
            child: SafeArea(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                    boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 24, spreadRadius: 2)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12)),
                        child: Icon(icon, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      overlay.insert(entry);

      // auto remove after a short time
      Future.delayed(const Duration(milliseconds: 1600), () {
        try {
          entry.remove();
        } catch (_) {}
      });

      return;
    }

    // Animated path — reuse animated card widget
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 84,
          left: 18,
          right: 18,
          child: SafeArea(
            child: _AnimatedMessageCard(
              message: message,
              color: color,
              bg: bg,
              border: border,
              icon: icon,
              onFinish: () => entry.remove(),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
  }

  static void showPositive(BuildContext context, String message, {bool animated = true}) =>
      _show(context, message, positive: true, animated: animated);

  static void showNegative(BuildContext context, String message, {bool animated = true}) =>
      _show(context, message, positive: false, animated: animated);
}

class _AnimatedMessageCard extends StatefulWidget {
  final String message;
  final Color color;
  final Color bg;
  final Color border;
  final IconData icon;
  final VoidCallback onFinish;

  const _AnimatedMessageCard({
    required this.message,
    required this.color,
    required this.bg,
    required this.border,
    required this.icon,
    required this.onFinish,
  });

  @override
  State<_AnimatedMessageCard> createState() => _AnimatedMessageCardState();
}

class _AnimatedMessageCardState extends State<_AnimatedMessageCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2200), () async {
      await _ctrl.reverse();
      widget.onFinish();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: widget.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.border),
                boxShadow: [BoxShadow(color: widget.color.withOpacity(0.12), blurRadius: 24, spreadRadius: 2)],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withOpacity(0.12)),
                    child: Icon(widget.icon, color: widget.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.message, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
