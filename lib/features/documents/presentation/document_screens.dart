import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/document_repository.dart';
import '../domain/managed_document.dart';

class DocumentDashboardScreen extends StatelessWidget {
  const DocumentDashboardScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.userName,
    required this.canGovern,
  });
  final DocumentRepository repository;
  final String userId, userName;
  final bool canGovern;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Secure document management')),
    floatingActionButton: canGovern
        ? FloatingActionButton.extended(
            onPressed: () => _upload(context),
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload'),
          )
        : null,
    body: StreamBuilder<List<ManagedDocument>>(
      stream: repository.watchDocuments(userId, canGovern),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!,
            alerts = docs
                .where((d) => d.expiresWithin(const Duration(days: 60)))
                .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Document expiry notifications',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (alerts.isEmpty)
              const ListTile(
                title: Text('No documents expire within 60 days.'),
              ),
            for (final d in alerts)
              ListTile(
                leading: const Icon(Icons.event_busy),
                title: Text(d.title),
                subtitle: Text(
                  '${d.expired ? 'Expired' : 'Expires'} ${d.expiresAt}',
                ),
              ),
            Text(
              'Document vault',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final d in docs)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text('${d.title} • v${d.currentVersion}'),
                  subtitle: Text(
                    '${d.category.name} • ${d.status.name}\n${d.ownerName} • ${d.referenceNumber}',
                  ),
                  isThreeLine: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DocumentDetailScreen(
                        repository: repository,
                        id: d.id,
                        userId: userId,
                        canGovern: canGovern,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  Future<void> _upload(BuildContext context) async {
    final picked = await FilePicker.pickFiles(withData: true);
    if (picked == null) return;
    if (!context.mounted) return;
    final selectedFile = picked.files.single;
    var category = DocumentCategory.other;
    var access = DocumentAccessLevel.owner;
    var expiresAt = DateTime.now().add(const Duration(days: 365));
    final title = TextEditingController(text: selectedFile.name),
        reference = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Upload secure document'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Reference number',
                ),
              ),
              DropdownButtonFormField(
                initialValue: category,
                items: DocumentCategory.values
                    .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                    .toList(),
                onChanged: (x) => setLocal(() => category = x!),
              ),
              DropdownButtonFormField(
                initialValue: access,
                items: DocumentAccessLevel.values
                    .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                    .toList(),
                onChanged: (x) => setLocal(() => access = x!),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expiry date'),
                subtitle: Text('$expiresAt'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                    initialDate: expiresAt,
                  );
                  if (date != null) setLocal(() => expiresAt = date);
                },
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await repository.upload(
        ownerId: userId,
        ownerName: userName,
        title: title.text,
        category: category,
        access: access,
        reference: reference.text,
        expiresAt: expiresAt,
        fileName: selectedFile.name,
        mimeType: _mime(selectedFile.extension),
        bytes: selectedFile.bytes!,
        actorId: userId,
      );
    }
  }
}

class DocumentDetailScreen extends StatelessWidget {
  const DocumentDetailScreen({
    super.key,
    required this.repository,
    required this.id,
    required this.userId,
    required this.canGovern,
  });
  final DocumentRepository repository;
  final String id, userId;
  final bool canGovern;
  @override
  Widget build(BuildContext context) => StreamBuilder<ManagedDocument>(
    stream: repository.watchDocument(id),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final d = snapshot.data!;
      return Scaffold(
        appBar: AppBar(title: Text(d.title)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: Text('${d.category.name} • ${d.status.name}'),
              subtitle: Text(
                '${d.fileName}\nVersion ${d.currentVersion} • Expires ${d.expiresAt}',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => _download(d),
                  child: const Text('Download / preview'),
                ),
                FilledButton.tonal(
                  onPressed: () => _version(context, d),
                  child: const Text('New version'),
                ),
                if (canGovern)
                  FilledButton(
                    onPressed: () => _approve(context, d, true),
                    child: const Text('Approve'),
                  ),
                if (canGovern)
                  OutlinedButton(
                    onPressed: () => _approve(context, d, false),
                    child: const Text('Reject'),
                  ),
                if (canGovern)
                  OutlinedButton(
                    onPressed: () => repository.archive(d, userId),
                    child: const Text('Archive'),
                  ),
              ],
            ),
            Text(
              'Version control',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<DocumentVersion>>(
              stream: repository.watchVersions(d.id),
              builder: (context, s) => Column(
                children: [
                  for (final v in s.data ?? <DocumentVersion>[])
                    ListTile(
                      title: Text('Version ${v.version} • ${v.fileName}'),
                      subtitle: Text('${v.changeNotes} • ${v.uploadedBy}'),
                    ),
                ],
              ),
            ),
            Text(
              'Document audit trail',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<DocumentAuditEvent>>(
              stream: repository.watchAudit(d.id),
              builder: (context, s) => Column(
                children: [
                  for (final a in s.data ?? <DocumentAuditEvent>[])
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(a.action),
                      subtitle: Text(
                        '${a.actorId} • ${a.details} • ${a.createdAt}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> _download(ManagedDocument d) async {
    final bytes = await repository.download(d.url),
        dir = await getTemporaryDirectory(),
        file = File('${dir.path}/${d.fileName}');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: d.title),
    );
  }

  Future<void> _version(BuildContext context, ManagedDocument d) async {
    final p = await FilePicker.pickFiles(withData: true);
    if (p == null || p.files.single.bytes == null) return;
    final selectedFile = p.files.single;
    final notes = TextEditingController();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New version notes'),
        content: TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'What changed in this version?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repository.newVersion(
        d,
        fileName: selectedFile.name,
        mimeType: _mime(selectedFile.extension),
        bytes: selectedFile.bytes!,
        notes: notes.text.trim(),
        actorId: userId,
      );
    }
  }

  Future<void> _approve(
    BuildContext context,
    ManagedDocument d,
    bool approved,
  ) async {
    final notes = TextEditingController(text: approved ? 'Approved' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approved ? 'Approve document' : 'Reject document'),
        content: TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approved ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repository.approve(d, approved, userId, notes.text.trim());
    }
  }
}

String _mime(String? extension) => switch (extension?.toLowerCase()) {
  'pdf' => 'application/pdf',
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  _ => 'application/octet-stream',
};
