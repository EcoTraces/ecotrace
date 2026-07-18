import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static Future<void> registerDevice(String uid) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token == null) return;
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

  static Stream<RemoteMessage> get foregroundMessages =>
      FirebaseMessaging.onMessage;
}
