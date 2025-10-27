// lib/widgets/offer_batches_widget.dart
// Offers-by-batches widget — localizable, realtime-updating, fancy UI (pure Flutter).
//
// This file is theme-aware and tuned to provide a clear difference between the
// overall page background and the offers card backgrounds in Dark mode while
// keeping Light mode default appearance unchanged.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/screens/checkout_payment_screen.dart';
import 'package:talabak_users/screens/PaymentScreen.dart';

const Color _kPrimary = Color(0xFF25AA50);
const double _kCardRadius = 18.0;

/// Fallback images
const String _noImageFallback =
    'https://media.istockphoto.com/id/1055079680/vector/black-linear-photo-camera-like-no-image-available.jpg?s=612x612&w=0&k=20&c=P1DebpeMIAtXj_ZbVsKVvg-duuL0v9DlrOZUvPG6UJk=';

const String _localPlaceholderAsset = 'assets/images/placeholder.png';

final Uint8List kTransparentImage = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82
]);

/// ----------------------------
/// File-level localization helper
/// ----------------------------
String _tr(BuildContext context, String key, String fallback) {
  final locale = Localizations.localeOf(context);
  final lang = locale.languageCode.toLowerCase();
  final dict = _localDict[lang] ?? _localDict['en']!;
  return dict[key] ?? fallback;
}

final Map<String, Map<String, String>> _localDict = {
  'en': {
    'offers.title': 'Offers',
    'offers.loading': 'Loading offers...',
    'offers.fetching_info': 'Fetching the best offers for you...',
    'offers.no_offers': 'No offers right now',
    'offers.view': 'View',
    'offers.special_offer': 'Special Offer',
    'offers.top_offers_for_you': 'Top Offers for you',
    'offers.saved_not_implemented': 'Saved (not implemented)',
    'offers.order_now': 'Order Now • {total} EGP',
    'offers.order_how_many': 'Order how many times?',
    'offers.items_in_offer': 'Items in this offer',
    'offers.available_n': 'Available {n}',
    'offers.total_label': 'Total',
    'offers.max_orders_allowed': 'Max orders allowed: {n}',
    'offers.up_to_pct': 'Up to {pct}%',
    'offers.fetch_failed': 'Failed to load offers',
    'toast.success_default': 'Operation completed successfully',
    'toast.error_default': 'Something went wrong',
  },
  'ar': {
    'offers.title': 'العروض',
    'offers.loading': 'جاري تحميل العروض...',
    'offers.fetching_info': 'نقوم بجلب أفضل العروض لك...',
    'offers.no_offers': 'لا توجد عروض الآن',
    'offers.view': 'عرض',
    'offers.special_offer': 'عرض خاص',
    'offers.top_offers_for_you': 'أفضل العروض لك',
    'offers.saved_not_implemented': 'تم الحفظ (لم يُنفَّذ)',
    'offers.order_now': 'اطلب الآن • {total} ج.م',
    'offers.order_how_many': 'كم مرة تريد الطلب؟',
    'offers.items_in_offer': 'عناصر في هذا العرض',
    'offers.available_n': 'متاح {n}',
    'offers.total_label': 'الإجمالي',
    'offers.max_orders_allowed': 'أقصى عدد للطلبات: {n}',
    'offers.up_to_pct': 'حتى {pct}%',
    'offers.fetch_failed': 'فشل تحميل العروض',
    'toast.success_default': 'تمت العملية بنجاح',
    'toast.error_default': 'حدث خطأ ما',
  },
};

/// ----------------------------
/// OffersBatchesWidget
/// ----------------------------
class OffersBatchesWidget extends StatefulWidget {
  final bool embedded;
  final double? embeddedHeight;
  final int limit;

  const OffersBatchesWidget({Key? key, this.embedded = false, this.embeddedHeight, this.limit = 12})
      : super(key: key);

  @override
  State<OffersBatchesWidget> createState() => _OffersBatchesWidgetState();
}

class _OffersBatchesWidgetState extends State<OffersBatchesWidget> with TickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NumberFormat _money = NumberFormat.currency(symbol: '', decimalDigits: 2);

  List<_BatchModel> _batches = [];
  bool _loading = true;
  String? _error;

  late final AnimationController _staggerController; // for list items
  late final AnimationController _loaderController; // for fancy loader animations

  RealtimeChannel? _batchesChannel;
  RealtimeChannel? _offersChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('INIT: OffersBatchesWidget.initState starting');
    _staggerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _loaderController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    _fetchBatches().then((_) {
      debugPrint('INIT: initial fetch done, setting up realtime');
      _setupRealtime();
    }).catchError((e, st) {
      debugPrint('INIT: initial fetch failed -> $e\n$st');
      _setupRealtime(); // still try realtime
    });
  }

  @override
  void dispose() {
    debugPrint('DISPOSE: OffersBatchesWidget.dispose tearing down');
    _staggerController.dispose();
    _loaderController.dispose();
    _removeRealtime();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchBatches() async {
    debugPrint('LOAD: _fetchBatches() starting');
    if (!mounted) debugPrint('LOAD: widget not mounted yet (fetch still running)');

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      debugPrint('LOAD: querying offer_batches with end_date >= $today limit=${widget.limit}');
      final resp = await _supabase
          .from('offer_batches')
          .select('id,restaurant_id,title,description,image_url,start_date,end_date,created_at')
          .gte('end_date', today)
          .order('created_at', ascending: false)
          .limit(widget.limit);

      final List<_BatchModel> list = [];
      if (resp is List) {
        debugPrint('LOAD: batches raw response count=${resp.length}');
        for (final b in resp) {
          if (b is Map) {
            final batchId = (b['id'] ?? '').toString();
            debugPrint('LOAD: fetching offers for batch=$batchId');
            final offersResp = await _supabase
                .from('offers')
                .select(
                'id,menu_item_id,restaurant_id,title,description,price,quantity,image_url,start_date,end_date,is_active,created_at,menu_items(id,name,price,image_url)')
                .eq('batch_id', batchId)
                .eq('is_active', true)
                .order('created_at', ascending: false);

            final List<_OfferModel> offers = [];
            if (offersResp is List) {
              for (final r in offersResp) {
                if (r is Map) {
                  final menu = (r['menu_items'] is Map) ? Map<String, dynamic>.from(r['menu_items']) : null;
                  final double offerPrice = double.tryParse((r['price'] ?? 0).toString()) ?? 0.0;
                  final double original = menu != null ? (double.tryParse((menu['price'] ?? 0).toString()) ?? 0.0) : offerPrice;
                  offers.add(_OfferModel(
                    id: (r['id'] ?? '').toString(),
                    restaurantId: (r['restaurant_id'] ?? '').toString(),
                    restaurantName: '',
                    menuItemId: (r['menu_item_id'] ?? '').toString(),
                    title: (r['title'] ?? '').toString(),
                    description: (r['description'] ?? '').toString(),
                    imageUrl: (r['image_url'] ?? '')?.toString(),
                    menuImageUrl: menu != null ? (menu['image_url']?.toString() ?? '') : null,
                    menuName: menu != null ? (menu['name']?.toString() ?? '') : '',
                    price: offerPrice,
                    originalPrice: original,
                    allowedQty: (r['quantity'] is int) ? r['quantity'] as int : int.tryParse((r['quantity'] ?? '1').toString()) ?? 1,
                    startDate: r['start_date'] != null ? DateTime.tryParse(r['start_date'].toString()) : null,
                    endDate: r['end_date'] != null ? DateTime.tryParse(r['end_date'].toString()) : null,
                  ));
                }
              }
            }

            final imageUrlCandidate = (b['image_url'] ?? '').toString();
            final imageUrl = (imageUrlCandidate.isNotEmpty)
                ? imageUrlCandidate
                : (offers.isNotEmpty
                ? (offers.first.menuImageUrl?.isNotEmpty == true
                ? offers.first.menuImageUrl
                : (offers.first.imageUrl?.isNotEmpty == true ? offers.first.imageUrl : ''))
                : '');

            list.add(_BatchModel(
              id: (b['id'] ?? '').toString(),
              restaurantId: (b['restaurant_id'] ?? '').toString(),
              title: (b['title'] ?? '').toString(),
              description: (b['description'] ?? '').toString(),
              imageUrl: imageUrl,
              startDate: b['start_date'] != null ? DateTime.tryParse(b['start_date'].toString()) : null,
              endDate: b['end_date'] != null ? DateTime.tryParse(b['end_date'].toString()) : null,
              offers: offers,
            ));
          }
        }
      }

      if (!mounted) {
        debugPrint('LOAD: widget unmounted before setState; aborting update');
        return;
      }

      setState(() {
        _batches = list;
      });

      debugPrint('LOAD: fetched and parsed ${list.length} batches');
      // play short stagger entrance
      _staggerController.forward(from: 0.0);
    } catch (e, st) {
      debugPrint('ERROR: Offer batches fetch error: $e\n$st');
      if (!mounted) return;
      final err = _tr(context, 'offers.fetch_failed', 'Failed to load offers');
      setState(() {
        _error = err;
      });
      // show translated overlay error
      OfferBannerToast.show(context, message: err, isSuccess: false);
    } finally {
      if (mounted) setState(() => _loading = false);
      debugPrint('LOAD: _fetchBatches completed _loading=$_loading');
    }
  }

  double _percentOff(double original, double offer) {
    if (original <= 0) return 0.0;
    final p = ((original - offer) / original) * 100.0;
    if (p.isNaN || p.isInfinite) return 0.0;
    return p.clamp(0.0, 100.0);
  }

  void _setupRealtime() {
    debugPrint('REALTIME: setting up realtime channels for offer_batches and offers');
    try {
      _batchesChannel = _supabase.channel('realtime-offer-batches');
      _batchesChannel!
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'offer_batches',
        callback: (payload, [ref]) {
          debugPrint('REALTIME: offer_batches event -> ${payload.toString()}');
          _fetchBatches();
        },
      )
          .subscribe();
      debugPrint('REALTIME: subscribed to offer_batches channel');

      _offersChannel = _supabase.channel('realtime-offers');
      _offersChannel!
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'offers',
        callback: (payload, [ref]) {
          debugPrint('REALTIME: offers event -> ${payload.toString()}');
          _fetchBatches();
        },
      )
          .subscribe();
      debugPrint('REALTIME: subscribed to offers channel');
    } catch (e, st) {
      debugPrint('REALTIME: subscribe failed: $e\n$st. Using polling fallback.');
      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        debugPrint('POLLING: periodic fetch triggered');
        _fetchBatches();
      });
    }
  }

  Future<void> _teardownRealtime() async {
    debugPrint('REALTIME: teardown requested (async)');
    try {
      if (_batchesChannel != null) {
        await _supabase.removeChannel(_batchesChannel!);
        _batchesChannel = null;
        debugPrint('REALTIME: removed batches channel via removeChannel');
      }
      if (_offersChannel != null) {
        await _supabase.removeChannel(_offersChannel!);
        _offersChannel = null;
        debugPrint('REALTIME: removed offers channel via removeChannel');
      }
    } catch (e) {
      debugPrint('REALTIME: error while removing channels: $e');
    } finally {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  void _removeRealtime() {
    debugPrint('REALTIME: synchronous removeRealtime called');
    try {
      if (_batchesChannel != null) {
        try {
          _batchesChannel!.unsubscribe();
          debugPrint('REALTIME: unsubscribed batches channel');
        } catch (_) {}
        try {
          _supabase.removeChannel(_batchesChannel!);
          debugPrint('REALTIME: removeChannel called for batches channel');
        } catch (_) {}
        _batchesChannel = null;
      }
      if (_offersChannel != null) {
        try {
          _offersChannel!.unsubscribe();
          debugPrint('REALTIME: unsubscribed offers channel');
        } catch (_) {}
        try {
          _supabase.removeChannel(_offersChannel!);
          debugPrint('REALTIME: removeChannel called for offers channel');
        } catch (_) {}
        _offersChannel = null;
      }
    } catch (e) {
      debugPrint('REALTIME: removeRealtime encountered an exception: $e');
    }
    _pollingTimer?.cancel();
  }

  // ----------------------------
  // Fancy loader & skeleton UI
  // ----------------------------
  Widget _buildFancyLoader(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Choose page background and card background explicitly for dark mode to create
    // a visible shade difference between the overall background and the card surfaces.
    final pageBackground = isLight ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFF060608);
    final cardSurface = isLight ? Theme.of(context).cardColor : const Color(0xFF111214);

    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? (isLight ? Colors.black87 : Colors.white70);

    // If embedded - keep small loader
    if (widget.embedded) {
      return SizedBox(
        height: widget.embeddedHeight ?? 180,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 46, height: 46, child: CircularProgressIndicator(strokeWidth: 3, color: _kPrimary)),
            const SizedBox(height: 8),
            Text(_tr(context, 'offers.loading', 'Loading offers...'), style: TextStyle(color: textColor)),
          ]),
        ),
      );
    }

    // Full-screen fancy loader
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        title: Text(_tr(context, 'offers.title', 'Offers'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // content column: animated header + skeleton list
            Column(
              children: [
                // Animated gradient header with rotating ring + pulse
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                  child: _FancyHeader(controller: _loaderController),
                ),
                // small spacing
                const SizedBox(height: 8),
                // skeleton list (staggered)
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemBuilder: (ctx, i) => _buildStaggeredSkeletonCard(i, cardSurface),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: 6,
                  ),
                ),
              ],
            ),

            // floating particles for depth (decorative)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _loaderController,
                  builder: (ctx, ch) => CustomPaint(
                    painter: _ParticlePainter(_loaderController.value, isLight ? Colors.grey : Colors.white.withOpacity(0.06)),
                  ),
                ),
              ),
            ),

            // optional small bottom informative bar
            Positioned(left: 16, right: 16, bottom: 18, child: _buildBottomBar(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textMuted = Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.85) ?? (isLight ? Colors.black54 : Colors.white60);
    final cardColor = isLight ? Theme.of(context).cardColor : const Color(0xFF111214);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.info_outline, size: 18, color: textMuted),
          const SizedBox(width: 8),
          Text(_tr(context, 'offers.fetching_info', 'Fetching the best offers for you...'), style: TextStyle(color: textMuted)),
        ]),
      ),
    );
  }

  Widget _buildStaggeredSkeletonCard(int index, Color cardSurface) {
    // compute a local t for stagger effect
    final raw = (_staggerController.value - index * 0.08).clamp(0.0, 1.0);
    final eased = Curves.easeOut.transform(raw);
    final opacity = eased;
    final translateY = (1 - eased) * 18;
    final scale = 0.97 + eased * 0.03;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, translateY),
        child: Transform.scale(
          scale: scale,
          child: _Shimmer(
            controller: _loaderController,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: cardSurface,
                borderRadius: BorderRadius.circular(_kCardRadius),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))],
                border: Border.all(color: _kPrimary.withOpacity(0.12), width: 0.8),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(_kCardRadius)),
                    child: Container(width: 140, height: double.infinity, color: Colors.grey[700]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(height: 16, width: double.infinity, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(6))),
                          const SizedBox(height: 8),
                          Container(height: 12, width: 140, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(6))),
                          const Spacer(),
                          Row(
                            children: [
                              Container(height: 14, width: 80, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(6))),
                              const Spacer(),
                              Container(height: 36, width: 90, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10))),
                            ],
                          )
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------
  // Build normal list item (modified: overlay "Up to" badge and View button above image)
  // ----------------------------
  Widget _buildBatchCard(BuildContext context, _BatchModel b, int index) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pageBackground = isLight ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFF060608);
    final cardSurface = isLight ? Theme.of(context).cardColor : const Color(0xFF111214);

    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? (isLight ? Colors.black87 : Colors.white70);

    double maxPct = 0.0;
    double batchTotal = 0.0;
    int minAllowedQty = 1 << 30;
    for (final o in b.offers) {
      final pct = _percentOff(o.originalPrice, o.price);
      if (pct > maxPct) maxPct = pct;
      batchTotal += o.price;
      minAllowedQty = math.min(minAllowedQty, o.allowedQty);
    }
    if (minAllowedQty == (1 << 30)) minAllowedQty = 10;

    final heroTag = 'batch_${b.id}';

    // formatted percent text
    final String pctText = (maxPct > 0)
        ? _tr(context, 'offers.up_to_pct', 'Up to {pct}%').replaceAll('{pct}', maxPct.toStringAsFixed(maxPct.truncateToDouble() == maxPct ? 0 : 1))
        : '';

    return GestureDetector(
      onTap: () {
        debugPrint('USER: tapped batch ${b.id}');
        Navigator.of(context).push(_fancyPageRoute(BatchDetailPage(batch: b, heroTag: heroTag)));
      },
      child: AnimatedBuilder(
        animation: _staggerController,
        builder: (ctx, child) {
          final t = (_staggerController.value - index * 0.06).clamp(0.0, 1.0);
          final eased = Curves.easeOut.transform(t);
          final opacity = eased;
          final translateY = (1 - eased) * 6;
          return Opacity(opacity: opacity, child: Transform.translate(offset: Offset(0, translateY), child: child));
        },
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: cardSurface,
            borderRadius: BorderRadius.circular(_kCardRadius),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 6))],
            border: Border.all(color: _kPrimary.withOpacity(0.12), width: 0.9),
          ),
          child: Row(
            children: [
              // IMAGE AREA with overlays
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(_kCardRadius)),
                child: Hero(
                  tag: heroTag,
                  child: SizedBox(
                    width: 180,
                    height: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // use top-level helper
                        imageFromUrl(b.imageUrl, controller: _loaderController, width: 180, height: double.infinity, fit: BoxFit.cover),
                        // top-left badge (Up to X%)
                        if (pctText.isNotEmpty)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)],
                              ),
                              child: Text(
                                pctText,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),
                        // top-right "View" small button overlay
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                debugPrint('USER: tapped view button on batch ${b.id}');
                                Navigator.of(context).push(_fancyPageRoute(BatchDetailPage(batch: b, heroTag: heroTag)));
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: cardSurface.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.visibility, size: 16, color: _kPrimary),
                                    const SizedBox(width: 6),
                                    Text(_tr(context, 'offers.view', 'View'), style: TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // CONTENT AREA
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              b.title.isNotEmpty ? b.title : _tr(context, 'offers.special_offer', 'Special Offer'),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Text(
                        b.description.isNotEmpty ? b.description : _tr(context, 'offers.items_in_offer', '${b.offers.length} items in this offer'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.9)),
                      ),

                      const Spacer(),

                      Row(
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${_money.format(batchTotal)} EGP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ]),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // custom page route with slide up + fade + scale
  Route _fancyPageRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim, secAnim) => page,
      transitionsBuilder: (context, anim, secAnim, child) {
        final opacity = anim.value;
        final scale = 0.98 + 0.02 * anim.value;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - anim.value) * 12),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('BUILD: OffersBatchesWidget.build (embedded=${widget.embedded}) _loading=$_loading _batches=${_batches.length}');

    if (_loading) {
      return _buildFancyLoader(context);
    }

    if (_error != null) {
      // show overlay toast once
      WidgetsBinding.instance.addPostFrameCallback((_) {
        OfferBannerToast.show(context, message: _error!, isSuccess: false);
      });

      return SizedBox(
        height: widget.embeddedHeight ?? 180,
        child: Center(
          child: Text(
            _error!,
            style: TextStyle(color: _kPrimary),
          ),
        ),
      );
    }

    if (_batches.isEmpty) {
      return SizedBox(
        height: widget.embeddedHeight ?? 140,
        child: Center(child: Text(_tr(context, 'offers.no_offers', 'No offers right now'), style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color))),
      );
    }

    if (widget.embedded) {
      final screenW = MediaQuery.of(context).size.width;
      final cardWidth = (screenW * 0.75).clamp(300.0, 560.0);
      return SizedBox(
        height: widget.embeddedHeight ?? 160,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          scrollDirection: Axis.horizontal,
          itemBuilder: (ctx, i) => SizedBox(width: cardWidth, child: _buildBatchCard(ctx, _batches[i], i)),
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemCount: _batches.length,
        ),
      );
    }

    // normal full screen offers list
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pageBackground = isLight ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFF060608);

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(title: Text(_tr(context, 'offers.title', 'Offers'), style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: _kPrimary, elevation: 0),
      body: RefreshIndicator(
        onRefresh: _fetchBatches,
        color: _kPrimary,
        child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemBuilder: (ctx, i) => _buildBatchCard(ctx, _batches[i], i),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: _batches.length),
      ),
    );
  }
}

/// -------------------------
/// Top-level image helper (shared)
/// - uses a loader controller to show shimmer while loading
/// - cross-fades into the real image
/// - falls back to _noImageFallback then the local asset
/// -------------------------
Widget imageFromUrl(String? url,
    {required AnimationController controller, BoxFit fit = BoxFit.cover, double? width, double? height}) {
  final candidate = (url ?? '').trim();
  final displayUrl = candidate.isNotEmpty ? candidate : _noImageFallback;

  return ClipRRect(
    borderRadius: BorderRadius.zero,
    child: Image.network(
      displayUrl,
      width: width,
      height: height,
      fit: fit,
      frameBuilder: (BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: frame == null
              ? SizedBox(
            width: width,
            height: height,
            child: _Shimmer(
              controller: controller,
              child: Container(
                color: Theme.of(context).cardColor,
                width: width,
                height: height,
                child: const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            ),
          )
              : FadeInImage(
            placeholder: MemoryImage(kTransparentImage),
            image: NetworkImage(displayUrl),
            fit: fit,
            width: width,
            height: height,
            fadeInDuration: const Duration(milliseconds: 360),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          _noImageFallback,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) {
            return Image.asset(_localPlaceholderAsset, width: width, height: height, fit: fit);
          },
        );
      },
    ),
  );
}

/// -------------------------
/// BatchDetailPage
/// -------------------------
class BatchDetailPage extends StatefulWidget {
  final _BatchModel batch;
  final String heroTag;
  const BatchDetailPage({Key? key, required this.batch, required this.heroTag}) : super(key: key);

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage> with TickerProviderStateMixin {
  late final AnimationController _loaderController;

  int _ordersCount = 1;
  bool _ordering = false;

  @override
  void initState() {
    super.initState();
    // local loader controller used by imageFromUrl and shimmer animations in this page
    _loaderController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _loaderController.dispose();
    super.dispose();
  }

  int get _maxOrders {
    if (widget.batch.offers.isEmpty) return 999;
    int minAllowed = widget.batch.offers.map((o) => o.allowedQty).reduce((a, b) => a < b ? a : b);
    if (minAllowed <= 0) return 999;
    return math.max(minAllowed * 100, 999);
  }

  double get _batchTotal {
    double t = 0;
    for (final o in widget.batch.offers) t += o.price;
    return t;
  }

  String _fmt(double v) => NumberFormat.currency(symbol: '', decimalDigits: 2).format(v);

  Future<void> _orderNow() async {
    if (_ordering) return;
    setState(() => _ordering = true);
    final subtotal = _batchTotal * _ordersCount;
    debugPrint('ACTION: ordering batch ${widget.batch.id} qty=$_ordersCount subtotal=$subtotal');

    // Build items list as plain Maps so PaymentScreen can accept them directly.
    final items = widget.batch.offers.map((o) {
      // pick best image available
      final image = (o.imageUrl?.isNotEmpty == true)
          ? o.imageUrl
          : (o.menuImageUrl?.isNotEmpty == true ? o.menuImageUrl : null);

      final name = (o.menuName.isNotEmpty) ? o.menuName : (o.title.isNotEmpty ? o.title : '');

      return <String, dynamic>{
        'offer_id': o.id,
        'menu_item_id': o.menuItemId,
        'name': name,
        'unit_price': o.price,
        'qty': _ordersCount,
        'total': (o.price * _ordersCount),
        'image_url': image,
        'restaurant_id': widget.batch.restaurantId,
      };
    }).toList();

    // Pass items via RouteSettings.arguments — PaymentScreen will read them if present.
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PaymentScreen(
        restaurantId: widget.batch.restaurantId,
        restaurantName: widget.batch.title,
      ),
      settings: RouteSettings(arguments: {
        'items': items,
        'subtotal': subtotal,
        'batch_id': widget.batch.id,
        'ordersCount': _ordersCount,
      }),
    ));

    if (mounted) setState(() => _ordering = false);
  }

  Widget _buildOfferRow(_OfferModel o) {
    // Show menuImageUrl first (if available), then the offer image, then fallback.
    final imageToShow = (o.menuImageUrl?.isNotEmpty == true)
        ? o.menuImageUrl!
        : ((o.imageUrl?.isNotEmpty == true) ? o.imageUrl! : _noImageFallback);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageFromUrl(imageToShow, controller: _loaderController, width: 64, height: 64, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.menuName.isNotEmpty ? o.menuName : (o.title.isNotEmpty ? o.title : _tr(context, 'offers.special_offer', 'Item')), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('${_fmt(o.price)} EGP', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_tr(context, 'offers.available_n', 'Available {n}').replaceAll('{n}', o.allowedQty.toString()), style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8))),
            if (o.originalPrice > 0 && o.originalPrice != o.price)
              Text('${_fmt(o.originalPrice)} EGP', style: TextStyle(decoration: TextDecoration.lineThrough, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7))),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.batch;
    final maxOrders = _maxOrders;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pageBackground = isLight ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFF060608);
    final cardSurface = isLight ? Theme.of(context).cardColor : const Color(0xFF111214);

    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        child: Stack(
          children: [
            // Main scrollable content
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Hero(
                    tag: widget.heroTag,
                    child: SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: imageFromUrl((b.imageUrl?.isNotEmpty == true) ? b.imageUrl! : _noImageFallback, controller: _loaderController, width: double.infinity, height: 220, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardSurface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 6))],
                        border: Border.all(color: _kPrimary.withOpacity(0.12), width: 0.9),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      b.title.isNotEmpty ? b.title : _tr(context, 'offers.special_offer', 'Offer batch'),
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (b.description.isNotEmpty) Text(b.description, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 8),
                              Text(_tr(context, 'offers.items_in_offer', 'Items in this offer'), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                              const SizedBox(height: 8),
                              Column(children: b.offers.map((o) => _buildOfferRow(o)).toList()),
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(_tr(context, 'offers.order_how_many', 'Order how many times?'), style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          onPressed: _ordersCount > 1 ? () => setState(() => _ordersCount--) : null,
                                          icon: const Icon(Icons.remove_circle_outline),
                                        ),
                                        Text('$_ordersCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        IconButton(
                                          onPressed: _ordersCount < maxOrders ? () => setState(() => _ordersCount++) : null,
                                          icon: const Icon(Icons.add_circle_outline),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_tr(context, 'offers.total_label', 'Total'), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: _batchTotal * _ordersCount),
                                    duration: const Duration(milliseconds: 360),
                                    builder: (context, value, child) => Text('${_fmt(value)} EGP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(_tr(context, 'offers.max_orders_allowed', 'Max orders allowed: {n}').replaceAll('{n}', maxOrders.toString()), style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8), fontSize: 12)),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),

            // Back button (top-left)
            Positioned(
              top: 12,
              left: 12,
              child: SafeArea(
                child: _circleButton(icon: Icons.arrow_back, onTap: () {
                  debugPrint('USER: back tapped on BatchDetailPage for ${widget.batch.id}');
                  Navigator.of(context).pop();
                }),
              ),
            ),

            // Bottom action bar (Order Now only)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _ordering ? null : _orderNow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _ordering
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                            _tr(context, 'offers.order_now', 'Order Now • {total} EGP').replaceAll('{total}', _fmt(_batchTotal * _ordersCount)),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardSurface = isLight ? Theme.of(context).cardColor : const Color(0xFF111214);
    final iconColor = Theme.of(context).iconTheme.color;
    return ClipOval(
      child: Material(
        color: cardSurface.withOpacity(0.95),
        child: InkWell(onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, color: iconColor))),
      ),
    );
  }
}

/// -------------------------
/// Lightweight fancy shimmer using loader controller
/// -------------------------
class _Shimmer extends StatelessWidget {
  final Widget child;
  final AnimationController controller;
  const _Shimmer({Key? key, required this.child, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, ch) {
        final v = controller.value;
        final dx = (v * 2) - 0.5;
        return ShaderMask(
          shaderCallback: (rect) {
            // dark-friendly shimmer stops
            return LinearGradient(
              begin: Alignment(-1 - dx, 0),
              end: Alignment(1 - dx, 0),
              colors: [Colors.grey.shade700, Colors.grey.shade600, Colors.grey.shade700],
              stops: const [0.1, 0.5, 0.9],
            ).createShader(Rect.fromLTWH(-rect.width + dx * rect.width, 0, rect.width * 2, rect.height));
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: child,
    );
  }
}

/// -------------------------
/// Fancy header widget (animated gradient + rotating ring + pulse)
/// -------------------------
class _FancyHeader extends StatelessWidget {
  final AnimationController controller;
  const _FancyHeader({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87;
    return AnimatedBuilder(animation: controller, builder: (ctx, ch) {
      final v = controller.value;
      // gradient alignment moves with v
      final align = Alignment(-1.0 + v * 2.0, 0);
      final ringRotation = v * 2 * math.pi;
      final pulse = 0.9 + 0.1 * (0.5 + 0.5 * math.sin(v * 2 * math.pi));

      return Row(
        children: [
          // rotating ring + pulse center
          Transform.rotate(
            angle: ringRotation,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_kPrimary.withOpacity(0.95), _kPrimary.withOpacity(0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 8))],
              ),
              child: Center(
                child: Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, shape: BoxShape.circle),
                    child: Icon(Icons.local_offer_rounded, color: _kPrimary),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // animated gradient title area
          Expanded(
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: align,
                  end: Alignment(-align.x, 0),
                  colors: [
                    Theme.of(context).cardColor.withOpacity(0.98),
                    Theme.of(context).scaffoldBackgroundColor.withOpacity(0.02),
                    Theme.of(context).cardColor.withOpacity(0.98),
                  ],
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 6))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Text(_tr(context, 'offers.top_offers_for_you', 'Top Offers for you'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor))),
                  // small animated indicator
                  Transform.translate(
                    offset: Offset(0, (0.5 - (v)) * 8),
                    child: Icon(Icons.refresh_rounded, color: Theme.of(context).iconTheme.color),
                  )
                ],
              ),
            ),
          )
        ],
      );
    });
  }
}

/// -------------------------
/// Particles painter (decorative floating circles)
/// -------------------------
class _ParticlePainter extends CustomPainter {
  final double t;
  final Color baseColor; // base color injected for consistent shading

  _ParticlePainter(this.t, this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 6; i++) {
      final dx = (i + 1) * size.width / 7;
      final baseY = size.height * 0.12 + (i % 2 == 0 ? 0 : size.height * 0.04);
      final y = baseY + math.sin(t * 2 * math.pi + i) * 12;
      final r = 6.0 + (i % 3) * 3.0;

      // use baseColor with slight opacity variation
      paint.color = baseColor.withOpacity(0.04 + (i % 3) * 0.02);

      canvas.drawCircle(Offset(dx, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.baseColor != baseColor;
}

/// -------------------------
/// Models
/// -------------------------
class _BatchModel {
  final String id;
  final String restaurantId;
  final String title;
  final String description;
  final String? imageUrl;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<_OfferModel> offers;

  _BatchModel({required this.id, required this.restaurantId, required this.title, required this.description, required this.imageUrl, required this.startDate, required this.endDate, required this.offers});
}

class _OfferModel {
  final String id;
  final String restaurantId;
  final String restaurantName;
  final String menuItemId;
  final String title;
  final String description;
  String? imageUrl;
  String? menuImageUrl;
  final String menuName;
  final double price;
  final double originalPrice;
  final int allowedQty;
  final DateTime? startDate;
  final DateTime? endDate;

  _OfferModel({required this.id, required this.restaurantId, required this.restaurantName, required this.menuItemId, required this.title, required this.description, required this.imageUrl, required this.menuImageUrl, required this.menuName, required this.price, required this.originalPrice, required this.allowedQty, required this.startDate, required this.endDate});
}

/// -------------------------
/// OfferBannerToast (local)
/// Professional rectangular overlay for bottom messages — themed and translatable.
/// Use: OfferBannerToast.show(context, message: "...", isSuccess: true/false)
/// -------------------------
class OfferBannerToast {
  static void show(BuildContext context, {required String message, bool isSuccess = true, Duration duration = const Duration(milliseconds: 2400)}) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(builder: (ctx) {
      return _OfferBannerToastWidget(
        message: message,
        isSuccess: isSuccess,
        duration: duration,
        onFinish: () {
          try {
            entry.remove();
          } catch (_) {}
        },
      );
    });

    overlay.insert(entry);
  }
}

class _OfferBannerToastWidget extends StatefulWidget {
  final String message;
  final bool isSuccess;
  final Duration duration;
  final VoidCallback onFinish;

  const _OfferBannerToastWidget({Key? key, required this.message, required this.isSuccess, required this.duration, required this.onFinish}) : super(key: key);

  @override
  State<_OfferBannerToastWidget> createState() => _OfferBannerToastWidgetState();
}

class _OfferBannerToastWidgetState extends State<_OfferBannerToastWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _offset = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
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
    final accent = widget.isSuccess ? (isLight ? Colors.green.shade700 : Colors.greenAccent.shade700) : (isLight ? Colors.red.shade700 : Colors.redAccent.shade200);
    final glow = widget.isSuccess ? Colors.greenAccent : Colors.redAccent;

    final bottomSafe = MediaQuery.of(context).viewPadding.bottom + 12.0;
    final cardColor = isLight ? Theme.of(context).cardColor.withOpacity(0.98) : const Color(0xFF111214).withOpacity(0.92);
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? (isLight ? Colors.black87 : Colors.white);

    return Positioned(
      bottom: bottomSafe,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offset,
        child: FadeTransition(
          opacity: _fade,
          child: Center(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.18)),
                  boxShadow: [
                    BoxShadow(color: glow.withOpacity(0.22), blurRadius: 28, spreadRadius: 2),
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  children: [
                    // small leading accent bar
                    Container(
                      width: 8,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: accent.withOpacity(0.28), blurRadius: 12, offset: const Offset(0, 3))],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(widget.isSuccess ? Icons.check_circle : Icons.error_outline, color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                      ),
                    ),
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
