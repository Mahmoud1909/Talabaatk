// lib/services/user_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

final SupabaseClient supabase = Supabase.instance.client;

/// Fetch single customer row by Firebase uid (auth_uid)
Future<Map<String, dynamic>?> fetchCustomerByUid(String uid) async {
  try {
    print('[user_service] fetchCustomerByUid -> uid: $uid');
    final resp = await supabase
        .from('customers')
        .select()
        .eq('auth_uid', uid)
        .maybeSingle();
    print('[user_service] fetchCustomerByUid response: $resp');
    return resp as Map<String, dynamic>?;
  } catch (e) {
    print('[user_service] fetchCustomerByUid ERROR: $e');
    return null;
  }
}

/// Insert or update (upsert) user row in customers table
Future<bool> insertOrUpdateUser({
  required String uid,
  required String firstName,
  String? lastName,
  String? photoUrl,
  String? birthDate, // format "YYYY-MM-DD" or null
  String? gender,
  String? phoneNumber,
  String? email,
  String? language, // NEW: 'ar' or 'en'
}) async {
  try {
    print('[user_service] insertOrUpdateUser -> Preparing data for uid: $uid');
    final data = {
      'auth_uid': uid,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'photo_url': photoUrl,
      'birth_date': birthDate,
      'gender': gender,
      'phone_number': phoneNumber,
      // include language only if provided (fallback server default applies)
      if (language != null) 'language': language,
    };

    final res = await supabase
        .from('customers')
        .upsert(data, onConflict: 'auth_uid')
        .select()
        .maybeSingle();

    print('[user_service] insertOrUpdateUser SUCCESS. returned: $res');
    return true;
  } catch (e) {
    print('[user_service] insertOrUpdateUser ERROR: $e');
    return false;
  }
}

/// Update only language for a given auth_uid
Future<bool> updateCustomerLanguage(String uid, String language) async {
  try {
    print('[user_service] updateCustomerLanguage -> uid: $uid, language: $language');
    await supabase
        .from('customers')
        .update({'language': language})
        .eq('auth_uid', uid);
    return true;
  } catch (e) {
    print('[user_service] updateCustomerLanguage ERROR: $e');
    return false;
  }
}

/// Unlink customer row from an auth UID (set auth_uid = NULL)
/// keeps the customer's data in DB but removes association with the auth provider.
Future<bool> unlinkCustomerAuthUid(String uid) async {
  try {
    print('[user_service] unlinkCustomerAuthUid -> uid: $uid');
    await supabase
        .from('customers')
        .update({'auth_uid': null})
        .eq('auth_uid', uid);
    print('[user_service] unlinkCustomerAuthUid SUCCESS');
    return true;
  } catch (e) {
    print('[user_service] unlinkCustomerAuthUid ERROR: $e');
    return false;
  }
}

/// Delete customer row by Firebase uid (auth_uid) - keep for admin use only
Future<bool> deleteCustomerByUid(String uid) async {
  try {
    print('[user_service] deleteCustomerByUid -> uid: $uid');
    await supabase.from('customers').delete().eq('auth_uid', uid);
    print('[user_service] deleteCustomerByUid SUCCESS');
    return true;
  } catch (e) {
    print('[user_service] deleteCustomerByUid ERROR: $e');
    return false;
  }
}
