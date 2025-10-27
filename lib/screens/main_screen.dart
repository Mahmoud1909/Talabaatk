import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:url_launcher/url_launcher.dart';

import 'package:talabak_users/screens/home_screen.dart';
import 'package:talabak_users/screens/OrdersScreen.dart';
import 'package:talabak_users/screens/account_previous_orders_screen.dart';
import 'package:talabak_users/screens/restaurant_detail_screen.dart';
import 'package:talabak_users/screens/item_detail_screen.dart';
import 'package:talabak_users/widgets/custom_header.dart';
import 'package:talabak_users/widgets/AdsBanner.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

enum _ErrorState { none, noRestaurant, failedToLoad }

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _loading = true;
  _ErrorState _errorState = _ErrorState.none;
  String? _restaurantId;
  late List<Widget> _screens = [];

  // Track per-session shown fullscreen banners (so we don't repeat).
  final Set<String> _sessionShownBanners = {};

  @override
  void initState() {
    super.initState();

    // Replace Flutter's raw error widget with a friendly card (prevents raw stack traces in UI).
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18.0,
                vertical: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 56,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Something went wrong.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please restart the app or contact support.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };

    _prepareAndBuildScreens();
  }

  Future<void> _prepareAndBuildScreens() async {
    setState(() {
      _loading = true;
      _errorState = _ErrorState.none;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String? rid = prefs.getString('restaurantId');

      final client = supabase.Supabase.instance.client;

      // Try to find restaurant linked to auth user if not in prefs
      if (rid == null) {
        final user = client.auth.currentUser;
        if (user != null) {
          final resp = await client
              .from('restaurants')
              .select()
              .eq('owner_id', user.id)
              .limit(1)
              .maybeSingle();
          if (resp != null &&
              resp is Map<String, dynamic> &&
              resp['id'] != null) {
            rid = resp['id'] as String;
          }
        }
      }

      // Fallback: take first restaurant available
      if (rid == null) {
        final resp2 = await client
            .from('restaurants')
            .select()
            .limit(1)
            .maybeSingle();
        if (resp2 != null &&
            resp2 is Map<String, dynamic> &&
            resp2['id'] != null) {
          rid = resp2['id'] as String;
        }
      }

      // If still no restaurant, set error state and show a friendly overlay
      if (rid == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorState = _ErrorState.noRestaurant;
        });

        // show a professional overlay banner (localized)
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final local = AppLocalizations.of(context);
            MessageBanner.showNegative(
              context,
              local?.noRestaurantFound ??
                  'No restaurant found for this account.',
            );
          });
        }
        return;
      }

      // Persist restaurant for next launches
      await prefs.setString('restaurantId', rid);

      final screens = <Widget>[
        HomeScreen(restaurantId: rid),
        OrdersScreen(),
        const AccountPreviousOrdersScreen(),
      ];

      if (!mounted) return;
      setState(() {
        _restaurantId = rid;
        _screens = screens;
        _loading = false;
        _errorState = _ErrorState.none;
      });

      // check fullscreen banners (non-blocking)
      _maybeShowFullscreenBanner();
    } catch (e, st) {
      debugPrint('MainScreen initialization error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorState = _ErrorState.failedToLoad;
      });

      // localized overlay
      if (mounted) {
        final local = AppLocalizations.of(context);
        MessageBanner.showNegative(
          context,
          local?.failedToLoadRestaurant ??
              'Failed to load restaurant info. Please try again.',
        );
      }
    }
  }

  Future<void> _maybeShowFullscreenBanner() async {
    try {
      final client = supabase.Supabase.instance.client;
      final result = await client
          .from('banners')
          .select()
          .eq('is_active', true)
          .eq('display_type', 'fullscreen')
          .order('position', ascending: true)
          .limit(3);

      final List<dynamic> rows = (result is List) ? result : <dynamic>[];
      final List<Map<String, dynamic>> banners = rows
          .where((m) => m is Map)
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      if (banners.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();

      for (final banner in banners) {
        final String id = (banner['id'] ?? '').toString();
        if (id.isEmpty) continue;

        final dynamic showEveryRaw = banner['show_every_n_visits'];
        final int showEvery = (showEveryRaw is int)
            ? showEveryRaw
            : int.tryParse(showEveryRaw?.toString() ?? '') ?? 1;

        final String key = 'banner_visits_$id';
        final int prev = prefs.getInt(key) ?? 0;
        final int now = prev + 1;
        await prefs.setInt(key, now);

        if (showEvery <= 1 || (now % showEvery) == 0) {
          if (_sessionShownBanners.contains(id)) continue;
          _sessionShownBanners.add(id);

          if (!mounted) return;
          await _showFullscreenBannerDialog(banner);
          return; // show only one per session-run
        }
      }
    } catch (e, st) {
      debugPrint('Error checking fullscreen banners: $e\n$st');
      // Do not expose this to the user; it's a non-critical background task.
    }
  }

  Future<void> _showFullscreenBannerDialog(Map<String, dynamic> banner) async {
    final String id = (banner['id'] ?? '').toString();
    final String title = (banner['title'] ?? '').toString();
    final String imageUrl =
        (banner['image_url'] ?? banner['image'] ?? banner['object_path'] ?? '')
            .toString();
    final String link = (banner['link'] ?? '').toString();
    final String targetType = (banner['target_type'] ?? '')
        .toString()
        .toLowerCase();
    final dynamic targetIdRaw = banner['target_id'] ?? banner['target'];

    Future<void> _onTap(BuildContext ctx) async {
      try {
        if (targetType == 'restaurant' && targetIdRaw != null) {
          final String targetId = targetIdRaw.toString();
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => RestaurantDetailScreen(restaurantId: targetId),
            ),
          );
          return;
        }
        if (targetType == 'item' && targetIdRaw != null) {
          final String itemId = targetIdRaw.toString();
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: itemId)),
          );
          return;
        }
        if (link.isNotEmpty) {
          final uri = Uri.tryParse(link);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      } catch (e) {
        debugPrint('fullscreen banner tap error: $e');
      }
    }

    if (!mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'banner_fullscreen',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim1, anim2) {
        return SafeArea(
          child: Builder(
            builder: (ctx2) {
              final Size screen = MediaQuery.of(ctx2).size;
              final double maxWidth = screen.width * 0.96;
              final double maxHeight = screen.height * 0.92;

              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: maxWidth,
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => _onTap(ctx2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.contain,
                                      placeholder: (c, u) => Container(
                                        color:
                                            Theme.of(c).brightness ==
                                                Brightness.light
                                            ? Colors.grey[200]
                                            : Colors.grey[800],
                                      ),
                                      errorWidget: (c, u, e) => Container(
                                        color:
                                            Theme.of(c).brightness ==
                                                Brightness.light
                                            ? Colors.grey[100]
                                            : Colors.grey[900],
                                        child: const Center(
                                          child: Icon(
                                            Icons.broken_image,
                                            size: 48,
                                            color: Colors.black26,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color:
                                          Theme.of(ctx2).brightness ==
                                              Brightness.light
                                          ? Colors.grey[100]
                                          : Colors.grey[900],
                                      child: const Center(
                                        child: Icon(
                                          Icons.image,
                                          size: 48,
                                          color: Colors.black26,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),

                        if (title.isNotEmpty)
                          Positioned(
                            left: 16,
                            right: 80,
                            bottom: 16,
                            child: Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                shadows: const [
                                  Shadow(blurRadius: 6, color: Colors.black45),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        Positioned(
                          top: 8,
                          right: 8,
                          child: SafeArea(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(ctx2).pop();
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (ctx, anim, secAnim, child) {
        final curved = Curves.easeOut.transform(anim.value);
        return Transform.scale(
          scale: curved,
          child: Opacity(opacity: anim.value, child: child),
        );
      },
    );
  }

  // If a screen is not scrollable, make sure it still has proper sizing
  Widget _wrapScreenForNested(Widget screen) {
    if (screen is ScrollView ||
        screen is SingleChildScrollView ||
        screen is CustomScrollView) {
      return screen;
    }
    if (screen is Scaffold) {
      return screen;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableHeight =
            (constraints.hasBoundedHeight && constraints.maxHeight.isFinite)
            ? constraints.maxHeight
            : (MediaQuery.of(context).size.height -
                  kToolbarHeight -
                  kBottomNavigationBarHeight);

        return SizedBox(
          width: double.infinity,
          height: availableHeight,
          child: screen,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    final isRtl = Localizations.localeOf(context).languageCode == 'ar';
    final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;

    // Colors adapt to theme
    final theme = Theme.of(context);
    final bottomBg = theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : Colors.white;
    final selectedColor = theme.colorScheme.primary;
    final unselectedColor =
        theme.iconTheme.color?.withOpacity(0.7) ?? Colors.grey;

    return Directionality(
      textDirection: textDirection,
      child: Builder(
        builder: (ctx) {
          if (_loading) {
            return Scaffold(
              body: Column(
                children: const [
                  CustomHeader(),
                  Expanded(child: Center(child: CircularProgressIndicator())),
                ],
              ),
            );
          }

          if (_errorState != _ErrorState.none) {
            final String message = (_errorState == _ErrorState.noRestaurant)
                ? (local?.noRestaurantFound ??
                      'No restaurant found for this account.')
                : (local?.failedToLoadRestaurant ??
                      'Failed to load restaurant info. Please try again.');

            return Scaffold(
              body: Column(
                children: [
                  const CustomHeader(),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _prepareAndBuildScreens,
                                  child: Text(local?.retry ?? 'Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Normal runtime: show nested scroll view with header and selected screen
          return Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                const SliverToBoxAdapter(child: CustomHeader()),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
              body: _wrapScreenForNested(_screens[_currentIndex]),
            ),
            // replace your existing bottomNavigationBar: Container(...) with this block
            bottomNavigationBar: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  // dynamic background color depending on theme
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 20,
                        spreadRadius: 1,
                        offset: const Offset(0, -8), // shadow upwards
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: BottomNavigationBar(
                      currentIndex: _currentIndex,
                      onTap: (index) => setState(() => _currentIndex = index),
                      backgroundColor: Colors.transparent,
                      // let container color show
                      elevation: 0,
                      type: BottomNavigationBarType.fixed,

                      // adaptive colors
                      selectedItemColor: Theme.of(context).colorScheme.primary,
                      unselectedItemColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54,

                      selectedLabelStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: const TextStyle(fontSize: 12),
                      iconSize: 28,

                      items: [
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.home),
                          label: local?.home ?? 'Home',
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.delivery_dining),
                          label: local?.orders ?? 'Orders',
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.history),
                          label: local?.previousOrders ?? 'Previous Orders',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// -------------------------
/// MessageBanner (professional overlay)
/// - Use MessageBanner.showPositive(context, message)
/// - Use MessageBanner.showNegative(context, message)
/// - Use MessageBanner.showInfo(context, message)
/// -------------------------
class MessageBanner {
  static void _show(
    BuildContext context,
    String message, {
    required Color accent,
    required Color background,
    required IconData icon,
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return _MessageBannerWidget(
          message: message,
          accent: accent,
          background: background,
          icon: icon,
          duration: duration,
          onFinish: () {
            try {
              entry.remove();
            } catch (_) {}
          },
        );
      },
    );

    overlay.insert(entry);
  }

  static void showPositive(BuildContext context, String message) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final Color good = const Color(0xFF2E7D32); // success
    _show(
      context,
      message,
      accent: good,
      background: good.withOpacity(isLight ? 0.08 : 0.12),
      icon: Icons.check_circle_outline,
    );
  }

  static void showNegative(BuildContext context, String message) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final Color bad = const Color(0xFFD32F2F); // error
    _show(
      context,
      message,
      accent: bad,
      background: bad.withOpacity(isLight ? 0.08 : 0.12),
      icon: Icons.error_outline,
    );
  }

  static void showInfo(BuildContext context, String message) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final Color info = Colors.blue.shade700;
    _show(
      context,
      message,
      accent: info,
      background: info.withOpacity(isLight ? 0.06 : 0.10),
      icon: Icons.info_outline,
    );
  }
}

class _MessageBannerWidget extends StatefulWidget {
  final String message;
  final Color accent;
  final Color background;
  final IconData icon;
  final Duration duration;
  final VoidCallback onFinish;

  const _MessageBannerWidget({
    Key? key,
    required this.message,
    required this.accent,
    required this.background,
    required this.icon,
    this.duration = const Duration(milliseconds: 2200),
    required this.onFinish,
  }) : super(key: key);

  @override
  State<_MessageBannerWidget> createState() => _MessageBannerWidgetState();
}

class _MessageBannerWidgetState extends State<_MessageBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    Future.delayed(widget.duration, () async {
      if (mounted) {
        await _ctrl.reverse();
        widget.onFinish();
      } else {
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? Colors.black87 : Colors.white;
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom + 12.0;
    final cardColor = widget.background;

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomSafe,
      child: SlideTransition(
        position: _offset,
        child: FadeTransition(
          opacity: _fade,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.accent.withOpacity(0.16)),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withOpacity(0.14),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: widget.accent.withOpacity(0.22),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(widget.icon, color: widget.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        await _ctrl.reverse();
                        widget.onFinish();
                      },
                      child: Icon(Icons.close, color: textColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
