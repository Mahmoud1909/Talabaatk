// lib/services/category_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/utils/category_model.dart';

final SupabaseClient supabase = Supabase.instance.client;

/// Returns all categories across all restaurants, but deduplicates
/// globally by lower-case trimmed name. If duplicates exist, choose one
/// by this priority:
///  1) Has non-empty image_url
///  2) Lower sort_order
///  3) Earlier created_at
Future<List<CategoryModel>> getAllCategories() async {
  try {
    debugPrint('[category_service] getAllCategories() start');

    final resp = await supabase
        .from('categories')
    // include restaurants(name) so we can show restaurantName if desired
        .select('id, restaurant_id, name, sort_order, created_at, description, image_url, image_path, restaurants(name)')
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);

    if (resp == null) {
      debugPrint('[category_service] Response is null — returning empty list');
      return [];
    }

    final List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(resp);
    debugPrint('[category_service] Raw rows returned (all restaurants): ${rows.length}');

    // Deduplicate by lower-case trimmed name with selection policy
    final Map<String, CategoryModel> chosenByName = {};
    int duplicatesSkipped = 0;

    for (final r in rows) {
      final rawName = (r['name'] ?? '').toString().trim();
      if (rawName.isEmpty) continue;
      final key = rawName.toLowerCase();

      final candidate = CategoryModel.fromMap(r);

      if (!chosenByName.containsKey(key)) {
        chosenByName[key] = candidate;
      } else {
        // decide which to keep between existing and candidate
        final existing = chosenByName[key]!;

        // Priority 1: prefer one with image
        final existingHasImage = (existing.imageUrl ?? '').isNotEmpty;
        final candidateHasImage = (candidate.imageUrl ?? '').isNotEmpty;
        if (existingHasImage && !candidateHasImage) {
          // keep existing
          duplicatesSkipped++;
          debugPrint('[category_service] Duplicate skipped (kept existing with image): ${candidate.name} id=${candidate.id}');
          continue;
        } else if (!existingHasImage && candidateHasImage) {
          // prefer candidate
          chosenByName[key] = candidate;
          debugPrint('[category_service] Replaced duplicate with one having image: ${candidate.name} id=${candidate.id}');
          continue;
        }

        // Priority 2: prefer lower sort_order
        if (candidate.sortOrder < existing.sortOrder) {
          chosenByName[key] = candidate;
          debugPrint('[category_service] Replaced duplicate by lower sort_order: ${candidate.name} id=${candidate.id}');
          continue;
        } else if (candidate.sortOrder > existing.sortOrder) {
          duplicatesSkipped++;
          debugPrint('[category_service] Duplicate skipped by sort_order: ${candidate.name} id=${candidate.id}');
          continue;
        }

        // Priority 3: prefer earlier created_at
        if (candidate.createdAt.isBefore(existing.createdAt)) {
          chosenByName[key] = candidate;
          debugPrint('[category_service] Replaced duplicate by earlier created_at: ${candidate.name} id=${candidate.id}');
        } else {
          duplicatesSkipped++;
          debugPrint('[category_service] Duplicate skipped by created_at: ${candidate.name} id=${candidate.id}');
        }
      }
    }

    final list = chosenByName.values.toList();

    // deterministic sort: by name (case-insensitive)
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    debugPrint('[category_service] Returning ${list.length} unique categories (skipped $duplicatesSkipped duplicates)');
    return list;
  } catch (e, st) {
    debugPrint('[category_service] ERROR in getAllCategories: $e\n$st');
    return [];
  }
}
