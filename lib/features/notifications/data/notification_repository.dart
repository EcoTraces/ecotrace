import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/notification.dart';

class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Stream<int> watchUnreadCount(String uid) =>
      watch(uid).map((items) => items.where((item) => !item.read).length);

  Stream<List<AppNotification>> watch(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('notifications')
      .snapshots()
      .map(
        (s) => s.docs.map(AppNotification.fromDoc).toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          ),
      );
  Stream<NotificationPreferences> preferences(String uid) => _db
      .collection('notificationPreferences')
      .doc(uid)
      .snapshots()
      .map(NotificationPreferences.fromDoc);
  Future<void> savePreferences(
    String uid,
    Map<String, bool> channels,
    Map<String, bool> types,
    String quiet,
  ) => _db.collection('notificationPreferences').doc(uid).set({
    'channels': channels,
    'types': types,
    'quietHours': quiet,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  Future<void> read(String uid, String id) => _db
      .collection('users')
      .doc(uid)
      .collection('notifications')
      .doc(id)
      .update({'read': true});
  Future<void> send({
    required List<String> users,
    required NotificationType type,
    required String title,
    required String body,
    required List<NotificationChannel> channels,
    required String actor,
  }) async {
    final batch = _db.batch();
    for (final uid in users) {
      batch.set(
        _db.collection('users').doc(uid).collection('notifications').doc(),
        {
          'type': type.name,
          'title': title,
          'body': body,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      for (final channel in channels.where(
        (c) => c != NotificationChannel.inApp,
      )) {
        batch.set(_db.collection('notificationOutbox').doc(), {
          'userId': uid,
          'channel': channel.name,
          'type': type.name,
          'title': title,
          'body': body,
          'status': 'queued',
          'createdBy': actor,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  Future<void> template(
    String name,
    NotificationType type,
    String title,
    String body,
  ) => _db.collection('notificationTemplates').add({
    'name': name,
    'type': type.name,
    'title': title,
    'body': body,
    'active': true,
    'createdAt': FieldValue.serverTimestamp(),
  });
}
