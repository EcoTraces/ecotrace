import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../domain/notification.dart';

class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  Stream<int> watchUnreadCount(String uid) =>
      watch(uid).map((items) => items.where((item) => !item.read).length);

  Stream<List<AppNotification>> watch(String uid) => _useApi ? _pollNotifications() : _db
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
  Stream<List<AppNotification>> _pollNotifications() async* {
    while (true) {
      final data = await _api.getList('/api/v1/communication/notifications');
      yield data.map(AppNotification.fromJson).toList();
      await Future<void>.delayed(const Duration(seconds: ApiConfig.pollingSeconds));
    }
  }
  Stream<NotificationPreferences> preferences(String uid) => _useApi ? _pollPreferences() : _db
      .collection('notificationPreferences')
      .doc(uid)
      .snapshots()
      .map(NotificationPreferences.fromDoc);
  Stream<NotificationPreferences> _pollPreferences() async* {
    while (true) {
      yield NotificationPreferences.fromJson(await _api.get('/api/v1/communication/preferences'));
      await Future<void>.delayed(const Duration(seconds: ApiConfig.pollingSeconds));
    }
  }
  Future<void> savePreferences(
    String uid,
    Map<String, bool> channels,
    Map<String, bool> types,
    String quiet,
  ) => _useApi ? _api.put('/api/v1/communication/preferences', {
    'channels': channels,
    'categories': types,
    'quietHours': quiet.isEmpty ? null : {'enabled': true, 'start': '22:00', 'end': '07:00', 'timezone': 'UTC'},
  }).then((_) {}) : _db.collection('notificationPreferences').doc(uid).set({
    'channels': channels,
    'types': types,
    'quietHours': quiet,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  Future<void> read(String uid, String id) => _useApi
      ? _api.patch('/api/v1/communication/notifications/$id/read', const {}).then((_) {})
      : _db
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
    if (_useApi) {
      await _api.post('/api/v1/communication/send', {
        'recipientIds': users, 'category': type.name, 'channels': channels.map((channel) => channel.name).toList(),
        'title': title, 'body': body, 'data': <String, dynamic>{}, 'priority': type == NotificationType.emergency ? 'critical' : 'normal',
      });
      return;
    }
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
  ) => _useApi
      ? _api.put('/api/v1/communication/templates/${DateTime.now().microsecondsSinceEpoch}', {
          'name': name, 'category': type.name, 'channel': 'inApp', 'subject': title, 'body': body, 'variables': <String>[], 'active': true,
        }).then((_) {})
      : _db.collection('notificationTemplates').add({
    'name': name,
    'type': type.name,
    'title': title,
    'body': body,
    'active': true,
    'createdAt': FieldValue.serverTimestamp(),
  });
}
