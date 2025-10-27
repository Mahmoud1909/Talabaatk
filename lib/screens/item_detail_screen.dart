// lib/screens/item_detail_screen.dart
// Item detail screen — updated per request:
// - Message banner: no blur, appears at top, no colored underlines, contains rectangular image
// - Dark / Light friendly
// - Lighter, subtler animations for banners
// - Shows fallback image when image missing or failed to load

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:talabak_users/services/cart_api.dart';
import 'package:talabak_users/services/menu_item_service.dart';
import 'package:talabak_users/utils/menu_item_model.dart';
import 'package:talabak_users/services/cart_service.dart';

/// ----------------------------
/// Small file-level localization helper
/// ----------------------------
String _tr(BuildContext context, String key, String fallback) {
  final locale = Localizations.localeOf(context);
  final lang = locale.languageCode.toLowerCase();
  final dict = _localDict[lang] ?? _localDict['en']!;
  return dict[key] ?? fallback;
}

final Map<String, Map<String, String>> _localDict = {
  'en': {
    'item.title': 'Item',
    'item.loading': 'Loading item...',
    'item.load_failed': 'Failed to load item data. Please check your connection and try again.',
    'please_sign_in': 'Please sign in to add items to cart',
    'adding_to_cart': 'Adding to cart...',
    'added_to_cart': 'Added to cart',
    'failed_add_to_cart': 'Failed to add item to cart',
    'choose_option': 'Choose option',
    'add_button': 'Add — {total}',
  },
  'ar': {
    'item.title': 'عن المنتج',
    'item.loading': 'جاري تحميل المنتج...',
    'item.load_failed': 'فشل تحميل بيانات المنتج. يرجى التحقق من الاتصال والمحاولة لاحقًا.',
    'please_sign_in': 'الرجاء تسجيل الدخول لإضافة المنتج إلى السلة',
    'adding_to_cart': 'جاري الإضافة إلى السلة...',
    'added_to_cart': 'تمت الإضافة إلى السلة',
    'failed_add_to_cart': 'فشل إضافة المنتج إلى السلة',
    'choose_option': 'اختر خيار',
    'add_button': 'أضف — {total}',
  },
};

/// Ensure Supabase session using Firebase ID token (best-effort).
Future<void> ensureSupabaseSessionFromFirebase() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) return;

    final client = supabase.Supabase.instance.client;
    try {
      await client.auth.signInWithIdToken(
        provider: supabase.OAuthProvider.google,
        idToken: idToken,
      );
    } catch (e) {
      // non-fatal
    }
  } catch (_) {}
}

/// Item detail screen
class ItemDetailScreen extends StatefulWidget {
  final String itemId;
  final String? cartItemId;
  final String? restaurantId;

  const ItemDetailScreen({Key? key, required this.itemId, this.cartItemId, this.restaurantId}) : super(key: key);

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  bool _loading = true;
  String? _error;
  MenuItemWithVariants? _data;

  String? _selectedVariantId;
  int _quantity = 1;
  bool _adding = false;

  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _loadItem();
  }

  Future<void> _loadItem() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await MenuItemService.getItemWithVariants(widget.itemId);
      if (data == null) throw Exception('Item not found');

      if (widget.cartItemId != null) {
        final cartItem = CartService.instance.findById(widget.cartItemId!);
        if (cartItem != null && cartItem.menuItemId == widget.itemId) {
          _quantity = cartItem.qty;
          _selectedVariantId = cartItem.variantId ?? (data.variants.isNotEmpty ? data.variants.first.id : null);
        } else {
          _selectedVariantId = data.variants.isNotEmpty ? data.variants.first.id : null;
        }
      } else {
        _selectedVariantId = data.variants.isNotEmpty ? data.variants.first.id : null;
      }

      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      MessageBanner.showNegative(context, _tr(context, 'item.load_failed', 'Failed to load item data. Please check your connection and try again.'));
    }
  }

  double _unitPrice() {
    if (_data == null) return 0.0;
    final baseAfterDiscount = _data!.item.effectivePrice();
    MenuItemVariant? variant;
    try {
      variant = _data!.variants.firstWhere((v) => v.id == _selectedVariantId);
    } catch (_) {
      variant = null;
    }
    return baseAfterDiscount + (variant?.extraPrice ?? 0.0);
  }

  String _formatPrice(double p) => '${p.toStringAsFixed(2)} EGP';

  Future<String?> getOrCreateCustomerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('customer_id');
      if (cached != null && cached.isNotEmpty) return cached;
    } catch (_) {}

    await ensureSupabaseSessionFromFirebase();

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;
    final firebaseUid = firebaseUser.uid;

    try {
      final client = supabase.Supabase.instance.client;
      final resp = await client
          .from('customers')
          .upsert({
        'auth_uid': firebaseUid,
        'email': firebaseUser.email,
        'first_name': firebaseUser.displayName,
        'photo_url': firebaseUser.photoURL,
      }, onConflict: 'auth_uid')
          .select('id')
          .maybeSingle();

      if (resp == null) return null;
      final m = Map<String, dynamic>.from(resp as Map);
      final id = m['id']?.toString();
      if (id != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('customer_id', id);
        } catch (_) {}
        return id;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _addToCart() async {
    if (_data == null || _adding) return;
    setState(() => _adding = true);

    final customerId = await getOrCreateCustomerId();
    if (customerId == null) {
      if (!mounted) return;
      MessageBanner.showNegative(context, _tr(context, 'please_sign_in', 'Please sign in to add items to cart'));
      setState(() => _adding = false);
      return;
    }

    final variant = _data!.variants.isNotEmpty
        ? _data!.variants.firstWhere(
          (v) => v.id == _selectedVariantId,
      orElse: () => _data!.variants.first,
    )
        : MenuItemVariant(
      id: '',
      menuItemId: _data!.item.id,
      name: '',
      extraPrice: 0.0,
    );

    final restaurantId = _data!.item.restaurantId;
    final provisionalId = '${_data!.item.id}-${variant.id.isNotEmpty ? variant.id : 'novar'}-local';

    String affectedId;
    try {
      // optimistic local update
      affectedId = CartService.instance.addOrIncrement(
        provisionalId: provisionalId,
        menuItemId: _data!.item.id,
        name: _data!.item.name,
        unitPrice: _unitPrice(),
        qty: _quantity,
        variantId: variant.id.isNotEmpty ? variant.id : null,
        variantName: variant.name,
        imageUrl: _data!.item.imageUrl,
        restaurantId: restaurantId,
      );

      // transient info banner (no blur, top of screen), include image
      MessageBanner.showPositive(context, _tr(context, 'adding_to_cart', 'Adding to cart...'),
          imageUrl: _data!.item.imageUrl);
    } catch (e) {
      affectedId = provisionalId;
      CartService.instance.addItem(CartItem(
        id: provisionalId,
        menuItemId: _data!.item.id,
        name: _data!.item.name,
        unitPrice: _unitPrice(),
        variantId: variant.id.isNotEmpty ? variant.id : null,
        variantName: variant.name,
        qty: _quantity,
        imageUrl: _data!.item.imageUrl,
        restaurantId: restaurantId,
      ));
    }

    final passLocalId = (affectedId == provisionalId) ? provisionalId : null;

    try {
      // server call
      await CartApi.addToCart(
        customerId: customerId,
        restaurantId: restaurantId,
        menuItemId: _data!.item.id,
        variantId: variant.id.isNotEmpty ? variant.id : null,
        name: _data!.item.name,
        clientUnitPrice: _unitPrice(),
        qty: _quantity,
        imageUrl: _data!.item.imageUrl,
        localCartItemId: passLocalId,
      );

      await CartApi.fetchAndSyncCartForUserAndRestaurant(restaurantId);

      if (mounted) {
        // confirmation banner at top, short-lived, include image
        MessageBanner.showPositive(context, _tr(context, 'added_to_cart', 'Added to cart'),
            imageUrl: _data!.item.imageUrl);
      }
    } catch (e) {
      final existing = CartService.instance.findById(affectedId);
      if (existing != null) {
        final newQty = existing.qty - _quantity;
        if (newQty <= 0) {
          CartService.instance.removeItem(existing.id);
        } else {
          CartService.instance.updateQty(existing.id, newQty);
        }
      }

      if (mounted) {
        MessageBanner.showNegative(context,
            '${_tr(context, 'failed_add_to_cart', 'Failed to add item to cart')}: ${e.toString()}',
            imageUrl: _data?.item.imageUrl);
      }
      return;
    } finally {
      if (!mounted) return;
      setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_tr(context, 'item.title', 'Item')),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18.0),
                  child: Text(
                    _tr(context, 'item.load_failed', 'Failed to load item data. Please check your connection and try again.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: Theme.of(context).brightness == Brightness.light ? Colors.red.shade50 : Colors.red.shade900.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _tr(context, 'item.load_failed', 'Failed to load item data. Please check your connection and try again.'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                    onPressed: () {
                      setState(() => _error = null);
                    },
                  )
                ],
              ),
            ),
          ],
        ),
      );
    }

    final data = _data!;
    final item = data.item;

    final bg = Theme.of(context).scaffoldBackgroundColor;
    final cardBg = Theme.of(context).cardColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Main rectangular image (professional look)
                Container(
                  height: MediaQuery.of(context).size.width * (10 / 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).brightness == Brightness.light ? Colors.grey[200] : Colors.grey[850],
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).brightness == Brightness.light ? Colors.black.withOpacity(0.04) : Colors.black.withOpacity(0.32),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      )
                    ],
                    border: Border.all(color: Theme.of(context).brightness == Brightness.light ? Colors.transparent : Colors.white10),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: item.imageUrl != null
                      ? CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, __) => Container(color: Theme.of(context).brightness == Brightness.light ? Colors.grey[200] : Colors.grey[800]),
                    errorWidget: (_, __, ___) => Center(child: Icon(Icons.fastfood, size: 48, color: Theme.of(context).iconTheme.color)),
                  )
                      : Center(child: Icon(Icons.fastfood, size: 48, color: Theme.of(context).iconTheme.color)),
                ),

                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Text(item.name,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.titleLarge?.color))),
                    const SizedBox(width: 8),
                    Text(_formatPrice(_unitPrice()),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodySmall?.color)),
                  ],
                ),
                const SizedBox(height: 8),

                if (item.description != null && item.description!.isNotEmpty)
                  Text(item.description!, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                const SizedBox(height: 16),

                if (data.variants.isNotEmpty) ...[
                  Text(_tr(context, 'choose_option', 'Choose option'),
                      style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color)),
                  const SizedBox(height: 8),
                  Column(
                    children: data.variants.map((v) {
                      final id = v.id;
                      final extra = (v.extraPrice ?? 0.0);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Radio<String?>(value: id, groupValue: _selectedVariantId, onChanged: (val) => setState(() => _selectedVariantId = val)),
                        title: Text(v.name ?? 'Option', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                        trailing: extra != 0.0 ? Text('+${extra.toStringAsFixed(2)} EGP', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)) : null,
                        onTap: () => setState(() => _selectedVariantId = id),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),

          // Bottom bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cardBg,
              boxShadow: [
                BoxShadow(
                    color: Theme.of(context).brightness == Brightness.light ? Colors.black.withOpacity(0.06) : Colors.black.withOpacity(0.18),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[800],
                      borderRadius: BorderRadius.circular(28)),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (_quantity > 1) setState(() => _quantity--);
                        },
                        icon: const Icon(Icons.remove),
                        splashRadius: 20,
                      ),
                      Text('$_quantity',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color)),
                      IconButton(
                        onPressed: () => setState(() => _quantity++),
                        icon: const Icon(Icons.add),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: _adding ? null : _addToCart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    child: _adding
                        ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                        : Text(
                      _tr(context, 'add_button', 'Add — {total}').replaceAll('{total}', _formatPrice(_unitPrice() * _quantity)),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// -------------------------
/// MessageBanner (overlay) — top-positioned, no blur, no vertical color bar,
/// shows optional rectangular item image on the left. Uses fallback when needed.
/// Use: MessageBanner.showPositive(context, message, imageUrl: url);
/// -------------------------
class MessageBanner {
  static const Duration _defaultDuration = Duration(milliseconds: 1400);

  static void _show(
      BuildContext context,
      String message, {
        required bool positive,
        Duration duration = _defaultDuration,
        String? imageUrl,
      }) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final Color good = const Color(0xFF2E7D32);
    final Color bad = const Color(0xFFD32F2F);
    final color = positive ? good : bad;

    late OverlayEntry entry;
    entry = OverlayEntry(builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final topPadding = media.viewPadding.top + 12;
      return Positioned(
        left: 12,
        right: 12,
        top: topPadding,
        child: SafeArea(
          top: false,
          child: _TopBanner(
            message: message,
            color: color,
            duration: duration,
            onFinish: () {
              try {
                entry.remove();
              } catch (_) {}
            },
            imageUrl: imageUrl,
          ),
        ),
      );
    });

    overlay.insert(entry);
  }

  static void showPositive(BuildContext context, String message, {Duration? duration, String? imageUrl}) =>
      _show(context, message, positive: true, duration: duration ?? _defaultDuration, imageUrl: imageUrl);

  static void showNegative(BuildContext context, String message, {Duration? duration, String? imageUrl}) =>
      _show(context, message, positive: false, duration: duration ?? _defaultDuration, imageUrl: imageUrl);
}

class _TopBanner extends StatefulWidget {
  final String message;
  final Color color;
  final Duration duration;
  final VoidCallback onFinish;
  final String? imageUrl;

  const _TopBanner({
    Key? key,
    required this.message,
    required this.color,
    required this.duration,
    required this.onFinish,
    this.imageUrl,
  }) : super(key: key);

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;

  // fallback image (requested)
  static const String _fallback =
      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSEnhiRiCprmjqoBUfgALTU7nHm6Db4nxMv3w&s';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _offset = Tween<Offset>(begin: const Offset(0, -0.08), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
    final bgColor = Theme.of(context).cardColor.withOpacity(isLight ? 0.98 : 0.94);
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? (isLight ? Colors.black87 : Colors.white);

    // choose image (use fallback when null/empty)
    final String imgUrl = (widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty) ? widget.imageUrl!.trim() : _fallback;

    // shadow - softer for light, stronger for dark
    final List<BoxShadow> imgShadows = isLight
        ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 3))]
        : [BoxShadow(color: Colors.black.withOpacity(0.36), blurRadius: 12, offset: const Offset(0, 6))];

    return SlideTransition(
      position: _offset,
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isLight ? 0.06 : 0.26), blurRadius: 10, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              // always show image container (uses fallback if needed)
              Container(
                width: 64,
                height: 48,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isLight ? Colors.grey[100] : Colors.grey[800],
                  border: Border.all(color: isLight ? Colors.transparent : Colors.white10),
                  boxShadow: imgShadows,
                ),
                clipBehavior: Clip.hardEdge,
                child: CachedNetworkImage(
                  imageUrl: imgUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: isLight ? Colors.grey[200] : Colors.grey[800]),
                  errorWidget: (_, __, ___) => Image.network(_fallback, fit: BoxFit.cover),
                ),
              ),

              // Message text
              Expanded(
                child: Text(
                  widget.message,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor, decoration: TextDecoration.none),
                ),
              ),

              // subtle icon
              const SizedBox(width: 8),
              Icon(Icons.check_circle_outline, color: widget.color),
              const SizedBox(width: 6),
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
    );
  }
}
