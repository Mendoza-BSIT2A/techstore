import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the app finds the custom REST API.
///
/// The same API exists in two places with identical endpoints:
///  * online, as a Supabase Edge Function (supabase/functions/store-api) - the default;
///  * locally, as PHP on XAMPP (backend/api).
///
/// Priority: URL saved in Server Settings, then `--dart-define=API_BASE_URL`,
/// then [hostedBaseUrl].
class ApiConfig {
  ApiConfig._();

  static const _prefsKey = 'api_base_url';
  static const _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  /// The custom API deployed as a Supabase Edge Function.
  static const hostedBaseUrl =
      'https://okgmzgejuidflamjbzdn.supabase.co/functions/v1/store-api';

  /// The PHP version of the API on XAMPP. The Android emulator reaches the
  /// PC's localhost through 10.0.2.2.
  static String get localBaseUrl =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2/techstore_api/api'
      : 'http://localhost/techstore_api/api';

  /// Base URL of the third-party API (https://dummyjson.com/docs/products).
  static const dummyJsonBaseUrl = 'https://dummyjson.com';

  static String get defaultBaseUrl =>
      _fromEnvironment.isNotEmpty ? normalize(_fromEnvironment) : hostedBaseUrl;

  static final ValueNotifier<String> baseUrl = ValueNotifier(defaultBaseUrl);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.isNotEmpty) baseUrl.value = saved;
    } catch (_) {
      // Preferences unavailable: keep the default URL.
    }
  }

  static Future<void> save(String url) async {
    final normalized = normalize(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalized);
    baseUrl.value = normalized;
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    baseUrl.value = defaultBaseUrl;
  }

  /// Trims whitespace and trailing slashes and adds `http://` when missing.
  static String normalize(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (!value.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      value = 'http://$value';
    }
    return value;
  }
}
