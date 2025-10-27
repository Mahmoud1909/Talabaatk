import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as ll;
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

const Color kPrimaryColor = Color(0xFF25AA50);

class MapPickerScreen extends StatefulWidget {
  final String apiKey;
  final gmap.LatLng? initialLatLng;
  final String? initialQuery;
  final String? countryCode;

  const MapPickerScreen({
    Key? key,
    required this.apiKey,
    this.initialLatLng,
    this.initialQuery,
    this.countryCode,
  }) : super(key: key);

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  // خرائط controllers
  gmap.GoogleMapController? _gmapController;
  final fmap.MapController _fmapController = fmap.MapController();

  // مركز الخريطة و الإحداثيات المختارة
  double _centerLat = 30.0444;
  double _centerLng = 31.2357;
  double? _pickedLat;
  double? _pickedLng;
  String? _pickedAddress;

  // علامات على الخرائط
  final Set<gmap.Marker> _gMarkers = {};
  final List<fmap.Marker> _fMarkers = [];

  // بحث / اقتراحات
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  static const Duration _debounceDuration = Duration(milliseconds: 400);
  bool _isSearching = false;
  bool _fetchingDetails = false;
  List<_PlacePrediction> _predictions = [];
  bool _showSuggestions = false;

  // Places session token
  String? _sessionToken;
  final _uuid = const Uuid();

  // تجنب طلب الموقع أكثر من مرة
  bool _triedToGetDeviceLocation = false;

  // كاش بسيط لجدول المدن
  List<Map<String, dynamic>>? _cachedCities;

  @override
  void initState() {
    super.initState();

    // إذا المرسل أعطى initialLatLng -> استخدمه
    if (widget.initialLatLng != null) {
      _centerLat = widget.initialLatLng!.latitude;
      _centerLng = widget.initialLatLng!.longitude;
      _pickedLat = _centerLat;
      _pickedLng = _centerLng;
      _updateMarkers();
      _reverseGeocodeAndSetAddress(_centerLat, _centerLng);
    } else {
      // حاول استخدام موقع الجهاز كإفتراضي بعد الرسم الأولي للشاشة
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryUseDeviceLocationAsDefault());
    }

    // إذا كان هناك استعلام أولي
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSearchChanged());
    }
  }

  @override
  void dispose() {
    _gmapController?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // -------------------------------- Places HTTP helpers --------------------------------

  void _ensureSessionToken() {
    _sessionToken ??= _uuid.v4();
  }

  void _clearSessionToken() {
    _sessionToken = null;
  }

  Future<List<_PlacePrediction>> _placesAutocomplete(String input) async {
    if (input.isEmpty) return [];
    _ensureSessionToken();

    final lang = Localizations.localeOf(context).languageCode;
    final params = <String, String>{
      'input': input,
      'key': widget.apiKey,
      'sessiontoken': _sessionToken!,
      'language': lang,
      'types': 'address',
    };
    if (widget.countryCode != null && widget.countryCode!.isNotEmpty) {
      params['components'] = 'country:${widget.countryCode}';
    }

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', params);
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return [];

    final Map<String, dynamic> json = jsonDecode(res.body) as Map<String, dynamic>;
    final status = (json['status'] as String?) ?? 'UNKNOWN';
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      debugPrint('Places autocomplete status: $status, error_message: ${json['error_message']}');
      return [];
    }

    final preds = <_PlacePrediction>[];
    final items = (json['predictions'] as List<dynamic>?) ?? [];
    for (final p in items) {
      final map = Map<String, dynamic>.from(p as Map);
      preds.add(_PlacePrediction(
        placeId: map['place_id']?.toString(),
        description: map['description']?.toString() ?? '',
        mainText: ((map['structured_formatting'] ?? {})['main_text'])?.toString() ?? '',
        secondaryText: ((map['structured_formatting'] ?? {})['secondary_text'])?.toString(),
      ));
    }
    return preds;
  }

  Future<_PlaceDetails?> _placeDetails(String placeId) async {
    if (placeId.isEmpty) return null;
    _ensureSessionToken();

    final lang = Localizations.localeOf(context).languageCode;
    final params = <String, String>{
      'place_id': placeId,
      'key': widget.apiKey,
      'sessiontoken': _sessionToken!,
      'fields': 'place_id,formatted_address,geometry,name',
      'language': lang,
    };

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', params);
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;

    final Map<String, dynamic> json = jsonDecode(res.body) as Map<String, dynamic>;
    final status = (json['status'] as String?) ?? 'UNKNOWN';
    if (status != 'OK') {
      debugPrint('Place details status: $status, error_message: ${json['error_message']}');
      return null;
    }

    final result = Map<String, dynamic>.from(json['result'] as Map);
    final geometry = result['geometry'] as Map<String, dynamic>?;
    final location = geometry != null ? (geometry['location'] as Map<String, dynamic>?) : null;
    final lat = location != null ? (location['lat'] as num?)?.toDouble() : null;
    final lng = location != null ? (location['lng'] as num?)?.toDouble() : null;
    final address = result['formatted_address']?.toString() ?? result['name']?.toString() ?? '';

    if (lat != null && lng != null) {
      return _PlaceDetails(latitude: lat, longitude: lng, formattedAddress: address);
    }
    return null;
  }

  // -------------------------------- UI actions --------------------------------

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () async {
      final q = _searchController.text.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _predictions = []);
        return;
      }

      if (!mounted) return;
      setState(() {
        _isSearching = true;
        _showSuggestions = true;
      });

      try {
        final preds = await _placesAutocomplete(q);
        if (!mounted) return;
        setState(() {
          _predictions = preds;
          _showSuggestions = preds.isNotEmpty;
        });
      } catch (e) {
        debugPrint('autocomplete error: $e');
      } finally {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _onSelectPrediction(_PlacePrediction p) async {
    _searchFocus.unfocus();
    setState(() {
      _showSuggestions = false;
      _predictions = [];
      _searchController.text = p.description;
      _fetchingDetails = true;
    });

    try {
      if (p.placeId == null) return;
      final details = await _placeDetails(p.placeId!);
      if (details != null) {
        await _moveTo(details.latitude, details.longitude, animate: true, zoom: 16);
        await _setPicked(details.latitude, details.longitude, addressHint: details.formattedAddress);
        _clearSessionToken();
      } else {
        await _reverseFromAddressString(p.description);
      }
    } catch (e) {
      debugPrint('selectPrediction error: $e');
      if (mounted) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc?.errorMessage('Failed to select place') ?? 'Failed to select place')),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingDetails = false);
    }
  }

  Future<void> _reverseFromAddressString(String address) async {
    try {
      final locs = await locationFromAddress(address);
      if (locs.isNotEmpty) {
        final l = locs.first;
        await _moveTo(l.latitude, l.longitude, animate: true, zoom: 16);
        await _setPicked(l.latitude, l.longitude, addressHint: address);
      } else {
        if (mounted) {
          final loc = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc?.noAddress ?? 'Address not found')),
          );
        }
      }
    } catch (e) {
      debugPrint('reverseFromAddressString error: $e');
      if (mounted) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc?.errorMessage('Failed to geocode address') ?? 'Failed to geocode address')),
        );
      }
    }
  }

  Future<void> _reverseGeocodeAndSetAddress(double lat, double lng) async {
    try {
      if (kIsWeb) {
        final lang = Localizations.localeOf(context).languageCode;
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/geocode/json',
          {
            'latlng': '$lat,$lng',
            'key': widget.apiKey,
            'language': lang,
          },
        );

        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final results = (data['results'] as List?) ?? [];
          if (results.isNotEmpty) {
            final formatted = results.first['formatted_address']?.toString() ?? '';
            if (mounted) setState(() => _pickedAddress = formatted.isNotEmpty ? formatted : (AppLocalizations.of(context)?.noAddress ?? 'Address not found'));
            return;
          }
        }
        if (mounted) setState(() => _pickedAddress = AppLocalizations.of(context)?.noAddress ?? 'Address not found');
      } else {
        final placemarks = await placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final formatted = [
            if (p.street != null && p.street!.isNotEmpty) p.street,
            if (p.locality != null && p.locality!.isNotEmpty) p.locality,
            if (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty) p.subAdministrativeArea,
            if (p.country != null && p.country!.isNotEmpty) p.country,
          ].where((e) => e != null && e.isNotEmpty).join(', ');
          if (mounted) setState(() => _pickedAddress = formatted.isNotEmpty ? formatted : (AppLocalizations.of(context)?.noAddress ?? 'Address not found'));
        } else {
          if (mounted) setState(() => _pickedAddress = AppLocalizations.of(context)?.noAddress ?? 'Address not found');
        }
      }
    } catch (e) {
      debugPrint('reverseGeocode error: $e');
      if (mounted) setState(() => _pickedAddress = AppLocalizations.of(context)?.noAddress ?? 'Address not found');
    }
  }

  Future<void> _setPicked(double lat, double lng, {String? addressHint}) async {
    if (!mounted) return;
    setState(() {
      _pickedLat = lat;
      _pickedLng = lng;
      _centerLat = lat;
      _centerLng = lng;
      _updateMarkers();
    });
    if (addressHint != null && addressHint.isNotEmpty) {
      setState(() => _pickedAddress = addressHint);
      return;
    }
    await _reverseGeocodeAndSetAddress(lat, lng);
  }

  Future<void> _moveTo(double lat, double lng, {bool animate = false, double? zoom}) async {
    _centerLat = lat;
    _centerLng = lng;
    if (kIsWeb) {
      try {
        _fmapController.move(ll.LatLng(lat, lng), zoom ?? 14);
      } catch (e) {
        debugPrint('flutter_map move error: $e');
      }
    } else {
      if (_gmapController == null) return;
      final update = gmap.CameraUpdate.newLatLngZoom(gmap.LatLng(lat, lng), (zoom ?? 14).toDouble());
      try {
        if (animate) {
          await _gmapController!.animateCamera(update);
        } else {
          await _gmapController!.moveCamera(update);
        }
      } catch (e) {
        debugPrint('camera error: $e');
      }
    }
  }

  Future<void> _onMapTap(double lat, double lng) async {
    await _setPicked(lat, lng);
    _clearSessionToken();
  }

  void _updateMarkers() {
    _gMarkers.clear();
    _fMarkers.clear();
    if (_pickedLat != null && _pickedLng != null) {
      _gMarkers.add(gmap.Marker(
        markerId: const gmap.MarkerId('picked'),
        position: gmap.LatLng(_pickedLat!, _pickedLng!),
      ));

      _fMarkers.add(
        fmap.Marker(
          point: ll.LatLng(_pickedLat!, _pickedLng!),
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, size: 40),
        ),
      );
    }
  }

  // ---------------- city override helpers ----------------

  /// يبحث في جدول cities محمّلًا الكاش إن لزم، ويطابق اسم المدينة بالعنوان (ar/en).
  Future<Map<String, dynamic>?> _findMatchingCity(String address) async {
    if (address.trim().isEmpty) return null;
    final lowerAddr = address.toLowerCase();

    try {
      if (_cachedCities == null) {
        final resp = await Supabase.instance.client.from('cities').select('id, city_name_en, city_name_ar').limit(2000);
        if (resp is List) {
          _cachedCities = List<Map<String, dynamic>>.from(resp.map((e) => Map<String, dynamic>.from(e as Map)));
        } else {
          _cachedCities = [];
        }
      }

      Map<String, dynamic>? best;
      int bestLen = 0;

      for (final c in _cachedCities!) {
        final en = (c['city_name_en'] ?? '').toString().toLowerCase();
        final ar = (c['city_name_ar'] ?? '').toString().toLowerCase();

        if (en.isNotEmpty && lowerAddr.contains(en) && en.length > bestLen) {
          best = c;
          bestLen = en.length;
        }
        if (ar.isNotEmpty && lowerAddr.contains(ar) && ar.length > bestLen) {
          best = c;
          bestLen = ar.length;
        }
      }

      return best;
    } catch (e) {
      debugPrint('findMatchingCity error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchOverrideForCityId(int cityId) async {
    try {
      final resp = await Supabase.instance.client
          .from('city_delivery_overrides')
          .select()
          .eq('city_id', cityId)
          .eq('active', true)
          .limit(1)
          .maybeSingle();
      if (resp == null) return null;
      return Map<String, dynamic>.from(resp as Map);
    } catch (e) {
      debugPrint('fetchOverrideForCityId error: $e');
      return null;
    }
  }

  // ----------------------------------------------------------------
  // IMPORTANT: previous flow showed a confirmation dialog when an override
  // was detected. Per request, we NOW APPLY OVERRIDE AUTOMATICALLY (no choice).
  // So when confirmSelection runs, if an override exists we directly pop the
  // override info. No dialog is shown.
  // ----------------------------------------------------------------

  // المستخدم يضغط تأكيد في الـ picker
  void _confirmSelection() async {
    final loc = AppLocalizations.of(context);
    if (_pickedLat != null && _pickedLng != null && _pickedAddress != null && _pickedAddress!.isNotEmpty) {
      try {
        final matchedCity = await _findMatchingCity(_pickedAddress!);

        if (matchedCity != null) {
          final cityId = (matchedCity['id'] is int) ? matchedCity['id'] as int : int.tryParse(matchedCity['id'].toString()) ?? -1;
          if (cityId != -1) {
            final override = await _fetchOverrideForCityId(cityId);
            if (override != null) {
              // ---- APPLY OVERRIDE AUTOMATICALLY (NO USER PROMPT) ----
              final feeNum = (override['fixed_fee'] is num) ? (override['fixed_fee'] as num).toDouble() : double.tryParse(override['fixed_fee']?.toString() ?? '') ?? 0.0;
              final isAr = Localizations.localeOf(context).languageCode == 'ar';
              final cityName = isAr ? (matchedCity['city_name_ar'] ?? matchedCity['city_name_en']) : (matchedCity['city_name_en'] ?? matchedCity['city_name_ar']);
              Navigator.of(context).pop({
                'address': _pickedAddress!,
                'latitude': _pickedLat!,
                'longitude': _pickedLng!,
                'override_fixed_fee': feeNum,
                'override_city_id': cityId,
                'override_city_name': cityName?.toString() ?? '',
              });
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('override detection error (auto-apply): $e');
      }

      // no override or not matched -> return normal selection
      Navigator.of(context).pop({
        'address': _pickedAddress!,
        'latitude': _pickedLat!,
        'longitude': _pickedLng!,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)?.pleasePickLocation ?? 'Please pick a location first')),
      );
    }
  }

  bool get _isDesktopPlatform =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS);

  // ---------------- Build UI ----------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final isRtl = Localizations.localeOf(context).languageCode == 'ar';
    final textDir = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final isDark = theme.brightness == Brightness.dark;

    // Buttons style - adapt to theme's color scheme
    final ButtonStyle addItemsStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      minimumSize: const Size(110, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: colorScheme.onSurface.withOpacity(0.12)),
      foregroundColor: colorScheme.onSurface,
      backgroundColor: theme.cardColor,
    );

    final ButtonStyle checkoutStyle = ElevatedButton.styleFrom(
      backgroundColor: kPrimaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      minimumSize: const Size(140, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

    return Directionality(
      textDirection: textDir,
      child: Scaffold(
        appBar: AppBar(
          title: Text(loc?.delivery_location ?? 'Pick Location'),
          backgroundColor: kPrimaryColor,
          actions: [
            IconButton(
              tooltip: loc?.useThisLocation ?? 'Use this location',
              icon: const Icon(Icons.check),
              onPressed: _confirmSelection,
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              GestureDetector(
                onTap: () => _searchFocus.unfocus(),
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: (kIsWeb || _isDesktopPlatform) ? _buildFlutterMap() : _buildGoogleMap(),
                ),
              ),

              // Search bar + suggestions
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  children: [
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(10),
                      color: theme.cardColor,
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => _onSearchChanged(),
                        onSubmitted: (_) => _onSearchChanged(),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search, color: colorScheme.onSurface.withOpacity(0.7)),
                          hintText: ((AppLocalizations.of(context) as dynamic?)?.searchPlaceHint) ?? 'Search address or place',
                          suffixIcon: _isSearching
                              ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                              : (_searchController.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _predictions = [];
                                _showSuggestions = false;
                              });
                              _clearSessionToken();
                            },
                          )
                              : null),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_showSuggestions && _predictions.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
                        child: Card(
                          elevation: 6,
                          color: theme.cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: _predictions.length,
                            itemBuilder: (ctx, i) {
                              final p = _predictions[i];
                              return ListTile(
                                title: Text(p.mainText.isNotEmpty ? p.mainText : p.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                                subtitle: p.secondaryText != null ? Text(p.secondaryText!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall) : null,
                                onTap: () => _onSelectPrediction(p),
                              );
                            },
                            separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // my location button
              Positioned(
                top: 12,
                right: 12,
                child: FloatingActionButton(
                  backgroundColor: theme.colorScheme.surface,
                  tooltip: loc?.useThisLocation ?? 'Use this location',
                  child: Icon(Icons.my_location, color: theme.iconTheme.color),
                  onPressed: () async {
                    await _tryUseDeviceLocationAsDefault();
                  },
                ),
              ),

              // bottom card with picked address & actions
              Positioned(
                left: 12,
                right: 12,
                bottom: 18,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: (_pickedAddress != null && _pickedAddress!.isNotEmpty)
                      ? Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: theme.cardColor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_pickedAddress!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _pickedLat = null;
                                      _pickedLng = null;
                                      _pickedAddress = null;
                                      _updateMarkers();
                                    });
                                  },
                                  style: addItemsStyle.copyWith(
                                    padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 12)),
                                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  ),
                                  child: Text(
                                    loc?.clear ?? 'Clear',
                                    style: TextStyle(color: colorScheme.onSurface),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _confirmSelection,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text(
                                  loc?.useThisLocation ?? 'Use this location',
                                  style: TextStyle(color: colorScheme.onPrimary),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // GoogleMap widget for mobile
  Widget _buildGoogleMap() {
    return gmap.GoogleMap(
      initialCameraPosition: gmap.CameraPosition(target: gmap.LatLng(_centerLat, _centerLng), zoom: 14),
      onMapCreated: (c) => _gmapController = c,
      onTap: (pos) => _onMapTap(pos.latitude, pos.longitude),
      markers: _gMarkers,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  // FlutterMap widget for web
  Widget _buildFlutterMap() {
    final center = ll.LatLng(_centerLat, _centerLng);

    return fmap.FlutterMap(
      mapController: _fmapController,
      options: fmap.MapOptions(
        initialCenter: ll.LatLng(_pickedLat ?? _centerLat, _pickedLng ?? _centerLng),
        initialZoom: 14,
        onTap: (tapPos, point) => _onMapTap(point.latitude, point.longitude),
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.example.app',
        ),
        fmap.MarkerLayer(
          markers: _fMarkers,
        ),
      ],
    );
  }

  Future<void> _tryUseDeviceLocationAsDefault() async {
    if (_triedToGetDeviceLocation) return;
    _triedToGetDeviceLocation = true;

    try {
      final pos = await _determinePosition();
      if (pos != null) {
        await _moveTo(pos.latitude, pos.longitude, animate: false, zoom: 14);
        await _setPicked(pos.latitude, pos.longitude);
      } else {
        if (mounted) {
          final loc = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc?.errorMessage('Could not get device location') ?? 'Could not get device location')),
          );
        }
      }
    } catch (e) {
      debugPrint('device location error: $e');
      if (mounted) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc?.errorMessage('Could not get device location') ?? 'Could not get device location')),
        );
      }
    }
  }

  /// Returns Position or null on failure/denied.
  Future<Position?> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        // suggest opening settings
        if (mounted) {
          final locDyn = (AppLocalizations.of(context) as dynamic?);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locDyn?.locationPermissionPermanentlyDenied ?? 'Location permission permanently denied. Enable in settings.'),
              action: SnackBarAction(
                label: locDyn?.openSettings ?? 'Settings',
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best, timeLimit: const Duration(seconds: 10));
      return pos;
    } catch (e) {
      debugPrint('determinePosition exception: $e');
      return null;
    }
  }
}

// small helper models
class _PlacePrediction {
  final String? placeId;
  final String description;
  final String mainText;
  final String? secondaryText;

  _PlacePrediction({
    this.placeId,
    required this.description,
    required this.mainText,
    this.secondaryText,
  });
}

class _PlaceDetails {
  final double latitude;
  final double longitude;
  final String formattedAddress;

  _PlaceDetails({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
  });
}
