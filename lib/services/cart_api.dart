// lib/services/cart_api.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talabak_users/services/cart_service.dart';

final SupabaseClient supabase = Supabase.instance.client;

class CartApi {
  /// Return cached customer_id or look it up from Supabase `customers` by auth_uid.
  static Future<String?> _currentCustomerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('customer_id');
      if (cached != null && cached.isNotEmpty) {
        debugPrint('CartApi: using cached customer_id=$cached');
        return cached;
      }
    } catch (e) {
      debugPrint('CartApi: prefs read error: $e');
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('CartApi: no supabase auth session found');
      return null;
    }

    try {
      final resp = await supabase.from('customers').select('id').eq('auth_uid', user.id).maybeSingle();
      if (resp == null) {
        debugPrint('CartApi: customers lookup returned null for auth_uid=${user.id}');
        return null;
      }
      final Map<String, dynamic> m = Map<String, dynamic>.from(resp as Map);
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('customer_id', id);
          debugPrint('CartApi: cached customer_id=$id');
        } catch (e) {
          debugPrint('CartApi: failed to cache customer_id: $e');
        }
        return id;
      }
    } catch (e, st) {
      debugPrint('CartApi._currentCustomerId error: $e\n$st');
    }
    return null;
  }

  /// Public wrapper to obtain current customer id.
  static Future<String?> currentCustomerId() async {
    return await _currentCustomerId();
  }

  /// Add item to cart using server RPC `cart_item_upsert`.
  static Future<Map<String, dynamic>?> addToCart({
    required String customerId,
    required String restaurantId,
    required String menuItemId,
    String? variantId,
    required String name,
    double? clientUnitPrice,
    int qty = 1,
    String? imageUrl,
    String? localCartItemId,
  }) async {
    debugPrint(
      'CartApi.addToCart start — customer=$customerId, restaurant=$restaurantId, menuItem=$menuItemId, variant=$variantId, qty=$qty, clientPrice=${clientUnitPrice ?? 'n/a'}',
    );

    final params = <String, dynamic>{
      'p_customer_uuid': customerId,
      'p_restaurant_uuid': restaurantId,
      'p_menu_item_uuid': menuItemId,
      'p_variant_uuid': variantId,
      'p_item_name': name,
      'p_quantity': qty,
      'p_unit_price': clientUnitPrice ?? 0.0,
      'p_image_url': imageUrl,
    };

    try {
      final dynamic resp = await supabase.rpc('cart_item_upsert', params: params);

      debugPrint('CartApi.addToCart: rpc returned type=${resp.runtimeType}');
      debugPrint('CartApi.addToCart: resp=$resp');

      if (resp == null) return null;

      Map<String, dynamic>? row;
      if (resp is List && resp.isNotEmpty) {
        row = Map<String, dynamic>.from(resp.first as Map);
      } else if (resp is Map) {
        row = Map<String, dynamic>.from(resp);
      }

      // Reconcile local provisional id with server id if possible.
      if (row != null && localCartItemId != null && localCartItemId.isNotEmpty) {
        final serverId = (row['cart_item_id'] ?? row['id'])?.toString();
        if (serverId != null && serverId.isNotEmpty) {
          CartService.instance.replaceLocalWithServerId(localCartItemId, serverId);
          debugPrint('CartApi.addToCart: reconciled local $localCartItemId -> server $serverId');
        }
      }

      return row;
    } on PostgrestException catch (pgErr) {
      debugPrint('CartApi.addToCart PostgrestException: ${pgErr.message} | details: ${pgErr.details} | hint: ${pgErr.hint}');
      rethrow;
    } catch (e, st) {
      debugPrint('CartApi.addToCart: unexpected error $e\n$st');
      rethrow;
    }
  }

  /// Fetch cart items for a specific restaurant for the current customer and
  /// replace local cart state with server state.
  static Future<void> fetchAndSyncCartForUserAndRestaurant(String restaurantId) async {
    final customerId = await _currentCustomerId();
    if (customerId == null) {
      debugPrint('CartApi.fetchAndSyncCartForUserAndRestaurant: no customer id, clearing local cart');
      CartService.instance.clear();
      return;
    }

    debugPrint('CartApi.fetchAndSyncCartForUserAndRestaurant: fetching for customer=$customerId restaurant=$restaurantId');

    try {
      final resp = await supabase.rpc('get_cart_items_for_restaurant', params: {
        'p_customer_id': customerId,
        'p_restaurant_id': restaurantId,
      });

      final dynamic data = (resp is Map && resp.containsKey('data')) ? resp['data'] : resp;
      final List<dynamic> rows = (data is List) ? data : (data == null ? [] : [data]);

      final items = rows.map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return CartItem(
          id: (m['cart_item_id'] ?? m['id']).toString(),
          menuItemId: (m['menu_item_id'] ?? '').toString(),
          variantId: m['variant_id']?.toString(),
          name: m['name']?.toString() ?? '',
          unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0.0,
          qty: (m['qty'] as int?) ?? int.tryParse(m['qty'].toString()) ?? 0,
          imageUrl: m['image_url'] as String?,
          restaurantId: restaurantId,
          variantName: null,
        );
      }).toList();

      // merge per-restaurant
      CartService.instance.replaceItemsForRestaurant(restaurantId, items);
      debugPrint('CartApi.fetchAndSyncCartForUserAndRestaurant: synced ${items.length} items for restaurant $restaurantId');
    } catch (e, st) {
      debugPrint('CartApi.fetchAndSyncCartForUserAndRestaurant error: $e\n$st');
    }
  }

  /// Fetch all carts and items for the current customer and sync local state.
  static Future<void> fetchAndSyncAllUserCarts() async {
    final customerId = await _currentCustomerId();
    if (customerId == null) {
      debugPrint('CartApi.fetchAndSyncAllUserCarts: no customer id, clearing local cart');
      CartService.instance.clear();
      return;
    }

    debugPrint('CartApi.fetchAndSyncAllUserCarts: fetching carts for customer=$customerId');

    try {
      final cartsResp = await supabase.from('carts').select('id, restaurant_id').eq('customer_id', customerId);

      final List<dynamic> cartRows = (cartsResp is List) ? cartsResp : (cartsResp is Map ? [cartsResp] : []);
      if (cartRows.isEmpty) {
        debugPrint('CartApi.fetchAndSyncAllUserCarts: no carts found');
        CartService.instance.clear();
        return;
      }

      final Map<String, String> cartToRestaurant = {};
      final List<String> cartIds = [];
      for (final r in cartRows) {
        final m = Map<String, dynamic>.from(r as Map);
        final id = m['id'] as String?;
        final rest = m['restaurant_id'] as String?;
        if (id != null) {
          cartIds.add(id);
          cartToRestaurant[id] = rest ?? '';
        }
      }

      if (cartIds.isEmpty) {
        CartService.instance.clear();
        return;
      }

      final itemsResp = await supabase
          .from('cart_items')
          .select('id, cart_id, menu_item_id, variant_id, name, unit_price, qty, image_url')
          .inFilter('cart_id', cartIds);

      final List<dynamic> itemRows = (itemsResp is List) ? itemsResp : (itemsResp is Map ? [itemsResp] : []);
      final items = itemRows.map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        final cartId = m['cart_id']?.toString();
        return CartItem(
          id: (m['id'] ?? '').toString(),
          menuItemId: (m['menu_item_id'] ?? '').toString(),
          variantId: m['variant_id']?.toString(),
          name: m['name']?.toString() ?? '',
          unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0.0,
          qty: (m['qty'] as int?) ?? int.tryParse(m['qty']?.toString() ?? '0') ?? 0,
          imageUrl: m['image_url'] as String?,
          restaurantId: (cartId != null && cartToRestaurant.containsKey(cartId)) ? cartToRestaurant[cartId] : null,
          variantName: null,
        );
      }).toList();

      CartService.instance.replaceAll(items);
      debugPrint('CartApi.fetchAndSyncAllUserCarts: synced ${items.length} items across ${cartIds.length} carts');
    } catch (e, st) {
      debugPrint('CartApi.fetchAndSyncAllUserCarts error: $e\n$st');
    }
  }

  /// Set an item's quantity via RPC and re-sync.
  static Future<void> setItemQty(String cartItemId, int qty, {String? restaurantId}) async {
    final customerId = await _currentCustomerId();
    if (customerId == null) throw Exception('Not authenticated');

    debugPrint('CartApi.setItemQty: cartItemId=$cartItemId qty=$qty');

    try {
      await supabase.rpc('update_cart_item_qty', params: {
        'p_cart_item_id': cartItemId,
        'p_qty': qty,
      });
    } catch (e) {
      debugPrint('CartApi.setItemQty RPC error: $e');
      rethrow;
    }

    if (restaurantId != null) {
      await fetchAndSyncCartForUserAndRestaurant(restaurantId);
    } else {
      await fetchAndSyncAllUserCarts();
    }
  }

  /// Remove a cart item and re-sync.
  static Future<void> removeFromCart(String cartItemId, {String? restaurantId}) async {
    final customerId = await _currentCustomerId();
    if (customerId == null) throw Exception('Not authenticated');

    debugPrint('CartApi.removeFromCart: cartItemId=$cartItemId');

    try {
      await supabase.from('cart_items').delete().eq('id', cartItemId);
    } catch (e) {
      debugPrint('CartApi.removeFromCart error: $e');
      rethrow;
    }

    if (restaurantId != null) {
      await fetchAndSyncCartForUserAndRestaurant(restaurantId);
    } else {
      await fetchAndSyncAllUserCarts();
    }
  }

  /// Clear the customer's cart for a given restaurant and re-sync.
  static Future<void> clearCartForRestaurant(String restaurantId) async {
    final customerId = await _currentCustomerId();
    if (customerId == null) throw Exception('Not authenticated');

    debugPrint('CartApi.clearCartForRestaurant: restaurantId=$restaurantId');

    try {
      final cartResp = await supabase
          .from('carts')
          .select('id')
          .eq('customer_id', customerId)
          .eq('restaurant_id', restaurantId)
          .limit(1);

      final List<dynamic> carts = (cartResp is List) ? cartResp : (cartResp is Map ? [cartResp] : []);
      if (carts.isEmpty) {
        debugPrint('CartApi.clearCartForRestaurant: no cart found to clear');
        return;
      }

      final cartId = (carts.first as Map)['id'] as String?;
      if (cartId == null) return;

      await supabase.from('carts').delete().eq('id', cartId);
      await fetchAndSyncAllUserCarts();
      debugPrint('CartApi.clearCartForRestaurant: cleared cart $cartId');
    } catch (e) {
      debugPrint('CartApi.clearCartForRestaurant error: $e');
      rethrow;
    }
  }

  /// Checkout the cart for a restaurant via RPC `checkout_cart_for_restaurant`.
  /// Returns created order id (String) if available, otherwise null.
  static Future<String?> checkoutCartForRestaurant({
    required String customerId,
    required String restaurantId,
  }) async {
    debugPrint('CartApi.checkoutCartForRestaurant: customer=$customerId restaurant=$restaurantId');
    try {
      final resp = await supabase.rpc('checkout_cart_for_restaurant', params: {
        'p_customer_id': customerId,
        'p_restaurant_id': restaurantId,
      });

      final data = (resp is Map && resp.containsKey('data')) ? resp['data'] : resp;

      if (data == null) {
        await fetchAndSyncAllUserCarts();
        return null;
      }

      if (data is Map && data['order_id'] != null) {
        final orderId = data['order_id'].toString();
        debugPrint('CartApi.checkoutCartForRestaurant: created order $orderId');
        await fetchAndSyncAllUserCarts();
        return orderId;
      } else if (data is String) {
        await fetchAndSyncAllUserCarts();
        return data;
      } else if (data is List && data.isNotEmpty) {
        final m = Map<String, dynamic>.from(data.first as Map);
        if (m.containsKey('order_id')) {
          await fetchAndSyncAllUserCarts();
          return m['order_id'].toString();
        }
      }

      await fetchAndSyncAllUserCarts();
      debugPrint('CartApi.checkoutCartForRestaurant: checkout completed (no order id returned)');
      return null;
    } catch (e, st) {
      debugPrint('CartApi.checkoutCartForRestaurant RPC error: $e\n$st');
      rethrow;
    }
  }

  /// Force-clear cart & items for a given customerId + restaurantId.
  /// Deletes cart_items for all carts of the (customer,restaurant) and then deletes the carts.
  /// Finally triggers a fetchAndSyncAllUserCarts to update local state.
  static Future<void> clearCartForRestaurantWithCustomer(String customerId, String restaurantId) async {
    if (customerId.isEmpty) throw Exception('customerId is required');
    try {
      // get carts for this customer+restaurant
      final cartResp = await supabase
          .from('carts')
          .select('id')
          .eq('customer_id', customerId)
          .eq('restaurant_id', restaurantId);

      final List<dynamic> carts = (cartResp is List) ? cartResp : (cartResp is Map ? [cartResp] : []);
      if (carts.isEmpty) {
        debugPrint('CartApi.clearCartForRestaurantWithCustomer: no cart found for customer=$customerId restaurant=$restaurantId');
        return;
      }

      final List<String> cartIds = carts.map((c) {
        final m = Map<String, dynamic>.from(c as Map);
        return (m['id'] as String);
      }).toList();

      // delete cart_items for those cart ids (if any)
      try {
        await supabase.from('cart_items').delete().inFilter('cart_id', cartIds);
      } catch (e) {
        debugPrint('CartApi.clearCartForRestaurantWithCustomer: failed to delete cart_items: $e');
        // continue to attempt to delete carts anyway
      }

      // delete carts
      await supabase.from('carts').delete().inFilter('id', cartIds);

      // finally sync local state
      await fetchAndSyncAllUserCarts();
      debugPrint('CartApi.clearCartForRestaurantWithCustomer: cleared cart(s) ${cartIds.join(", ")} for customer=$customerId');
    } catch (e, st) {
      debugPrint('CartApi.clearCartForRestaurantWithCustomer ERROR: $e\n$st');
      rethrow;
    }
  }
}
