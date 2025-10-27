// lib/screens/category_restaurants_screen.dart
// Rewritten: ensure visible containers in Light mode (scaffold not pure white),
// give consistent shadows to all cards, dark/light friendly.
// Search field exactly matches the visual style from SearchAdsBannerMulti.

import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:talabak_users/services/restaurant_service.dart';
import 'package:talabak_users/utils/location_helper.dart';
import 'package:talabak_users/screens/restaurant_detail_screen.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

const Color kPrimaryColor = Color(0xFFFF5C01);

enum SortOption { aToZ, fastDelivery, under45, closer }

class CategoryRestaurantsScreen extends StatefulWidget {
  final String categoryName;
  final int? restaurantTypeId;

  const CategoryRestaurantsScreen({Key? key, required this.categoryName, this.restaurantTypeId}) : super(key: key);

  @override
  State<CategoryRestaurantsScreen> createState() => _CategoryRestaurantsScreenState();
}

class _CategoryRestaurantsScreenState extends State<CategoryRestaurantsScreen> with TickerProviderStateMixin {
  late Future<List<NearestRestaurant>> _futureRestaurantsRpc;
  late Future<List<Map<String, dynamic>>> _futureRestaurantsByType;

  final TextEditingController _searchController = TextEditingController();
  SortOption _selectedSort = SortOption.aToZ;
  bool _isSearching = false;

  bool _bannerVisible = false;
  String _bannerMessage = '';
  bool _bannerIsError = false;

  final List<AnimationController> _itemControllers = [];

  static const double _fallbackLat = 30.0444;
  static const double _fallbackLon = 31.2357;

  final SupabaseClient _supabase = Supabase.instance.client;
  int _lastAnimatedCount = 0;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(statusBarColor: kPrimaryColor));

    if (widget.restaurantTypeId != null) {
      _futureRestaurantsByType = _fetchRestaurantsByType(widget.restaurantTypeId!);
    } else {
      _futureRestaurantsRpc = _fetchAndPrepareRestaurantsRpc();
    }

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    for (final c in _itemControllers) {
      c.dispose();
    }
    _itemControllers.clear();
    super.dispose();
  }

  Future<List<NearestRestaurant>> _fetchAndPrepareRestaurantsRpc() async {
    try {
      final pos = await determinePosition();
      final lat = pos?.latitude ?? _fallbackLat;
      final lon = pos?.longitude ?? _fallbackLon;

      if (kDebugMode) debugPrint('[CategoryRestaurantsScreen] pos -> $lat,$lon');

      final nearby = await getNearestRestaurants(lat: lat, lon: lon, limit: 200, category: widget.categoryName);

      // dedupe by restaurantId keeping nearest branch
      final Map<String, NearestRestaurant> byRestaurant = {};
      for (final item in nearby) {
        final existing = byRestaurant[item.restaurantId];
        if (existing == null) byRestaurant[item.restaurantId] = item;
        else {
          final existingDist = existing.distanceMeters ?? double.infinity;
          final newDist = item.distanceMeters ?? double.infinity;
          if (newDist < existingDist) byRestaurant[item.restaurantId] = item;
        }
      }

      final deduped = byRestaurant.values.toList();
      return deduped;
    } catch (e, st) {
      if (kDebugMode) debugPrint('RPC fetch error: $e\n$st');
      final msg = _friendlyErrorMessage(e);
      _showBanner(msg, isError: true);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRestaurantsByType(int typeId) async {
    try {
      final linkResp = await _supabase.from('restaurant_restaurant_types').select('restaurant_id').eq('type_id', typeId);

      final ids = <String>[];
      if (linkResp is List) {
        for (final r in linkResp) {
          final rid = r['restaurant_id'];
          if (rid != null) ids.add(rid.toString());
        }
      }

      if (ids.isEmpty) return [];

      final idsList = ids.map((e) => e.toString()).toList();

      final resp = await _supabase
          .from('restaurants')
          .select('id, name, logo_url, prep_time_min, prep_time_max, is_open, is_hidden, status, delivery_fee, category')
          .filter('id', 'in', '(${idsList.join(',')})')
          .eq('status', 'accept')
          .eq('is_hidden', false)
          .order('name', ascending: true)
          .limit(500);

      final rows = <Map<String, dynamic>>[];
      if (resp is List) for (final r in resp) rows.add(Map<String, dynamic>.from(r as Map));

      return rows;
    } catch (e, st) {
      if (kDebugMode) debugPrint('DB fetch error: $e\n$st');
      final msg = _friendlyErrorMessage(e);
      _showBanner(msg, isError: true);
      rethrow;
    }
  }

  List<NearestRestaurant> _filterAndSortNearest(List<NearestRestaurant> source) {
    final q = _searchController.text.trim().toLowerCase();
    List<NearestRestaurant> list = source.where((r) {
      if (q.isEmpty) return true;
      final nameMatch = r.restaurantName.toLowerCase().contains(q);
      final addrMatch = r.branchAddress.toLowerCase().contains(q);
      return nameMatch || addrMatch;
    }).toList();

    switch (_selectedSort) {
      case SortOption.aToZ:
        list.sort((a, b) => a.restaurantName.toLowerCase().compareTo(b.restaurantName.toLowerCase()));
        break;
      case SortOption.fastDelivery:
        list.sort((a, b) {
          final aScore = (a.prepMax ?? a.prepMin ?? 9999);
          final bScore = (b.prepMax ?? b.prepMin ?? 9999);
          if (aScore != bScore) return aScore.compareTo(bScore);
          return (a.distanceMeters ?? double.infinity).compareTo(b.distanceMeters ?? double.infinity);
        });
        break;
      case SortOption.under45:
        list = list.where((r) {
          final max = r.prepMax ?? r.prepMin;
          final min = r.prepMin;
          if (max != null) return max <= 45;
          if (min != null) return min <= 45;
          return false;
        }).toList();
        list.sort((a, b) => (a.distanceMeters ?? double.infinity).compareTo(b.distanceMeters ?? double.infinity));
        break;
      case SortOption.closer:
        list.sort((a, b) => (a.distanceMeters ?? double.infinity).compareTo(b.distanceMeters ?? double.infinity));
        break;
    }

    return list;
  }

  List<Map<String, dynamic>> _filterAndSortMaps(List<Map<String, dynamic>> source) {
    final q = _searchController.text.trim().toLowerCase();
    List<Map<String, dynamic>> list = source.where((r) {
      if (q.isEmpty) return true;
      final name = (r['name'] ?? '').toString().toLowerCase();
      final cat = (r['category'] ?? '').toString().toLowerCase();
      return name.contains(q) || cat.contains(q);
    }).toList();

    switch (_selectedSort) {
      case SortOption.aToZ:
        list.sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
        break;
      case SortOption.fastDelivery:
        list.sort((a, b) {
          final aScore = (a['prep_time_max'] ?? a['prep_time_min'] ?? 9999) as int;
          final bScore = (b['prep_time_max'] ?? b['prep_time_min'] ?? 9999) as int;
          return aScore.compareTo(bScore);
        });
        break;
      case SortOption.under45:
        list = list.where((r) {
          final max = r['prep_time_max'] as int?;
          final min = r['prep_time_min'] as int?;
          if (max != null) return max <= 45;
          if (min != null) return min <= 45;
          return false;
        }).toList();
        break;
      case SortOption.closer:
        break;
    }

    return list;
  }

  Future<void> _refresh() async {
    if (widget.restaurantTypeId != null) {
      setState(() {
        _futureRestaurantsByType = _fetchRestaurantsByType(widget.restaurantTypeId!);
      });
      try {
        await _futureRestaurantsByType;
      } catch (_) {}
    } else {
      setState(() {
        _futureRestaurantsRpc = _fetchAndPrepareRestaurantsRpc();
      });
      try {
        await _futureRestaurantsRpc;
      } catch (_) {}
    }
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _isSearching = _searchController.text.trim().isNotEmpty;
    });
  }

  void _onSortSelected(SortOption option) {
    if (_selectedSort == option) return;
    if (!mounted) return;
    setState(() {
      _selectedSort = option;
    });
  }

  AnimationController _ensureItemController(int index) {
    while (_itemControllers.length <= index) {
      final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
      _itemControllers.add(c);
    }
    return _itemControllers[index];
  }

  void _prepareAndRunStaggered(int count) {
    for (int i = 0; i < count; i++) {
      _ensureItemController(i);
      _itemControllers[i].reset();
    }
    if (_itemControllers.length > count) {
      for (int i = _itemControllers.length - 1; i >= count; i--) {
        _itemControllers[i].dispose();
        _itemControllers.removeAt(i);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (int i = 0; i < count && i < _itemControllers.length; i++) {
        Future.delayed(Duration(milliseconds: 40 * i), () {
          if (mounted) _itemControllers[i].forward();
        });
      }
    });
    _lastAnimatedCount = count;
  }

  void _showBanner(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _bannerMessage = message;
      _bannerIsError = isError;
      _bannerVisible = true;
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _bannerVisible = false);
    });
  }

  String _friendlyErrorMessage(dynamic e) {
    final loc = AppLocalizations.of(context);
    final raw = e?.toString() ?? '';
    if (e is SocketException || raw.contains('SocketException') || raw.contains('Failed host lookup') || raw.toLowerCase().contains('network')) {
      return loc?.no_network_short ?? 'No internet connection';
    }
    return loc?.somethingWentWrong ?? 'Something went wrong';
  }

  bool _looksLikeNetworkError(Object? err) {
    if (err == null) return false;
    final s = err.toString().toLowerCase();
    if (err is SocketException) return true;
    if (s.contains('socketexception') || s.contains('failed host lookup') || s.contains('network') || s.contains('host lookup')) return true;
    return false;
  }

  String _formatPrepWithVariation(String idSeed, int? min, int? max) {
    final seed = idSeed.hashCode;
    final rnd = Random(seed);
    const int maxShift = 5;
    final t = AppLocalizations.of(context);

    if (min != null && max != null) {
      final shiftMin = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final shiftMax = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final newMin = (min + shiftMin).clamp(1, 999);
      final newMax = (max + shiftMax).clamp(newMin, 999);
      return '$newMin - $newMax ${t?.minutes ?? 'mins'}';
    } else if (min != null) {
      final shift = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final newMin = (min + shift).clamp(1, 999);
      return '$newMin ${t?.minutes ?? 'mins'}';
    } else if (max != null) {
      final shift = rnd.nextInt(maxShift + 1) - (maxShift ~/ 2);
      final newMax = (max + shift).clamp(1, 999);
      return '$newMax ${t?.minutes ?? 'mins'}';
    } else {
      final base = 30 + (rnd.nextInt(11) - 5);
      return '$base ${t?.minutes ?? 'mins'}';
    }
  }

  String _formatFee(dynamic fee) {
    final t = AppLocalizations.of(context);
    if (fee == null) return t?.deliveryFree ?? 'Free';
    double? f;
    if (fee is double) f = fee;
    else if (fee is num) f = fee.toDouble();
    else f = double.tryParse(fee.toString());
    if (f == null || f == 0) return t?.deliveryFree ?? 'Free';
    return t?.deliveryFee(f.toStringAsFixed(2)) ?? '${f.toStringAsFixed(2)} EGP';
  }

  Widget _sortChipsRow() {
    final t = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _sortChip(t?.sortAToZ ?? 'A to Z', SortOption.aToZ),
          const SizedBox(width: 8),
          _sortChip(t?.sortFastDelivery ?? 'Fast delivery', SortOption.fastDelivery),
          const SizedBox(width: 8),
          _sortChip(t?.sortUnder45 ?? 'Under 45 mins', SortOption.under45),
          const SizedBox(width: 8),
          _sortChip(t?.sortCloser ?? 'Closer to site', SortOption.closer),
        ],
      ),
    );
  }

  Widget _sortChip(String label, SortOption option) {
    final selected = _selectedSort == option;
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: selected ? Colors.white : theme.textTheme.bodyLarge?.color)),
        selected: selected,
        onSelected: (_) => _onSortSelected(option),
        selectedColor: kPrimaryColor,
        backgroundColor: theme.cardColor,
        elevation: selected ? 4 : 1,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildCardFromMap(Map<String, dynamic> r, int index) {
    final id = r['id']?.toString() ?? '';
    final logo = (r['logo_url'] ?? '')?.toString();
    final name = (r['name'] ?? '').toString();
    final isOpen = r['is_open'] == true;

    final controller = _ensureItemController(index);
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeOutExpo);

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(animation),
        child: AnimatedRestaurantCard(
          logoUrl: logo,
          title: name,
          subtitle: _formatPrepWithVariation(id, r['prep_time_min'] as int?, r['prep_time_max'] as int?),
          openText: isOpen ? (AppLocalizations.of(context)?.open ?? 'Open') : (AppLocalizations.of(context)?.closed ?? 'Closed'),
          open: isOpen,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: id, initialLogo: logo, initialName: name))),
        ),
      ),
    );
  }

  Widget _buildCardFromNearest(NearestRestaurant r, int index) {
    final controller = _ensureItemController(index);
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeOutExpo);

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(animation),
        child: AnimatedRestaurantCard(
          logoUrl: r.logoUrl,
          title: r.restaurantName,
          subtitle: r.branchAddress.isNotEmpty ? r.branchAddress : _formatPrepWithVariation(r.restaurantId, r.prepMin, r.prepMax),
          openText: (r.prepMin != null || r.prepMax != null) ? _formatPrepWithVariation(r.restaurantId, r.prepMin, r.prepMax) : null,
          open: true,
          trailingSmall: r.distanceMeters != null ? Text(AppLocalizations.of(context)?.distance((r.distanceMeters! / 1000).toStringAsFixed(1)) ?? '${(r.distanceMeters! / 1000).toStringAsFixed(1)} km', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)) : null,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: r.restaurantId, initialLogo: r.logoUrl, initialName: r.restaurantName))),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, {double minHeight = 200}) {
    return SizedBox(
      height: minHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu, size: 56, color: kPrimaryColor.withOpacity(0.9)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerWidget(String message, bool isError) {
    final theme = Theme.of(context);
    final accent = isError ? theme.colorScheme.error : Colors.green.shade600;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.12)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.6 : 0.06), blurRadius: 12, spreadRadius: 1, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withOpacity(0.12)), child: Icon(isError ? Icons.error_outline : Icons.check_circle, color: accent)),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.textTheme.bodyLarge?.color))),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineState(AppLocalizations? t, {double minHeight = 240}) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final line1 = isAr ? 'لا يوجد اتصال بالإنترنت' : 'No internet connection';
    final line2 = isAr ? 'تحقق من الاتصال وأعد المحاولة' : 'Please check your connection and try again';
    return SizedBox(
      height: minHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 92, color: Colors.grey.shade400),
            const SizedBox(height: 18),
            Text(line1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(line2, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () async => await _refresh(),
              icon: const Icon(Icons.refresh),
              label: Text(t?.retry ?? (isAr ? 'إعادة المحاولة' : 'Retry')),
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final title = widget.categoryName;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // IMPORTANT: make scaffold bg slightly off-white in light mode so cards are visible
    final scaffoldBg = isDark ? theme.colorScheme.background : Colors.grey[50];

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(title),
        backgroundColor: kPrimaryColor,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(statusBarColor: kPrimaryColor),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: kPrimaryColor,
        child: widget.restaurantTypeId != null
            ? FutureBuilder<List<Map<String, dynamic>>>(
          future: _futureRestaurantsByType,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))],
              );
            }

            if (snapshot.hasError) {
              final err = snapshot.error;
              if (_looksLikeNetworkError(err)) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [_buildOfflineState(t, minHeight: MediaQuery.of(context).size.height - 160)],
                );
              } else {
                final errMsg = snapshot.error?.toString() ?? 'Unknown error';
                final userMsg = t?.errorMessage(errMsg) ?? 'Error: $errMsg';
                if (kDebugMode) debugPrint('CategoryRestaurantsScreen (byType) error: $errMsg');
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [SizedBox(height: MediaQuery.of(context).size.height - 160, child: Center(child: Text(userMsg, textAlign: TextAlign.center)))],
                );
              }
            }

            final raw = snapshot.data ?? <Map<String, dynamic>>[];
            final items = _filterAndSortMaps(raw);

            if (_lastAnimatedCount != items.length) _prepareAndRunStaggered(items.length);

            if (raw.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 24),
                  _buildEmptyState(t?.noRestaurantsCategory ?? 'No restaurants found in this category.', minHeight: 200),
                  const SizedBox(height: 120),
                ],
              );
            }

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: _buildSearchField(theme),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t?.allRestaurants ?? 'All restaurants', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(t?.results(items.length) ?? '${items.length} results', style: TextStyle(color: theme.textTheme.bodySmall?.color)),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
                SliverToBoxAdapter(child: _sortChipsRow()),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _bannerVisible ? _buildBannerWidget(_bannerMessage, _bannerIsError) : const SizedBox.shrink(),
                    crossFadeState: _bannerVisible ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 300),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        return Column(
                          children: [
                            _buildCardFromMap(items[index], index),
                            if (index != items.length - 1) const SizedBox(height: 12),
                          ],
                        );
                      },
                      childCount: items.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        )
            : FutureBuilder<List<NearestRestaurant>>(
          future: _futureRestaurantsRpc,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))],
              );
            }

            if (snapshot.hasError) {
              final err = snapshot.error;
              if (_looksLikeNetworkError(err)) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [_buildOfflineState(t, minHeight: MediaQuery.of(context).size.height - 160)],
                );
              } else {
                final errMsg = snapshot.error?.toString() ?? 'Unknown error';
                final userMsg = t?.errorMessage(errMsg) ?? 'Error: $errMsg';
                if (kDebugMode) debugPrint('CategoryRestaurantsScreen FutureBuilder error: $errMsg');
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [SizedBox(height: MediaQuery.of(context).size.height - 160, child: Center(child: Text(userMsg, textAlign: TextAlign.center)))],
                );
              }
            }

            final raw = snapshot.data ?? <NearestRestaurant>[];
            final items = _filterAndSortNearest(raw);

            if (_lastAnimatedCount != items.length) _prepareAndRunStaggered(items.length);

            if (raw.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 24),
                  _buildEmptyState(t?.noRestaurantsCategory ?? 'No restaurants found in this category.', minHeight: 200),
                  const SizedBox(height: 120),
                ],
              );
            }

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: _buildSearchField(theme),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t?.allRestaurants ?? 'All restaurants', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(t?.results(items.length) ?? '${items.length} results', style: TextStyle(color: theme.textTheme.bodySmall?.color)),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
                SliverToBoxAdapter(child: _sortChipsRow()),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _bannerVisible ? _buildBannerWidget(_bannerMessage, _bannerIsError) : const SizedBox.shrink(),
                    crossFadeState: _bannerVisible ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 300),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        return Column(
                          children: [
                            _buildCardFromNearest(items[index], index),
                            if (index != items.length - 1) const SizedBox(height: 12),
                          ],
                        );
                      },
                      childCount: items.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- exact professional search field styling (copied to match SearchAdsBannerMulti) ----
  Widget _buildSearchField(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    // Styling matches SearchAdsBannerMulti:
    // - Dark: inner background black, typed text & hint use primary color, prefix icon uses primary.
    // - Light: inner background white, text black, border subtle dark.
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
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      child: Material(
        color: Colors.transparent,
        elevation: isDark ? 8 : 3,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.6 : 0.04), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _refresh(),
            cursorColor: const Color(0xFFFF5C01),
            style: TextStyle(fontSize: 16, color: typedTextColor),
            onChanged: (_) => _onSearchChanged(),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)?.searchNewHint ?? 'Search restaurants or items...',
              hintStyle: TextStyle(color: hintColor),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12.0, right: 6.0),
                child: Icon(Icons.search, color: _isSearching ? kPrimaryColor : iconColor, size: 22),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 48),
              suffixIcon: _searchController.text.isNotEmpty
                  ? GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _onSearchChanged();
                  FocusScope.of(context).unfocus();
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: Icon(Icons.close, size: 20, color: isDark ? const Color(0xFFFF5C01) : Colors.black54),
                ),
              )
                  : null,
              filled: true,
              fillColor: fillColor,
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              enabledBorder: enabledBorder,
              focusedBorder: focusedBorder,
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------ Animated restaurant card ------------------
class AnimatedRestaurantCard extends StatefulWidget {
  final String? logoUrl;
  final String title;
  final String subtitle;
  final String? openText;
  final bool open;
  final Widget? trailingSmall;
  final VoidCallback? onTap;

  const AnimatedRestaurantCard({
    Key? key,
    this.logoUrl,
    required this.title,
    required this.subtitle,
    this.openText,
    required this.open,
    this.trailingSmall,
    this.onTap,
  }) : super(key: key);

  @override
  State<AnimatedRestaurantCard> createState() => _AnimatedRestaurantCardState();
}

class _AnimatedRestaurantCardState extends State<AnimatedRestaurantCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _hoverAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _hoverAnim = Tween<double>(begin: 1.0, end: 0.985).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _buildStatusPill({
    required BuildContext context,
    required String text,
    required bool isOpen,
  }) {
    final theme = Theme.of(context);
    final bg = isOpen ? kPrimaryColor.withOpacity(0.12) : theme.dividerColor.withOpacity(0.06);
    final border = kPrimaryColor.withOpacity(0.14);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: kPrimaryColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        if (widget.onTap != null) widget.onTap!();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _hoverAnim,
        child: Material(
          color: theme.cardColor,
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          shadowColor: Colors.black.withOpacity(isDark ? 0.6 : 0.06),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: widget.logoUrl != null
                      ? CachedNetworkImage(
                    imageUrl: widget.logoUrl!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    placeholder: (c, s) => SizedBox(width: 72, height: 72, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kPrimaryColor))),
                    errorWidget: (c, s, e) => Container(width: 72, height: 72, color: Colors.grey.shade200, child: const Icon(Icons.restaurant)),
                  )
                      : Container(width: 72, height: 72, color: Colors.grey.shade200, child: const Icon(Icons.restaurant)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (widget.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(widget.subtitle, style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatusPill(
                      context: context,
                      text: widget.openText ?? (widget.open ? (AppLocalizations.of(context)?.open ?? 'Open') : (AppLocalizations.of(context)?.closed ?? 'Closed')),
                      isOpen: widget.open,
                    ),
                    if (widget.trailingSmall != null) ...[
                      const SizedBox(height: 8),
                      widget.trailingSmall!,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
