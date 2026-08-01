import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../data/notification_repository.dart';

/// A live bell icon whose badge reflects the signed-in user's unread messages.
class NotificationBadgeIcon extends StatelessWidget {
  const NotificationBadgeIcon({
    super.key,
    this.color,
    this.size,
    this.repository,
  });

  final Color? color;
  final double? size;
  final NotificationRepository? repository;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.notifications_none, color: color, size: size);
    // Dashboard widgets are also rendered in previews and widget tests before
    // Firebase bootstrap completes. The bell remains usable without a badge
    // until the authenticated application tree is ready.
    if (Firebase.apps.isEmpty) return icon;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return icon;

    return StreamBuilder<int>(
      stream: (repository ?? NotificationRepository()).watchUnreadCount(uid),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) return icon;
        return Badge(
          label: Text(count > 99 ? '99+' : '$count'),
          child: icon,
        );
      },
    );
  }
}
