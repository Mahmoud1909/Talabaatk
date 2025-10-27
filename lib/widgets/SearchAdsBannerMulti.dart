// lib/widgets/search_ads_banner_multi.dart
// Dark-mode aware version of SearchAdsBannerMulti.
// - In Dark mode the TextField inner background becomes black,
//   typed text & hint use the app primary color, border & prefix icon use primary color.
// - In Light mode the TextField keeps white background with black text and black border.
// - Prefix search icon is always shown (even when field empty).
// - Suggestions overlay adapts to current theme colors.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:talabak_users/screens/restaurant_detail_screen.dart';
import 'package:talabak_users/screens/item_detail_screen.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

class SearchAdsBannerMulti extends StatefulWidget {
  const SearchAdsBannerMulti({super.key});

  @override
  State<SearchAdsBannerMulti> createState() => _SearchAdsBannerMultiState();
}

class _SearchAdsBannerMultiState extends State<SearchAdsBannerMulti> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _overlay;
  Timer? _debounce;
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> _results = []; // items: {type, id, name, subtitle?, imageUrl, restaurantId?}

  // last computed caret offset and field height (in logical pixels)
  double _lastCaretDx = 8.0;
  double _lastFieldHeight = 48.0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {})); // update clear button state
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        // when field loses focus, keep overlay but allow tapping outside to close
        // we don't forcibly remove overlay here to allow interaction with suggestions if needed
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _ctrl.removeListener(() {});
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _results = [];
        _error = null;
      });
      _removeOverlay();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = supabase.Supabase.instance.client;

      final restaurantsRes = await client
          .from('restaurants')
          .select('id, name, logo_url, description')
          .ilike('name', '%$query%')
          .order('name', ascending: true)
          .limit(6);

      final itemsRes = await client
          .from('menu_items')
          .select('id, name, image_url, restaurant_id')
          .ilike('name', '%$query%')
          .order('name', ascending: true)
          .limit(6);

      final List<dynamic> restRows = (restaurantsRes is List) ? restaurantsRes : <dynamic>[];
      final List<dynamic> itemRows = (itemsRes is List) ? itemsRes : <dynamic>[];

      final List<Map<String, dynamic>> merged = [];

      for (final r in restRows) {
        if (r is Map) {
          merged.add({
            'type': 'restaurant',
            'id': r['id']?.toString() ?? '',
            'name': r['name']?.toString() ?? '',
            'subtitle': r['description']?.toString() ?? '',
            'imageUrl': (r['logo_url'] ?? r['cover_url'])?.toString() ?? '',
          });
        }
      }

      for (final it in itemRows) {
        if (it is Map) {
          merged.add({
            'type': 'item',
            'id': it['id']?.toString() ?? '',
            'name': it['name']?.toString() ?? '',
            'subtitle': null,
            'imageUrl': (it['image_url'] ?? '')?.toString() ?? '',
            'restaurantId': it['restaurant_id']?.toString(),
          });
        }
      }

      final limited = merged.take(8).toList();

      if (!mounted) return;
      setState(() {
        _results = limited;
        _loading = false;
      });

      // compute caret pos before showing overlay so overlay is positioned under last line
      _computeCaretAndFieldMetrics();
      _showOverlay();
    } catch (e, st) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
      debugPrint('Search error: $e\n$st');
      _computeCaretAndFieldMetrics();
      _showOverlay();
    }
  }

  void _computeCaretAndFieldMetrics() {
    try {
      final fieldContext = _fieldKey.currentContext;
      if (fieldContext == null) return;
      final box = fieldContext.findRenderObject() as RenderBox?;
      if (box == null) return;
      final double fieldWidth = box.size.width;
      _lastFieldHeight = box.size.height;

      // horizontal inner padding approximate (InputDecoration left/right + prefix icon)
      const double horizontalPadding = 12.0;

      final theme = Theme.of(fieldContext);
      final bool isDark = theme.brightness == Brightness.dark;
      final typedTextColor = isDark ? const Color(0xFFFF5C01) : Colors.black87;

      final tp = TextPainter(
        text: TextSpan(text: _ctrl.text, style: TextStyle(fontSize: 16, color: typedTextColor)),
        textDirection: Directionality.of(fieldContext),
        maxLines: null,
      );

      // layout using the inner width (exclude a safe margin)
      tp.layout(minWidth: 0, maxWidth: (fieldWidth - horizontalPadding * 2).clamp(0.0, fieldWidth));
      final lines = tp.computeLineMetrics();
      if (lines.isNotEmpty) {
        final last = lines.last;
        double caretX = last.left + last.width;
        caretX += horizontalPadding;
        caretX = caretX.clamp(8.0, fieldWidth - 16.0);
        _lastCaretDx = caretX;
      } else {
        _lastCaretDx = horizontalPadding;
      }
    } catch (_) {
      _lastCaretDx = 8.0;
      _lastFieldHeight = 48.0;
    }
  }

  void _showOverlay() {
    _removeOverlay();

    final overlayState = Overlay.of(context);
    if (overlayState == null) return;

    _overlay = OverlayEntry(builder: (context) {
      final media = MediaQuery.of(context);
      final screenWidth = media.size.width;
      final maxOverlayWidth = (screenWidth - 32).clamp(200.0, 640.0);
      final overlayWidth = maxOverlayWidth;

      double anchorDx = _lastCaretDx;
      final double leftMost = 16.0;
      final double rightMost = screenWidth - 16.0;
      if (anchorDx + overlayWidth > rightMost) {
        anchorDx = (rightMost - overlayWidth).clamp(leftMost, rightMost);
      }
      if (anchorDx < leftMost) anchorDx = leftMost;

      final theme = Theme.of(context);
      final bool isDark = theme.brightness == Brightness.dark;
      final background = isDark ? theme.cardColor : Colors.white;

      return Stack(
        children: [
          // transparent barrier to allow tapping outside to close
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _removeOverlay();
                _focus.unfocus();
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // the overlay anchored to the CompositedTransformTarget but additionally offset by computed anchorDx
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, _lastFieldHeight + 8),
            child: Transform.translate(
              offset: Offset(anchorDx - 16.0, 0),
              child: Material(
                color: Colors.transparent,
                elevation: 12,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: overlayWidth, maxHeight: 380),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.6 : 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _buildOverlayBody(theme),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });

    overlayState.insert(_overlay!);
  }

  Widget _buildOverlayBody(ThemeData theme) {
    final loc = AppLocalizations.of(context);
    final searchingText = loc?.searching ?? 'Searching...';
    final errorText = loc?.error ?? 'Error';
    final noResultsText = loc?.noResults ?? 'No results';
    final bool isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return SizedBox(
        height: 64,
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 12),
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? const Color(0xFFFF5C01) : theme.colorScheme.primary)),
            const SizedBox(width: 12),
            Text(searchingText, style: theme.textTheme.bodyMedium),
          ]),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('$errorText: $_error', style: theme.textTheme.bodyMedium),
      );
    }

    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14.0),
        child: Text(noResultsText, style: theme.textTheme.bodyMedium),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemBuilder: (c, i) {
        final r = _results[i];
        final type = (r['type'] ?? 'restaurant') as String;
        final id = r['id']?.toString() ?? '';
        final name = r['name']?.toString() ?? '';
        final subtitle = r['subtitle']?.toString();
        final imageUrl = r['imageUrl']?.toString() ?? '';

        Widget? trailingWidget;
        if (type == 'restaurant') {
          trailingWidget = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5C01),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              loc?.restaurantLabel ?? 'Restaurant',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          );
        }

        final titleStyle = theme.textTheme.bodyLarge?.copyWith(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600);
        final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(color: isDark ? Colors.white70 : Colors.black54);

        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: (imageUrl.isNotEmpty)
                  ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: isDark ? Colors.grey[800] : Colors.grey[200]),
                errorWidget: (_, __, ___) => Container(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  child: Icon(type == 'restaurant' ? Icons.storefront_outlined : Icons.fastfood, color: isDark ? Colors.white24 : Colors.black26),
                ),
              )
                  : Container(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                child: Icon(type == 'restaurant' ? Icons.storefront_outlined : Icons.fastfood, color: isDark ? Colors.white24 : Colors.black38),
              ),
            ),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
          subtitle: subtitle != null && subtitle.isNotEmpty ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle) : null,
          trailing: trailingWidget,
          onTap: () => _onSuggestionTap(r),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          horizontalTitleGap: 8,
        );
      },
      separatorBuilder: (_, __) => Divider(height: 1, thickness: 1, color: theme.dividerColor),
      itemCount: _results.length,
    );
  }

  void _onSuggestionTap(Map<String, dynamic> r) {
    _removeOverlay();
    _focus.unfocus();
    final type = r['type'] as String?;
    final id = r['id']?.toString() ?? '';

    _ctrl.clear();

    if (type == 'restaurant') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: id)));
      return;
    }

    if (type == 'item') {
      final restaurantId = r['restaurantId']?.toString();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: id, restaurantId: restaurantId)));
      return;
    }
  }

  void _removeOverlay() {
    try {
      _overlay?.remove();
    } catch (_) {}
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // Colors and styles according to desired behavior:
    // - Dark: inner background black, typed text & hint = primary color, border & prefix icon = primary color.
    // - Light: background white, text black, border black.
    final fillColor = isDark ? Colors.black : Colors.white;
    final typedTextColor = isDark ? const Color(0xFFFF5C01) : Colors.black87;
    final hintColor = isDark ? const Color(0xFFFF5C01).withOpacity(0.9) : Colors.black54;
    final iconColor = isDark ? const Color(0xFFFF5C01) : Colors.black54;
    final enabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: isDark ? const Color(0xFFFF5C01) : Colors.black, width: 1.2),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: const Color(0xFFFF5C01), width: 1.6),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          CompositedTransformTarget(
            link: _layerLink,
            child: Container(
              key: _fieldKey,
              constraints: const BoxConstraints(minHeight: 48),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                style: TextStyle(fontSize: 16, color: typedTextColor),
                onChanged: _onTextChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (s) => _search(s),
                cursorColor: const Color(0xFFFF5C01),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)?.searchHint ?? 'Search restaurants or items...',
                  hintStyle: TextStyle(color: hintColor),
                  prefixIcon: Icon(Icons.search, color: iconColor),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? GestureDetector(onTap: () {
                    _ctrl.clear();
                    _onTextChanged('');
                    _removeOverlay();
                  }, child: Icon(Icons.close, color: isDark ? const Color(0xFFFF5C01) : Colors.black54))
                      : null,
                  filled: true,
                  fillColor: fillColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  enabledBorder: enabledBorder,
                  focusedBorder: focusedBorder,
                ),
                maxLines: null, // allow multiple lines so caret can be on last line if user wraps
              ),
            ),
          ),

          const SizedBox(height: 8),
          // Note: AdsBanner and other content should be added in the parent (HomeScreen).
        ],
      ),
    );
  }
}
