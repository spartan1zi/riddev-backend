import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

const _prefsKey = 'riddev_customer_api_base_url';

/// Effective API origin (no `/api` suffix). Uses Settings override, else compile-time [kApiBaseUrl].
Future<String> resolveCustomerApiBaseUrl() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefsKey);
  if (raw != null && raw.trim().isNotEmpty) {
    var u = raw.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    return u.replaceAll(RegExp(r'/+$'), '');
  }
  return kApiBaseUrl;
}

Future<void> saveCustomerApiBaseUrlOverride(String? value) async {
  final prefs = await SharedPreferences.getInstance();
  if (value == null || value.trim().isEmpty) {
    await prefs.remove(_prefsKey);
  } else {
    await prefs.setString(_prefsKey, value.trim());
  }
}

Future<String?> getCustomerApiBaseUrlOverride() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey);
}
