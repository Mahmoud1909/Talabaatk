// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/screens/category_restaurants_screen.dart';
import 'package:talabak_users/screens/restaurant_detail_screen.dart';
import 'package:talabak_users/services/category_service.dart';
import 'package:talabak_users/services/restaurant_service.dart';
import 'package:talabak_users/utils/category_model.dart';
import 'package:talabak_users/widgets/SearchAdsBannerMulti.dart';
import 'package:talabak_users/widgets/AdsBanner.dart';
import 'package:talabak_users/widgets/big_brands_near_you.dart';
import 'package:talabak_users/widgets/categories_row.dart';
import 'package:talabak_users/widgets/offers_widget.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

const Color kPrimaryColor = Color(0xFFFF5C01);

/// HomeScreen: enhanced with polished animations and a
/// distinctive overlay banner system for user messages
class HomeScreen extends StatefulWidget {
  final String restaurantId;

  const HomeScreen({Key? key, required this.restaurantId}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late Future<List<CategoryModel>> _futureCats;
  late Future<List<NearestRestaurant>> _futureRestaurants;
  late Future<bool> _offersFuture;

  String? _selectedCategoryName;

  // root animation controller for entrance/stagger effects
  late final AnimationController _rootAnim;

  @override
  void initState() {
    super.initState();
    _rootAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _rootAnim.forward();

    _loadCategories();
    _loadNearestRestaurants();
    _offersFuture = _checkHasOffers();

    // Keep status bar color in sync with app bar / brand color
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: kPrimaryColor,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _rootAnim.dispose();
    super.dispose();
  }

  void _loadCategories() {
    _futureCats = getAllCategories();
  }

  void _loadNearestRestaurants({String? categoryName}) {
    // Example fallback coords; replace with real location helper if available
    _futureRestaurants = getNearestRestaurants(
      lat: 30.0444,
      lon: 31.2357,
      limit: 12,
      category: categoryName,
    );
  }

  Future<bool> _checkHasOffers() async {
    try {
      final resp = await Supabase.instance.client.from('offers').select('id').eq('is_active', true).limit(1);
      return resp is List && resp.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loadCategories();
      _loadNearestRestaurants(categoryName: _selectedCategoryName);
      _offersFuture = _checkHasOffers();
    });

    try {
      await Future.wait([_futureCats, _futureRestaurants, _offersFuture]);
    } catch (e) {
      // show professional error banner overlay (translatable string recommended)
      MessageBanner.showNegative(context, 'Failed to load data. Please try again.');
      if (kDebugMode) {
        debugPrint('HomeScreen._refresh error: $e');
      }
    }
  }

  void _onCategoryTap(dynamic cat) {
    String name = '';
    int? typeId;

    // حالة CategoryModel (لو تأتي من مكان آخر)
    if (cat is CategoryModel) {
      // حاول الحصول على الاسم من الحقل المألوف في الـ model
      try {
        name = (cat.name ?? '').toString();
      } catch (_) {
        name = cat.toString();
      }
      // حاول الحصول على id إن وُجد (قد يكون int أو String)
      try {
        final dynamic rawId = (cat as dynamic).id;
        if (rawId != null) {
          typeId = (rawId is int) ? rawId : int.tryParse(rawId.toString());
        }
      } catch (_) {
        typeId = null;
      }
    }
    // حالة Map (التي يرسلها RestaurantTypesRow)
    else if (cat is Map<String, dynamic>) {
      name = (cat['name_en'] ?? cat['name_ar'] ?? cat['name'])?.toString() ?? '';
      final dynamic idRaw = cat['id'] ?? cat['type_id'];
      if (idRaw != null) {
        typeId = (idRaw is int) ? idRaw : int.tryParse(idRaw.toString());
      }
    }
    // أي نوع آخر — استخدم toString كاحتياط
    else {
      name = cat?.toString() ?? '';
    }

    // تطبيق الحالة والانتقال للشاشة
    setState(() => _selectedCategoryName = name);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryRestaurantsScreen(
          categoryName: name,
          restaurantTypeId: typeId,
        ),
      ),
    );
  }

  void _onBrandTap(NearestRestaurant nr) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RestaurantDetailScreen(
      restaurantId: nr.restaurantId,
      initialLogo: nr.logoUrl,
      initialCover: null,
      initialName: nr.restaurantName,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context); // optional: use loc when available

    final width = MediaQuery.of(context).size.width;
    final double offersHeight = (width >= 1100) ? 420 : (width >= 800) ? 380 : (width >= 520) ? 340 : 300;

    return Scaffold(
      // appBar omitted to keep a full-screen feel; control status bar above instead.
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _rootAnim, curve: Curves.easeOut),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

                  // Search widget with subtle entrance slide
                  SlideFadeWrapper(
                    delay: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      // Wrap SearchAdsBannerMulti with a Theme to customise its TextField decoration
                      child: Builder(builder: (ctx) {
                        final brightness = Theme.of(ctx).brightness;
                        final isDark = brightness == Brightness.dark;

                        final enabledBorder = OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(color: isDark ? kPrimaryColor : Colors.black, width: 1.2),
                        );
                        final focusedBorder = OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(color: kPrimaryColor, width: 1.6),
                        );

                        final fillColor = isDark ? Colors.black : Colors.white;
                        final hintStyle = TextStyle(color: isDark ? kPrimaryColor.withOpacity(0.9) : Colors.black54);
                        final labelStyle = TextStyle(color: isDark ? kPrimaryColor.withOpacity(0.9) : Colors.black87);
                        final typedTextColor = isDark ? kPrimaryColor : Colors.black;
                        final iconColor = isDark ? kPrimaryColor : Colors.black54;

                        return IconTheme(
                          data: IconThemeData(color: iconColor),
                          child: Theme(
                            data: Theme.of(ctx).copyWith(
                              inputDecorationTheme: InputDecorationTheme(
                                enabledBorder: enabledBorder,
                                focusedBorder: focusedBorder,
                                filled: true,
                                fillColor: fillColor,
                                hintStyle: hintStyle,
                                labelStyle: labelStyle,
                                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              ),
                              textSelectionTheme: TextSelectionThemeData(cursorColor: kPrimaryColor),
                              textTheme: Theme.of(ctx).textTheme.apply(bodyColor: typedTextColor, displayColor: typedTextColor),
                            ),
                            child: DefaultTextStyle(
                              style: TextStyle(color: typedTextColor),
                              child: const SearchAdsBannerMulti(),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Large Ads banner with hero-like elevation
                  SlideFadeWrapper(
                    delay: 80,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: AdsBanner(height: 300),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Categories row (staggered)
                  FutureBuilder<List<CategoryModel>>(
                    future: _futureCats,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return SizedBox(height: 110, child: Center(child: CircularProgressIndicator(color: kPrimaryColor)));
                      } else if (snapshot.hasError) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          MessageBanner.showNegative(context, 'Failed to load categories.');
                        });
                        return const SizedBox(height: 110, child: Center(child: Text('Failed to load categories')));
                      } else {
                        final cats = snapshot.data ?? [];
                        if (cats.isEmpty) return const SizedBox(height: 110, child: Center(child: Text('No categories yet')));
                        return SlideFadeWrapper(
                          delay: 140,
                          child: RestaurantTypesRow(onTap: _onCategoryTap),
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 20),

                  // Big brands (nearest)
                  FutureBuilder<List<NearestRestaurant>>(
                    future: _futureRestaurants,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return SizedBox(height: 180, child: Center(child: CircularProgressIndicator(color: kPrimaryColor)));
                      } else if (snapshot.hasError) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          MessageBanner.showNegative(context, 'Failed to load nearby restaurants.');
                        });
                        return SizedBox(height: 180, child: Center(child: Text('Failed to load restaurants: ${snapshot.error}')));
                      } else {
                        final restaurants = snapshot.data ?? [];
                        if (restaurants.isEmpty) return const SizedBox(height: 160, child: Center(child: Text('No nearby restaurants')));

                        return SlideFadeWrapper(
                          delay: 220,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 4))],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BigBrandsNearYou(
                                  items: restaurants,
                                  onTap: _onBrandTap,
                                  maxItems: 5,
                                  title: _selectedCategoryName != null ? 'Big brands near you — ${_selectedCategoryName!}' : 'Big brands near you',
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 24),

                  // Offers embedded section (animated switcher)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: FutureBuilder<bool>(
                      future: _offersFuture,
                      builder: (context, snapshot) {
                        final hasOffers = snapshot.data == true;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 420),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: hasOffers
                              ? Container(
                            key: const ValueKey('offers_present'),
                            margin: const EdgeInsets.only(bottom: 18),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.local_offer, color: kPrimaryColor),
                                      const SizedBox(width: 8),
                                      // Hot offers text: white in dark mode, dark color in light mode
                                      Builder(builder: (ctx) {
                                        final isDark = Theme.of(ctx).brightness == Brightness.dark;
                                        final hotOffersColor = isDark ? Colors.white : Colors.black87;
                                        return Text(
                                          'Hot offers',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: hotOffersColor),
                                        );
                                      }),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OffersBatchesWidget(embedded: false)));
                                        },
                                        child: const Text('See all'),
                                      ),
                                    ],
                                  ),
                                ),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Builder(builder: (ctx) {
                                    // Offers container color: grayish in dark mode, white in light
                                    final isDark = Theme.of(ctx).brightness == Brightness.dark;
                                    final offersCardColor = isDark ? const Color(0xFF1F1F1F) : Colors.white;
                                    return Material(
                                      elevation: 6,
                                      color: offersCardColor,
                                      child: SizedBox(
                                        height: offersHeight,
                                        // embedded offers widget (kept non-const to avoid const/Theme tension)
                                        child: OffersBatchesWidget(embedded: true, embeddedHeight: null),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                          )
                              : const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // bottom spacing to make room for overlay banner (so it doesn't overlap content)
                  const SizedBox(height: 110),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small helper widget to combine slide + fade with a delay (stagger feel)
class SlideFadeWrapper extends StatefulWidget {
  final Widget child;
  final int delay; // milliseconds
  final Duration duration;

  const SlideFadeWrapper({Key? key, required this.child, this.delay = 0, this.duration = const Duration(milliseconds: 420)}) : super(key: key);

  @override
  State<SlideFadeWrapper> createState() => _SlideFadeWrapperState();
}

class _SlideFadeWrapperState extends State<SlideFadeWrapper> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _offset = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    if (widget.delay <= 0) {
      _ctrl.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// -------------------------
/// Message Banner (overlay)
/// -------------------------
/// Usage:
///   MessageBanner.showPositive(context, "Saved");
///   MessageBanner.showNegative(context, "Failed to save");
class MessageBanner {
  static void _show(BuildContext context, String message, {required bool positive}) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final Color good = const Color(0xFF2E7D32);   // sweet / success
    final Color bad = const Color(0xFFD32F2F);    // bitter / error
    final color = positive ? good : bad;
    final bg = positive ? good.withOpacity(0.08) : bad.withOpacity(0.08);
    final border = positive ? good.withOpacity(0.16) : bad.withOpacity(0.16);
    final icon = positive ? Icons.check_circle_outline : Icons.error_outline;

    late OverlayEntry entry;
    entry = OverlayEntry(builder: (context) {
      return Positioned(
        left: 18,
        right: 18,
        bottom: 18 + MediaQuery.of(context).padding.bottom,
        child: _AnimatedBanner(
          message: message,
          color: color,
          bg: bg,
          border: border,
          icon: icon,
          onFinish: () {
            try {
              entry.remove();
            } catch (_) {}
          },
        ),
      );
    });

    overlay.insert(entry);
  }

  static void showPositive(BuildContext context, String message) => _show(context, message, positive: true);
  static void showNegative(BuildContext context, String message) => _show(context, message, positive: false);
}

class _AnimatedBanner extends StatefulWidget {
  final String message;
  final Color color;
  final Color bg;
  final Color border;
  final IconData icon;
  final VoidCallback onFinish;

  const _AnimatedBanner({
    Key? key,
    required this.message,
    required this.color,
    required this.bg,
    required this.border,
    required this.icon,
    required this.onFinish,
  }) : super(key: key);

  @override
  State<_AnimatedBanner> createState() => _AnimatedBannerState();
}

class _AnimatedBannerState extends State<_AnimatedBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _ctrl.forward();

    // auto-hide after a short delay
    Future.delayed(const Duration(milliseconds: 2400), () async {
      if (mounted) {
        await _ctrl.reverse();
        widget.onFinish();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87;

    return FadeTransition(
      opacity: _ctrl,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: widget.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.border),
                boxShadow: [BoxShadow(color: widget.color.withOpacity(0.12), blurRadius: 24, spreadRadius: 2)],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withOpacity(0.12)),
                    child: Icon(widget.icon, color: widget.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.message, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor))),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () async {
                      await _ctrl.reverse();
                      widget.onFinish();
                    },
                    child: Icon(Icons.close, color: widget.color.withOpacity(0.9)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
