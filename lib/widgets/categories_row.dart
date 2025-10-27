import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

class RestaurantTypesRow extends StatefulWidget {
  final List<Map<String, dynamic>>? initialTypes;
  final void Function(Map<String, dynamic> type)? onTap; // optional: if provided parent handles tap
  final double baseItemSize;
  final double spacing;

  const RestaurantTypesRow({
    Key? key,
    this.initialTypes,
    this.onTap,
    this.baseItemSize = 64,
    this.spacing = 12,
  }) : super(key: key);

  @override
  State<RestaurantTypesRow> createState() => _RestaurantTypesRowState();
}

class _RestaurantTypesRowState extends State<RestaurantTypesRow> with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Color _primary = const Color(0xFF25AA50);

  List<Map<String, dynamic>> _types = [];
  bool _loading = true;
  String? _statusMessage;
  DateTime? _statusAt;

  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    if (widget.initialTypes != null && widget.initialTypes!.isNotEmpty) {
      _types = List<Map<String, dynamic>>.from(widget.initialTypes!);
      _loading = false;
      _animController.forward(from: 0);
    } else {
      _loadTypes();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() {
      _statusMessage = msg;
      _statusAt = DateTime.now();
    });
    Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_statusAt != null && DateTime.now().difference(_statusAt!).inSeconds >= 4) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
    if (kDebugMode) debugPrint('[RestaurantTypesRow] $msg');
  }

  Future<void> _loadTypes() async {
    setState(() => _loading = true);
    try {
      final resp = await _supabase
          .from('restaurant_types')
          .select('id, name_en, name_ar, image_url, created_at')
          .order('name_en', ascending: true);

      final List<Map<String, dynamic>> list = [];
      if (resp is List) {
        for (final r in resp) {
          try {
            list.add(Map<String, dynamic>.from(r as Map));
          } catch (_) {
            // ignore malformed row
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _types = list;
        _loading = false;
      });

      final loc = AppLocalizations.of(context);
      final loadedMsg = loc?.restaurantTypesLoadedCount(list.length) ?? '${list.length} types loaded';
      _setStatus(loadedMsg);
      _animController.forward(from: 0);
    } catch (e, st) {
      debugPrint('[_loadTypes] error: $e\n$st');
      _setStatus(AppLocalizations.of(context)?.errorUpdate ?? 'Failed to load types');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Robust fetch:
  /// 1) lookup join table restaurant_restaurant_types by type_id -> get restaurant ids -> fetch restaurants by id (preferred)
  /// 2) fallback: restaurants.restaurant_type_id == typeId
  /// 3) fallback: textual ilike matches on restaurant_type or category
  Future<List<Map<String, dynamic>>> _fetchRestaurantsForType(Map<String, dynamic> type) async {
    final List<Map<String, dynamic>> results = [];
    try {
      final String? idRaw = (type['id'] ?? type['type_id'])?.toString();
      final int? typeId = (idRaw != null && idRaw.isNotEmpty) ? int.tryParse(idRaw) : null;
      final String name = ((type['name_en'] ?? type['name_ar'] ?? type['name']) ?? '').toString().trim();

      // 1) try join table
      if (typeId != null) {
        try {
          final joinResp = await _supabase
              .from('restaurant_restaurant_types')
              .select('restaurant_id')
              .eq('type_id', typeId)
              .limit(1000);

          if (joinResp is List && joinResp.isNotEmpty) {
            final ids = joinResp
                .map((r) => r['restaurant_id']?.toString())
                .where((e) => e != null && e!.isNotEmpty)
                .map((e) => e!)
                .toList();

            if (ids.isNotEmpty) {
              final restResp = await _supabase
                  .from('restaurants')
                  .select('id, name, logo_url, prep_time_min, prep_time_max, is_open, is_hidden, status, category')
                  .inFilter('id', ids) // ✅ الطريقة الصح
                  .eq('status', 'accept')
                  .eq('is_hidden', false)
                  .order('name', ascending: true)
                  .limit(500);

              if (restResp is List && restResp.isNotEmpty) {
                for (final r in restResp) {
                  results.add(Map<String, dynamic>.from(r as Map));
                }
                return results;
              }
            }

          }
        } catch (e) {
          debugPrint('[RestaurantTypesRow] join-table fetch failed: $e');
          // continue to other fallbacks
        }

        // 2) fallback: direct restaurant_type_id column (in case some data uses direct FK)
        try {
          final resp = await _supabase
              .from('restaurants')
              .select('id, name, logo_url, prep_time_min, prep_time_max, is_open, is_hidden, status, category')
              .eq('restaurant_type_id', typeId)
              .eq('status', 'accept')
              .eq('is_hidden', false)
              .order('name', ascending: true)
              .limit(200);

          if (resp is List && resp.isNotEmpty) {
            for (final r in resp) results.add(Map<String, dynamic>.from(r as Map));
            if (results.isNotEmpty) return results;
          }
        } catch (e) {
          debugPrint('[RestaurantTypesRow] fetch by restaurant_type_id failed: $e');
        }
      }

      // 3) textual fallback (match name against restaurant_type or category)
      if (name.isNotEmpty) {
        try {
          final pattern = '%$name%';
          final resp1 = await _supabase
              .from('restaurants')
              .select('id, name, logo_url, prep_time_min, prep_time_max, is_open, is_hidden, status, category')
              .ilike('restaurant_type', pattern)
              .eq('status', 'accept')
              .eq('is_hidden', false)
              .order('name', ascending: true)
              .limit(200);
          if (resp1 is List && resp1.isNotEmpty) {
            for (final r in resp1) results.add(Map<String, dynamic>.from(r as Map));
            return results;
          }

          final resp2 = await _supabase
              .from('restaurants')
              .select('id, name, logo_url, prep_time_min, prep_time_max, is_open, is_hidden, status, category')
              .ilike('category', pattern)
              .eq('status', 'accept')
              .eq('is_hidden', false)
              .order('name', ascending: true)
              .limit(200);
          if (resp2 is List && resp2.isNotEmpty) {
            for (final r in resp2) results.add(Map<String, dynamic>.from(r as Map));
            return results;
          }
        } catch (e) {
          debugPrint('[RestaurantTypesRow] fallback name matching failed: $e');
        }
      }
    } catch (e, st) {
      debugPrint('[RestaurantTypesRow] _fetchRestaurantsForType ERROR: $e\n$st');
    }
    return results;
  }

  Future<void> _showRestaurantsForTypeInternal(Map<String, dynamic> type) async {
    final loc = AppLocalizations.of(context);
    _setStatus(loc?.uploadingImage ?? 'Loading...');
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc?.loading ?? 'Loading...'), duration: const Duration(milliseconds: 700)),
        );
      }

      final restaurants = await _fetchRestaurantsForType(type);
      _setStatus(loc?.imageUploaded ?? '${restaurants.length} restaurants');

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, controller) {
              final isAr = Localizations.localeOf(context).languageCode == 'ar';
              final title = isAr ? (type['name_ar'] ?? type['name_en']) : (type['name_en'] ?? type['name_ar']);
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10)],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          Expanded(child: Text((title ?? '').toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                          IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: restaurants.isEmpty
                          ? Center(child: Text(loc?.noRestaurantsFound ?? 'No restaurants found for this type'))
                          : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: restaurants.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final r = restaurants[i];
                          final logo = r['logo_url']?.toString();
                          final name = r['name']?.toString() ?? '';
                          final prepMin = r['prep_time_min']?.toString() ?? '';
                          final prepMax = r['prep_time_max']?.toString() ?? '';
                          final isOpen = r['is_open'] == true;
                          return ListTile(
                            onTap: () {
                              Navigator.of(context).pop();
                              final rid = r['id']?.toString();
                              if (rid != null && rid.isNotEmpty) {
                                Navigator.of(context).pushNamed('/restaurant/$rid');
                              }
                            },
                            leading: CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.grey.shade100,
                              backgroundImage: (logo != null && logo.isNotEmpty) ? NetworkImage(logo) : null,
                              child: (logo == null || logo.isEmpty) ? const Icon(Icons.fastfood) : null,
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(prepMin.isNotEmpty ? '$prepMin - $prepMax ${loc?.minutes ?? 'min'}' : (loc?.noPrepTime ?? '—')),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isOpen ? Colors.green.shade50 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isOpen ? (loc?.open ?? 'Open') : (loc?.closed ?? 'Closed'),
                                style: TextStyle(color: isOpen ? Colors.green.shade800 : Colors.black54, fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e, st) {
      debugPrint('[_showRestaurantsForType] error: $e\n$st');
      _setStatus(AppLocalizations.of(context)?.errorUpdate ?? 'Failed to load restaurants');
      if (mounted) {
        final msg = AppLocalizations.of(context)?.errorUpdate ?? 'Failed to load restaurants';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Widget _buildCircleImage(String? imageUrl, double size) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          imageUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Center(child: SizedBox(width: size * 0.28, height: size * 0.28, child: const CircularProgressIndicator(strokeWidth: 2)));
          },
          errorBuilder: (ctx, err, st) => _placeholder(size),
        ),
      );
    } else {
      return _placeholder(size);
    }
  }

  Widget _placeholder(double size) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(Icons.fastfood, size: size * 0.45, color: Colors.grey.shade600),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final double scale = (screenWidth / 360).clamp(0.85, 1.35);
    final double itemSize = (widget.baseItemSize * scale).roundToDouble();

    // Helper to measure text height with TextPainter, capping at maxLines (2)
    double measureTextHeight(String text, TextStyle style, double maxWidth, TextDirection textDirection, {int maxLines = 2}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: textDirection,
        maxLines: maxLines,
      )..layout(minWidth: 0, maxWidth: maxWidth);
      return tp.size.height;
    }

    final isArGlobal = Localizations.localeOf(context).languageCode == 'ar';
    final textDirectionForMeasure = isArGlobal ? TextDirection.rtl : TextDirection.ltr;
    final textStyle = TextStyle(fontSize: (12 * scale).clamp(10, 14), fontWeight: FontWeight.w600);
    final double textMaxWidth = itemSize + 8;

    // compute max item height among all types to set the ListView height (prevents overflow)
    double maxItemHeight = itemSize + 6 + measureTextHeight('A', textStyle, textMaxWidth, textDirectionForMeasure); // baseline
    for (final t in _types) {
      final displayName = (isArGlobal ? (t['name_ar'] ?? t['name_en']) : (t['name_en'] ?? t['name_ar']))?.toString() ?? '';
      final h = measureTextHeight(displayName, textStyle, textMaxWidth, textDirectionForMeasure, maxLines: 2);
      final itemH = itemSize + 6 + h;
      if (itemH > maxItemHeight) maxItemHeight = itemH;
    }

    // add some safety padding
    maxItemHeight = maxItemHeight + 12;

    // Wrap in SafeArea + LayoutBuilder to adapt to all screens and avoid bottom overflow (8px)
    return SafeArea(
      top: false,
      bottom: true,
      child: LayoutBuilder(builder: (context, constraints) {
        final bottomInset = MediaQuery.of(context).viewPadding.bottom + MediaQuery.of(context).viewInsets.bottom;
        final availableHeight = constraints.hasBoundedHeight ? constraints.maxHeight : MediaQuery.of(context).size.height;
        final double safeMax = (availableHeight - bottomInset - 8).clamp(0.0, double.infinity);
        double finalHeight = math.min(maxItemHeight, safeMax.isFinite && safeMax > 0 ? safeMax : maxItemHeight);

        // fallback small guard
        if (finalHeight.isNaN || finalHeight <= 0) finalHeight = maxItemHeight;

        if (_loading) {
          // keep loading box within safe area
          final loadingHeight = math.min(itemSize + 50, finalHeight);
          return SizedBox(
            height: loadingHeight,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(loc?.syncing ?? 'Syncing...', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        // compute text area height available for each item (so we can constrain text and apply ellipsis reliably)
        final double textAreaHeight = math.max(0.0, finalHeight - itemSize - 12); // 12 is spacing/padding guard

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: finalHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                // removed vertical padding to avoid extra height, keep horizontal spacing
                padding: EdgeInsets.symmetric(horizontal: widget.spacing),
                itemCount: _types.length,
                separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
                itemBuilder: (context, index) {
                  final t = _types[index];
                  final isAr = Localizations.localeOf(context).languageCode == 'ar';
                  final displayName = (isAr ? (t['name_ar'] ?? t['name_en']) : (t['name_en'] ?? t['name_ar']))?.toString() ?? '';
                  final imageUrl = t['image_url']?.toString();
                  final anim = CurvedAnimation(parent: _animController, curve: Interval((index * 0.03).clamp(0.0, 0.7), 1.0, curve: Curves.easeOut));
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.98, end: 1.0).animate(anim),
                      child: SizedBox(
                        width: itemSize + 20,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(itemSize / 2 + 8),
                            onTap: () {
                              if (widget.onTap != null) {
                                try {
                                  widget.onTap!.call(t);
                                } catch (e) {
                                  debugPrint('[RestaurantTypesRow] widget.onTap threw: $e');
                                }
                                return;
                              }
                              _showRestaurantsForTypeInternal(t);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Semantics(
                                  label: displayName,
                                  button: true,
                                  child: Container(
                                    width: itemSize,
                                    height: itemSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4, offset: const Offset(0, 2))],
                                    ),
                                    child: _buildCircleImage(imageUrl, itemSize),
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // ---------- TEXT AREA: constrained height + ellipsis ----------
                                SizedBox(
                                  width: itemSize + 8,
                                  height: textAreaHeight,
                                  child: Text(
                                    displayName,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                    softWrap: true,
                                    locale: Localizations.localeOf(context),
                                    textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                                    style: textStyle,
                                  ),
                                ),
                                // -------------------------------------------------------------
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (_statusMessage != null)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: Container(
                  key: ValueKey(_statusMessage),
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [_primary, _primary.withOpacity(0.85)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(_statusMessage ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

// ---------- RestaurantTypesPicker class unchanged ----------

class RestaurantTypesPicker extends StatefulWidget {
  final String? restaurantId;
  final void Function(List<int> selectedIds)? onSaved;

  const RestaurantTypesPicker({Key? key, this.restaurantId, this.onSaved}) : super(key: key);

  @override
  State<RestaurantTypesPicker> createState() => _RestaurantTypesPickerState();
}

class _RestaurantTypesPickerState extends State<RestaurantTypesPicker> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Color _primary = const Color(0xFF25AA50);

  List<Map<String, dynamic>> _types = [];
  Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadTypesAndSelection();
  }

  Future<void> _loadTypesAndSelection() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final resp = await _supabase.from('restaurant_types').select('id, name_en, name_ar, image_url').order('name_en', ascending: true);
      final list = <Map<String, dynamic>>[];
      if (resp is List) {
        for (final r in resp) {
          try {
            list.add(Map<String, dynamic>.from(r as Map));
          } catch (_) {}
        }
      }

      final sel = <int>{};
      if (widget.restaurantId != null && widget.restaurantId!.isNotEmpty) {
        final respSel = await _supabase
            .from('restaurant_restaurant_types')
            .select('type_id')
            .eq('restaurant_id', widget.restaurantId!);

        if (respSel is List) {
          for (final r in respSel) {
            try {
              sel.add((r['type_id'] as num).toInt());
            } catch (_) {}
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _types = list;
        _selected = sel;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[RestaurantTypesPicker] load error: $e\n$st');
      if (mounted) setState(() {
        _status = AppLocalizations.of(context)?.errorUpdate ?? 'Failed to load types';
        _loading = false;
      });
    }
  }

  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) _selected.remove(id);
      else _selected.add(id);
    });
  }

  Future<void> _save() async {
    final loc = AppLocalizations.of(context);
    if (widget.restaurantId == null || widget.restaurantId!.isEmpty) {
      widget.onSaved?.call(_selected.toList());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc?.saved ?? 'Saved')));
      return;
    }

    setState(() {
      _saving = true;
      _status = null;
    });

    try {
      if (widget.restaurantId != null && widget.restaurantId!.isNotEmpty) {
        await _supabase
            .from('restaurant_restaurant_types')
            .delete()
            .eq('restaurant_id', widget.restaurantId!);

        if (_selected.isNotEmpty) {
          final rows = _selected.map((tid) => {
            'restaurant_id': widget.restaurantId!,
            'type_id': tid,
          }).toList();
          await _supabase.from('restaurant_restaurant_types').insert(rows);
        }
      }

      widget.onSaved?.call(_selected.toList());

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(loc?.saved ?? 'Saved')));
        setState(() {
          _saving = false;
        });
      }
    } catch (e, st) {
      debugPrint('[RestaurantTypesPicker] save error: $e\n$st');
      if (mounted) {
        setState(() {
          _status = AppLocalizations.of(context)?.errorUpdate ?? 'Failed to save';
          _saving = false;
        });
      }
    }

  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (_loading) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc?.restaurantTypes ?? 'Restaurant types', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _types.map((t) {
            final id = (t['id'] is int) ? t['id'] as int : int.tryParse(t['id']?.toString() ?? '') ?? 0;
            final isSelected = _selected.contains(id);
            final display = Localizations.localeOf(context).languageCode == 'ar'
                ? (t['name_ar'] ?? t['name_en']).toString()
                : (t['name_en'] ?? t['name_ar']).toString();
            return FilterChip(
              label: Text(display, style: TextStyle(color: isSelected ? Colors.white : Colors.black87)),
              selected: isSelected,
              onSelected: (_) => _toggle(id),
              selectedColor: _primary,
              backgroundColor: Colors.grey[100],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_status != null) Text(_status!, style: TextStyle(color: Colors.red.shade700)),
        Row(
          children: [
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(loc?.save ?? 'Save'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _loadTypesAndSelection, child: Text(loc?.refresh ?? 'Refresh')),
          ],
        ),
      ],
    );
  }
}
