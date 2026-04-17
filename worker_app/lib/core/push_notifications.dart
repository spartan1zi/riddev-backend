import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';
import 'api_client.dart';

bool _fcmRefreshListenerAttached = false;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Registers FCM token with the API after login. Safe to call multiple times.
Future<void> registerPushNotifications(ApiClient api) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Firebase init skipped (configure firebase_options.dart): $e');
    return;
  }

  if (Platform.isAndroid) {
    try {
      await Permission.notification.request().timeout(const Duration(seconds: 60));
    } catch (_) {}
  }

  final messaging = FirebaseMessaging.instance;
  await messaging.setAutoInitEnabled(true);
  try {
    await messaging
        .requestPermission(alert: true, badge: true, sound: true)
        .timeout(const Duration(seconds: 30));
  } catch (e) {
    debugPrint('FCM requestPermission: $e');
  }

  String? token;
  try {
    token = await messaging.getToken().timeout(const Duration(seconds: 20));
  } catch (e) {
    debugPrint('FCM getToken failed or timed out: $e');
    return;
  }
  if (token != null && token.isNotEmpty) {
    try {
      await api.registerFcmToken(token);
    } catch (e) {
      debugPrint('FCM token register failed: $e');
    }
  }

  if (!_fcmRefreshListenerAttached) {
    _fcmRefreshListenerAttached = true;
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      try {
        await api.registerFcmToken(t);
      } catch (e) {
        debugPrint('FCM token refresh register failed: $e');
      }
    });
  }
}
