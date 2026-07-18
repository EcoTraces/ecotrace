import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/compliance_repository.dart';
import '../domain/compliance_record.dart';

class ComplianceDashboardScreen extends StatelessWidget {
  const ComplianceDashboardScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.canManage,
  });
  final ComplianceRepository repository;
  final String currentUserId;
  final bool canManage;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ComplianceDocument>>(
    stream: repository.watchDocuments(),
    builder: (context, documentSnapshot) =>
        StreamBuilder<List<ComplianceInspection>>(
          stream: repository.watchInspections(),
          builder: (context, inspectionSnapshot) =>
              StreamBuilder<List<ComplianceViolation>>(
                stream: repository.watchViolations(),
                builder: (context, violationSnapshot) =>
                    StreamBuilder<List<PenaltyRecord>>(
                      stream: repository.watchPenalties(),
                      builder: (context, penaltySnapshot) =>
                          StreamBuilder<List<RegulatoryBody>>(
                            stream: repository.watchRegulatoryBodies(),
                            builder: (context, bodySnapshot) {
                              if (![
                                documentSnapshot,
                                inspectionSnapshot,
                                violationSnapshot,
                                penaltySnapshot,
                                bodySnapshot,
                              ].every((snapshot) => snapshot.hasData)) {
                                return const Scaffold(
                                  body: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final documents = documentSnapshot.data!;
                              final inspections = inspectionSnapshot.data!;
                              final violations = violationSnapshot.data!;
                              final penalties = penaltySnapshot.data!;
                              final bodies = bodySnapshot.data!;
                              final score = ComplianceScore.calculate(
                                documents: documents,
                                inspections: inspections,
                                violations: violations,
                              );
                              return DefaultTabController(
                                length: 5,
                                child: Scaffold(
                                  appBar: AppBar(
                                    title: const Text(
                                      'Compliance and regulatory',
                                    ),
                                    actions: [
                                      IconButton(
                                        onPressed: () => _auditReport(
                                          documents,
                                          inspections,
                                          violations,
                                          penalties,
                                          score,
                                        ),
                                        icon: const Icon(
                                          Icons.picture_as_pdf_outlined,
                                        ),
                                        tooltip: 'Audit-ready report',
                                      ),
                                    ],
                                    bottom: const TabBar(
                                      isScrollable: true,
                                      tabs: [
                                        Tab(text: 'Overview'),
                                        Tab(text: 'Documents'),
                                        Tab(text: 'Inspections'),
                                        Tab(text: 'Violations'),
                                        Tab(text: 'Regulators'),
                                      ],
                                    ),
                                  ),
                                  body: TabBarView(
                                    children: [
                                      _overview(
                                        context,
                                        documents,
                                        inspections,
                                        violations,
                                        penalties,
                                        score,
                                      ),
                                      _documents(context, documents, bodies),
                                      _inspections(
                                        context,
                                        inspections,
                                        bodies,
                                      ),
                                      _violations(
                                        context,
                                        violations,
                                        penalties,
                                      ),
                                      _regulators(context, bodies),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                    ),
              ),
        ),
  );

  Widget _overview(
    BuildContext context,
    List<ComplianceDocument> documents,
    List<ComplianceInspection> inspections,
    List<ComplianceViolation> violations,
    List<PenaltyRecord> penalties,
    ComplianceScore score,
  ) {
    final expiring = documents
        .where((document) => document.expiresWithin(const Duration(days: 60)))
        .toList();
    final openViolations = violations
        .where(
          (violation) => violation.status != ComplianceViolationStatus.resolved,
        )
        .toList();
    final overdueActions = openViolations
        .where((violation) => violation.overdue)
        .toList();
    final upcoming =
        inspections
            .where(
              (inspection) =>
                  inspection.status == ComplianceInspectionStatus.scheduled,
            )
            .toList()
          ..sort(
            (a, b) => (a.scheduledAt ?? DateTime(2100)).compareTo(
              b.scheduledAt ?? DateTime(2100),
            ),
          );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Compliance score', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Text(
                  '${score.overall.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: _scoreColor(score.overall),
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: score.overall / 100,
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  children: [
                    Text(
                      'Documents ${score.documentScore.toStringAsFixed(0)}%',
                    ),
                    Text(
                      'Inspections ${score.inspectionScore.toStringAsFixed(0)}%',
                    ),
                    Text(
                      'Violations ${score.violationScore.toStringAsFixed(0)}%',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric(
              'Valid documents',
              documents
                  .where(
                    (document) =>
                        document.status == ComplianceDocumentStatus.valid &&
                        !document.isExpired,
                  )
                  .length
                  .toString(),
              Icons.verified_outlined,
            ),
            _metric(
              'Expiry alerts',
              expiring.length.toString(),
              Icons.event_busy_outlined,
            ),
            _metric(
              'Open violations',
              openViolations.length.toString(),
              Icons.gavel_outlined,
            ),
            _metric(
              'Overdue actions',
              overdueActions.length.toString(),
              Icons.warning_amber,
            ),
            _metric(
              'Scheduled inspections',
              upcoming.length.toString(),
              Icons.event_note_outlined,
            ),
            _metric(
              'Penalties',
              penalties.length.toString(),
              Icons.payments_outlined,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Document expiry alerts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (canManage)
              TextButton.icon(
                onPressed: () => _requirement(context),
                icon: const Icon(Icons.checklist),
                label: const Text('Add checklist requirement'),
              ),
          ],
        ),
        if (expiring.isEmpty)
          const ListTile(title: Text('No documents expire within 60 days.')),
        for (final document in expiring)
          Card(
            color: document.isExpired
                ? Theme.of(context).colorScheme.errorContainer
                : null,
            child: ListTile(
              leading: const Icon(Icons.notification_important_outlined),
              title: Text(document.title),
              subtitle: Text(
                '${document.referenceNumber} • ${document.isExpired ? 'Expired' : 'Expires'} ${document.expiresAt}',
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Upcoming inspections',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (upcoming.isEmpty)
          const ListTile(title: Text('No inspections scheduled.')),
        for (final inspection in upcoming.take(5))
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(inspection.entityName),
            subtitle: Text(
              '${inspection.inspectorName} • ${inspection.scheduledAt}',
            ),
          ),
      ],
    );
  }

  Widget _documents(
    BuildContext context,
    List<ComplianceDocument> documents,
    List<RegulatoryBody> bodies,
  ) => Scaffold(
    floatingActionButton: canManage
        ? FloatingActionButton.extended(
            onPressed: () => _document(context, bodies),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Add document'),
          )
        : null,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        if (documents.isEmpty)
          const ListTile(title: Text('No licences or certificates recorded.')),
        for (final document in documents)
          Card(
            child: ListTile(
              leading: Icon(
                document.type == ComplianceDocumentType.recyclerCertification
                    ? Icons.recycling
                    : Icons.workspace_premium_outlined,
              ),
              title: Text(document.title),
              subtitle: Text(
                '${document.type.label} • ${document.referenceNumber}\n${document.entityName} • ${document.status.name}${document.expiresAt == null ? '' : ' • Expires ${document.expiresAt}'}',
              ),
              isThreeLine: true,
              trailing: canManage
                  ? PopupMenuButton<ComplianceDocumentStatus>(
                      onSelected: (status) => _runCompliance(
                        context,
                        () => repository.updateDocumentStatus(document, status),
                        'Document status updated.',
                      ),
                      itemBuilder: (_) => ComplianceDocumentStatus.values
                          .map(
                            (status) => PopupMenuItem(
                              value: status,
                              child: Text(status.name),
                            ),
                          )
                          .toList(),
                    )
                  : null,
            ),
          ),
      ],
    ),
  );

  Widget _inspections(
    BuildContext context,
    List<ComplianceInspection> inspections,
    List<RegulatoryBody> bodies,
  ) => Scaffold(
    floatingActionButton: canManage
        ? FloatingActionButton.extended(
            onPressed: () => _scheduleInspection(context, bodies),
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('Schedule'),
          )
        : null,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        if (inspections.isEmpty)
          const ListTile(title: Text('No compliance inspections recorded.')),
        for (final inspection in inspections)
          Card(
            child: ExpansionTile(
              leading: Icon(
                inspection.score >= 80
                    ? Icons.fact_check_outlined
                    : Icons.rule_folder_outlined,
              ),
              title: Text(inspection.entityName),
              subtitle: Text(
                '${inspection.status.name} • ${inspection.scheduledAt}\nScore ${inspection.score.toStringAsFixed(1)}%',
              ),
              children: [
                for (final entry in inspection.checklist.entries)
                  ListTile(
                    dense: true,
                    leading: Icon(entry.value ? Icons.check : Icons.close),
                    title: Text(entry.key),
                  ),
                if (inspection.findings.isNotEmpty)
                  ListTile(
                    title: const Text('Findings'),
                    subtitle: Text(inspection.findings),
                  ),
                if (inspection.recommendations.isNotEmpty)
                  ListTile(
                    title: const Text('Recommendations'),
                    subtitle: Text(inspection.recommendations),
                  ),
                if (canManage &&
                    [
                      ComplianceInspectionStatus.scheduled,
                      ComplianceInspectionStatus.inProgress,
                    ].contains(inspection.status))
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton(
                      onPressed: () => _completeInspection(context, inspection),
                      child: const Text('Complete inspection'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _violations(
    BuildContext context,
    List<ComplianceViolation> violations,
    List<PenaltyRecord> penalties,
  ) => Scaffold(
    floatingActionButton: canManage
        ? FloatingActionButton.extended(
            onPressed: () => _violation(context),
            icon: const Icon(Icons.gavel),
            label: const Text('Record violation'),
          )
        : null,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        if (violations.isEmpty)
          const ListTile(title: Text('No compliance violations.')),
        for (final violation in violations)
          Card(
            color: violation.overdue
                ? Theme.of(context).colorScheme.errorContainer
                : null,
            child: ExpansionTile(
              leading: Icon(
                violation.severity == ViolationSeverity.critical
                    ? Icons.dangerous_outlined
                    : Icons.warning_amber,
              ),
              title: Text(
                '${violation.referenceNumber} • ${violation.entityName}',
              ),
              subtitle: Text(
                '${violation.severity.name} • ${violation.status.name}\n${violation.description}',
              ),
              children: [
                if (violation.correctiveActionPlan.isNotEmpty)
                  ListTile(
                    title: const Text('Corrective action plan'),
                    subtitle: Text(
                      '${violation.correctiveActionPlan}\nOwner: ${violation.correctiveActionOwner} • Due ${violation.correctiveActionDueAt}',
                    ),
                  ),
                if (violation.resolutionEvidence.isNotEmpty)
                  ListTile(
                    title: const Text('Resolution evidence'),
                    subtitle: Text(violation.resolutionEvidence),
                  ),
                if (canManage &&
                    violation.status != ComplianceViolationStatus.resolved)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              _correctiveAction(context, violation),
                          child: const Text('Corrective action'),
                        ),
                        OutlinedButton(
                          onPressed: () => _penalty(context, violation),
                          child: const Text('Penalty'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              _resolveViolation(context, violation),
                          child: const Text('Resolve'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        Text('Penalty records', style: Theme.of(context).textTheme.titleLarge),
        if (penalties.isEmpty)
          const ListTile(title: Text('No penalties recorded.')),
        for (final penalty in penalties)
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(
              '${penalty.referenceNumber} • ${penalty.currency} ${penalty.amount.toStringAsFixed(2)}',
            ),
            subtitle: Text('${penalty.status.name} • Due ${penalty.dueAt}'),
            trailing: canManage
                ? PopupMenuButton<PenaltyStatus>(
                    onSelected: (status) =>
                        repository.updatePenaltyStatus(penalty, status),
                    itemBuilder: (_) => PenaltyStatus.values
                        .map(
                          (status) => PopupMenuItem(
                            value: status,
                            child: Text(status.name),
                          ),
                        )
                        .toList(),
                  )
                : null,
          ),
      ],
    ),
  );

  Widget _regulators(
    BuildContext context,
    List<RegulatoryBody> bodies,
  ) => Scaffold(
    floatingActionButton: canManage
        ? FloatingActionButton.extended(
            onPressed: () => _regulator(context),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Add regulator'),
          )
        : null,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        if (bodies.isEmpty)
          const ListTile(title: Text('No regulatory bodies configured.')),
        for (final body in bodies)
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance),
              title: Text(body.name),
              subtitle: Text(
                '${body.jurisdiction}\n${body.contactName} • ${body.contactEmail} • ${body.contactPhone}',
              ),
              isThreeLine: true,
            ),
          ),
      ],
    ),
  );

  Future<void> _regulator(BuildContext context) async {
    final name = TextEditingController(),
        jurisdiction = TextEditingController(),
        contact = TextEditingController(),
        email = TextEditingController(),
        phone = TextEditingController();
    final ok = await _form(context, 'Regulatory body', 'Save', [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Regulatory body name'),
      ),
      TextField(
        controller: jurisdiction,
        decoration: const InputDecoration(labelText: 'Jurisdiction'),
      ),
      TextField(
        controller: contact,
        decoration: const InputDecoration(labelText: 'Contact name'),
      ),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Contact email'),
      ),
      TextField(
        controller: phone,
        decoration: const InputDecoration(labelText: 'Contact phone'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.saveRegulatoryBody(
          name: name.text,
          jurisdiction: jurisdiction.text,
          contactName: contact.text,
          contactEmail: email.text,
          contactPhone: phone.text,
        ),
        'Regulatory body saved.',
      );
    }
    for (final controller in [name, jurisdiction, contact, email, phone]) {
      controller.dispose();
    }
  }

  Future<void> _document(
    BuildContext context,
    List<RegulatoryBody> bodies,
  ) async {
    var type = ComplianceDocumentType.operationalLicence;
    RegulatoryBody? body = bodies.firstOrNull;
    DateTime? issued = DateTime.now(),
        expires = DateTime.now().add(const Duration(days: 365));
    final title = TextEditingController(),
        reference = TextEditingController(),
        entity = TextEditingController(),
        notes = TextEditingController();
    final files = <Uint8List>[];
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Licence, certificate or submission'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<ComplianceDocumentType>(
                      initialValue: type,
                      items: ComplianceDocumentType.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => type = value!),
                    ),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: 'Document title',
                      ),
                    ),
                    TextField(
                      controller: reference,
                      decoration: const InputDecoration(
                        labelText: 'Reference number',
                      ),
                    ),
                    TextField(
                      controller: entity,
                      decoration: const InputDecoration(
                        labelText: 'Licensed or certified entity',
                      ),
                    ),
                    if (bodies.isNotEmpty)
                      DropdownButtonFormField<RegulatoryBody>(
                        initialValue: body,
                        decoration: const InputDecoration(
                          labelText: 'Regulatory body',
                        ),
                        items: bodies
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setLocal(() => body = value),
                      ),
                    ListTile(
                      title: const Text('Issue date'),
                      subtitle: Text('$issued'),
                      onTap: () async {
                        final date = await _date(context, issued!);
                        if (date != null) setLocal(() => issued = date);
                      },
                    ),
                    ListTile(
                      title: const Text('Expiry / submission deadline'),
                      subtitle: Text('$expires'),
                      onTap: () async {
                        final date = await _date(context, expires!);
                        if (date != null) setLocal(() => expires = date);
                      },
                    ),
                    TextField(
                      controller: notes,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await ImagePicker().pickMultiImage(
                          imageQuality: 80,
                        );
                        for (final file in picked) {
                          files.add(await file.readAsBytes());
                        }
                        setLocal(() {});
                      },
                      icon: const Icon(Icons.attach_file),
                      label: Text('Documents (${files.length})'),
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
        ) ??
        false;
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.saveDocument(
          type: type,
          title: title.text,
          referenceNumber: reference.text,
          entityName: entity.text,
          regulatoryBody: body,
          issuedAt: issued,
          expiresAt: expires,
          notes: notes.text,
          files: files,
          actorId: currentUserId,
        ),
        'Compliance document saved.',
      );
    }
    for (final controller in [title, reference, entity, notes]) {
      controller.dispose();
    }
  }

  Future<void> _requirement(BuildContext context) async {
    final category = TextEditingController(text: 'Environmental'),
        title = TextEditingController(),
        description = TextEditingController();
    var mandatory = true;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Compliance checklist requirement'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Requirement'),
                  ),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  SwitchListTile(
                    value: mandatory,
                    onChanged: (value) => setLocal(() => mandatory = value),
                    title: const Text('Mandatory'),
                  ),
                ],
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
        ) ??
        false;
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.saveRequirement(
          category: category.text,
          title: title.text,
          description: description.text,
          mandatory: mandatory,
        ),
        'Checklist requirement saved.',
      );
    }
    category.dispose();
    title.dispose();
    description.dispose();
  }

  Future<void> _scheduleInspection(
    BuildContext context,
    List<RegulatoryBody> bodies,
  ) async {
    final requirements = await repository.watchRequirements().first;
    if (!context.mounted) return;
    RegulatoryBody? body = bodies.firstOrNull;
    DateTime scheduled = DateTime.now().add(const Duration(days: 7));
    final entity = TextEditingController(), inspector = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Schedule compliance inspection'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: entity,
                    decoration: const InputDecoration(
                      labelText: 'Entity or facility',
                    ),
                  ),
                  TextField(
                    controller: inspector,
                    decoration: const InputDecoration(labelText: 'Inspector'),
                  ),
                  if (bodies.isNotEmpty)
                    DropdownButtonFormField<RegulatoryBody>(
                      initialValue: body,
                      items: bodies
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => body = value),
                    ),
                  ListTile(
                    title: const Text('Inspection date'),
                    subtitle: Text('$scheduled'),
                    onTap: () async {
                      final date = await _date(context, scheduled);
                      if (date != null) setLocal(() => scheduled = date);
                    },
                  ),
                  Text(
                    '${requirements.length} active checklist requirement(s)',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Schedule'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.scheduleInspection(
          entityName: entity.text,
          regulatoryBody: body,
          inspectorName: inspector.text,
          scheduledAt: scheduled,
          requirements: requirements
              .where((requirement) => requirement.active)
              .toList(),
          actorId: currentUserId,
        ),
        'Inspection scheduled.',
      );
    }
    entity.dispose();
    inspector.dispose();
  }

  Future<void> _completeInspection(
    BuildContext context,
    ComplianceInspection inspection,
  ) async {
    final checklist = Map<String, bool>.from(inspection.checklist);
    final findings = TextEditingController(),
        recommendations = TextEditingController();
    final reports = <Uint8List>[];
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Inspection report'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in checklist.entries)
                      CheckboxListTile(
                        value: entry.value,
                        onChanged: (value) => setLocal(
                          () => checklist[entry.key] = value ?? false,
                        ),
                        title: Text(entry.key),
                      ),
                    TextField(
                      controller: findings,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Inspection findings',
                      ),
                    ),
                    TextField(
                      controller: recommendations,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Recommendations',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await ImagePicker().pickMultiImage(
                          imageQuality: 80,
                        );
                        for (final file in picked) {
                          reports.add(await file.readAsBytes());
                        }
                        setLocal(() {});
                      },
                      icon: const Icon(Icons.attach_file),
                      label: Text('Report evidence (${reports.length})'),
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
                  child: const Text('Complete'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.completeInspection(
          inspection,
          checklist: checklist,
          findings: findings.text,
          recommendations: recommendations.text,
          reports: reports,
          actorId: currentUserId,
        ),
        'Inspection report completed.',
      );
    }
    findings.dispose();
    recommendations.dispose();
  }

  Future<void> _violation(BuildContext context) async {
    var severity = ViolationSeverity.major;
    final entity = TextEditingController(),
        requirement = TextEditingController(),
        description = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Record compliance violation'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: entity,
                    decoration: const InputDecoration(
                      labelText: 'Entity or facility',
                    ),
                  ),
                  TextField(
                    controller: requirement,
                    decoration: const InputDecoration(
                      labelText: 'Regulation or requirement',
                    ),
                  ),
                  DropdownButtonFormField<ViolationSeverity>(
                    initialValue: severity,
                    items: ViolationSeverity.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => severity = value!),
                  ),
                  TextField(
                    controller: description,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Violation description',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Record'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.recordViolation(
          entityName: entity.text,
          requirement: requirement.text,
          description: description.text,
          severity: severity,
          actorId: currentUserId,
        ),
        'Violation recorded.',
      );
    }
    entity.dispose();
    requirement.dispose();
    description.dispose();
  }

  Future<void> _correctiveAction(
    BuildContext context,
    ComplianceViolation violation,
  ) async {
    final plan = TextEditingController(text: violation.correctiveActionPlan),
        owner = TextEditingController(text: violation.correctiveActionOwner);
    DateTime due =
        violation.correctiveActionDueAt ??
        DateTime.now().add(const Duration(days: 30));
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Corrective action plan'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: plan,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Corrective actions',
                    ),
                  ),
                  TextField(
                    controller: owner,
                    decoration: const InputDecoration(
                      labelText: 'Responsible owner',
                    ),
                  ),
                  ListTile(
                    title: const Text('Due date'),
                    subtitle: Text('$due'),
                    onTap: () async {
                      final date = await _date(context, due);
                      if (date != null) setLocal(() => due = date);
                    },
                  ),
                ],
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
        ) ??
        false;
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.setCorrectiveAction(
          violation,
          plan: plan.text,
          owner: owner.text,
          dueAt: due,
        ),
        'Corrective action recorded.',
      );
    }
    plan.dispose();
    owner.dispose();
  }

  Future<void> _resolveViolation(
    BuildContext context,
    ComplianceViolation violation,
  ) async {
    final evidence = TextEditingController();
    final ok = await _text(
      context,
      'Resolve violation',
      'Resolution evidence and verification',
      evidence,
      'Resolve',
    );
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.resolveViolation(
          violation,
          evidence: evidence.text,
          actorId: currentUserId,
        ),
        'Violation resolved.',
      );
    }
    evidence.dispose();
  }

  Future<void> _penalty(
    BuildContext context,
    ComplianceViolation violation,
  ) async {
    final reference = TextEditingController(),
        amount = TextEditingController(),
        currency = TextEditingController(text: 'USD'),
        notes = TextEditingController();
    DateTime due = DateTime.now().add(const Duration(days: 30));
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Penalty record'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Penalty reference',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: currency,
                          decoration: const InputDecoration(
                            labelText: 'Currency',
                          ),
                        ),
                      ),
                    ],
                  ),
                  ListTile(
                    title: const Text('Due date'),
                    subtitle: Text('$due'),
                    onTap: () async {
                      final date = await _date(context, due);
                      if (date != null) setLocal(() => due = date);
                    },
                  ),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                      labelText: 'Penalty notes',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Record'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runCompliance(
        context,
        () => repository.recordPenalty(
          violation,
          referenceNumber: reference.text,
          amount: double.tryParse(amount.text) ?? 0,
          currency: currency.text,
          dueAt: due,
          notes: notes.text,
        ),
        'Penalty recorded.',
      );
    }
    reference.dispose();
    amount.dispose();
    currency.dispose();
    notes.dispose();
  }

  Future<void> _auditReport(
    List<ComplianceDocument> documents,
    List<ComplianceInspection> inspections,
    List<ComplianceViolation> violations,
    List<PenaltyRecord> penalties,
    ComplianceScore score,
  ) async {
    final report = pw.Document();
    report.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Compliance Audit Report'),
          pw.Text('Generated ${DateTime.now()}'),
          pw.Text(
            'Overall compliance score: ${score.overall.toStringAsFixed(1)}%',
          ),
          pw.Text('Document score: ${score.documentScore.toStringAsFixed(1)}%'),
          pw.Text(
            'Inspection score: ${score.inspectionScore.toStringAsFixed(1)}%',
          ),
          pw.Text(
            'Violation score: ${score.violationScore.toStringAsFixed(1)}%',
          ),
          pw.Header(level: 1, text: 'Licences, certifications and submissions'),
          pw.TableHelper.fromTextArray(
            headers: const ['Type', 'Title', 'Reference', 'Status', 'Expiry'],
            data: documents
                .map(
                  (document) => [
                    document.type.label,
                    document.title,
                    document.referenceNumber,
                    document.status.name,
                    '${document.expiresAt ?? ''}',
                  ],
                )
                .toList(),
          ),
          pw.Header(level: 1, text: 'Inspections'),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Entity',
              'Inspector',
              'Status',
              'Score',
              'Findings',
            ],
            data: inspections
                .map(
                  (inspection) => [
                    inspection.entityName,
                    inspection.inspectorName,
                    inspection.status.name,
                    inspection.score.toStringAsFixed(1),
                    inspection.findings,
                  ],
                )
                .toList(),
          ),
          pw.Header(level: 1, text: 'Violations and corrective actions'),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Reference',
              'Severity',
              'Status',
              'Corrective action',
              'Due',
            ],
            data: violations
                .map(
                  (violation) => [
                    violation.referenceNumber,
                    violation.severity.name,
                    violation.status.name,
                    violation.correctiveActionPlan,
                    '${violation.correctiveActionDueAt ?? ''}',
                  ],
                )
                .toList(),
          ),
          pw.Header(level: 1, text: 'Penalty records'),
          ...penalties.map(
            (penalty) => pw.Text(
              '${penalty.referenceNumber}: ${penalty.currency} ${penalty.amount}; ${penalty.status.name}; due ${penalty.dueAt}',
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => report.save());
  }
}

Color _scoreColor(double score) => score >= 80
    ? Colors.green
    : score >= 60
    ? Colors.orange
    : Colors.red;
Widget _metric(String label, String value, IconData icon) => SizedBox(
  width: 170,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(label),
        ],
      ),
    ),
  ),
);
Future<DateTime?> _date(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
Future<bool> _form(
  BuildContext context,
  String title,
  String action,
  List<Widget> children,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<bool> _text(
  BuildContext context,
  String title,
  String label,
  TextEditingController controller,
  String action,
) => _form(context, title, action, [
  TextField(
    controller: controller,
    maxLines: 4,
    decoration: InputDecoration(labelText: label),
  ),
]);
Future<void> _runCompliance(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compliance operation failed: $error')),
      );
    }
  }
}
