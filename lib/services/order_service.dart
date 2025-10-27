// lib/services/order_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/utils/order.dart';
import 'package:talabak_users/utils/order_item.dart';

final SupabaseClient _supabase = Supabase.instance.client;

class OrderService {
  final supabase = _supabase;

// lib/services/order_service.dart
  Future<Order?> createOrder(Order order, List<OrderItem> items, {bool autoAssignDriver = true}) async {
    try {
      final orderPayload = Map<String, dynamic>.from(order.toJson());
      orderPayload.remove('order_items');

      // Respect autoAssignDriver flag
      orderPayload['auto_assign_driver'] = autoAssignDriver;

      debugPrint('OrderService.createOrder payload: $orderPayload');

      final orderResp = await supabase
          .from('orders')
          .insert(orderPayload)
          .select()
          .maybeSingle();

      if (orderResp == null) {
        debugPrint('OrderService.createOrder ERROR: orderResp was null');
        return null;
      }

      final insertedOrderId = orderResp['id'] as String;

      if (items.isNotEmpty) {
        final itemsPayload = items.map((it) {
          final m = it.toJson();
          m['order_id'] = insertedOrderId;
          return m;
        }).toList();

        await supabase.from('order_items').insert(itemsPayload);
      }

      return fetchOrderById(insertedOrderId);
    } catch (e, st) {
      debugPrint('OrderService.createOrder ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<Order?> fetchOrderById(String id) async {
    try {
      final response = await supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Order.fromJson(Map<String, dynamic>.from(response as Map));
    } catch (e, st) {
      debugPrint('OrderService.fetchOrderById ERROR: $e\n$st');
      return null;
    }
  }

  Future<List<Order>> fetchOrdersByCustomer(String customerId) async {
    try {
      final response = await supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      if (response == null) return [];
      return (response as List)
          .map((o) => Order.fromJson(Map<String, dynamic>.from(o as Map)))
          .toList();
    } catch (e, st) {
      debugPrint('OrderService.fetchOrdersByCustomer ERROR: $e\n$st');
      return [];
    }
  }

  Future<List<Order>> fetchOrdersByRestaurant(String restaurantId) async {
    try {
      final response = await supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('restaurant_id', restaurantId)
          .order('created_at', ascending: false);

      if (response == null) return [];
      return (response as List)
          .map((o) => Order.fromJson(Map<String, dynamic>.from(o as Map)))
          .toList();
    } catch (e, st) {
      debugPrint('OrderService.fetchOrdersByRestaurant ERROR: $e\n$st');
      return [];
    }
  }

  Future<void> updateOrderStatus({
    required String orderId,
    String? status,
    String? customerPhone,
    String? comment,
    String? driverId,
    String? branchId,
    double? deliveryFee,
  }) async {
    try {
      final Map<String, dynamic> updates = {};
      if (status != null) updates['status'] = status;
      if (customerPhone != null) updates['customer_phone'] = customerPhone;
      if (comment != null) updates['comment'] = comment;
      if (driverId != null) updates['driver_id'] = driverId;
      if (branchId != null) updates['branch_id'] = branchId;
      if (deliveryFee != null) updates['delivery_fee'] = deliveryFee;

      if (updates.isNotEmpty) {
        await supabase.from('orders').update(updates).eq('id', orderId);
        debugPrint('OrderService.updateOrderStatus: $updates');
      }
    } catch (e, st) {
      debugPrint('OrderService.updateOrderStatus ERROR: $e\n$st');
    }
  }
}
