// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/foundation.dart';
import 'package:talabak_users/constants/supabase_config.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_screen.dart';
import 'package:talabak_users/firebase_options.dart';
import 'package:talabak_users/l10n/app_localizations.dart';
import 'theme/light_theme.dart';
import 'theme/dark_theme.dart';
//Hi
const Color kPrimaryColor = Color(0xFF25AA50);

Future<void> ensureSupabaseSessionFromFirebase() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) return;

    final client = sb.Supabase.instance.client;
    try {
      await client.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
      );
    } catch (_) {
      // non-fatal, silently ignore
    }
  } catch (_) {
    // ignore unexpected errors during bootstrap
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Supabase init
  await initSupabase();

  // load onboarding and saved locale & theme
  final prefs = await SharedPreferences.getInstance();
  final bool seenOnboarding = prefs.getBool('seenOnboarding') ?? false;
  String? savedLocaleCode = prefs.getString('locale'); // "en" or "ar" or null
  String? savedThemeMode = prefs.getString('themeMode'); // "light" | "dark" | "system"

  // Default locale fallback
  if (savedLocaleCode == null) {
    savedLocaleCode = 'ar';
    await prefs.setString('locale', savedLocaleCode);
  }

  // Default theme fallback -> system
  if (savedThemeMode == null) {
    savedThemeMode = 'system';
    await prefs.setString('themeMode', savedThemeMode);
  }

  // Attempt to bootstrap Supabase session & cart (non-fatal; errors ignored)
  try {
    await ensureSupabaseSessionFromFirebase();
    // other bootstrap tasks (CartService, CartApi) can be placed here if needed
  } catch (_) { /* ignore non-fatal bootstrap errors */ }

  // Listen to auth state changes and attempt to ensure Supabase session + optionally sync remote locale
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user != null) {
      await ensureSupabaseSessionFromFirebase();

      // try to bootstrap user's language if present in customers table
      try {
        final client = sb.Supabase.instance.client;
        final resp = await client.from('customers').select('language').eq('auth_uid', user.uid).maybeSingle();
        final lang = resp?['language'] as String?;
        if (lang != null && (lang == 'ar' || lang == 'en')) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('locale', lang);
          TalabakApp.appKey.currentState?._setLocale(Locale(lang));
        }
      } catch (_) {
        // ignore errors
      }
    } else {
      // user signed out - optional cleanup
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('customer_id');
      } catch (_) {}
    }
  });

  runApp(TalabakApp(
    showOnboarding: !seenOnboarding,
    initialLocaleCode: savedLocaleCode,
    initialThemeModeString: savedThemeMode,
    key: TalabakApp.appKey,
  ));
}

class TalabakApp extends StatefulWidget {
  static final GlobalKey<_TalabakAppState> appKey = GlobalKey<_TalabakAppState>();

  final bool showOnboarding;
  final String? initialLocaleCode;
  final String? initialThemeModeString;

  const TalabakApp({Key? key, required this.showOnboarding, this.initialLocaleCode, this.initialThemeModeString}) : super(key: key);

  /// Call this from anywhere to change the app locale and persist it.
  static Future<void> setLocale(BuildContext context, Locale locale) async {
    final state = appKey.currentState;
    if (state != null) {
      await state._setLocale(locale);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('locale', locale.languageCode);
    }
  }

  /// Call this from anywhere to change the app ThemeMode and persist it.
  /// Accepts ThemeMode.light / ThemeMode.dark / ThemeMode.system
  static Future<void> setThemeMode(BuildContext context, ThemeMode mode) async {
    final state = appKey.currentState;
    if (state != null) {
      await state._setThemeMode(mode);
    } else {
      final prefs = await SharedPreferences.getInstance();
      final name = mode == ThemeMode.light ? 'light' : mode == ThemeMode.dark ? 'dark' : 'system';
      await prefs.setString('themeMode', name);
    }
  }

  @override
  _TalabakAppState createState() => _TalabakAppState();
}

class _TalabakAppState extends State<TalabakApp> {
  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    if (widget.initialLocaleCode != null && widget.initialLocaleCode!.isNotEmpty) {
      _locale = Locale(widget.initialLocaleCode!);
    } else {
      _locale = const Locale('ar');
    }

    final tTheme = widget.initialThemeModeString ?? 'system';
    _themeMode = tTheme == 'light' ? ThemeMode.light : (tTheme == 'dark' ? ThemeMode.dark : ThemeMode.system);
  }

  Future<void> _setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.languageCode);
    setState(() {
      _locale = locale;
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final name = mode == ThemeMode.light ? 'light' : mode == ThemeMode.dark ? 'dark' : 'system';
    await prefs.setString('themeMode', name);
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Set status bar color once (matching app bar)
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: kPrimaryColor,
      statusBarIconBrightness: Brightness.light,
    ));

    return MaterialApp(
      key: const ValueKey('TalabakMaterialApp'),
      title: 'Talabak',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: _locale,
      home: widget.showOnboarding ? const OnboardingScreen() : const MainScreen(),
    );
  }
}
//#25aa50