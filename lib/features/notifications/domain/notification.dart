import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationChannel { push, sms, email, inApp }

enum NotificationType {
  pickupReminder,
  assignment,
  statusUpdate,
  payment,
  reward,
  compliance,
  maintenance,
  emergency,
  general,
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
  });
  final String id, title, body;
  final NotificationType type;
  final bool read;
  final DateTime? createdAt;
  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return AppNotification(
      id: d.id,
      type: NotificationType.values.byName(x['type'] ?? 'general'),
      title: x['title'] ?? '',
      body: x['body'] ?? '',
      read: x['read'] ?? false,
      createdAt: (x['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class NotificationPreferences {
  const NotificationPreferences({
    required this.channels,
    required this.types,
    required this.quietHours,
  });
  final Map<String, bool> channels, types;
  final String quietHours;
  factory NotificationPreferences.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final x = d.data() ?? {};
    return NotificationPreferences(
      channels: Map<String, bool>.from(x['channels'] ?? {}),
      types: Map<String, bool>.from(x['types'] ?? {}),
      quietHours: x['quietHours'] ?? '',
    );
  }
}
