// lib/screens/onboarding_screen.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:talabak_users/screens/main_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talabak_users/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:desktop_webview_auth/desktop_webview_auth.dart';
import 'package:desktop_webview_auth/google.dart';
import 'package:flutter/services.dart';

// localization
import 'package:talabak_users/l10n/app_localizations.dart';
import 'package:talabak_users/main.dart' show TalabakApp; // used to set locale

// New imports for Apple Sign-In + crypto
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';

const String _kGoogleWebClientId =
    '16300746563-an0smgbhf2q4e2dc6ur9d4u3bme4upt3.apps.googleusercontent.com';

const String _kLocalRedirectUri = 'http://localhost:8585/';

/// Custom exception to surface user-friendly errors from signInWithGoogle()/Apple.
class SignInException implements Exception {
  final String code;
  final String message;

  SignInException(this.code, this.message);

  @override
  String toString() => 'SignInException($code): $message';
}

// --- Helper functions for Apple nonce ---
String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

String _sha256ofString(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  return digest.toString();
}


Future<UserCredential?> signInWithGoogle() async {
  // NOTE: This function now throws SignInException for real errors so caller can
  // display a user-facing message. Returns null when user cancels the flow.
  debugPrint("🚀 [FLOW] Starting Google Sign-In...");

  try {
    late UserCredential userCredential;

    if (kIsWeb) {
      debugPrint("[WEB] Detected Web platform. Signing in with popup...");
      try {
        final GoogleAuthProvider authProvider = GoogleAuthProvider();
        userCredential = await FirebaseAuth.instance.signInWithPopup(
          authProvider,
        );
        debugPrint(
          "[WEB] signInWithPopup returned user: ${userCredential.user?.email}",
        );
      } on FirebaseAuthException catch (e, st) {
        debugPrint("[WEB][ERROR] Firebase web signInWithPopup failed: $e");
        debugPrint(st.toString());
        throw SignInException(
          'web_auth_failed',
          e.message ?? 'Failed to sign in with Google (web).',
        );
      } catch (e, st) {
        debugPrint("[WEB][ERROR] Unexpected web sign-in error: $e");
        debugPrint(st.toString());
        throw SignInException(
          'web_unexpected',
          'Unexpected error during Google sign-in (web).',
        );
      }

      // ----- CASE 2: DESKTOP (Windows / macOS / Linux) -----
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      debugPrint(
        "[DESKTOP] Detected Desktop platform. Starting desktop OAuth flow...",
      );

      final args = GoogleSignInArgs(
        clientId: _kGoogleWebClientId,
        redirectUri: _kLocalRedirectUri,
        scope: "email profile openid",
      );

      try {
        debugPrint(
          "[DESKTOP] Opening sign-in window (desktop_webview_auth)...",
        );
        final result = await DesktopWebviewAuth.signIn(args);

        if (result == null) {
          debugPrint(
            "[DESKTOP][INFO] User cancelled Google Sign-In (Desktop).",
          );
          return null; // user cancelled -> not an error
        }

        // Basic validation of tokens presence
        if ((result.accessToken == null || result.accessToken!.isEmpty) &&
            (result.idToken == null || result.idToken!.isEmpty)) {
          debugPrint(
            "[DESKTOP][ERROR] No tokens returned from OAuth provider.",
          );
          throw SignInException(
            'no_tokens',
            'No tokens returned from OAuth provider.',
          );
        }

        // Exchange tokens with Firebase
        try {
          debugPrint(
            "[DESKTOP] Creating Google credential and signing in to Firebase...",
          );
          final credential = GoogleAuthProvider.credential(
            accessToken: result.accessToken,
            idToken: result.idToken,
          );

          userCredential = await FirebaseAuth.instance.signInWithCredential(
            credential,
          );
          debugPrint(
            "[DESKTOP] Firebase sign-in successful: ${userCredential.user?.email}",
          );
        } on FirebaseAuthException catch (e, st) {
          debugPrint(
            "[DESKTOP][ERROR] Firebase signInWithCredential failed: $e",
          );
          debugPrint(st.toString());
          throw SignInException(
            'firebase_token_exchange_failed',
            'Failed to sign in with the provided Google credential.',
          );
        } catch (e, st) {
          debugPrint("[DESKTOP][ERROR] Unexpected error exchanging tokens: $e");
          debugPrint(st.toString());
          throw SignInException(
            'desktop_unexpected',
            'Unexpected error during desktop sign-in.',
          );
        }
      } on MissingPluginException catch (e) {
        debugPrint(
          "[DESKTOP][ERROR] Missing plugin for desktop_webview_auth: $e",
        );
        throw SignInException(
          'missing_plugin',
          'Desktop sign-in not available: missing plugin or platform support.',
        );
      } catch (e, st) {
        debugPrint(
          "[DESKTOP][ERROR] Unexpected error during desktop OAuth flow: $e",
        );
        debugPrint(st.toString());
        throw SignInException(
          'desktop_flow_error',
          'Unexpected error during desktop sign-in.',
        );
      }

      // ----- CASE 3: MOBILE (Android / iOS) -----
    } else {
      debugPrint(
        "[MOBILE] Detected Mobile platform. Opening Google Sign-In via google_sign_in package...",
      );
      try {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

        if (googleUser == null) {
          debugPrint(
            "[MOBILE][INFO] Google Sign-In was cancelled by the user (mobile).",
          );
          return null;
        }

        debugPrint("[MOBILE] Google account selected: ${googleUser.email}");

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        debugPrint(
          "[MOBILE] Firebase sign-in successful: ${userCredential.user?.email}",
        );
      } on PlatformException catch (e, st) {
        debugPrint(
          "[MOBILE][ERROR] PlatformException during mobile sign-in: $e",
        );
        debugPrint(st.toString());
        throw SignInException(
          'mobile_platform_error',
          'Failed to sign in on this device.',
        );
      } on FirebaseAuthException catch (e, st) {
        debugPrint("[MOBILE][ERROR] Firebase mobile signIn failed: $e");
        debugPrint(st.toString());
        throw SignInException(
          'firebase_mobile_failed',
          e.message ?? 'Firebase login failed.',
        );
      } catch (e, st) {
        debugPrint(
          "[MOBILE][ERROR] Unexpected error during mobile sign-in: $e",
        );
        debugPrint(st.toString());
        throw SignInException(
          'mobile_unexpected',
          'Unexpected error during mobile sign-in.',
        );
      }
    }

    // ----- AFTER SUCCESSFUL LOGIN: COMMON STEPS -----
    debugPrint("🔥 [COMMON] Firebase authentication flow completed.");
    final user = userCredential.user;
    if (user == null) {
      debugPrint("[COMMON][ERROR] No Firebase user returned after sign-in.");
      throw SignInException(
        'no_user',
        'No Firebase user returned after sign-in.',
      );
    }

    // Firebase ID token
    String? idToken;
    try {
      idToken = await user.getIdToken();
      debugPrint(
        "[COMMON] Firebase ID token retrieved: ${idToken != null && idToken.isNotEmpty}",
      );
    } catch (e) {
      debugPrint("[COMMON][WARN] Failed to get Firebase ID token: $e");
      // not fatal for user sign-in, continue
    }

    // Sync with Supabase (optional)
    final supabaseClient = supabase.Supabase.instance.client;
    if (idToken != null && idToken.isNotEmpty) {
      try {
        debugPrint("[COMMON] Signing in to Supabase using Firebase idToken...");
        final authResponse = await supabaseClient.auth.signInWithIdToken(
          provider: supabase.OAuthProvider.google,
          idToken: idToken,
        );
        debugPrint(
          "[COMMON] Supabase sign-in finished. Session present: ${authResponse.session != null}",
        );
      } catch (e, st) {
        debugPrint("[COMMON][WARN] Supabase signInWithIdToken failed: $e");
        debugPrint(st.toString());
        // don't fail the whole flow for Supabase sync problems
      }
    } else {
      debugPrint(
        "[COMMON][INFO] No idToken available, skipping Supabase sign-in.",
      );
    }

    // Upsert into Supabase customers table (best-effort)
    try {
      debugPrint("[COMMON] Upserting user into Supabase 'customers' table...");
      final upsertResponse = await supabaseClient.from('customers').upsert({
        'auth_uid': user.uid,
        'email': user.email,
        'first_name': user.displayName,
        'photo_url': user.photoURL,
      });
      debugPrint("[COMMON] Upsert result: $upsertResponse");
    } catch (e, st) {
      debugPrint("[COMMON][ERROR] Error during Supabase upsert: $e");
      debugPrint(st.toString());
      // non-fatal
    }

    return userCredential;
  } catch (e) {
    // Re-throw SignInException or wrap unknown errors
    if (e is SignInException) rethrow;
    debugPrint("💥 [OUTER] Error during Google Sign-In (outer catch): $e");
    throw SignInException(
      'unexpected_outer',
      'Unexpected error during sign-in.',
    );
  }
}

// ---------------- Apple Sign-In (new) ----------------

Future<UserCredential?> signInWithApple() async {
  debugPrint("🚀 [FLOW] Starting Apple Sign-In...");

  try {
    late UserCredential userCredential;
    AuthorizationCredentialAppleID? appleCredential;

    // Web flow: try popup via Firebase OAuthProvider
    if (kIsWeb) {
      debugPrint("[WEB] Using Firebase web popup for Apple sign-in.");
      try {
        final provider = OAuthProvider("apple.com");
        provider.addScope('email');
        provider.addScope('name');
        userCredential = await FirebaseAuth.instance.signInWithPopup(provider);
        debugPrint(
          "[WEB] Apple web popup returned user: ${userCredential.user?.email}",
        );
      } on FirebaseAuthException catch (e, st) {
        debugPrint("[WEB][ERROR] Apple web popup failed: $e");
        debugPrint(st.toString());
        throw SignInException(
          'web_auth_failed',
          e.message ?? 'Failed to sign in with Apple (web).',
        );
      }
      // iOS native flow
    } else if (Platform.isIOS) {
      debugPrint("[MOBILE][iOS] Starting native Apple Sign-In...");
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      if (appleCredential.identityToken == null ||
          appleCredential.identityToken!.isEmpty) {
        debugPrint("[MOBILE][iOS][ERROR] No identity token from Apple.");
        throw SignInException(
          'no_token',
          'No identity token returned from Apple.',
        );
      }

      final oauthCredential = OAuthProvider(
        "apple.com",
      ).credential(idToken: appleCredential.identityToken, rawNonce: rawNonce);

      userCredential = await FirebaseAuth.instance.signInWithCredential(
        oauthCredential,
      );
      debugPrint(
        "[MOBILE][iOS] Firebase sign-in successful: ${userCredential.user?.email}",
      );
    } else {
      debugPrint(
        "[PLATFORM] Apple Sign-In not supported on this platform in current implementation.",
      );
      throw SignInException(
        'platform_not_supported',
        'Apple Sign-In supported on iOS and Web only.',
      );
    }

    // Common post sign-in
    final user = userCredential.user;
    if (user == null) {
      debugPrint(
        "[COMMON][ERROR] No Firebase user returned after Apple sign-in.",
      );
      throw SignInException(
        'no_user',
        'No Firebase user returned after sign-in.',
      );
    }

    // Fetch idToken for Supabase sign-in
    String? idToken;
    try {
      idToken = await user.getIdToken();
      debugPrint(
        "[COMMON] Firebase ID token retrieved: ${idToken != null && idToken.isNotEmpty}",
      );
    } catch (e) {
      debugPrint("[COMMON][WARN] Failed to get Firebase ID token: $e");
    }

    // Try to sign in to Supabase with Apple provider (best-effort)
    final supabaseClient = supabase.Supabase.instance.client;
    if (idToken != null && idToken.isNotEmpty) {
      try {
        debugPrint("[COMMON] Signing in to Supabase with Apple idToken...");
        final authResponse = await supabaseClient.auth.signInWithIdToken(
          provider: supabase.OAuthProvider.apple,
          idToken: idToken,
        );
        debugPrint(
          "[COMMON] Supabase sign-in finished. Session present: ${authResponse.session != null}",
        );
      } catch (e, st) {
        debugPrint(
          "[COMMON][WARN] Supabase signInWithIdToken (apple) failed: $e",
        );
        debugPrint(st.toString());
      }
    } else {
      debugPrint(
        "[COMMON][INFO] No idToken available, skipping Supabase sign-in.",
      );
    }

    // Upsert into Supabase customers table:
    try {
      String firstName = '';
      String lastName = '';

      // First prefer Firebase displayName if present
      final display = user.displayName ?? '';
      if (display.trim().isNotEmpty) {
        final parts = display.trim().split(RegExp(r'\s+'));
        firstName = parts.isNotEmpty ? parts.first : '';
        lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }

      // If we have appleCredential (iOS) and it provided names, prefer them (only available first time)
      if (appleCredential != null) {
        final given = appleCredential.givenName;
        final family = appleCredential.familyName;
        if (given != null && given.trim().isNotEmpty) firstName = given.trim();
        if (family != null && family.trim().isNotEmpty)
          lastName = family.trim();
      }

      final upsertResponse = await supabaseClient.from('customers').upsert({
        'auth_uid': user.uid,
        'email': user.email,
        'first_name': firstName,
        'last_name': lastName,
        'photo_url': '', // Apple doesn't supply photo
      });

      debugPrint("[COMMON] Upsert result (apple): $upsertResponse");
    } catch (e, st) {
      debugPrint("[COMMON][ERROR] Error during Supabase upsert (apple): $e");
      debugPrint(st.toString());
    }

    return userCredential;
  } catch (e) {
    if (e is SignInException) rethrow;
    debugPrint("💥 [OUTER] Error during Apple Sign-In (outer catch): $e");
    throw SignInException(
      'unexpected_outer',
      'Unexpected error during Apple sign-in.',
    );
  }
}


Future<void> syncFirebaseWithSupabase() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // fixed: handle nullable return from getIdToken by providing fallback ''
  final String idToken = await user.getIdToken() ?? '';
  debugPrint("[SYNC] Retrieved Firebase idToken length: ${idToken.length}");

  // Determine provider
  String providerId = 'google.com';
  if (user.providerData.isNotEmpty) {
    providerId = user.providerData.first.providerId ?? 'google.com';
  }

  supabase.OAuthProvider supabaseProvider = supabase.OAuthProvider.google;
  if (providerId == 'apple.com') {
    supabaseProvider = supabase.OAuthProvider.apple;
  } else if (providerId == 'google.com') {
    supabaseProvider = supabase.OAuthProvider.google;
  }

  try {
    final client = supabase.Supabase.instance.client;
    await client.auth.signInWithIdToken(
      provider: supabaseProvider,
      idToken: idToken,
    );
    debugPrint(
      'Supabase signInWithIdToken succeeded for provider: $providerId.',
    );
  } catch (e) {
    debugPrint('Supabase signInWithIdToken failed: $e');
  }

  try {
    final display = user.displayName ?? '';
    final parts = display.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    await insertOrUpdateUser(
      uid: user.uid,
      firstName: first,
      lastName: last,
      photoUrl: user.photoURL ?? '',
      birthDate: null,
      gender: null,
      phoneNumber: user.phoneNumber ?? '',
    );
    debugPrint('insertOrUpdateUser succeeded.');
  } catch (e) {
    debugPrint('insertOrUpdateUser failed: $e');
  }
}


class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // --- fields for inline Account Form inside onboarding ---
  final GlobalKey<FormState> _accountFormKey = GlobalKey<FormState>();
  late TextEditingController _emailController;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  DateTime? _birthday;
  String? _gender;
  bool _accountSaving = false;
  bool _showAccountForm =
      false; // when true, show account form inside onboarding sheet

  Map<String, String> selectedCountry = {
    "name": "Egypt",
    "code": "+20",
    "flag": "🇪🇬",
  };
  String phoneNumber = '';
  List<String> otpDigits = List.filled(6, '');
  String verificationId = '';

  String email = '';
  bool _googleLoading = false;
  bool _appleLoading = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: '');
    _firstNameController = TextEditingController(text: '');
    _lastNameController = TextEditingController(text: '');
    _phoneController = TextEditingController(text: '');
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _goToNextPage() {
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildPageIndicator() {
    return SmoothPageIndicator(
      controller: _pageController,
      count: 3, // indicator for the first three intro pages
      effect: const WormEffect(
        dotColor: Colors.grey,
        activeDotColor: Colors.white,
        dotHeight: 10,
        dotWidth: 10,
      ),
    );
  }

  // centralized friendly error UI shown at bottom (professional overlay)
  void _showErrorSnack({
    required String userMessage,
    String? technicalDetails,
    bool allowRetry = false,
    VoidCallback? onRetry,
  }) {
    final t = AppLocalizations.of(context);
    final accentColor = const Color(
      0xFF25AA50,
    ); // professional accent color (can be changed)

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'error_dialog',
      barrierColor: Colors.black.withOpacity(0.45),
      // full-screen semi-transparent black
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, animation, secondary) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 20,
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // top color bar
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    userMessage,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => Navigator.of(context).pop(),
                                  borderRadius: BorderRadius.circular(8),
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.close, size: 20),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (kDebugMode &&
                                technicalDetails != null &&
                                technicalDetails.isNotEmpty)
                              _DebugExpandableDetails(
                                details: technicalDetails,
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (allowRetry && onRetry != null)
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      try {
                                        onRetry();
                                      } catch (_) {}
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accentColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                    child: Text(t?.retry ?? 'Retry'),
                                  ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: Text(
                                    t?.close ?? 'Close',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
    );
  }

  /// Update remote language on Supabase (best-effort). Returns true on success or when no user.
  Future<bool> _updateRemoteLanguage(String lang) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint(
          'No Firebase user signed in - skipping remote language update (onboarding).',
        );
        return true;
      }
      final client = supabase.Supabase.instance.client;
      await client
          .from('customers')
          .update({'language': lang})
          .eq('auth_uid', uid);
      debugPrint('Remote language updated to $lang for uid $uid (onboarding).');
      return true;
    } catch (e) {
      debugPrint('Failed to update remote language (onboarding): $e');
      return false;
    }
  }

  /// Show languages dialog (used inside onboarding). Similar UX to settings.
  void _showLanguagesDialog() {
    final loc = AppLocalizations.of(context)!;

    bool saving = false;
    String status = '';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> _selectLang(String langCode) async {
            if (saving) return;
            setState(() {
              saving = true;
              status = (langCode == 'ar')
                  ? (loc.savingLanguage ?? 'Saving language...')
                  : (loc.savingLanguage ?? 'Saving language...');
            });

            final remoteOk = await _updateRemoteLanguage(langCode);

            // persist locally
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('locale', langCode);
            } catch (e) {
              debugPrint('Failed to save locale locally: $e');
            }

            // apply app locale immediately
            try {
              await TalabakApp.setLocale(context, Locale(langCode));
            } catch (e) {
              debugPrint('Failed to set locale via TalabakApp: $e');
            }

            // small delay so user sees state change
            await Future.delayed(const Duration(milliseconds: 350));

            setState(() {
              saving = false;
              status = remoteOk
                  ? (langCode == 'ar'
                        ? (loc.languageSaved ?? 'Language saved')
                        : (loc.languageSaved ?? 'Language saved'))
                  : (langCode == 'ar'
                        ? (loc.languageSavedLocalFailed ??
                              'Saved locally (sync failed)')
                        : (loc.languageSavedLocalFailed ??
                              'Saved locally (sync failed)'));
            });

            // close dialog after a short pause on success
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) Navigator.of(context, rootNavigator: true).pop();
            // show a small SnackBar to confirm
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(status),
                  backgroundColor: remoteOk
                      ? Colors.green.shade600
                      : Colors.orange.shade800,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }

          Widget langButton(String title, String code) {
            return Expanded(
              child: OutlinedButton(
                onPressed: saving ? null : () => _selectLang(code),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text(loc.languages),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(loc.selectLanguage, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                Row(
                  children: [
                    langButton(loc.arabic, 'ar'),
                    const SizedBox(width: 12),
                    langButton(loc.english, 'en'),
                  ],
                ),
                const SizedBox(height: 12),
                if (saving)
                  Text(
                    Localizations.localeOf(context).languageCode == 'ar'
                        ? (loc.savingLanguage ?? 'Saving language...')
                        : (loc.savingLanguage ?? 'Saving language...'),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  )
                else if (status.isNotEmpty)
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 13,
                      color: status.contains('فشل') || status.contains('Failed')
                          ? Colors.red.shade600
                          : Colors.green.shade700,
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: Text(loc.no),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onGoogleSignInPressed() async {
    final loc = AppLocalizations.of(context);
    setState(() => _googleLoading = true);

    try {
      final UserCredential? result = await signInWithGoogle();
      if (result == null) {
        // User cancelled - show a subtle info message (not an error)
        _showErrorSnack(
          userMessage: loc?.signInFailed ?? 'Sign in cancelled',
          allowRetry: false,
        );
        return;
      }

      // ensure Supabase sync (sign-in + upsert)
      await syncFirebaseWithSupabase();

      // Now check whether profile exists / is complete
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        // fallback: just mark seen and go to main
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('seenOnboarding', true);
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        }
        return;
      }

      bool needProfile = false;
      try {
        final record = await fetchCustomerByUid(firebaseUser.uid);
        if (record == null) {
          needProfile = true;
        } else {
          final firstName = (record['first_name'] ?? '') as String;
          final lastName = (record['last_name'] ?? '') as String;
          // phone is optional now — only require first and last name
          if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
            needProfile = true;
          }
        }
      } catch (e) {
        debugPrint("Could not fetch customer record: $e");
        // Be conservative and show profile form
        needProfile = true;
      }

      if (needProfile) {
        // Prefill form fields from Firebase user (and later from DB when saving)
        _emailController.text = firebaseUser.email ?? '';
        final display = firebaseUser.displayName ?? '';
        final parts = display.trim().split(RegExp(r'\s+'));
        _firstNameController.text = parts.isNotEmpty ? parts.first : '';
        _lastNameController.text = parts.length > 1
            ? parts.sublist(1).join(' ')
            : '';
        _phoneController.text = firebaseUser.phoneNumber ?? '';

        // Show inline account form inside onboarding (same background & semi-transparent sheet)
        setState(() {
          _showAccountForm = true;
        });
        return; // do not navigate away
      }

      // Already has profile -> mark seen and go to main
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('seenOnboarding', true);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } on SignInException catch (e) {
      debugPrint('SignInException: ${e.code} - ${e.message}');
      _showErrorSnack(
        userMessage:
            AppLocalizations.of(context)?.googleSignInFailed ??
            'Google sign-in failed',
        technicalDetails: e.message,
        allowRetry: true,
        onRetry: () {
          _onGoogleSignInPressed();
        },
      );
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'FirebaseAuthException during Google sign-in: ${e.code} ${e.message}',
      );
      _showErrorSnack(
        userMessage:
            AppLocalizations.of(context)?.signInFailed ?? 'Sign in failed',
        technicalDetails: '${e.code}: ${e.message}',
        allowRetry: true,
        onRetry: () => _onGoogleSignInPressed(),
      );
    } catch (e) {
      debugPrint('Unexpected error during Google sign-in: $e');
      _showErrorSnack(
        userMessage:
            AppLocalizations.of(context)?.signInFailed ?? 'Sign in failed',
        technicalDetails: e.toString(),
        allowRetry: true,
        onRetry: () => _onGoogleSignInPressed(),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _onAppleSignInPressed() async {
    final loc = AppLocalizations.of(context);
    setState(() => _appleLoading = true);

    try {
      final UserCredential? result = await signInWithApple();
      if (result == null) {
        // user cancelled
        _showErrorSnack(
          userMessage: loc?.signInFailed ?? 'Sign in cancelled',
          allowRetry: false,
        );
        return;
      }

      // ensure Supabase sync (sign-in + upsert)
      await syncFirebaseWithSupabase();

      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('seenOnboarding', true);
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        }
        return;
      }

      bool needProfile = false;
      try {
        final record = await fetchCustomerByUid(firebaseUser.uid);
        if (record == null) {
          needProfile = true;
        } else {
          final firstName = (record['first_name'] ?? '') as String;
          final lastName = (record['last_name'] ?? '') as String;
          if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
            needProfile = true;
          }
        }
      } catch (e) {
        debugPrint("Could not fetch customer record (apple): $e");
        needProfile = true;
      }

      if (needProfile) {
        _emailController.text = firebaseUser.email ?? '';
        final display = firebaseUser.displayName ?? '';
        final parts = display.trim().split(RegExp(r'\s+'));
        _firstNameController.text = parts.isNotEmpty ? parts.first : '';
        _lastNameController.text = parts.length > 1
            ? parts.sublist(1).join(' ')
            : '';
        _phoneController.text = firebaseUser.phoneNumber ?? '';

        setState(() => _showAccountForm = true);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('seenOnboarding', true);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } on SignInException catch (e) {
      debugPrint('SignInException (apple): ${e.code} - ${e.message}');
      _showErrorSnack(
        userMessage:
            AppLocalizations.of(context)?.signInFailed ?? 'Sign in failed',
        technicalDetails: e.message,
        allowRetry: true,
        onRetry: () => _onAppleSignInPressed(),
      );
    } catch (e) {
      debugPrint('Unexpected error during Apple sign-in: $e');
      _showErrorSnack(
        userMessage:
            AppLocalizations.of(context)?.signInFailed ?? 'Sign in failed',
        technicalDetails: e.toString(),
        allowRetry: true,
        onRetry: () => _onAppleSignInPressed(),
      );
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  })
  {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            validator: validator,
            decoration: InputDecoration(
              isDense: true,
              suffixIcon: suffixIcon,
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _birthday = picked);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _saveAccountAndContinue() async {
    if (!_accountFormKey.currentState!.validate()) return;
    setState(() => _accountSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final newDisplayName =
            '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                .trim();
        if (newDisplayName.isNotEmpty && newDisplayName != user.displayName) {
          await user.updateDisplayName(newDisplayName);
          await user.reload();
        }

        final birthStr = _birthday == null ? null : _formatDate(_birthday!);

        final ok = await insertOrUpdateUser(
          uid: user.uid,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          photoUrl: user.photoURL ?? '',
          // protect from null (do not change other code)
          birthDate: birthStr,
          gender: _gender,
          phoneNumber: _phoneController.text.trim(),
          email: _emailController.text.trim(),
        );

        if (!ok) {
          _showErrorSnack(
            userMessage:
                AppLocalizations.of(context)?.failedToSave ??
                'Failed to save profile',
          );
          return;
        }
      }

      // mark onboarding seen and go to main screen
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('seenOnboarding', true);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      _showErrorSnack(
        userMessage:
            AppLocalizations.of(context)?.failedToSave ??
            'Failed to save profile',
      );
    } finally {
      if (mounted) setState(() => _accountSaving = false);
    }
  }

  Widget _buildAccountFormSheet() {
    final t = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            GestureDetector(
              onTap: () {
                // cancel filling profile (optional behavior)
                setState(() => _showAccountForm = false);
              },
              child: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.arrow_back, color: Color(0xFF25AA50)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                t.accountInfo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF25AA50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _accountSaving ? null : _saveAccountAndContinue,
              child: Text(t.save),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Form(
              key: _accountFormKey,
              child: Column(
                children: [
                  _buildLabeledField(
                    label: t.email,
                    controller: _emailController,
                    enabled: false,
                  ),
                  _buildLabeledField(
                    label: t.firstName,
                    controller: _firstNameController,
                    enabled: true,
                    validator: (value) => (value == null || value.isEmpty)
                        ? t.requiredField
                        : null,
                  ),
                  _buildLabeledField(
                    label: t.lastName,
                    controller: _lastNameController,
                    enabled: true,
                    validator: (value) => (value == null || value.isEmpty)
                        ? t.requiredField
                        : null,
                  ),
                  _buildLabeledField(
                    label: (t.phone is String) ? t.phone('') : t.phone(''),
                    controller: _phoneController,
                    enabled: true,
                    keyboardType: TextInputType.phone,
                    // phone is optional now — no required validator
                    validator: (value) {
                      // optional: you can add format validation here when value is non-empty
                      return null;
                    },
                  ),
                  GestureDetector(
                    onTap: () => _pickBirthday(),
                    child: AbsorbPointer(
                      child: _buildLabeledField(
                        label: t.birthday,
                        controller: TextEditingController(
                          text: _birthday == null
                              ? ''
                              : _formatDate(_birthday!),
                        ),
                        enabled: false,
                        suffixIcon: const Icon(Icons.calendar_today),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.genderOptional,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        Row(
                          children: [
                            Radio<String>(
                              value: 'male',
                              groupValue: _gender,
                              onChanged: (v) => setState(() => _gender = v),
                            ),
                            Text(t.male),
                            const SizedBox(width: 12),
                            Radio<String>(
                              value: 'female',
                              groupValue: _gender,
                              onChanged: (v) => setState(() => _gender = v),
                            ),
                            Text(t.female),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _accountSaving
                          ? null
                          : _saveAccountAndContinue,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _accountSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              t.save,
                              style: const TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnboardingContent() {
    final loc = AppLocalizations.of(context)!;

    // If showing the account form (inline), render it:
    if (_showAccountForm) {
      return _buildAccountFormSheet();
    }

    if (_currentPage < 3) {
      // first three intro pages
      String title;
      String subtitle;
      switch (_currentPage) {
        case 0:
          title = loc.onboardingTapEatSmile ?? 'Tap - Eat - Smile';
          subtitle =
              loc.onboardingTapEatSmileSubtitle ??
              'Your favorite meals, just a tap away';
          break;
        case 1:
          title = loc.onboardingFlavorInAFlash ?? 'Flavor in a Flash';
          subtitle =
              loc.onboardingFlavorInAFlashSubtitle ??
              'Hot, fresh, and fast to your door';
          break;
        case 2:
          title = loc.onboardingFoodYourWay ?? 'Food, Your Way';
          subtitle =
              loc.onboardingFoodYourWaySubtitle ??
              'Order exactly what you love';
          break;
        default:
          title = '';
          subtitle = '';
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(child: Center(child: _buildPageIndicator())),
              ElevatedButton(
                onPressed: _goToNextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  loc.next ?? 'Next',
                  style: const TextStyle(color: Colors.black),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (_currentPage == 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.enterYourEmail ?? 'Enter your email',
            style: const TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            loc.signInQuicklyWithGoogle ?? 'Sign in quickly with Google',
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 30),
          Center(
            child: SizedBox(
              width: 260,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _googleLoading ? null : _onGoogleSignInPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFAF7EF),
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _googleLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    "G",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  loc.google,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Apple Sign-In button
                  SizedBox(
                    height: 56,
                    child: SignInWithAppleButton(
                      onPressed: _appleLoading ? null : _onAppleSignInPressed,
                      borderRadius: BorderRadius.circular(12),
                      // styling is handled by package on iOS; on other platforms it will render a default button
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
        ],
      );
    } else {
      // page 4 (OTP or others) - keep as-is but localized keys can be used if needed
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/background.jpg",
              fit: BoxFit.cover,
            ),
          ),
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: 5,
            itemBuilder: (_, __) => const SizedBox.shrink(),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.72,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(25),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _showLanguagesDialog,
                        icon: const Icon(
                          Icons.language,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: Text(
                          loc?.languages ?? 'Language',
                          style: const TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.12),
                          ),
                          backgroundColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // content
                  Expanded(child: _buildOnboardingContent()),
                ],
              ),
            ),
          ),
          if (_accountSaving || _googleLoading || _appleLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.25),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _buildFlagOption(
  String flagEmoji,
  String code,
  String countryCode,
  String selectedCode,
  void Function(void Function()) setState,
)
{
  return GestureDetector(
    onTap: () {
      setState(() {
        selectedCode = code;
      });
    },
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: selectedCode == code
            ? Colors.white.withOpacity(0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(flagEmoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(code, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    ),
  );
}

class _DebugExpandableDetails extends StatefulWidget {
  final String details;

  const _DebugExpandableDetails({required this.details});

  @override
  State<_DebugExpandableDetails> createState() =>
      _DebugExpandableDetailsState();
}

class _DebugExpandableDetailsState extends State<_DebugExpandableDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Row(
            children: [
              Text(
                loc?.details ?? 'Details',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _open ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Colors.grey[700],
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Text(
                widget.details,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ),
          crossFadeState: _open
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}
