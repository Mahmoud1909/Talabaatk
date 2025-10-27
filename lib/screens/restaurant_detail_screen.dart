// lib/screens/restaurant_detail_screen.dart
// Refactored — Dark/Light ready, improved category pills, searchable category menu
// Localized version — strings use AppLocalizations where available

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// alias Restaurant model to avoid name collisions
import 'package:talabak_users/utils/Restaurant_Model.dart' as rest_model;
import 'package:talabak_users/utils/menu_item_model.dart';
import 'package:talabak_users/screens/item_detail_screen.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

class RestaurantDetailScreen extends StatefulWidget {
  final String restaurantId;
  final String? initialLogo;
  final String? initialCover;
  final String? initialName;

  const RestaurantDetailScreen({
    super.key,
    required this.restaurantId,
    this.initialLogo,
    this.initialCover,
    this.initialName,
  });

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  rest_model.RestaurantBasic? _restaurantBasic;
  List<rest_model.CategoryShort> _categories = [];
  Map<String, List<MenuItemModel>> _menuByCategory = {};

  final ScrollController _scrollController = ScrollController();
  final ScrollController _categoryListController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};
  final Map<String, GlobalKey> _categoryButtonKeys = {};
  String? _activeCategoryId;
  bool _userTappedCategory = false;

  Map<String, double> _categoryProximities = {};

  static const double _logoSize = 88.0;
  static const double _categoryBarHeight = 64.0;
  static const double _appBarExpanded = 260.0;
  static const double _infoCardOverlap = 72.0;
  static const double _gapAfterInfoCard = 20.0;

  bool _categoryPinned = false;
  Timer? _snapTimer;

  // use theme primary as accent but keep fallback
  Color get _accent => Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _snapTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _categoryListController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // restaurant
      final res = await _supabase
          .from('restaurants')
          .select('id, name, logo_url, cover_url, description, prep_time_min, prep_time_max, delivery_fee')
          .eq('id', widget.restaurantId)
          .maybeSingle();

      if (res == null) throw Exception('Restaurant not found');
      _restaurantBasic = rest_model.RestaurantBasic.fromMap(Map<String, dynamic>.from(res));

      // categories
      final catResp = await _supabase
          .from('categories')
          .select('id, name')
          .eq('restaurant_id', widget.restaurantId)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      final List<dynamic> catRows = catResp is List ? catResp : [];
      final loadedCats = catRows.map((r) => rest_model.CategoryShort.fromMap(Map<String, dynamic>.from(r))).toList();

      // menu items: include discount fields
      final menuResp = await _supabase
          .from('menu_items')
          .select('id, restaurant_id, name, description, price, image_url, image_path, category_id, has_discount, discount_percent')
          .eq('restaurant_id', widget.restaurantId)
          .order('created_at', ascending: true);
      final List<dynamic> menuRows = menuResp is List ? menuResp : [];

      final List<MenuItemModel> items = menuRows
          .map((r) => MenuItemModel.fromMap(Map<String, dynamic>.from(r)))
          .toList();

      // group items by category
      final Map<String, List<MenuItemModel>> grouped = {};
      for (final c in loadedCats) grouped[c.id] = [];
      if (items.any((it) => it.categoryId == null || it.categoryId!.isEmpty)) grouped['uncategorized'] = [];
      for (final it in items) {
        final key = (it.categoryId == null || it.categoryId!.isEmpty) ? 'uncategorized' : it.categoryId!;
        grouped.putIfAbsent(key, () => []).add(it);
      }

      // build categories list (add 'Other' for uncategorized) — fallback 'Other'
      final cats = List<rest_model.CategoryShort>.from(loadedCats);
      if (grouped.containsKey('uncategorized') && (grouped['uncategorized']?.isNotEmpty ?? false)) {
        cats.add(rest_model.CategoryShort(id: 'uncategorized', name: 'Other')); // temporary label, will localize after frame
      }

      // assign state
      _menuByCategory = grouped;
      _categories = cats;

      // prepare keys
      _sectionKeys.clear();
      _categoryButtonKeys.clear();
      for (final c in _categories) {
        _sectionKeys[c.id] = GlobalKey();
        _categoryButtonKeys[c.id] = GlobalKey();
      }

      _categoryProximities = {for (final c in _categories) c.id: 0.0};
      if (_categories.isNotEmpty) _activeCategoryId = _categories.first.id;

      if (!mounted) return;
      setState(() => _loading = false);

      // after first frame localize 'uncategorized' label safely
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          final loc = AppLocalizations.of(context);
          final String otherLabel = loc?.other ?? 'Other';
          bool changed = false;
          for (var i = 0; i < _categories.length; i++) {
            if (_categories[i].id == 'uncategorized' && _categories[i].name != otherLabel) {
              _categories[i] = rest_model.CategoryShort(id: 'uncategorized', name: otherLabel);
              changed = true;
            }
          }
          if (changed) setState(() {});
        } catch (_) {}
        _onScroll();
      });

      // ensure initial onScroll
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    } catch (e, st) {
      debugPrint('RestaurantDetail load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ---------------------- Category menu (modal sheet) ----------------------
  void _openCategoryMenu() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        String query = '';
        final TextEditingController searchCtrl = TextEditingController();
        List<rest_model.CategoryShort> filtered = List.from(_categories);

        return StatefulBuilder(builder: (context, setStateSheet) {
          void _applyFilter(String q) {
            query = q.trim().toLowerCase();
            setStateSheet(() {
              if (query.isEmpty) filtered = List.from(_categories);
              else filtered = _categories.where((c) => c.name.toLowerCase().contains(query)).toList();
            });
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: theme.dividerColor),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            onChanged: _applyFilter,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)?.search ?? 'Search',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                          },
                          child: Text(AppLocalizations.of(context)?.done ?? 'Done'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: theme.dividerColor),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor.withOpacity(0.6)),
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        final bool isSelected = c.id == _activeCategoryId;
                        final itemCount = (_menuByCategory[c.id]?.length ?? 0);
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: isSelected ? _accent : theme.colorScheme.surfaceVariant,
                            child: Icon(Icons.fastfood, size: 18, color: isSelected ? Colors.white : theme.iconTheme.color),
                          ),
                          title: Text(c.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          subtitle: itemCount > 0 ? Text('$itemCount ${AppLocalizations.of(context)?.items ?? 'items'}') : null,
                          trailing: isSelected ? Icon(Icons.check_circle, color: _accent) : null,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            // scroll to that category and set active
                            _scrollToCategory(c.id);
                            setState(() => _activeCategoryId = c.id);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // ---------------------- Scrolling helpers ----------------------
  Future<void> _scrollToCategory(String catId) async {
    final ctx = _sectionKeys[catId]?.currentContext;
    if (ctx == null) {
      // if section not rendered, just set active and center button
      setState(() => _activeCategoryId = catId);
      _scrollCategoryButtonIntoView(catId);
      return;
    }
    _userTappedCategory = true;
    try {
      await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 360), alignment: 0.0);
    } catch (_) {}
    _scrollCategoryButtonIntoView(catId);
    setState(() => _activeCategoryId = catId);
    Future.delayed(const Duration(milliseconds: 300), () => _userTappedCategory = false);
  }

  void _scrollCategoryButtonIntoView(String catId) {
    final key = _categoryButtonKeys[catId];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null || !_categoryListController.hasClients) return;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox) return;
    final box = ro as RenderBox;

    final listRO = _categoryListController.position.context.storageContext.findRenderObject();
    if (listRO is! RenderBox) return;

    final buttonCenter = box.localToGlobal(Offset(box.size.width / 2, 0)).dx;
    final listLeft = listRO.localToGlobal(Offset.zero).dx;
    final screenCenter = (listLeft + MediaQuery.of(context).size.width) / 2;

    final target = _categoryListController.offset + (buttonCenter - screenCenter);
    _categoryListController.animateTo(
      target.clamp(0.0, _categoryListController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _centerNearestCategory() {
    if (!_categoryListController.hasClients) return;
    final listRO = _categoryListController.position.context.storageContext.findRenderObject();
    if (listRO is! RenderBox) return;
    final listLeft = listRO.localToGlobal(Offset.zero).dx;
    final screenCenter = (listLeft + MediaQuery.of(context).size.width) / 2;

    String? closestId;
    double closestDist = double.infinity;

    for (final entry in _categoryButtonKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox) continue;
      final box = ro as RenderBox;
      final center = box.localToGlobal(Offset(box.size.width / 2, 0)).dx;
      final dist = (center - screenCenter).abs();
      if (dist < closestDist) {
        closestDist = dist;
        closestId = entry.key;
      }
    }

    if (closestId != null) {
      _scrollCategoryButtonIntoView(closestId);
      setState(() => _activeCategoryId = closestId);
    }
  }

  void _onScroll() {
    if (_userTappedCategory) return;
    String? closestId;
    double closestDistance = double.infinity;
    final baseline = MediaQuery.of(context).padding.top + kToolbarHeight + _categoryBarHeight + 8;
    final Map<String, double> newProx = {};
    for (final entry in _sectionKeys.entries) {
      final key = entry.value;
      final ctx = key.currentContext;
      if (ctx == null) {
        newProx[entry.key] = 0.0;
        continue;
      }
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox) {
        newProx[entry.key] = 0.0;
        continue;
      }
      final box = ro as RenderBox;
      final global = box.localToGlobal(Offset.zero);
      final dy = global.dy - baseline;
      final absDy = dy.abs();
      if (absDy < closestDistance) {
        closestDistance = absDy;
        closestId = entry.key;
      }
      const threshold = 200.0;
      final prox = (1.0 - (absDy / threshold)).clamp(0.0, 1.0);
      newProx[entry.key] = prox;
    }

    final changed = _activeCategoryId != closestId || !_mapEquals(_categoryProximities, newProx);
    if (changed) {
      setState(() {
        _activeCategoryId = closestId;
        _categoryProximities = newProx;
      });
      if (closestId != null) _scrollCategoryButtonIntoView(closestId);
    }

    final expandedHeight = _appBarExpanded + _infoCardOverlap;
    final threshold = expandedHeight - kToolbarHeight - (_infoCardOverlap / 2) - _gapAfterInfoCard;
    final pinned = _scrollController.hasClients && _scrollController.offset >= threshold;
    if (pinned != _categoryPinned) setState(() => _categoryPinned = pinned);
  }

  bool _mapEquals(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) if ((a[k] ?? 0.0) != (b[k] ?? 0.0)) return false;
    return true;
  }

  // ---------------------- Search ----------------------
  void _onSearchPressed() {
    final allItems = _menuByCategory.values.expand((e) => e).toList();
    showSearch<MenuItemModel?>(
      context: context,
      delegate: _MenuItemSearchDelegate(allItems),
    );
  }

  // ---------------------- UI building ----------------------

  Widget _buildCover(String? cover) {
    final theme = Theme.of(context);
    if (cover != null && cover.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: cover,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: theme.colorScheme.surfaceVariant.withOpacity(0.6)),
        errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceVariant.withOpacity(0.6)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary.withOpacity(0.12), theme.colorScheme.primaryContainer.withOpacity(0.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildInfoCard(rest_model.RestaurantBasic rest, String? logoUrl) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: theme.shadowColor.withOpacity(0.10), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: _logoSize,
              height: _logoSize,
              color: theme.colorScheme.surfaceVariant,
              child: logoUrl != null && logoUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: logoUrl, fit: BoxFit.cover, placeholder: (_, __) => Container(color: theme.colorScheme.surfaceVariant))
                  : Icon(Icons.storefront_outlined, size: 36, color: theme.iconTheme.color?.withOpacity(0.6)),
            ),
          ),

          const SizedBox(width: 12),

          // Middle column: name, description and small meta
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rest.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Container(height: 2, width: 64, decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2))),

                const SizedBox(height: 8),

                // Short description
                Text(
                  rest.description ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8)),
                ),

                const SizedBox(height: 8),

                // Row for prep time and delivery
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: theme.iconTheme.color?.withOpacity(0.7)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _prepTimeText(rest.prepMin, rest.prepMax, rest.id),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _dot(),
                    const SizedBox(width: 10),
                    Icon(Icons.delivery_dining, size: 16, color: theme.iconTheme.color?.withOpacity(0.7)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        rest.deliveryFee == null ? '-' : (rest.deliveryFee == 0 ? (loc?.deliveryFree ?? 'Free') : (loc?.currency(rest.deliveryFee!.toStringAsFixed(2)) ?? rest.deliveryFee!.toStringAsFixed(2)) ),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Fixed icon on the right
          Icon(Icons.chevron_right, color: theme.iconTheme.color?.withOpacity(0.38)),
        ],
      ),
    );
  }

  Widget _dot() => Container(width: 6, height: 6, decoration: BoxDecoration(color: Theme.of(context).dividerColor, shape: BoxShape.circle));

  String _prepTimeText(int? min, int? max, String id) {
    final loc = AppLocalizations.of(context);
    final rnd = Random(id.hashCode);
    const maxShift = 5;
    if (min != null && max != null) {
      final shiftMin = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final shiftMax = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final newMin = (min + shiftMin).clamp(1, 999);
      final newMax = (max + shiftMax).clamp(newMin, 999);
      return loc?.prepRange(newMax, newMin) ?? '$newMin-${newMax} ${loc?.mins(0) ?? 'mins'}';
    } else if (min != null) {
      final shift = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      return loc?.mins((min + shift).clamp(1, 999)) ?? '${(min + shift).clamp(1, 999)} mins';
    } else if (max != null) {
      final shift = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      return loc?.mins((max + shift).clamp(1, 999)) ?? '${(max + shift).clamp(1, 999)} mins';
    } else {
      final base = 30 + (rnd.nextInt(11) - 5);
      return loc?.mins(base) ?? '$base mins';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_loading) return const Scaffold(body: SafeArea(child: Center(child: CircularProgressIndicator())));
    if (_error != null) return Scaffold(appBar: AppBar(title: Text(loc?.restaurant ?? 'Restaurant')), body: Center(child: Text(loc?.errorMessage(_error ?? '') ?? _error!)));

    final rest = _restaurantBasic!;
    final cover = rest.coverUrl ?? widget.initialCover;
    final logo = rest.logoUrl ?? widget.initialLogo;

    final expandedHeight = _appBarExpanded + _infoCardOverlap;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: expandedHeight,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              color: theme.appBarTheme.iconTheme?.color ?? theme.iconTheme.color,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              IconButton(onPressed: _onSearchPressed, icon: const Icon(Icons.search), color: theme.appBarTheme.actionsIconTheme?.color ?? theme.iconTheme.color),
              const SizedBox(width: 6),
            ],
            flexibleSpace: LayoutBuilder(builder: (context, constraints) {
              final minH = kToolbarHeight + MediaQuery.of(context).padding.top;
              final available = (expandedHeight - minH).clamp(0.0, double.infinity);
              final t = ((constraints.maxHeight - minH) / (available == 0 ? 1 : available)).clamp(0.0, 1.0);

              final topOverlayOpacity = (1.0 - t).clamp(0.0, 1.0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(cover),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withOpacity(0.18 * t)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: MediaQuery.of(context).padding.top + kToolbarHeight,
                    child: IgnorePointer(
                      child: Container(color: _accent.withOpacity(topOverlayOpacity)),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: -(_infoCardOverlap / 2) + (1.0 - t) * 24.0,
                    child: SafeArea(
                      bottom: false,
                      child: Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(0, (1.0 - t) * 12.0),
                          child: IgnorePointer(
                            ignoring: t < 0.12,
                            child: _buildInfoCard(rest, logo),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          SliverToBoxAdapter(child: SizedBox(height: _gapAfterInfoCard)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _CategoryBarDelegate(
              minExtent: _categoryBarHeight,
              maxExtent: _categoryBarHeight,
              builder: (context, _) {
                final backgroundColor = _categoryPinned ? _accent : Theme.of(context).cardColor;
                return Container(
                  height: _categoryBarHeight,
                  color: backgroundColor,
                  child: Material(
                    color: backgroundColor,
                    elevation: 2,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        // هنا حولت الـ menu button ليفتح قائمة الكاتيجورى الاحترافية
                        GestureDetector(
                          onTap: _openCategoryMenu,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
                            child: Icon(Icons.list, size: 20, color: _categoryPinned ? Colors.white : Theme.of(context).iconTheme.color),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notif) {
                              if (notif is ScrollEndNotification || (notif is UserScrollNotification && notif.direction == ScrollDirection.idle)) {
                                _snapTimer?.cancel();
                                _snapTimer = Timer(const Duration(milliseconds: 120), () => _centerNearestCategory());
                              }
                              return false;
                            },
                            child: ListView.separated(
                              controller: _categoryListController,
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              itemCount: _categories.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, idx) {
                                final c = _categories[idx];
                                final selected = c.id == _activeCategoryId;
                                final prox = (_categoryProximities[c.id] ?? (selected ? 1.0 : 0.0)).clamp(0.0, 1.0);

                                // more polished pill styling
                                final Color pillColor = _categoryPinned
                                    ? (selected ? Colors.white.withOpacity(0.14) : Colors.transparent)
                                    : (selected ? _accent : Theme.of(context).cardColor);
                                final Color borderColor = _categoryPinned ? Colors.transparent : (selected ? Colors.transparent : Theme.of(context).dividerColor);
                                final Color textColor = _categoryPinned ? Colors.white : (selected ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87);
                                final double buttonInnerHeight = max(40.0, _categoryBarHeight - 18);

                                return GestureDetector(
                                  key: _categoryButtonKeys[c.id],
                                  onTap: () => _scrollToCategory(c.id),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    decoration: BoxDecoration(
                                      color: pillColor,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: borderColor),
                                      boxShadow: selected && !_categoryPinned ? [BoxShadow(color: _accent.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 4))] : null,
                                    ),
                                    child: SizedBox(
                                      height: buttonInnerHeight,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          Flexible(
                                            fit: FlexFit.loose,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.circle, size: 8, color: _categoryPinned ? Colors.white60 : (selected ? Colors.white60 : Theme.of(context).dividerColor)),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(c.name, style: TextStyle(color: textColor, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 220),
                                            width: selected ? 28 : (prox > 0.35 ? 18 : 0),
                                            height: 3,
                                            decoration: BoxDecoration(
                                              color: prox > 0.35 ? (selected ? (_categoryPinned ? Colors.white : Colors.white) : _accent) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: const SizedBox(height: 8)),
          // menu sections
          for (final cat in _categories) ...[
            SliverToBoxAdapter(
              child: Padding(
                key: _sectionKeys[cat.id],
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(cat.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ),
            if ((_menuByCategory[cat.id] ?? []).isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Text(AppLocalizations.of(context)?.no_items ?? 'No items', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7))),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.65),
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final item = _menuByCategory[cat.id]![index];
                      return _MenuItemCard(item: item);
                    },
                    childCount: _menuByCategory[cat.id]!.length,
                  ),
                ),
              ),
            SliverToBoxAdapter(child: const SizedBox(height: 8)),
          ],
          SliverToBoxAdapter(child: const SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class _CategoryBarDelegate extends SliverPersistentHeaderDelegate {
  final double minExtent;
  final double maxExtent;
  final Widget Function(BuildContext, double) builder;

  _CategoryBarDelegate({required this.minExtent, required this.maxExtent, required this.builder});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => builder(context, shrinkOffset);

  @override
  bool shouldRebuild(covariant _CategoryBarDelegate oldDelegate) => oldDelegate.maxExtent != maxExtent || oldDelegate.minExtent != minExtent;

  @override
  FloatingHeaderSnapConfiguration? get snapConfiguration => null;
}

class _MenuItemCard extends StatelessWidget {
  final MenuItemModel item;
  const _MenuItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final double discounted = item.effectivePrice();
    final bool hasDiscount =
        item.hasDiscount && (item.discountPercent > 0.0) && (discounted < item.price);
    final theme = Theme.of(context);

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      shadowColor: theme.shadowColor.withOpacity(0.08),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: item.id)),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: LayoutBuilder(builder: (context, constraints) {
            final double width = constraints.maxWidth;
            final double maxHeight = constraints.maxHeight;

            // layout calculations omitted for brevity (same as before)
            const double outerVerticalPadding = 8.0 * 2;
            const double gapBetweenImageAndContent = 8.0;
            const double bottomSafeSpacing = 8.0;
            const double minReservedForText = 56.0;

            double availableForImage = maxHeight.isFinite
                ? (maxHeight -
                outerVerticalPadding -
                gapBetweenImageAndContent -
                bottomSafeSpacing -
                minReservedForText -
                6)
                : double.infinity;

            double imageHeight;
            if (availableForImage.isFinite && availableForImage > 40) {
              imageHeight = min(width * 0.7, availableForImage);
            } else if (maxHeight.isFinite && maxHeight > 0) {
              imageHeight = maxHeight * 0.45;
            } else {
              imageHeight = width * 0.7;
            }

            imageHeight = imageHeight.clamp(56.0, width * 0.95);

            return Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: item.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: Theme.of(context).colorScheme.surfaceVariant),
                            errorWidget: (_, __, ___) => Container(
                              color: Theme.of(context).colorScheme.surfaceVariant,
                              child: const Icon(Icons.fastfood),
                            ),
                          )
                        else
                          Container(color: Theme.of(context).colorScheme.surfaceVariant, child: const Icon(Icons.fastfood)),
                        if (hasDiscount)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.shade700,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '-${item.discountPercent.toStringAsFixed(item.discountPercent.truncateToDouble() == item.discountPercent ? 0 : 1)}%',
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: gapBetweenImageAndContent),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                      ),

                      const Spacer(),

                      if (hasDiscount)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: width * 0.82),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  loc?.currency(item.price.toStringAsFixed(2)) ?? item.price.toStringAsFixed(2),
                                  style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough, color: theme.textTheme.bodySmall?.color),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: width * 0.78),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      loc?.currency(discounted.toStringAsFixed(2)) ?? discounted.toStringAsFixed(2),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: width),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              loc?.currency(item.price.toStringAsFixed(2)) ?? item.price.toStringAsFixed(2),
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: bottomSafeSpacing),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// --------- Search Delegate for menu items (local search over loaded items) ----------
class _MenuItemSearchDelegate extends SearchDelegate<MenuItemModel?> {
  final List<MenuItemModel> items;

  _MenuItemSearchDelegate(this.items) : super(searchFieldLabel: 'Search items');

  List<MenuItemModel> _filtered(String q) {
    final ql = q.trim().toLowerCase();
    if (ql.isEmpty) return items;
    return items.where((i) {
      final name = i.name.toLowerCase();
      final desc = (i.description ?? '').toLowerCase();
      return name.contains(ql) || desc.contains(ql);
    }).toList();
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty) IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))
  ];

  @override
  Widget buildResults(BuildContext context) {
    final results = _filtered(query);
    if (results.isEmpty) return Center(child: Text('No items found'));
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final it = results[idx];
        return ListTile(
          leading: it.imageUrl != null && it.imageUrl!.isNotEmpty
              ? ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 56, height: 56, child: CachedNetworkImage(imageUrl: it.imageUrl!, fit: BoxFit.cover)))
              : const SizedBox(width: 56, height: 56, child: Icon(Icons.fastfood)),
          title: Text(it.name),
          subtitle: it.description != null ? Text(it.description!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
          trailing: Text('${it.effectivePrice().toStringAsFixed(2)}'),
          onTap: () {
            // navigate to item detail
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: it.id)));
            close(context, it);
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = _filtered(query);
    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, idx) {
        final it = suggestions[idx];
        return ListTile(
          leading: it.imageUrl != null && it.imageUrl!.isNotEmpty
              ? ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 56, height: 56, child: CachedNetworkImage(imageUrl: it.imageUrl!, fit: BoxFit.cover)))
              : const SizedBox(width: 56, height: 56, child: Icon(Icons.fastfood)),
          title: Text(it.name),
          subtitle: it.description != null ? Text(it.description!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: it.id)));
            close(context, it);
          },
        );
      },
    );
  }
}
