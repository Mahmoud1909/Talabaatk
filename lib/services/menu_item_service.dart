// lib/services/menu_item_service.dart
import 'package:talabak_users/services/supabase_client.dart'; // your central client
import 'package:talabak_users/utils/menu_item_model.dart';
import 'package:flutter/foundation.dart';
import 'package:talabak_users/services/supabase_client.dart'; // تأكد أن هذا الملف يعرض المتغير `supabase`
import 'package:talabak_users/utils/menu_item_model.dart'; // عدّل المسار إذا ملفك في utils/

final _sb = supabase; // Supabase.instance.client alias from your project

class MenuItemService {
  /// Fetch a single menu item by id
  static Future<MenuItemModel?> getMenuItemById(String itemId) async {
    try {
      final resp = await _sb
          .from('menu_items')
          .select('id, restaurant_id, name, description, price, image_url, has_discount, discount_percent, category_id')
          .eq('id', itemId)
          .maybeSingle();

      if (resp == null) return null;
      return MenuItemModel.fromMap(Map<String, dynamic>.from(resp));
    } catch (e) {
      debugPrint('getMenuItemById ERROR: $e');
      return null;
    }
  }

  /// Fetch variants (if any) for an item
  static Future<List<MenuItemVariant>> getVariantsForItem(String itemId) async {
    try {
      final resp = await _sb
          .from('menu_item_variants')
          .select('id, menu_item_id, name, extra_price, sort_order')
          .eq('menu_item_id', itemId)
          .order('sort_order', ascending: true);

      if (resp == null) return [];
      final List rows = resp as List;
      return rows.map((r) => MenuItemVariant.fromMap(Map<String, dynamic>.from(r))).toList();
    } catch (e) {
      debugPrint('getVariantsForItem ERROR: $e');
      return [];
    }
  }

  /// Convenience that fetches item + variants
  static Future<MenuItemWithVariants?> getItemWithVariants(String itemId) async {
    final item = await getMenuItemById(itemId);
    if (item == null) return null;
    final variants = await getVariantsForItem(itemId);
    return MenuItemWithVariants(item: item, variants: variants);
  }
}
