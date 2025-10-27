// lib/widgets/ads_banner.dart
// AdsBanner: responsive, modern, auto-scrolling banners from Supabase.
// Localized: uses AppLocalizations for user-visible strings.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:url_launcher/url_launcher.dart';
import 'package:talabak_users/screens/restaurant_detail_screen.dart';
import 'package:talabak_users/screens/item_detail_screen.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

class AdsBanner extends StatefulWidget {
  final double height;
  final Duration autoScrollDuration;
  final bool showIndicators;

  const AdsBanner({
    Key? key,
    this.height = 450, // larger default height for clearer images
    this.autoScrollDuration = const Duration(seconds: 4),
    this.showIndicators = true,
  }) : super(key: key);

  @override
  State<AdsBanner> createState() => _AdsBannerState();
}

class _AdsBannerState extends State<AdsBanner> {
  final supabase.SupabaseClient _supabase = supabase.Supabase.instance.client;
  late PageController _pageController;

  Timer? _autoTimer;
  List<Map<String, dynamic>> _banners = [];
  int _current = 0;
  bool _loading = true;
  String? _error;

  bool _userInteracting = false;

  @override
  void initState() {
    super.initState();
    // smaller peek so the image takes most of the width
    _pageController = PageController(viewportFraction: 0.96, initialPage: 0);
    _fetchBanners();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchBanners() async {
    try {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
      });

      final dynamic raw = await _supabase
          .from('banners')
          .select()
          .eq('is_active', true)
          .order('position', ascending: true);

      final List<dynamic> rows = (raw is List)
          ? raw
          : (raw is Map && raw['data'] is List)
          ? (raw['data'] as List<dynamic>)
          : <dynamic>[];

      _banners = rows
          .map<Map<String, dynamic>>((r) {
        if (r is Map) return Map<String, dynamic>.from(r);
        return <String, dynamic>{};
      })
          .where((m) => m.isNotEmpty)
          .toList();

      if (!mounted) return;

      if (_banners.isNotEmpty) {
        _current = 0;
        try {
          _pageController.jumpToPage(0);
        } catch (_) {}
      }

      if (_banners.length > 1) {
        _startAutoScroll();
      } else {
        _stopAutoScroll();
      }

      setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('AdsBanner.fetch error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Keep message generic; localized string used in build()
        _error = 'ads_load_error';
      });
    }
  }

  void _startAutoScroll() {
    _stopAutoScroll();
    if (_banners.length <= 1) return;
    _autoTimer = Timer.periodic(widget.autoScrollDuration, (_) async {
      if (!mounted) return;
      if (_banners.isEmpty) return;
      if (!_pageController.hasClients) return;
      if (_userInteracting) return;

      final next = (_current + 1) % _banners.length;
      try {
        await _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeInOut,
        );
        if (mounted) setState(() => _current = next);
      } catch (_) {}
    });
  }

  void _stopAutoScroll() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  String _resolveImageUrl(Map<String, dynamic> banner) {
    try {
      final dynamic imageUrlRaw = banner['image_url'] ?? banner['image'];
      final String imageUrl = imageUrlRaw != null ? imageUrlRaw.toString() : '';
      if (imageUrl.isNotEmpty) return imageUrl;

      final dynamic imagePathRaw = banner['image_path'] ?? banner['path'];
      final String imagePath = imagePathRaw != null ? imagePathRaw.toString() : '';
      if (imagePath.isEmpty) return '';

      final dynamic pub = _supabase.storage.from('banners').getPublicUrl(imagePath);
      if (pub is String && pub.isNotEmpty) return pub;
      if (pub is Map) {
        final List<String> keys = ['publicUrl', 'publicURL', 'public_url'];
        for (final k in keys) {
          if (pub[k] != null) {
            final String candidate = pub[k].toString();
            if (candidate.isNotEmpty) return candidate;
          }
        }
        if (pub['data'] is Map && pub['data']['publicUrl'] != null) {
          final String candidate = pub['data']['publicUrl'].toString();
          if (candidate.isNotEmpty) return candidate;
        }
      }
    } catch (e) {
      debugPrint('AdsBanner._resolveImageUrl error: $e');
    }
    return '';
  }

  Future<void> _handleTap(BuildContext ctx, Map<String, dynamic> banner) async {
    try {
      final dynamic typeRaw = banner['target_type'] ?? banner['type'];
      final String targetType = typeRaw != null ? typeRaw.toString().toLowerCase() : '';
      final dynamic targetIdRaw = banner['target_id'] ?? banner['target'] ?? banner['entity_id'];
      final dynamic linkRaw = banner['link'] ?? banner['url'];
      final String link = linkRaw != null ? linkRaw.toString() : '';

      if (targetType == 'restaurant' && targetIdRaw != null) {
        final String targetId = targetIdRaw.toString();
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: targetId)));
        return;
      }

      if (targetType == 'item' && targetIdRaw != null) {
        final String itemId = targetIdRaw.toString();
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: itemId)));
        return;
      }

      if (link.isNotEmpty) {
        final uri = Uri.tryParse(link);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint('AdsBanner._handleTap error: $e');
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: const Center(child: Icon(Icons.image, size: 48, color: Colors.black26)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    if (_loading) {
      return SizedBox(height: widget.height, child: const Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      // _error stores a key name when set in fetch; use localized message if possible
      final msg = _error == 'ads_load_error' ? loc.ads_load_error : _error!;
      return SizedBox(
        height: widget.height,
        child: Center(child: Text(msg, style: const TextStyle(color: Colors.redAccent))),
      );
    }

    if (_banners.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notif) {
                if (notif is UserScrollNotification) {
                  final ScrollDirection dir = notif.direction;
                  if (dir == ScrollDirection.forward || dir == ScrollDirection.reverse) {
                    _userInteracting = true;
                    _stopAutoScroll();
                  } else if (dir == ScrollDirection.idle) {
                    _userInteracting = false;
                    if (_banners.length > 1) _startAutoScroll();
                  }
                }
                return false;
              },
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: _banners.length,
                    onPageChanged: (idx) {
                      if (!mounted) return;
                      setState(() => _current = idx);
                    },
                    itemBuilder: (context, index) {
                      final banner = _banners[index];
                      final String url = _resolveImageUrl(banner);
                      final String title = (banner['title'] ?? '')?.toString() ?? '';

                      // center-scale effect - smaller diff so image appears clearer
                      double scale = 0.99;
                      if (_pageController.hasClients) {
                        try {
                          final page = _pageController.page ?? _pageController.initialPage.toDouble();
                          final diff = (page - index).abs();
                          scale = (1 - (diff * 0.04)).clamp(0.96, 1.0);
                        } catch (_) {}
                      } else {
                        scale = (_current == index) ? 1.0 : 0.98;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0), // removed vertical padding for full height
                        child: Semantics(
                          label: title.isNotEmpty ? title : loc.banner,
                          button: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _handleTap(context, banner),
                            onHighlightChanged: (h) {
                              _userInteracting = h;
                              if (h) _stopAutoScroll();
                              else if (!_userInteracting && _banners.length > 1) _startAutoScroll();
                            },
                            child: Transform.scale(
                              scale: scale,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    url.isNotEmpty
                                        ? CachedNetworkImage(
                                      imageUrl: url,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      placeholder: (c, u) => Container(color: Colors.grey[200]),
                                      errorWidget: (c, u, e) => _buildPlaceholder(),
                                    )
                                        : _buildPlaceholder(),

                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.black.withOpacity(0.28), Colors.transparent],
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                          ),
                                        ),
                                      ),
                                    ),

                                    Positioned(
                                      left: 12,
                                      bottom: 12,
                                      right: 86,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (title.isNotEmpty)
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              if ((banner['discount_text'] ?? banner['discount']) != null &&
                                                  (banner['discount_text'] ?? banner['discount']).toString().isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(
                                                    (banner['discount_text'] ?? banner['discount']).toString(),
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.12),
                                              blurRadius: 12,
                                              spreadRadius: 1,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                      ),
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

                  // chevrons
                  if (_banners.length > 1)
                    Positioned(
                      left: 6,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            _userInteracting = true;
                            _stopAutoScroll();
                            final prev = (_current - 1) < 0 ? (_banners.length - 1) : (_current - 1);
                            _pageController.animateToPage(prev, duration: const Duration(milliseconds: 360), curve: Curves.easeInOut);
                          },
                          child: Container(
                            height: 36,
                            width: 36,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.36),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                          ),
                        ),
                      ),
                    ),

                  if (_banners.length > 1)
                    Positioned(
                      right: 6,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            _userInteracting = true;
                            _stopAutoScroll();
                            final next = (_current + 1) % _banners.length;
                            _pageController.animateToPage(next, duration: const Duration(milliseconds: 360), curve: Curves.easeInOut);
                          },
                          child: Container(
                            height: 36,
                            width: 36,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.36),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.chevron_right, color: Colors.white, size: 26),
                          ),
                        ),
                      ),
                    ),

                  // indicators overlay
                  if (widget.showIndicators && _banners.isNotEmpty)
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_banners.length, (i) {
                          final bool active = _current == i;
                          return GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(i, duration: const Duration(milliseconds: 360), curve: Curves.easeInOut);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: active ? 18 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: active ? Colors.redAccent : Colors.white70,
                                boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))] : null,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
