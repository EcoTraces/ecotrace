import 'package:flutter/material.dart';
import '../data/notification_repository.dart';
import '../domain/notification.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({
    super.key,
    required this.repository,
    required this.uid,
    required this.canManage,
  });
  final NotificationRepository repository;
  final String uid;
  final bool canManage;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications and communication'),
      actions: [
        IconButton(onPressed: () => _prefs(c), icon: const Icon(Icons.tune)),
      ],
    ),
    floatingActionButton: canManage
        ? FloatingActionButton(
            onPressed: () => _send(c),
            child: const Icon(Icons.send),
          )
        : null,
    body: StreamBuilder<List<AppNotification>>(
      stream: repository.watch(uid),
      builder: (c, s) => ListView(
        children: [
          for (final n in s.data ?? <AppNotification>[])
            ListTile(
              leading: Icon(
                n.type == NotificationType.emergency
                    ? Icons.emergency
                    : Icons.notifications_outlined,
              ),
              title: Text(n.title),
              subtitle: Text(n.body),
              trailing: n.read ? null : const Icon(Icons.circle, size: 10),
              onTap: () => repository.read(uid, n.id),
            ),
        ],
      ),
    ),
  );
  Future<void> _prefs(BuildContext c) async {
    final channels = {for (final x in NotificationChannel.values) x.name: true},
        types = {for (final x in NotificationType.values) x.name: true};
    await repository.savePreferences(uid, channels, types, '22:00–07:00');
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(
        const SnackBar(content: Text('Notification preferences saved.')),
      );
    }
  }

  Future<void> _send(BuildContext c) async {
    await repository.send(
      users: [uid],
      type: NotificationType.general,
      title: 'EcoTrace update',
      body: 'Platform notification test',
      channels: NotificationChannel.values,
      actor: uid,
    );
  }
}
