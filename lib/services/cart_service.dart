// lib/services/cart_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local model representing a cart item (server id or provisional local id).
class CartItem {
  final String id;
  final String menuItemId;
  final String? restaurantId;
  final String name;
  final double unitPrice;
  final String? variantId;
  final String? variantName;
  int qty;
  final String? imageUrl;
  final DateTime addedAt;

  CartItem({
    required this.id,
    required this.menuItemId,
    required this.name,
    required this.unitPrice,
    this.variantId,
    this.variantName,
    this.qty = 1,
    this.imageUrl,
    this.restaurantId,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  CartItem copyWith({
    String? id,
    String? menuItemId,
    String? restaurantId,
    String? name,
    double? unitPrice,
    String? variantId,
    String? variantName,
    int? qty,
    String? imageUrl,
    DateTime? addedAt,
  }) {
    return CartItem(
      id: id ?? this.id,
      menuItemId: menuItemId ?? this.menuItemId,
      name: name ?? this.name,
      unitPrice: unitPrice ?? this.unitPrice,
      variantId: variantId ?? this.variantId,
      variantName: variantName ?? this.variantName,
      qty: qty ?? this.qty,
      imageUrl: imageUrl ?? this.imageUrl,
      restaurantId: restaurantId ?? this.restaurantId,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  double get total => unitPrice * qty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'menuItemId': menuItemId,
      'restaurantId': restaurantId,
      'name': name,
      'unitPrice': unitPrice,
      'variantId': variantId,
      'variantName': variantName,
      'qty': qty,
      'imageUrl': imageUrl,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory CartItem.fromMap(Map<String, dynamic> m) {
    DateTime parseAddedAt(dynamic v) {
      if (v == null) return DateTime.now();
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    DateTime added;
    if (m.containsKey('addedAt')) {
      added = parseAddedAt(m['addedAt']);
    } else if (m.containsKey('created_at')) {
      added = parseAddedAt(m['created_at']);
    } else if (m.containsKey('createdAt')) {
      added = parseAddedAt(m['createdAt']);
    } else {
      added = DateTime.now();
    }

    return CartItem(
      id: (m['id'] ?? '').toString(),
      menuItemId: (m['menuItemId'] ?? m['menu_item_id'] ?? '').toString(),
      restaurantId: (m['restaurantId'] ?? m['restaurant_id'])?.toString(),
      name: (m['name'] ?? '').toString(),
      unitPrice: (m['unitPrice'] is num)
          ? (m['unitPrice'] as num).toDouble()
          : double.tryParse(m['unitPrice']?.toString() ?? '0') ?? 0.0,
      variantId: (m['variantId'] ?? m['variant_id'])?.toString(),
      variantName: (m['variantName'] ?? m['variant_name'])?.toString(),
      qty: (m['qty'] is int)
          ? (m['qty'] as int)
          : int.tryParse(m['qty']?.toString() ?? '0') ?? 0,
      imageUrl: (m['imageUrl'] ?? m['image_url'])?.toString(),
      addedAt: added,
    );
  }
}

class CartService extends ChangeNotifier {
  CartService._private();
  static final CartService instance = CartService._private();

  final Map<String, CartItem> _items = {};

  // notify which restaurants are being cleared (so UI can show spinner)
  final ValueNotifier<Set<String>> clearingRestaurants = ValueNotifier<Set<String>>({});

  void startClearingRestaurant(String restaurantId) {
    final s = Set<String>.from(clearingRestaurants.value);
    s.add(restaurantId);
    clearingRestaurants.value = s;
    notifyListeners();
  }

  void stopClearingRestaurant(String restaurantId) {
    final s = Set<String>.from(clearingRestaurants.value);
    s.remove(restaurantId);
    clearingRestaurants.value = s;
    notifyListeners();
  }

  bool isClearingRestaurant(String restaurantId) => clearingRestaurants.value.contains(restaurantId);

  // persistence
  static const String _prefsKey = 'local_cart_v1';
  Timer? _saveTimer;
  static const Duration _saveDebounce = Duration(milliseconds: 400);

  List<CartItem> get items {
    final list = _items.values.toList(growable: false);
    list.sort((a, b) {
      final cmp = a.addedAt.compareTo(b.addedAt);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  Map<String, CartItem> toMap() => Map<String, CartItem>.from(_items);
  CartItem? findById(String id) => _items[id];

  CartItem? findByKeys({
    required String menuItemId,
    String? variantId,
    String? restaurantId,
  }) {
    try {
      return _items.values.firstWhere((it) =>
      it.menuItemId == menuItemId &&
          it.variantId == variantId &&
          (restaurantId == null || it.restaurantId == restaurantId));
    } catch (_) {
      return null;
    }
  }

  void addItem(CartItem item) {
    if (_items.containsKey(item.id)) {
      _items[item.id]!.qty += item.qty;
      debugPrint('CartService: increased qty for ${item.id} -> ${_items[item.id]!.qty}');
    } else {
      _items[item.id] = item;
      debugPrint('CartService: added item ${item.id} (${item.name}) x${item.qty}');
    }
    _scheduleSave();
    notifyListeners();
  }

  String addOrIncrement({
    required String provisionalId,
    required String menuItemId,
    required String name,
    required double unitPrice,
    required int qty,
    String? variantId,
    String? variantName,
    String? imageUrl,
    String? restaurantId,
  }) {
    final existing = findByKeys(menuItemId: menuItemId, variantId: variantId, restaurantId: restaurantId);
    if (existing != null) {
      existing.qty += qty;
      debugPrint('CartService: addOrIncrement merged into existing ${existing.id} -> qty=${existing.qty}');
      _scheduleSave();
      notifyListeners();
      return existing.id;
    }

    final item = CartItem(
      id: provisionalId,
      menuItemId: menuItemId,
      name: name,
      unitPrice: unitPrice,
      variantId: variantId,
      variantName: variantName,
      qty: qty,
      imageUrl: imageUrl,
      restaurantId: restaurantId,
    );

    _items[item.id] = item;
    debugPrint('CartService: addOrIncrement created provisional ${item.id} x${item.qty}');
    _scheduleSave();
    notifyListeners();
    return item.id;
  }

  void removeItem(String id) {
    if (_items.containsKey(id)) {
      _items.remove(id);
      debugPrint('CartService: removed item $id');
      _scheduleSave();
      notifyListeners();
    } else {
      debugPrint('CartService: removeItem called but id not found: $id');
    }
  }

  void updateQty(String id, int qty) {
    if (!_items.containsKey(id)) {
      debugPrint('CartService: updateQty called for unknown id: $id');
      return;
    }
    if (qty <= 0) {
      _items.remove(id);
      debugPrint('CartService: updateQty removed item $id (qty <= 0)');
    } else {
      _items[id]!.qty = qty;
      debugPrint('CartService: updateQty set $id -> $qty');
    }
    _scheduleSave();
    notifyListeners();
  }

  double get totalPrice => _items.values.fold(0.0, (s, it) => s + it.total);

  void clear() {
    _items.clear();
    debugPrint('CartService: cleared local cart');
    _scheduleSave();
    notifyListeners();
  }

  void replaceAll(List<CartItem> items) {
    final Map<String, DateTime> existingAdded = {for (final e in _items.values) e.id: e.addedAt};

    _items.clear();
    for (final it in items) {
      final added = existingAdded[it.id] ?? it.addedAt;
      final withAdded = it.copyWith(addedAt: added);
      _items[withAdded.id] = withAdded;
    }
    debugPrint('CartService: replaced all items from server (${_items.length})');
    _scheduleSave();
    notifyListeners();
  }

  void setItems(List<CartItem> items) => replaceAll(items);

  void replaceLocalWithServerId(String localId, String serverId) {
    if (!_items.containsKey(localId)) {
      debugPrint('CartService: replaceLocalWithServerId - localId not found: $localId');
      return;
    }

    final old = _items.remove(localId)!;

    if (_items.containsKey(serverId)) {
      _items[serverId]!.qty += old.qty;
      debugPrint('CartService: merged local($localId) -> existing server($serverId). New qty=${_items[serverId]!.qty}');
    } else {
      final newItem = old.copyWith(id: serverId);
      _items[serverId] = newItem;
      debugPrint('CartService: replaced local id $localId with server id $serverId');
    }

    _scheduleSave();
    notifyListeners();
  }

  void replaceItemsForRestaurant(String? restaurantId, List<CartItem> items) {
    if (restaurantId == null) {
      debugPrint('CartService: replaceItemsForRestaurant called with null restaurantId');
      return;
    }

    final Map<String, DateTime> existingAdded = {for (final e in _items.values) e.id: e.addedAt};

    _items.removeWhere((_, v) => v.restaurantId == restaurantId);

    for (final it in items) {
      final added = existingAdded[it.id] ?? it.addedAt;
      final withAdded = it.copyWith(addedAt: added);
      _items[withAdded.id] = withAdded;
    }

    debugPrint('CartService: replaced items for restaurant $restaurantId -> ${items.length} items');
    _scheduleSave();
    notifyListeners();
  }

  /// احذف كل العناصر المحلية الخاصة بمطعم معيّن
  void removeItemsForRestaurant(String restaurantId) {
    _items.removeWhere((_, v) => v.restaurantId == restaurantId);
    debugPrint('CartService: removed local items for restaurant $restaurantId');
    _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => _saveToLocal());
  }

  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _items.values.map((i) => i.toMap()).toList();
      final jsonStr = jsonEncode(list);
      await prefs.setString(_prefsKey, jsonStr);
      debugPrint('CartService: saved ${_items.length} items locally');
    } catch (e, st) {
      debugPrint('CartService: saveToLocal error: $e\n$st');
    }
  }

  Future<void> persistNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToLocal();
  }

  Future<void> loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('CartService: no local cart found');
        return;
      }
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _items.clear();
      for (final m in list) {
        final map = Map<String, dynamic>.from(m as Map);
        final it = CartItem.fromMap(map);
        _items[it.id] = it;
      }
      debugPrint('CartService: loaded ${_items.length} items from local storage');
      notifyListeners();
    } catch (e, st) {
      debugPrint('CartService: loadFromLocal error: $e\n$st');
    }
  }
}
