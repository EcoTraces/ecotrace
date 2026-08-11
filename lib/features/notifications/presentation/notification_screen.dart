import 'package:flutter/material.dart';
import '../data/notification_repository.dart';
import '../domain/notification.dart';

class NotificationScreen extends StatefulWidget {
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
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationTemplate> templates = const [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final result = await widget.repository.getTemplates();
    if (mounted) setState(() => templates = result);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications and communication'),
      actions: [
        if (widget.canManage)
          IconButton(
            onPressed: () => _templates(c),
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Message templates',
          ),
        IconButton(
          onPressed: () => _prefs(c),
          icon: const Icon(Icons.tune),
          tooltip: 'Notification preferences',
        ),
      ],
    ),
    floatingActionButton: widget.canManage
        ? FloatingActionButton(
            onPressed: () => _send(c),
            child: const Icon(Icons.send),
          )
        : null,
    body: StreamBuilder<List<AppNotification>>(
      stream: widget.repository.watch(widget.uid),
      builder: (c, s) {
        final items = s.data ?? const <AppNotification>[];
        if (items.isEmpty) {
          return const Center(child: Text('No notifications yet.'));
        }
        return ListView(
          children: [
            for (final n in items)
              ListTile(
                leading: Icon(
                  n.type == NotificationType.emergency
                      ? Icons.emergency
                      : Icons.notifications_outlined,
                ),
                title: Text(n.title),
                subtitle: Text(n.body),
                trailing: n.read ? null : const Icon(Icons.circle, size: 10),
                onTap: () => widget.repository.read(widget.uid, n.id),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _prefs(BuildContext c) async {
    final current = await widget.repository.preferences(widget.uid).first;
    if (!c.mounted) return;
    final channels = {
      for (final x in NotificationChannel.values)
        x.name: current.channels[x.name] ?? true,
    };
    final types = {
      for (final x in NotificationType.values)
        x.name: current.types[x.name] ?? true,
    };
    final quietParts = current.quietHours.split(RegExp('[–-]'));
    var quietEnabled = current.quietHours.isNotEmpty;
    final quietStart = TextEditingController(
      text: quietParts.isNotEmpty && quietParts.first.trim().isNotEmpty
          ? quietParts.first.trim()
          : '22:00',
    );
    final quietEnd = TextEditingController(
      text: quietParts.length > 1 && quietParts.last.trim().isNotEmpty
          ? quietParts.last.trim()
          : '07:00',
    );
    final ok = await showDialog<bool>(
      context: c,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Notification preferences'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Channels',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final x in NotificationChannel.values)
                  CheckboxListTile(
                    dense: true,
                    title: Text(x.name),
                    value: channels[x.name],
                    onChanged: (v) =>
                        setLocal(() => channels[x.name] = v ?? true),
                  ),
                const Divider(),
                const Text(
                  'Categories',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final x in NotificationType.values)
                  CheckboxListTile(
                    dense: true,
                    title: Text(x.name),
                    value: types[x.name],
                    onChanged: (v) =>
                        setLocal(() => types[x.name] = v ?? true),
                  ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Quiet hours'),
                  value: quietEnabled,
                  onChanged: (v) => setLocal(() => quietEnabled = v),
                ),
                if (quietEnabled)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: quietStart,
                          decoration: const InputDecoration(
                            labelText: 'Start (HH:MM)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: quietEnd,
                          decoration: const InputDecoration(
                            labelText: 'End (HH:MM)',
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.repository.savePreferences(
        widget.uid,
        channels,
        types,
        quietEnabled: quietEnabled,
        quietStart: quietStart.text.trim(),
        quietEnd: quietEnd.text.trim(),
      );
      if (c.mounted) {
        ScaffoldMessenger.of(
          c,
        ).showSnackBar(const SnackBar(content: Text('Preferences saved.')));
      }
    }
  }

  Future<void> _send(BuildContext c) async {
    var type = NotificationType.general;
    final recipients = TextEditingController(text: widget.uid);
    final title = TextEditingController();
    final body = TextEditingController();
    final channels = {
      for (final x in NotificationChannel.values) x: x == NotificationChannel.inApp,
    };
    final ok = await showDialog<bool>(
      context: c,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Send notification'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: recipients,
                  decoration: const InputDecoration(
                    labelText: 'Recipient user IDs (comma-separated)',
                  ),
                ),
                DropdownButtonFormField<NotificationType>(
                  initialValue: type,
                  items: NotificationType.values
                      .map(
                        (x) =>
                            DropdownMenuItem(value: x, child: Text(x.name)),
                      )
                      .toList(),
                  onChanged: (x) => type = x ?? type,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: body,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
                Wrap(
                  spacing: 6,
                  children: NotificationChannel.values
                      .map(
                        (x) => FilterChip(
                          label: Text(x.name),
                          selected: channels[x] ?? false,
                          onSelected: (v) => setLocal(() => channels[x] = v),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final users = recipients.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final selectedChannels = channels.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList();
      if (users.isEmpty || title.text.trim().isEmpty || selectedChannels.isEmpty) {
        return;
      }
      await widget.repository.send(
        users: users,
        type: type,
        title: title.text.trim(),
        body: body.text.trim(),
        channels: selectedChannels,
        actor: widget.uid,
      );
      if (c.mounted) {
        ScaffoldMessenger.of(
          c,
        ).showSnackBar(const SnackBar(content: Text('Notification sent.')));
      }
    }
  }

  Future<void> _templates(BuildContext c) async {
    await showDialog<void>(
      context: c,
      builder: (context) => AlertDialog(
        title: const Text('Message templates'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _newTemplate(c);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New template'),
                ),
              ),
              Expanded(
                child: templates.isEmpty
                    ? const Center(child: Text('No templates saved yet.'))
                    : ListView(
                        children: [
                          for (final t in templates)
                            ListTile(
                              title: Text(t.name),
                              subtitle: Text(
                                '${t.category} • ${t.channel}\n${t.subject}',
                              ),
                              isThreeLine: true,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _newTemplate(BuildContext c) async {
    var type = NotificationType.general;
    var channel = NotificationChannel.inApp;
    final name = TextEditingController();
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: c,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New message template'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Template name',
                  ),
                ),
                DropdownButtonFormField<NotificationType>(
                  initialValue: type,
                  items: NotificationType.values
                      .map(
                        (x) =>
                            DropdownMenuItem(value: x, child: Text(x.name)),
                      )
                      .toList(),
                  onChanged: (x) => setLocal(() => type = x ?? type),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                DropdownButtonFormField<NotificationChannel>(
                  initialValue: channel,
                  items: NotificationChannel.values
                      .map(
                        (x) =>
                            DropdownMenuItem(value: x, child: Text(x.name)),
                      )
                      .toList(),
                  onChanged: (x) => setLocal(() => channel = x ?? channel),
                  decoration: const InputDecoration(labelText: 'Channel'),
                ),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                TextField(
                  controller: body,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Body'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true &&
        name.text.trim().isNotEmpty &&
        body.text.trim().isNotEmpty) {
      await widget.repository.template(
        name.text.trim(),
        type,
        title.text.trim(),
        body.text.trim(),
        channel: channel,
      );
      await _loadTemplates();
    }
  }
}
