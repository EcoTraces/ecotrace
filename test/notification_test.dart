import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/notifications/domain/notification.dart';

void main() {
  test('notification channels cover push SMS email and in-app', () {
    expect(
      NotificationChannel.values,
      containsAll([
        NotificationChannel.push,
        NotificationChannel.sms,
        NotificationChannel.email,
        NotificationChannel.inApp,
      ]),
    );
  });
  test('notification types cover operational communication', () {
    expect(
      NotificationType.values,
      containsAll([
        NotificationType.pickupReminder,
        NotificationType.assignment,
        NotificationType.statusUpdate,
        NotificationType.payment,
        NotificationType.reward,
        NotificationType.compliance,
        NotificationType.maintenance,
        NotificationType.emergency,
      ]),
    );
  });
}
