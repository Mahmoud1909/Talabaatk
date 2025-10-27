// lib/screens/orders_screen.dart
// Orders screen — shows active (non-delivered) orders for the current customer.
// Dark/Light friendly, polished animations, and realtime subscription.

import 'dart:async';
import 'dart:math' show min;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:talabak_users/screens/main_screen.dart';
import 'package:talabak_users/services/order_service.dart';
import 'package:talabak_users/utils/order.dart';
import 'package:talabak_users/services/supabase_service.dart' as userService;
import 'package:talabak_users/services/supabase_client.dart' as client;
import 'package:talabak_users/services/cart_api.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with TickerProviderStateMixin {
  final OrderService _orderService = OrderService();
  bool _loading = true;
  String? _error;
  List<Order> _orders = [];
  Map<String, String> _restaurantNames = {};

  supa.RealtimeChannel? _ordersChannel;
  String? _currentCustomerId;

  // for subtle "pressed" animation on cards:
  final Set<String> _pressedCardIds = {};

  @override
  void initState() {
    super.initState();
    _fetchMyOrders();
  }

  @override
  void dispose() {
    _unsubscribeRealtime();
    super.dispose();
  }

  void _showBottomError({
    required String userMessage,
    String? technicalDetails,
    bool allowRetry = false,
    VoidCallback? onRetry,
  }) {
    if (!mounted) return;
    final loc = AppLocalizations.of(context);

    final snack = SnackBar(
      content: Text(userMessage),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 5),
      action: allowRetry && onRetry != null
          ? SnackBarAction(
        label: loc?.retry ?? 'Retry',
        onPressed: onRetry,
        textColor: Theme.of(context).colorScheme.onError,
      )
          : (kDebugMode && technicalDetails != null
          ? SnackBarAction(
        label: 'Details',
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(loc?.errorMessage('Details') ?? 'Details'),
              content: SingleChildScrollView(child: Text(technicalDetails)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(loc?.close ?? 'Close'),
                ),
              ],
            ),
          );
        },
      )
          : null),
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(snack);
  }

  Future<void> _fetchMyOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? customerId = await CartApi.currentCustomerId();
      debugPrint('OrdersScreen: cached customerId=$customerId');

      if (customerId == null || customerId.isEmpty) {
        final supUser = client.supabase.auth.currentUser ?? client.supabase.auth.currentSession?.user;
        if (supUser != null) {
          var customerRow = await userService.fetchCustomerByUid(supUser.id);
          if (customerRow == null) {
            final upserted = await userService.insertOrUpdateUser(
              uid: supUser.id,
              firstName: supUser.userMetadata?['first_name'] ?? (supUser.email ?? 'User'),
              email: supUser.email,
            );
            if (upserted) customerRow = await userService.fetchCustomerByUid(supUser.id);
          }
          if (customerRow != null && customerRow['id'] != null) {
            customerId = customerRow['id'] as String;
          }
        }
      }

      if (customerId == null || customerId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _orders = [];
          _restaurantNames = {};
          _loading = false;
        });
        return;
      }

      final prevCustomer = _currentCustomerId;
      _currentCustomerId = customerId;
      if (prevCustomer != _currentCustomerId) {
        _subscribeRealtimeOrders(_currentCustomerId!);
      }

      final orders = await _orderService.fetchOrdersByCustomer(customerId);

      final filteredOrders = orders.where((o) => o.status.toLowerCase() != 'delivered').toList();

      final Map<String, Order> dedup = {};
      for (final o in filteredOrders) {
        dedup[o.id] = o;
      }
      final uniqueOrders = dedup.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final restIds = uniqueOrders.map((o) => o.restaurantId).whereType<String>().toSet().toList();
      final Map<String, String> restMap = {};
      if (restIds.isNotEmpty) {
        try {
          final resp = await client.supabase.from('restaurants').select('id, name').inFilter('id', restIds);
          if (resp is List) {
            for (final r in resp) {
              final m = Map<String, dynamic>.from(r as Map);
              final id = (m['id'] as String?) ?? '';
              final name = (m['name'] as String?) ?? id;
              if (id.isNotEmpty) restMap[id] = name;
            }
          }
        } catch (e, st) {
          debugPrint('Failed to load restaurant names: $e\n$st');
        }
      }

      if (!mounted) return;
      setState(() {
        _orders = uniqueOrders;
        _restaurantNames = restMap;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('OrdersScreen._fetchMyOrders error: $e\n$st');
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      setState(() {
        _error = loc?.failedToLoadOrders ?? 'Failed to load orders. Please try again.';
        _loading = false;
      });

      _showBottomError(
        userMessage: _error ?? 'Failed to load orders.',
        technicalDetails: kDebugMode ? '$e\n\n$st' : null,
        allowRetry: true,
        onRetry: _fetchMyOrders,
      );
    }
  }

  void _subscribeRealtimeOrders(String customerId) {
    _unsubscribeRealtime();

    try {
      final channelName = 'public:orders:customer=$customerId';
      _ordersChannel = client.supabase.channel(channelName);

      _ordersChannel!
          .onPostgresChanges(
        event: supa.PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: supa.PostgresChangeFilter(
          type: supa.PostgresChangeFilterType.eq,
          column: 'customer_id',
          value: customerId,
        ),
        callback: (payload) {
          try {
            final p = payload as supa.PostgresChangePayload;
            final newRec = p.newRecord;
            final oldRec = p.oldRecord;

            void removeById(String id) {
              if (!mounted) return;
              final idx = _orders.indexWhere((o) => o.id == id);
              if (idx >= 0) {
                setState(() {
                  _orders.removeAt(idx);
                });
              }
            }

            if (newRec != null && oldRec == null) {
              final status = (newRec['status'] ?? '').toString().toLowerCase();
              if (status.contains('delivered')) {
                final id = (newRec['id'] ?? '').toString();
                if (id.isNotEmpty) removeById(id);
              } else {
                _fetchMyOrders();
              }
            } else if (newRec != null && oldRec != null) {
              final status = (newRec['status'] ?? '').toString().toLowerCase();
              final id = (newRec['id'] ?? '').toString();
              if (status.contains('delivered')) {
                if (id.isNotEmpty) removeById(id);
              } else {
                _fetchMyOrders();
              }
            } else if (newRec == null && oldRec != null) {
              final id = (oldRec['id'] ?? '').toString();
              if (id.isNotEmpty) removeById(id);
            }
          } catch (e, st) {
            debugPrint('Realtime payload handling error (orders screen): $e\n$st');
          }
        },
      )
          .subscribe();

      debugPrint('OrdersScreen: subscribed to realtime orders channel for customer $customerId');
    } catch (e) {
      debugPrint('OrdersScreen: failed to subscribe to realtime channel: $e');
    }
  }

  void _unsubscribeRealtime() {
    try {
      if (_ordersChannel != null) {
        try {
          client.supabase.removeChannel(_ordersChannel!);
        } catch (_) {}
        _ordersChannel = null;
      }
    } catch (e) {
      debugPrint('OrdersScreen: error unsubscribing realtime channel: $e');
    }
  }

  String _statusLabel(String status) {
    final s = status.trim().toLowerCase();
    final code = Localizations.localeOf(context).languageCode;
    if (s.contains('delivering') || s.contains('in transit') || s.contains('on the way')) {
      return code == 'ar' ? 'في الطريق' : 'Delivering';
    }
    if (s.contains('placed') || s.contains('pending')) return code == 'ar' ? 'قيد الانتظار' : 'Placed';
    if (s.contains('accepted') || s.contains('preparing')) return code == 'ar' ? 'قيد التحضير' : 'Preparing';
    if (s.contains('delivered') || s.contains('completed')) return code == 'ar' ? 'تم التوصيل' : 'Delivered';
    if (s.contains('cancel')) return code == 'ar' ? 'ملغي' : 'Cancelled';
    return status.isNotEmpty ? (status[0].toUpperCase() + (status.length > 1 ? status.substring(1) : '')) : '';
  }

  Color _statusColor(String s) {
    final st = s.toLowerCase();
    if (st.contains('placed') || st.contains('pending')) return Colors.orange;
    if (st.contains('accepted') || st.contains('preparing')) return Colors.blue;
    if (st.contains('delivering') || st.contains('in transit') || st.contains('on the way')) return Colors.indigo;
    if (st.contains('delivered') || st.contains('completed')) return Colors.green;
    if (st.contains('cancel')) return Colors.red;
    return Colors.grey;
  }

  Widget _animatedOrderItem(Order order, int index) {
    // subtle staggered entrance animation
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 12.0, end: 0.0),
      duration: Duration(milliseconds: 360 + (index * 30).clamp(0, 240)),
      curve: Curves.easeOut,
      builder: (context, val, child) {
        return Opacity(
          opacity: (20 - val) / 20.0,
          child: Transform.translate(
            offset: Offset(0, val),
            child: child,
          ),
        );
      },
      child: _orderCard(order),
    );
  }

  Widget _orderCard(Order order) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt.toLocal());
    final restName = _restaurantNames[order.restaurantId] ??
        (order.restaurantId.isNotEmpty ? order.restaurantId.substring(0, min(8, order.restaurantId.length)) : 'Restaurant');

    final firstImg = (order.items.isNotEmpty && order.items.first.imageUrl != null && order.items.first.imageUrl!.isNotEmpty)
        ? order.items.first.imageUrl
        : null;

    final itemCount = order.items.fold<int>(0, (s, it) => s + it.qty);
    final label = _statusLabel(order.status);
    final chipColor = _statusColor(order.status);

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressedCardIds.add(order.id));
      },
      onTapCancel: () {
        setState(() => _pressedCardIds.remove(order.id));
      },
      onTapUp: (_) {
        setState(() => _pressedCardIds.remove(order.id));
        // open detail modal with smooth animation
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: theme.scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          builder: (_) => _orderDetailSheet(order, restName),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        transform: _pressedCardIds.contains(order.id) ? (Matrix4.identity()..scale(0.995)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {}, // handled in gesture above
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                if (firstImg != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      firstImg,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: Colors.grey[200], child: const Icon(Icons.fastfood)),
                    ),
                  )
                else
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.fastfood, color: theme.iconTheme.color),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(restName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: chipColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                          )
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('$itemCount items • $dateStr', style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8))),
                      if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(order.deliveryAddress!, style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${order.total.toStringAsFixed(2)} EGP', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(dateStr, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.6))),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _orderDetailSheet(Order order, String restName) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final statusLabel = _statusLabel(order.status);
    final chipColor = _statusColor(order.status);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // header
            Row(
              children: [
                Expanded(child: Text('${loc?.orders ?? 'Order'} • $restName', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${order.total.toStringAsFixed(2)} EGP', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(6)),
                      child: Text(statusLabel, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                    )
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: order.items.length,
                separatorBuilder: (_, __) => Divider(height: 14, color: theme.dividerColor),
                itemBuilder: (context, i) {
                  final it = order.items[i];
                  return Row(
                    children: [
                      if (it.imageUrl != null && it.imageUrl!.isNotEmpty)
                        ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(it.imageUrl!, width: 48, height: 48, fit: BoxFit.cover))
                      else
                        Container(width: 48, height: 48, decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(6)), child: Icon(Icons.fastfood, color: theme.iconTheme.color)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('${it.qty} × ${it.unitPrice.toStringAsFixed(2)} EGP', style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8))),
                        ]),
                      ),
                      Text((it.qty * it.unitPrice).toStringAsFixed(2), style: theme.textTheme.bodyMedium),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.phone, size: 18, color: theme.iconTheme.color),
                  const SizedBox(width: 8),
                  Text(order.customerPhone!, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (order.comment != null && order.comment!.isNotEmpty) ...[
              Align(alignment: Alignment.centerLeft, child: Text(loc?.comment ?? 'Comment', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold))),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                child: Text(order.comment!, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(loc?.close ?? 'Close'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.08)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // placeholder: could open contact or reorder flow
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
                    child: Text(loc?.contact ?? 'Contact', style: const TextStyle(color: Colors.white)),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _changeStatus({
    required String orderId,
    String? status,
    String? customerPhone,
    String? comment,
  }) async {
    try {
      await _orderService.updateOrderStatus(
        orderId: orderId,
        status: status,
        customerPhone: customerPhone,
        comment: comment,
      );
      await _fetchMyOrders();
    } catch (e, st) {
      debugPrint('Failed to update status: $e\n$st');
      final loc = AppLocalizations.of(context);
      _showBottomError(
        userMessage: loc?.failedToUpdateStatus ?? 'Failed to update status.',
        technicalDetails: kDebugMode ? '$e\n\n$st' : null,
        allowRetry: true,
        onRetry: () => _changeStatus(orderId: orderId, status: status, customerPhone: customerPhone, comment: comment),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Builder(builder: (context) {
        if (_loading) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(strokeWidth: 3, color: colorScheme.primary),
                ),
                const SizedBox(height: 12),
                Text(loc?.loading ?? 'Loading...', style: theme.textTheme.bodyLarge),
              ],
            ),
          );
        }

        if (_error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _fetchMyOrders, child: Text(loc?.retry ?? 'Retry')),
              ],
            ),
          );
        }

        if (_orders.isEmpty) {
          return RefreshIndicator(
            onRefresh: _fetchMyOrders,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_bag_outlined, size: 92, color: theme.disabledColor),
                    const SizedBox(height: 18),
                    Text(
                      loc?.noOrdersYet ?? 'No orders yet',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36.0),
                      child: Text(
                        loc?.noOrdersDescription ??
                            "Looks like you haven't placed any orders yet. Start exploring restaurants and order your favorite meal!",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const MainScreen()),
                              (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 6,
                      ),
                      child: Text(
                        loc?.go ?? 'Go',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _fetchMyOrders,
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            itemCount: _orders.length,
            itemBuilder: (context, i) {
              final order = _orders[i];
              return _animatedOrderItem(order, i);
            },
          ),
        );
      }),
    );
  }
}

// Primary app color (kept as constant in this file)
const Color kPrimaryColor = Color(0xFFFF5C01);
