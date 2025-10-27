// lib/widgets/big_brands_near_you.dart
// Adapted to support Dark Mode with theme-aware colors while preserving behavior.
// - Uses ThemeData / ColorScheme for colors so light/dark switch looks natural.
// - Keeps layout, grouping, and navigation identical to original.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:talabak_users/screens/restaurant_detail_screen.dart';
import 'package:talabak_users/services/restaurant_service.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

class BigBrandsNearYou extends StatelessWidget {
  final List<NearestRestaurant> items;
  final void Function(NearestRestaurant)? onTap;
  final int maxItems;
  final String? title; // if null, use localized title

  const BigBrandsNearYou({
    super.key,
    required this.items,
    this.onTap,
    this.maxItems = 5,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // 1) Deduplicate by restaurantId -> keep nearest branch
    final Map<String, NearestRestaurant> byRestaurant = {};
    for (final item in items) {
      final existing = byRestaurant[item.restaurantId];
      if (existing == null) {
        byRestaurant[item.restaurantId] = item;
      } else {
        final existingDist = existing.distanceMeters;
        final newDist = item.distanceMeters;
        if (newDist != null && (existingDist == null || newDist < existingDist)) {
          byRestaurant[item.restaurantId] = item;
        }
      }
    }

    // 2) Sort by distance and limit results
    final unique = byRestaurant.values.toList()
      ..sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));
    final limited = unique.take(maxItems).toList();

    // 3) Group into columns of 2 (stacked)
    final List<List<NearestRestaurant>> groups = [];
    for (var i = 0; i < limited.length; i += 2) {
      groups.add(limited.sublist(i, i + 2 > limited.length ? limited.length : i + 2));
    }

    const double cardWidth = 330.0;
    const double cardHeight = 80.0;
    final double columnHeight = (cardHeight * 2) + 8;

    // Panel background appropriate for mode
    final panelBg = isDark ? theme.colorScheme.surfaceVariant : const Color(0xFFFFF3D7);
    final titleColor = theme.textTheme.titleLarge?.color ?? (isDark ? Colors.white : Colors.black87);

    return Container(
      color: panelBg,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title (localized if title == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              title ?? loc.big_brands_near_you,
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.bold, color: titleColor),
            ),
          ),
          const SizedBox(height: 8),

          // Horizontal scroll list
          SizedBox(
            height: columnHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final pair = groups[idx];
                return SizedBox(
                  width: cardWidth,
                  child: Column(
                    children: [
                      _RestaurantCard(
                        nr: pair[0],
                        height: cardHeight,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        onTap: onTap,
                      ),
                      const SizedBox(height: 8),
                      if (pair.length > 1)
                        _RestaurantCard(
                          nr: pair[1],
                          height: cardHeight,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          onTap: onTap,
                        )
                      else
                        SizedBox(height: cardHeight), // keep spacing
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  final NearestRestaurant nr;
  final double height;
  final BorderRadius borderRadius;
  final void Function(NearestRestaurant)? onTap;

  const _RestaurantCard({
    required this.nr,
    required this.height,
    required this.borderRadius,
    this.onTap,
  });

  void _openRestaurantDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RestaurantDetailScreen(
          restaurantId: nr.restaurantId,
          initialLogo: nr.logoUrl,
          initialCover: null,
          initialName: nr.restaurantName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // Colors & styles adapted to current theme
    final cardColor = theme.cardColor;
    final elevation = 6.0;
    final shadowColor = isDark ? Colors.black.withOpacity(0.6) : Colors.black.withOpacity(0.12);
    final titleStyle = theme.textTheme.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
    final metaStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 13, color: theme.textTheme.bodyMedium?.color?.withOpacity(0.78));
    final iconColor = theme.iconTheme.color?.withOpacity(0.75) ?? (isDark ? Colors.white70 : Colors.black54);

    return Material(
      color: cardColor,
      borderRadius: borderRadius,
      elevation: elevation,
      shadowColor: shadowColor,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () {
          if (onTap != null) {
            onTap!(nr);
          } else {
            _openRestaurantDetail(context);
          }
        },
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: nr.logoUrl != null
                    ? CachedNetworkImage(
                  imageUrl: nr.logoUrl!,
                  width: height - 16,
                  height: height - 16,
                  fit: BoxFit.cover,
                  placeholder: (c, s) => SizedBox(
                    width: height - 16,
                    height: height - 16,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
                  ),
                  errorWidget: (c, s, e) => Container(
                    width: height - 16,
                    height: height - 16,
                    color: isDark ? Colors.grey.shade800 : Colors.grey[200],
                    child: Icon(Icons.restaurant, color: isDark ? Colors.white24 : Colors.grey),
                  ),
                )
                    : Container(
                  width: height - 16,
                  height: height - 16,
                  color: isDark ? Colors.grey.shade800 : Colors.grey[200],
                  child: Icon(Icons.restaurant, color: isDark ? Colors.white24 : Colors.grey),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nr.restaurantName,
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: iconColor),
                        const SizedBox(width: 6),
                        Text(
                          _prepTimeWithVariationLocalized(context, nr.restaurantId, nr.prepMin, nr.prepMax),
                          style: metaStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Distance (localized)
              if (nr.distanceMeters != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    loc.distance((nr.distanceMeters! / 1000).toStringAsFixed(1)),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Deterministic prep time with slight variation — localized using AppLocalizations
  static String _prepTimeWithVariationLocalized(BuildContext context, String restaurantId, int? min, int? max) {
    final loc = AppLocalizations.of(context)!;
    final seed = restaurantId.hashCode;
    final rnd = Random(seed);
    const int maxShift = 5; // up to ±5 minutes shift
    if (min != null && max != null) {
      final shiftMin = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final shiftMax = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      int newMin = (min + shiftMin).clamp(1, 999);
      int newMax = (max + shiftMax).clamp(newMin, 999);
      return loc.prepRange(newMax, newMin);
    } else if (min != null) {
      final shift = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final newMin = (min + shift).clamp(1, 999);
      return loc.mins(newMin);
    } else if (max != null) {
      final shift = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final newMax = (max + shift).clamp(1, 999);
      return loc.mins(newMax);
    } else {
      final base = 30 + (rnd.nextInt(11) - 5); // 25..35
      return loc.mins(base);
    }
  }
}
