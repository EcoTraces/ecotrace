import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/audit_repository.dart';
import '../domain/audit_event.dart';

class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({
    super.key,
    required this.repository,
    this.embedded = false,
  });

  final AuditRepository repository;
  final bool embedded;

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  String query = '';
  AuditAction? action;
  DateTimeRange? dates;

  AuditFilter get filter => AuditFilter(
    query: query,
    action: action,
    from: dates?.start,
    to: dates?.end.add(const Duration(days: 1)),
  );

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<List<AuditEvent>>(
      stream: widget.repository.watchEvents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load audit records: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data!
            .where((event) => event.matches(filter))
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      onChanged: (value) => setState(() => query = value),
                      decoration: const InputDecoration(
                        labelText: 'Search audit records',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  DropdownButton<AuditAction?>(
                    value: action,
                    hint: const Text('All actions'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All actions'),
                      ),
                      ...AuditAction.values.map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => action = value),
                  ),
                  OutlinedButton.icon(
                    onPressed: _selectDates,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      dates == null ? 'Any date' : _dateLabel(dates!),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: events.isEmpty ? null : () => _export(events),
                    icon: const Icon(Icons.download_outlined),
                    label: Text('Export CSV (${events.length})'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _verifyIntegrity(context),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Verify chain integrity'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: events.isEmpty
                  ? const Center(
                      child: Text('No audit records match these filters.'),
                    )
                  : ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (context, index) =>
                          _AuditTile(event: events[index]),
                    ),
            ),
          ],
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Audit trail')),
      body: body,
    );
  }

  Future<void> _selectDates() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: dates,
    );
    if (selected != null && mounted) setState(() => dates = selected);
  }

  String _dateLabel(DateTimeRange range) =>
      '${range.start.toIso8601String().substring(0, 10)} – ${range.end.toIso8601String().substring(0, 10)}';

  Future<void> _verifyIntegrity(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Verifying audit chain...'),
          ],
        ),
      ),
    );
    try {
      final result = await widget.repository.checkIntegrity();
      if (!context.mounted) return;
      Navigator.pop(context);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                result == null
                    ? Icons.help_outline
                    : result.valid
                    ? Icons.verified_outlined
                    : Icons.report_gmailerrorred,
                color: result == null
                    ? null
                    : result.valid
                    ? Colors.green
                    : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                result == null
                    ? 'Unavailable'
                    : result.valid
                    ? 'Chain intact'
                    : 'Tampering detected',
              ),
            ],
          ),
          content: Text(
            result == null
                ? 'Chain verification requires the authenticated API.'
                : 'Verified ${result.recordsVerified} record(s).\n'
                      'Last hash: ${result.lastHash}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.pop(context);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Icon(Icons.report_gmailerrorred, color: Colors.red),
          content: Text('Chain verification failed: $error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _export(List<AuditEvent> events) async {
    final rows = <List<dynamic>>[
      [
        'Timestamp',
        'Actor',
        'Role',
        'Action',
        'Entity type',
        'Entity ID',
        'Description',
        'IP address',
        'Device',
        'Source',
        'Success',
      ],
      ...events.map(
        (event) => [
          event.createdAt?.toIso8601String() ?? '',
          event.actorName,
          event.actorRole,
          event.action.name,
          event.entityType,
          event.entityId,
          event.description,
          event.ipAddress,
          event.deviceInformation,
          event.source,
          event.success,
        ],
      ),
    ];
    final data = Csv().encode(rows);
    await SharePlus.instance.share(
      ShareParams(
        title: 'EcoTrace audit export',
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(data)),
            mimeType: 'text/csv',
            name: 'ecotrace_audit_export.csv',
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.event});
  final AuditEvent event;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: CircleAvatar(child: Icon(_icon(event.action), size: 20)),
    title: Text(event.description),
    subtitle: Text(
      '${event.actorName.isEmpty ? event.actorId : event.actorName} • ${event.action.name} • ${event.entityType}/${event.entityId}\n'
      '${event.createdAt?.toLocal().toString() ?? 'Timestamp pending'}',
    ),
    isThreeLine: true,
    trailing: Icon(
      event.success ? Icons.verified_outlined : Icons.error_outline,
      color: event.success ? Colors.green : Colors.red,
    ),
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.action.name),
        content: SingleChildScrollView(
          child: SelectableText(
            'Actor: ${event.actorName} (${event.actorId})\n'
            'Role: ${event.actorRole}\nEntity: ${event.entityType}/${event.entityId}\n'
            'IP: ${event.ipAddress.isEmpty ? 'Pending trusted backend enrichment' : event.ipAddress}\n'
            'Device: ${event.deviceInformation}\nSource: ${event.source}\n'
            'Severity: ${event.severity.name}\nChanges: ${event.changes}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  IconData _icon(AuditAction action) => switch (action) {
    AuditAction.login || AuditAction.logout => Icons.login,
    AuditAction.payment => Icons.payments_outlined,
    AuditAction.itemMovement => Icons.swap_horiz,
    AuditAction.roleChange ||
    AuditAction.permissionChange => Icons.admin_panel_settings_outlined,
    AuditAction.configurationChange => Icons.settings_outlined,
    AuditAction.delete || AuditAction.reject => Icons.warning_amber_outlined,
    _ => Icons.history,
  };
}
