import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:talabak_users/services/supabase_service.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

const Color kPrimaryColor = Color(0xFF25AA50);

enum StatusType { success, error }

class AccountInfoScreen extends StatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _emailController;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;

  DateTime? _birthday;
  String? _gender;

  bool _isEditing = false;
  bool _loading = false;

  // Status message (replaces SnackBar). This shows a boxed message in the UI.
  String? _statusMessage;
  StatusType? _statusType;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;

    _emailController = TextEditingController(text: user?.email ?? '');
    String displayName = user?.displayName ?? '';
    List<String> parts = displayName.trim().split(RegExp(r'\s+'));
    _firstNameController = TextEditingController(text: parts.isNotEmpty ? parts.first : '');
    _lastNameController = TextEditingController(text: parts.length > 1 ? parts.sublist(1).join(' ') : '');
    _phoneController = TextEditingController(text: '');

    // Set status bar color to match app bar (initial).
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: kPrimaryColor,
      statusBarIconBrightness: Brightness.light,
    ));

    if (user != null) {
      _loadFromDatabase(user.uid);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _setStatus(String message, StatusType type, {int autoHideSeconds = 4}) {
    setState(() {
      _statusMessage = message;
      _statusType = type;
    });
    // auto hide after few seconds
    Future.delayed(Duration(seconds: autoHideSeconds), () {
      if (mounted) setState(() => _statusMessage = null);
    });
  }

  Future<void> _loadFromDatabase(String uid) async {
    setState(() => _loading = true);
    try {
      final record = await fetchCustomerByUid(uid);
      if (record != null) {
        _emailController.text = (record['email'] ?? _emailController.text) as String;
        _firstNameController.text = (record['first_name'] ?? _firstNameController.text) as String;
        _lastNameController.text = (record['last_name'] ?? _lastNameController.text) as String;
        _phoneController.text = (record['phone_number'] ?? '') as String;

        final birth = record['birth_date'];
        if (birth != null) {
          if (birth is String) {
            final parts = birth.split('-');
            if (parts.length == 3) {
              final y = int.tryParse(parts[0]) ?? 2000;
              final m = int.tryParse(parts[1]) ?? 1;
              final d = int.tryParse(parts[2]) ?? 1;
              _birthday = DateTime(y, m, d);
            }
          } else if (birth is DateTime) {
            _birthday = birth;
          }
        }

        _gender = record['gender'] as String?;
      } else {
        // intentionally no logs printed
      }
    } catch (_) {
      if (mounted) {
        final t = AppLocalizations.of(context)!;
        _setStatus(t.failedToLoadOrders, StatusType.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _birthday = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final newDisplayName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
        if (newDisplayName.isNotEmpty && newDisplayName != user.displayName) {
          await user.updateDisplayName(newDisplayName);
          await user.reload();
        }

        final birthStr = _birthday == null ? null : _formatDate(_birthday!);

        final ok = await insertOrUpdateUser(
          uid: user.uid,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          photoUrl: user.photoURL,
          birthDate: birthStr,
          gender: _gender,
          phoneNumber: _phoneController.text.trim(),
          email: _emailController.text.trim(),
        );

        if (!ok) {
          if (mounted) {
            final t = AppLocalizations.of(context)!;
            _setStatus(t.failedToSave, StatusType.error);
          }
          return;
        }
      }

      if (mounted) {
        final t = AppLocalizations.of(context)!;
        _setStatus(t.profileSaved, StatusType.success);
        setState(() => _isEditing = false);
      }
    } catch (_) {
      if (mounted) {
        final t = AppLocalizations.of(context)!;
        _setStatus(t.failedToSave, StatusType.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deleteAccountTitle),
        content: Text(t.deleteAccountMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);
    final t = AppLocalizations.of(context)!;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final uid = user.uid;

        // 1) delete record from DB (Supabase)
        final dbOk = await deleteCustomerByUid(uid);
        if (!dbOk) {
          if (mounted) _setStatus(t.failedToDelete, StatusType.error);
          return;
        }

        // 2) delete Firebase account (may require recent login)
        await user.delete();
      }

      if (mounted) {
        // Navigate to login
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'requires-recent-login') {
          _setStatus(t.requiresRecentLogin, StatusType.error);
        } else {
          _setStatus(t.failedToDelete, StatusType.error);
        }
      }
    } catch (_) {
      if (mounted) _setStatus(t.failedToDelete, StatusType.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    Widget? suffixIcon,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(value, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            if (suffixIcon != null) suffixIcon,
          ],
        ),
      ),
    );
  }

  // Helper to obtain phone label safely (works with different ARB shapes)
  String _phoneLabel(AppLocalizations t) {
    try {
      final dynamic maybe = t.phone;
      if (maybe is String) return maybe;
      if (maybe is String Function(String)) return maybe('');
      // fallback
      return maybe.toString();
    } catch (_) {
      return 'Phone';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Match system status bar color to the app bar color
    final appBarColor = theme.appBarTheme.backgroundColor ?? kPrimaryColor;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: appBarColor,
      statusBarIconBrightness: Brightness.light,
    ));

    final phoneLabel = _phoneLabel(t);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top header (uses primary color, fixed)
            Container(
              height: 80,
              color: kPrimaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.arrow_back, color: kPrimaryColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.accountInfo,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _loading
                        ? null
                        : () {
                      if (_isEditing) {
                        _saveProfile();
                      } else {
                        setState(() => _isEditing = true);
                      }
                    },
                    child: Text(_isEditing ? t.save : t.edit),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Status box (success / error) - distinct, translatable
                          if (_statusMessage != null && _statusType != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: StatusBox(
                                message: _statusMessage!,
                                type: _statusType!,
                              ),
                            ),

                          _buildLabeledField(
                            label: t.email,
                            controller: _emailController,
                            enabled: false,
                          ),
                          _buildLabeledField(
                            label: t.firstName,
                            controller: _firstNameController,
                            enabled: _isEditing,
                            validator: (value) => (value == null || value.isEmpty) && _isEditing
                                ? t.requiredField
                                : null,
                          ),
                          _buildLabeledField(
                            label: t.lastName,
                            controller: _lastNameController,
                            enabled: _isEditing,
                            validator: (value) => (value == null || value.isEmpty) && _isEditing
                                ? t.requiredField
                                : null,
                          ),
                          _buildLabeledField(
                            label: phoneLabel,
                            controller: _phoneController,
                            enabled: _isEditing,
                            keyboardType: TextInputType.phone,
                          ),

                          // Birthday - read only field with calendar icon
                          _buildReadOnlyField(
                            label: t.birthday,
                            value: _birthday == null ? '' : _formatDate(_birthday!),
                            suffixIcon: const Icon(Icons.calendar_today),
                            onTap: _isEditing ? _pickBirthday : null,
                          ),

                          // Gender group
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.dividerColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.genderOptional,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Radio<String>(
                                      value: 'male',
                                      groupValue: _gender,
                                      onChanged:
                                      _isEditing ? (v) => setState(() => _gender = v) : null,
                                    ),
                                    Text(t.male),
                                    const SizedBox(width: 12),
                                    Radio<String>(
                                      value: 'female',
                                      groupValue: _gender,
                                      onChanged:
                                      _isEditing ? (v) => setState(() => _gender = v) : null,
                                    ),
                                    Text(t.female),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _loading ? null : _confirmDeleteAccount,
                              style: OutlinedButton.styleFrom(
                                shape:
                                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(t.deleteAccount,
                                  style: TextStyle(color: theme.colorScheme.onSurface)),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),

                  if (_loading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.25),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A professional-looking status box used for success/error messages.
/// The text is passed from localization keys.
class StatusBox extends StatelessWidget {
  final String message;
  final StatusType type;

  const StatusBox({super.key, required this.message, required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Colors: success (green) and error (red). You can adjust to theme if you like.
    final Color bg = type == StatusType.success ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final Color border = type == StatusType.success ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
    final Color textColor = type == StatusType.success ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: border.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              type == StatusType.success ? Icons.check_circle : Icons.error,
              color: border,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
