import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

const _prefsKey = 'riddev_worker_api_base_url';

Future<String> resolveWorkerApiBaseUrl() async {
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

Future<void> saveWorkerApiBaseUrlOverride(String? value) async {
  final prefs = await SharedPreferences.getInstance();
  if (value == null || value.trim().isEmpty) {
    await prefs.remove(_prefsKey);
  } else {
    await prefs.setString(_prefsKey, value.trim());
  }
}

Future<String?> getWorkerApiBaseUrlOverride() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey);
}
