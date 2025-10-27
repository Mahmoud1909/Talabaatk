// lib/utils/settings_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:talabak_users/l10n/app_localizations.dart';
import 'package:talabak_users/main.dart' show TalabakApp;
import 'package:talabak_users/screens/account_info_screen.dart';
import 'package:talabak_users/screens/main_screen.dart';
import 'package:talabak_users/screens/onboarding_screen.dart';
import 'package:talabak_users/services/supabase_service.dart';
import 'package:url_launcher/url_launcher_string.dart';

final supabase = Supabase.instance.client;
const Color kPrimaryColor = Color(0xFF25AA50);

/// Custom header with matching status bar color
class CustomHeader extends StatelessWidget {
  const CustomHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    // Ensure status bar uses the primary color and icons remain legible
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: kPrimaryColor,
      statusBarIconBrightness: Brightness.light,
    ));

    return Container(
      height: 80,
      color: kPrimaryColor,
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
            },
            child: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.arrow_back, color: kPrimaryColor),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            loc.settingsTitle,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// Settings screen — English, translatable texts, no prints
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  ThemeMode _currentThemeMode = ThemeMode.light; // default: light (as requested)
  bool _themeBusy = false;
  late final AnimationController _motionCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _motionCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _fadeIn = CurvedAnimation(parent: _motionCtrl, curve: Curves.easeOut);
    _motionCtrl.forward();
    _loadThemeFromPrefs();
  }

  @override
  void dispose() {
    _motionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThemeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('themeMode') ?? 'light';
    setState(() {
      _currentThemeMode = mode == 'dark' ? ThemeMode.dark : (mode == 'system' ? ThemeMode.system : ThemeMode.light);
    });
  }

  Future<void> _saveRemoteLanguage(String lang) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await supabase.from('customers').update({'language': lang}).eq('auth_uid', uid);
      }
    } catch (_) {
      // intentionally silent — we don't print logs on screen
    }
  }

  void _showLoadingDialog(BuildContext context, {String? message}) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final text = message ?? (isAr ? 'الرجاء الانتظار...' : 'Please wait...');
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'loading',
      pageBuilder: (_, __, ___) => WillPopScope(
        onWillPop: () async => false,
        child: SafeArea(
          child: Center(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 36),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 64, height: 64, child: CircularProgressIndicator(strokeWidth: 4)),
                  const SizedBox(height: 14),
                  Text(text),
                ]),
              ),
            ),
          ),
        ),
      ),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    );
  }

  void _hideLoadingDialog(BuildContext context) {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  // Professional boxed toast for success / error
  void _showSuccess(BuildContext context, String message) {
    ToastOverlay.show(context, message: message, icon: Icons.check_circle, color: Colors.green.shade600, glowColor: Colors.greenAccent);
  }

  void _showError(BuildContext context, String message) {
    ToastOverlay.show(context, message: message, icon: Icons.error_outline, color: Colors.red.shade600, glowColor: Colors.redAccent);
  }

  Future<void> _onSelectLanguage(BuildContext context, String langCode) async {
    _showLoadingDialog(context, message: (langCode == 'ar') ? 'جاري حفظ اللغة...' : 'Saving language...');
    await _saveRemoteLanguage(langCode);
    await TalabakApp.setLocale(context, Locale(langCode));
    _hideLoadingDialog(context);
    _showSuccess(context, (langCode == 'ar') ? 'تم تغيير اللغة' : 'Language changed');
  }

  Future<void> _performLogout(BuildContext context) async {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    _showLoadingDialog(context, message: isAr ? 'جاري تسجيل الخروج...' : 'Logging out...');
    var anyError = false;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      anyError = true;
    }
    try {
      await supabase.auth.signOut();
    } catch (_) {
      anyError = true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('customer_id');
      await prefs.setBool('seenOnboarding', false);
    } catch (_) {
      anyError = true;
    }
    _hideLoadingDialog(context);
    if (!anyError) {
      _showSuccess(context, isAr ? 'تم تسجيل الخروج بنجاح' : 'Logged out successfully');
      Future.delayed(const Duration(milliseconds: 420), () {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()), (r) => false);
      });
    } else {
      _showError(context, isAr ? 'حدث خطأ — حاول مرة أخرى' : 'Something went wrong — please try again');
    }
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    setState(() => _themeBusy = true);
    final prefs = await SharedPreferences.getInstance();
    final name = mode == ThemeMode.dark ? 'dark' : (mode == ThemeMode.system ? 'system' : 'light');
    await prefs.setString('themeMode', name);
    await TalabakApp.setThemeMode(context, mode);
    // small motion to emphasize change
    _motionCtrl.forward(from: 0);
    setState(() {
      _currentThemeMode = mode;
    });
    // keep status bar color stable (primary)
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: kPrimaryColor, statusBarIconBrightness: Brightness.light));
    setState(() => _themeBusy = false);
    _showSuccess(context, Localizations.localeOf(context).languageCode == 'ar' ? 'تم تغيير الوضع' : 'Theme changed');
  }

  // Reusable decorated container for each setting row (professional look)
  Widget _decoratedBox({required Widget child}) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _fadeIn,
      builder: (_, __) => Opacity(
        opacity: _fadeIn.value,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 360),
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: child,
        ),
      ),
    );
  }

  // Special danger container for Delete Account (dark red background)
  Widget _dangerBox({required Widget child}) {
    final theme = Theme.of(context);
    // dark red color
    const dangerBg = Color(0xFF8B0000);
    // always white text inside as requested
    final textColor = Colors.white;

    return AnimatedBuilder(
      animation: _fadeIn,
      builder: (_, __) => Opacity(
        opacity: _fadeIn.value,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 360),
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: dangerBg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: textColor),
            child: IconTheme.merge(
              data: IconThemeData(color: textColor),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(children: [
          const CustomHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: ListView(
                key: ValueKey(_currentThemeMode), // triggers animation on theme change
                padding: const EdgeInsets.only(top: 12, bottom: 24),
                children: [
                  // Account info
                  _decoratedBox(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountInfoScreen())),
                      title: Text(loc.accountInfo, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      trailing: Icon(Icons.chevron_right, color: theme.iconTheme.color),
                    ),
                  ),

                  // Theme picker (replaces "Notifications")
                  _decoratedBox(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(loc.darkMode, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _currentThemeMode == ThemeMode.dark
                            ? (Localizations.localeOf(context).languageCode == 'ar' ? 'الوضع: ليلي' : 'Mode: Dark')
                            : _currentThemeMode == ThemeMode.light
                            ? (Localizations.localeOf(context).languageCode == 'ar' ? 'الوضع: نهاري' : 'Mode: Light')
                            : (Localizations.localeOf(context).languageCode == 'ar' ? 'استخدام إعداد النظام' : 'Use system setting'),
                        style: theme.textTheme.bodyMedium,
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: loc.system,
                          icon: const Icon(Icons.smartphone),
                          onPressed: () => _changeTheme(ThemeMode.system),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                          child: Switch(
                            key: ValueKey(_currentThemeMode == ThemeMode.dark),
                            value: _currentThemeMode == ThemeMode.dark,
                            onChanged: _themeBusy ? null : (v) => _changeTheme(v ? ThemeMode.dark : ThemeMode.light),
                            activeColor: kPrimaryColor,
                          ),
                        ),
                      ]),
                    ),
                  ),

                  // Languages
                  _decoratedBox(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(loc.languages, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      trailing: Icon(Icons.chevron_right, color: theme.iconTheme.color),
                      onTap: () => _showLanguagesDialog(context),
                    ),
                  ),

                  // Privacy Policy (New) — opens external link
                  _decoratedBox(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(loc.privacyPolicy, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () async {
                        const url = 'https://doc-hosting.flycricket.io/talabaatk-privacy-policy/0a57df15-150d-4acf-9050-0c35c80bf00d/privacy';
                        try {
                          await launchUrlString(url);
                        } catch (_) {
                          _showError(context, loc.somethingWentWrong);
                        }
                      },
                    ),
                  ),

                  // Terms of Use (New) — opens external link
                  _decoratedBox(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(loc.termsOfUse, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () async {
                        const url = 'https://doc-hosting.flycricket.io/talabaatk-terms-of-use/f59716d2-ccec-42ff-b333-7b050efb95e0/terms';
                        try {
                          await launchUrlString(url);
                        } catch (_) {
                          _showError(context, loc.somethingWentWrong);
                        }
                      },
                    ),
                  ),

                  // Logout (kept before delete as requested)
                  _decoratedBox(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(loc.logOut, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      trailing: Icon(Icons.exit_to_app, color: theme.colorScheme.error),
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ),

                  // Delete Account (moved AFTER logout) — styled as dark red container per request
                  _dangerBox(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(loc.deleteAccount, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      subtitle: Text(loc.deleteAccountDesc, style: theme.textTheme.bodySmall?.copyWith(color: null)),
                      trailing: const Icon(Icons.delete_forever),
                      onTap: () => _showDeleteAccountDialog(context),
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _showLanguagesDialog(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    bool saving = false;
    String status = '';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setState) {
        Future<void> _pick(String code) async {
          if (saving) return;
          setState(() {
            saving = true;
            status = (code == 'ar') ? 'جاري حفظ اللغة...' : 'Saving language...';
          });
          await _saveRemoteLanguage(code);
          await TalabakApp.setLocale(context, Locale(code));
          await Future.delayed(const Duration(milliseconds: 300));
          setState(() {
            saving = false;
            status = (code == 'ar') ? 'تم حفظ اللغة' : 'Language saved';
          });
        }

        Widget button(String title, String code) {
          return Expanded(
            child: OutlinedButton(
              onPressed: saving ? null : () => _pick(code),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Theme.of(context).dividerColor),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
          );
        }

        return AlertDialog(
          title: Text(loc.languages),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(loc.selectLanguage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(children: [button(loc.arabic, 'ar'), const SizedBox(width: 12), button(loc.english, 'en')]),
            const SizedBox(height: 12),
            if (saving) Text(Localizations.localeOf(context).languageCode == 'ar' ? 'جاري حفظ اللغة...' : 'Saving language...', style: Theme.of(context).textTheme.bodySmall),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(status, style: TextStyle(fontSize: 13, color: status.contains('فشل') ? Colors.red.shade600 : Colors.green.shade700)),
              ),
          ]),
          actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: Text(loc.no))],
        );
      }),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(loc.logoutConfirmTitle),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(loc.logoutConfirmMessage, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _dialogButton(context, loc.no, false),
            const SizedBox(width: 12),
            _dialogButton(context, loc.yes, true, onPressedPrimary: () => _performLogout(context)),
          ]),
        ]),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(loc.deleteConfirmTitle),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(loc.deleteConfirmMessage, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _dialogButton(context, loc.cancel, false),
            const SizedBox(width: 12),
            _dialogButton(context, loc.delete, true, onPressedPrimary: () => _performDeleteAccount(context)),
          ]),
        ]),
      ),
    );
  }


  Future<void> _performDeleteAccount(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    _showLoadingDialog(context, message: loc.deletingAccount);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    bool unlinked = false;
    bool firebaseDeleted = false;
    String? firebaseError;

    // 1) Unlink customer row (leave data but remove auth uid)
    if (uid != null) {
      try {
        unlinked = await unlinkCustomerAuthUid(uid);
      } catch (e) {
        unlinked = false;
      }
    }

    // 2) Try to delete Firebase Auth user (may require recent auth)
    try {
      await FirebaseAuth.instance.currentUser?.delete();
      firebaseDeleted = true;
    } catch (e) {
      // If delete failed because of requires-recent-login, inform user.
      if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
        firebaseError = loc.reauthRequired;
      } else {
        firebaseError = loc.somethingWentWrong;
      }
      // Sign out as fallback to clear session
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }

    // 3) Sign out Supabase (best-effort)
    try {
      await supabase.auth.signOut();
    } catch (_) {}

    // 4) Clear local prefs and return to onboarding
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setBool('seenOnboarding', false);
    } catch (_) {}

    _hideLoadingDialog(context);

    // UX logic:
    if (unlinked) {
      // whether firebaseDeleted or not, unlinked means DB data preserved and dissociated
      if (firebaseDeleted) {
        _showSuccess(context, loc.deleteSuccess); // "Account deleted successfully"
      } else {
        _showSuccess(context, loc.deletePartialSuccess); // e.g. "data unlinked, reauth needed to delete auth"
        if (firebaseError != null) _showError(context, firebaseError);
      }

      Future.delayed(const Duration(milliseconds: 420), () {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()), (r) => false);
      });
      return;
    }

    // otherwise failed to unlink
    _showError(context, loc.deleteFailed);
  }

  Widget _dialogButton(BuildContext context, String label, bool primary, {VoidCallback? onPressedPrimary}) {
    final theme = Theme.of(context);
    return Expanded(
      child: OutlinedButton(
        onPressed: () {
          Navigator.pop(context);
          if (onPressedPrimary != null) onPressedPrimary();
        },
        style: OutlinedButton.styleFrom(backgroundColor: primary ? kPrimaryColor : Colors.transparent, side: BorderSide(color: theme.dividerColor)),
        child: Text(label, style: TextStyle(color: primary ? Colors.white : theme.textTheme.bodyMedium?.color)),
      ),
    );
  }
}

/// Toast overlay: boxed professional messages (success / error)
class ToastOverlay {
  static void show(BuildContext context,
      {required String message, required IconData icon, required Color color, required Color glowColor, Duration duration = const Duration(milliseconds: 2200)}) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (context) {
      return Positioned(top: 88.0, left: 18.0, right: 18.0, child: ToastWidget(message: message, icon: icon, color: color, glowColor: glowColor, onFinish: () => entry.remove(), duration: duration));
    });
    overlay.insert(entry);
  }
}

class ToastWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color color;
  final Color glowColor;
  final Duration duration;
  final VoidCallback onFinish;
  const ToastWidget({super.key, required this.message, required this.icon, required this.color, required this.glowColor, required this.onFinish, this.duration = const Duration(milliseconds: 2200)});

  @override
  State<ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<ToastWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _offset = Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(widget.duration, () async {
      await _ctrl.reverse();
      widget.onFinish();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SlideTransition(
      position: _offset,
      child: FadeTransition(
        opacity: _fade,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.96),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: widget.glowColor.withOpacity(0.45), blurRadius: 30, spreadRadius: 4), BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withOpacity(0.12), boxShadow: [BoxShadow(color: widget.glowColor.withOpacity(0.25), blurRadius: 14, spreadRadius: 1)]),
                  child: Icon(widget.icon, color: widget.color, size: 22),
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(widget.message, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
