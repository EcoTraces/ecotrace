import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';

class NotificationService {
  static ApiClient get _api =>
      ApiClient(baseUrl: ApiConfig.notificationBaseUrl);

  static Future<void> registerDevice(String uid) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken(
      vapidKey: kIsWeb && ApiConfig.fcmWebVapidKey.isNotEmpty
          ? ApiConfig.fcmWebVapidKey
          : null,
    );
    if (token == null) return;
    await _registerToken(uid, token);
    messaging.onTokenRefresh.listen(
      (updatedToken) => _registerToken(uid, updatedToken).catchError((_) {}),
    );
  }

  static Future<void> _registerToken(String uid, String token) async {
    if (ApiConfig.notificationsEnabled) {
      await _retry(
        () => _api.post('/notifications/register-token', {
          'userId': uid,
          'deviceToken': token,
          'platform': _platform,
        }),
      );
      return;
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc('primary')
        .set({
          'token': token,
          'platform': 'fcm',
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<void> removeCurrentDevice() async {
    if (!ApiConfig.notificationsEnabled) return;
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb && ApiConfig.fcmWebVapidKey.isNotEmpty
          ? ApiConfig.fcmWebVapidKey
          : null,
    );
    if (token == null) return;
    await _retry(
      () => _api.delete(
        '/notifications/remove-token',
        payload: {'deviceToken': token},
      ),
    );
  }

  static Future<T> _retry<T>(Future<T> Function() operation) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 2 << attempt));
        }
      }
    }
    throw lastError!;
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      _ => 'web',
    };
  }

  static Stream<RemoteMessage> get foregroundMessages =>
      FirebaseMessaging.onMessage;
}
