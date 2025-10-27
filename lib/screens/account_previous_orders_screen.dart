// lib/screens/account_previous_orders_screen.dart
import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:talabak_users/services/order_service.dart';
import 'package:talabak_users/services/cart_api.dart';
import 'package:talabak_users/services/supabase_client.dart' as client;
import 'package:talabak_users/services/supabase_service.dart' as userService;
import 'package:talabak_users/utils/order.dart';
import 'package:talabak_users/utils/order_item.dart';
import 'package:talabak_users/screens/main_screen.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

/// Keep global subscription slot for compatibility (no prints)
StreamSubscription<List<Map<String, dynamic>>>? _ordersSub;

const Color kPrimaryColor = Color(0xFFFF5C01);

class AccountPreviousOrdersScreen extends StatefulWidget {
  const AccountPreviousOrdersScreen({Key? key}) : super(key: key);

  @override
  State<AccountPreviousOrdersScreen> createState() => _AccountPreviousOrdersScreenState();
}

class _AccountPreviousOrdersScreenState extends State<AccountPreviousOrdersScreen> with SingleTickerProviderStateMixin {
  final OrderService _orderService = OrderService();

  bool _loading = true;
  String? _error;
  final List<Order> _orders = [];
  final Map<String, String> _restaurantNames = {};
  final Map<String, String?> _restaurantLogos = {};
  final Map<String, String> _driverNames = {};

  supa.RealtimeChannel? _ordersChannel;
  String? _currentCustomerId;

  // AnimatedList key
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  // entrance animation controller for subtle global motion
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    // play a soft entrance
    _entranceController.forward();
    _initAndSubscribe();
  }

  @override
  void dispose() {
    _unsubscribeRealtime();
    _entranceController.dispose();
    super.dispose();
  }

  bool _isDeliveredStatus(String? status) {
    if (status == null) return false;
    return status.toLowerCase().trim() == 'delivered';
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final al = a.toLocal();
    final bl = b.toLocal();
    return al.year == bl.year && al.month == bl.month && al.day == bl.day;
  }

  bool _isOrderFromToday(Order o) => _isSameLocalDay(o.createdAt, DateTime.now());

  Future<void> _initAndSubscribe() async {
    String? customerId = await CartApi.currentCustomerId();

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
          if (upserted) {
            customerRow = await userService.fetchCustomerByUid(supUser.id);
          }
        }
        if (customerRow != null && customerRow['id'] != null) {
          customerId = customerRow['id'] as String;
        }
      }
    }

    if (customerId == null || customerId.isEmpty) {
      if (mounted) {
        setState(() {
          _orders.clear();
          _loading = false;
        });
      }
      return;
    }

    _currentCustomerId = customerId;
    await _loadAndShowDeliveredOrders();
    _subscribeToRealtimeOrders(customerId);
  }

  Future<void> _loadAndShowDeliveredOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? customerId = await CartApi.currentCustomerId();
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
        if (mounted) setState(() {
          _orders.clear();
          _loading = false;
        });
        return;
      }

      _currentCustomerId = customerId;

      final allOrders = await _orderService.fetchOrdersByCustomer(customerId);

      // keep only delivered + created today
      final deliveredToday = allOrders.where((o) => _isDeliveredStatus(o.status) && _isOrderFromToday(o)).toList();

      // dedupe & sort newest first
      final Map<String, Order> dedup = {};
      for (final o in deliveredToday) dedup[o.id] = o;
      final unique = dedup.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final restIds = unique.map((o) => o.restaurantId).whereType<String>().toSet().toList();
      final driverIds = unique.map((o) => o.driverId).whereType<String>().toSet().toList();

      await _fetchRestaurantsMeta(restIds);
      await _fetchDriversMeta(driverIds);

      if (!mounted) return;

      // populate AnimatedList with staggered insert
      _populateAnimatedList(unique);
      setState(() {
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      setState(() {
        _error = t?.failedToLoadOrders ?? 'Failed to load orders';
        _loading = false;
      });
    }
  }

  Future<void> _fetchRestaurantsMeta(List<String> restIds) async {
    if (restIds.isEmpty) return;
    try {
      final resp = await client.supabase.from('restaurants').select('id, name, logo_url').inFilter('id', restIds);
      if (resp is List) {
        for (final r in resp) {
          final m = Map<String, dynamic>.from(r as Map);
          final id = (m['id'] as String?) ?? '';
          final name = (m['name'] as String?) ?? id;
          final logo = (m['logo_url'] as String?)?.toString();
          if (id.isNotEmpty) {
            _restaurantNames[id] = name;
            _restaurantLogos[id] = logo;
          }
        }
      }
    } catch (_) {
      // silent on purpose
    }
  }

  Future<void> _fetchDriversMeta(List<String> driverIds) async {
    if (driverIds.isEmpty) return;
    try {
      final resp = await client.supabase.from('drivers').select('id, first_name, last_name').inFilter('id', driverIds);
      if (resp is List) {
        for (final d in resp) {
          final m = Map<String, dynamic>.from(d as Map);
          final id = (m['id'] as String?) ?? '';
          final first = (m['first_name'] as String?) ?? '';
          final last = (m['last_name'] as String?) ?? '';
          if (id.isNotEmpty) {
            _driverNames[id] = ('$first ${last.isNotEmpty ? last : ''}').trim();
          }
        }
      }
    } catch (_) {
      // silent on purpose
    }
  }

  void _subscribeToRealtimeOrders(String customerId) {
    _unsubscribeRealtime();
    try {
      final channelName = 'public:orders:customer=$customerId';
      _ordersChannel = client.supabase.channel(channelName);

      _ordersChannel!
          .onPostgresChanges(
        event: supa.PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: supa.PostgresChangeFilter(type: supa.PostgresChangeFilterType.eq, column: 'customer_id', value: customerId),
        callback: (payload) {
          try {
            final newRec = (payload as supa.PostgresChangePayload).newRecord;
            final oldRec = (payload as supa.PostgresChangePayload).oldRecord;

            if (newRec != null && oldRec == null) {
              final order = _orderFromMap(Map<String, dynamic>.from(newRec as Map));
              if (_isDeliveredStatus(order.status) && _isOrderFromToday(order)) {
                _handleAddedOrder(order);
              }
            } else if (newRec != null && oldRec != null) {
              final order = _orderFromMap(Map<String, dynamic>.from(newRec as Map));
              if (_isDeliveredStatus(order.status) && _isOrderFromToday(order)) {
                _handleUpsertOrder(order);
              } else {
                _handleRemoveOrderById(order.id);
              }
            } else if (newRec == null && oldRec != null) {
              final id = (oldRec as Map)['id']?.toString() ?? '';
              if (id.isNotEmpty) _handleRemoveOrderById(id);
            }
          } catch (_) {
            // silent
          }
        },
      ).subscribe();
    } catch (_) {
      // silent
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
      _ordersSub?.cancel();
      _ordersSub = null;
    } catch (_) {}
  }

  void _handleAddedOrder(Order order) {
    if (!mounted) return;
    final exists = _orders.any((o) => o.id == order.id);
    if (!exists) {
      _maybeFetchMetaFor(order);
      _orders.insert(0, order);
      _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 420));
    }
  }

  void _handleUpsertOrder(Order order) {
    if (!mounted) return;
    final idx = _orders.indexWhere((o) => o.id == order.id);
    if (idx >= 0) {
      _maybeFetchMetaFor(order);
      setState(() {
        _orders[idx] = order;
      });
    } else {
      _handleAddedOrder(order);
    }
  }

  void _handleRemoveOrderById(String id) {
    if (!mounted) return;
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx >= 0) {
      final removed = _orders.removeAt(idx);
      _listKey.currentState?.removeItem(
        idx,
            (context, animation) => SizeTransition(
          sizeFactor: animation,
          axisAlignment: 0.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: _orderCard(removed, animateBadge: false),
          ),
        ),
        duration: const Duration(milliseconds: 420),
      );
    }
  }

  Future<void> _maybeFetchMetaFor(Order order) async {
    final restIds = <String>[];
    final driverIds = <String>[];
    if (!_restaurantNames.containsKey(order.restaurantId) && order.restaurantId.isNotEmpty) restIds.add(order.restaurantId);
    if (order.driverId != null && !_driverNames.containsKey(order.driverId!) && order.driverId!.isNotEmpty) driverIds.add(order.driverId!);

    if (restIds.isNotEmpty) await _fetchRestaurantsMeta(restIds);
    if (driverIds.isNotEmpty) await _fetchDriversMeta(driverIds);

    if (mounted) setState(() {});
  }

  // populate AnimatedList with staggered animation
  void _populateAnimatedList(List<Order> items) async {
    // clear current list without animations
    for (int i = _orders.length - 1; i >= 0; i--) {
      _orders.removeAt(i);
    }
    // insert new items with small stagger
    for (int i = 0; i < items.length; i++) {
      _orders.insert(i, items[i]);
      _listKey.currentState?.insertItem(i, duration: Duration(milliseconds: 350 + (i * 30)));
      await Future.delayed(const Duration(milliseconds: 35));
    }
  }

  Order _orderFromMap(Map<String, dynamic> m) {
    DateTime created = DateTime.now();
    try {
      if (m['created_at'] != null) created = DateTime.tryParse(m['created_at'].toString())?.toLocal() ?? DateTime.now();
    } catch (_) {}
    double total = 0.0;
    try {
      final t = m['total'];
      if (t != null) total = double.tryParse(t.toString()) ?? 0.0;
    } catch (_) {}
    List<OrderItem> items = [];
    try {
      if (m.containsKey('items') && m['items'] is List) {
        items = (m['items'] as List).map((it) {
          if (it is Map) {
            return OrderItem(
              id: (it['id'] ?? '').toString(),
              orderId: (it['order_id'] ?? '').toString(),
              menuItemId: (it['menu_item_id'] ?? '').toString(),
              variantId: (it['variant_id'] ?? '').toString(),
              name: (it['name'] ?? '').toString(),
              unitPrice: double.tryParse((it['unit_price'] ?? '0').toString()) ?? 0.0,
              qty: int.tryParse((it['qty'] ?? '1').toString()) ?? 1,
              imageUrl: (it['image_url'] ?? '')?.toString(),
            );
          }
          return null;
        }).whereType<OrderItem>().toList();
      }
    } catch (_) {}

    return Order(
      id: (m['id'] ?? '').toString(),
      customerId: (m['customer_id'] ?? '').toString(),
      restaurantId: (m['restaurant_id'] ?? '').toString(),
      total: total,
      status: (m['status'] ?? '').toString(),
      createdAt: created,
      driverId: (m['driver_id'] ?? '')?.toString(),
      branchId: (m['branch_id'] ?? '')?.toString(),
      deliveryLatitude: m['delivery_latitude'] is num ? (m['delivery_latitude'] as num).toDouble() : null,
      deliveryLongitude: m['delivery_longitude'] is num ? (m['delivery_longitude'] as num).toDouble() : null,
      deliveryAddress: (m['delivery_address'] ?? '')?.toString(),
      comment: (m['comment'] ?? '')?.toString(),
      customerPhone: (m['customer_phone'] ?? '')?.toString(),
      items: items,
    );
  }

  String _formatDateTime(DateTime dt) => DateFormat('yyyy-MM-dd • HH:mm').format(dt.toLocal());

  Color _statusColor(String s) {
    final st = s.toLowerCase();
    if (st.contains('delivered') || st.contains('completed')) return Colors.green.shade600;
    if (st.contains('accepted') || st.contains('preparing')) return Colors.blue.shade600;
    if (st.contains('placed') || st.contains('pending')) return Colors.orange.shade700;
    if (st.contains('cancel')) return Colors.red.shade600;
    return Colors.grey.shade600;
  }

  Widget _orderCard(Order o, {bool animateBadge = true}) {
    final t = AppLocalizations.of(context)!;
    final restName = _restaurantNames[o.restaurantId] ?? (o.restaurantId.isNotEmpty ? o.restaurantId.substring(0, min(8, o.restaurantId.length)) : t.restaurant);
    final logo = _restaurantLogos[o.restaurantId];
    final dateStr = _formatDateTime(o.createdAt);
    final amountStr = t.currency(o.total.toStringAsFixed(2));
    final status = o.status;

    // Use Material with elevation and shadow so cards are visible on light backgrounds
    return Material(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).cardColor,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          leading: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.grey.shade100,
              image: (logo != null && logo.isNotEmpty) ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover) : null,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: (logo == null || logo.isEmpty) ? Icon(Icons.restaurant_menu, color: Colors.grey.shade600) : null,
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(restName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(dateStr, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(amountStr, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 360),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor(status).withOpacity(0.18)),
                  ),
                  child: Text(status.toUpperCase(), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ])
            ],
          ),
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 6),
              if (o.items.isNotEmpty) ...[
                Text(t.items, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...o.items.map((it) => _buildItemRow(it)).toList(),
                const Divider(height: 18),
              ],
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(o.deliveryAddress != null && o.deliveryAddress!.isNotEmpty ? o.deliveryAddress! : t.noAddress)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.person_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(t.deliveryWithDriver(o.driverId != null ? (_driverNames[o.driverId] ?? '') : '') ?? (o.driverId != null ? (_driverNames[o.driverId] ?? t.assignedDriver) : t.notAssigned))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.phone_outlined, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(t.phone(o.customerPhone ?? '—'))),
              ]),
              const SizedBox(height: 8),
              if (o.comment != null && o.comment!.isNotEmpty) ...[
                Text(t.comment, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(o.comment!),
                const SizedBox(height: 8),
              ],
              if (_isDeliveredStatus(o.status)) ...[
                const SizedBox(height: 8),
                // distinctive boxed message (sweet)
                DistinctiveMessageBox(isPositive: true),
              ],
            ])
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(OrderItem it) {
    final subtotal = (it.qty * it.unitPrice).toStringAsFixed(2);
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        if (it.imageUrl != null && it.imageUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(it.imageUrl!, width: 56, height: 46, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
              return Container(width: 56, height: 46, color: Colors.grey.shade200, child: const Icon(Icons.fastfood));
            }),
          )
        else
          Container(width: 56, height: 46, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.fastfood)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${it.qty} × ${it.unitPrice.toStringAsFixed(2)} ${AppLocalizations.of(context)!.currencySymbol}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ]),
        ),
        Text('$subtotal ${AppLocalizations.of(context)!.currencySymbol}'),
      ]),
    );
  }

  // small wrapper used for removal animation builder
  Widget _orderListItemBuilder(BuildContext context, int index, Animation<double> animation) {
    final order = _orders[index];

    // curved animations for nicer feel
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved);

    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      axisAlignment: 0.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: SlideTransition(
          position: slide,
          child: FadeTransition(
            opacity: curved,
            child: _orderCard(order),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // keep status bar same color as app bar
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: kPrimaryColor, statusBarIconBrightness: Brightness.light));

    final t = AppLocalizations.of(context)!;

    // Choose a non-pure-white background in light mode so cards stand out
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final Color scaffoldBg = isLight ? const Color(0xFFF7F8FA) : Theme.of(context).scaffoldBackgroundColor;

    if (_loading) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor), strokeWidth: 4),
              ),
              const SizedBox(height: 12),
              Text(t.loadingOrders),
            ]),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(child: Text(_error!, style: Theme.of(context).textTheme.bodyLarge)),
      );
    }

    if (_orders.isEmpty) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: RefreshIndicator(
          onRefresh: _loadAndShowDeliveredOrders,
          color: kPrimaryColor,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 80),
              FadeTransition(
                opacity: CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.history_outlined, size: 96, color: Colors.grey.shade400),
                  const SizedBox(height: 18),
                  Text(t.noOrdersTitle, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36.0),
                    child: Text(t.noOrdersSubtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainScreen()), (route) => false);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text(t.go, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 40),
                ]),
              ),
            ],
          ),
        ),
      );
    }

    // main animated list
    return Scaffold(
      backgroundColor: scaffoldBg,
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
        child: RefreshIndicator(
          onRefresh: _loadAndShowDeliveredOrders,
          color: kPrimaryColor,
          child: AnimatedList(
            key: _listKey,
            padding: const EdgeInsets.only(top: 12, bottom: 20),
            initialItemCount: _orders.length,
            itemBuilder: (context, index, animation) => _orderListItemBuilder(context, index, animation),
          ),
        ),
      ),
    );
  }
}

/// Distinctive message box: positive (sweet) / negative (bitter)
class DistinctiveMessageBox extends StatelessWidget {
  final bool isPositive;
  const DistinctiveMessageBox({super.key, this.isPositive = true});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final Color goodColor = Colors.green.shade600;
    final Color badColor = Colors.red.shade600;

    final bg = isPositive ? goodColor.withOpacity(0.08) : badColor.withOpacity(0.08);
    final border = isPositive ? goodColor.withOpacity(0.12) : badColor.withOpacity(0.12);
    final icon = isPositive ? Icons.emoji_events : Icons.sentiment_dissatisfied;
    final title = isPositive ? (t.sweetBoxTitle) : (t.bitterBoxTitle);
    final body = isPositive ? (t.sweetBoxBody) : (t.bitterBoxBody);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(shape: BoxShape.circle, color: (isPositive ? goodColor : badColor).withOpacity(0.12)),
          child: Icon(icon, color: (isPositive ? goodColor : badColor)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body, style: theme.textTheme.bodyMedium),
          ]),
        ),
      ]),
    );
  }
}
