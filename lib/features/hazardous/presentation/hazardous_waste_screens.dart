import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../recycling/domain/recycling_batch.dart';
import '../data/hazardous_waste_repository.dart';
import '../domain/hazardous_waste.dart';

class HazardousWasteDashboardScreen extends StatelessWidget {
  const HazardousWasteDashboardScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.canCertify,
  });
  final HazardousWasteRepository repository;
  final String currentUserId;
  final bool canCertify;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Hazardous waste management'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Hazardous inventory'),
            Tab(text: 'Safety training'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _training(context),
            icon: const Icon(Icons.school_outlined),
            tooltip: 'Record safety training',
          ),
        ],
      ),
      body: TabBarView(
        children: [
          StreamBuilder<List<HazardousWasteRecord>>(
            stream: repository.watchRecords(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Unable to load hazardous records: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final records = snapshot.data!;
              final weight = records.fold<double>(
                0,
                (total, record) => total + record.weightKg,
              );
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 8,
                        children: [
                          Text('Records: ${records.length}'),
                          Text(
                            'Controlled weight: ${weight.toStringAsFixed(2)} kg',
                          ),
                          Text(
                            'Incident holds: ${records.where((record) => record.status == HazardousWasteStatus.incidentHold).length}',
                          ),
                          Text(
                            'Disposed/certified: ${records.where((record) => [HazardousWasteStatus.disposed, HazardousWasteStatus.certified].contains(record.status)).length}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (records.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('No hazardous waste identified.'),
                      ),
                    ),
                  for (final record in records)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            record.status == HazardousWasteStatus.incidentHold
                                ? Icons.warning
                                : Icons.health_and_safety_outlined,
                          ),
                        ),
                        title: Text(
                          '${record.code} • ${record.category.label}',
                        ),
                        subtitle: Text(
                          '${record.weightKg} kg • ${record.status.name}\n${record.storageLocation.isEmpty ? 'Storage unassigned' : record.storageLocation}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HazardousWasteRecordScreen(
                              repository: repository,
                              initial: record,
                              currentUserId: currentUserId,
                              canCertify: canCertify,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          StreamBuilder<List<SafetyTrainingRecord>>(
            stream: repository.watchTraining(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: ListTile(
                      title: Text('Training records: ${snapshot.data!.length}'),
                      subtitle: Text(
                        'Current: ${snapshot.data!.where((record) => record.valid).length} • Expired: ${snapshot.data!.where((record) => !record.valid).length}',
                      ),
                    ),
                  ),
                  for (final record in snapshot.data!)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          record.valid
                              ? Icons.verified_user_outlined
                              : Icons.warning_amber,
                        ),
                        title: Text('${record.staffId} • ${record.course}'),
                        subtitle: Text(
                          'Completed ${record.completedAt ?? ''}\nExpires ${record.expiresAt ?? 'No expiry'}',
                        ),
                        isThreeLine: true,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _identify(context),
        icon: const Icon(Icons.add_alert),
        label: const Text('Identify waste'),
      ),
    ),
  );

  Future<void> _identify(BuildContext context) async {
    final batches = await repository.watchRecyclingBatches().first;
    if (!context.mounted) return;
    RecyclingBatch? sourceBatch;
    var useBatch = batches.isNotEmpty;
    if (useBatch) {
      sourceBatch = batches
          .where((batch) => !batch.completionVerified)
          .firstOrNull;
    }
    if (sourceBatch == null) useBatch = false;
    final reference = TextEditingController(),
        classification = TextEditingController(),
        weight = TextEditingController(),
        quantity = TextEditingController(text: '0'),
        instructions = TextEditingController();
    var category = HazardousMaterialCategory.lithiumBattery;
    final activeBatches = batches
        .where((batch) => !batch.completionVerified)
        .toList();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Hazardous waste identification'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (activeBatches.isNotEmpty)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: useBatch,
                        onChanged: (value) => setLocal(() {
                          useBatch = value;
                          sourceBatch ??= activeBatches.first;
                        }),
                        title: const Text('Link to recycling batch'),
                      ),
                    if (useBatch)
                      DropdownButtonFormField<RecyclingBatch>(
                        initialValue: sourceBatch,
                        decoration: const InputDecoration(
                          labelText: 'Source batch',
                        ),
                        items: activeBatches
                            .map(
                              (batch) => DropdownMenuItem(
                                value: batch,
                                child: Text(batch.code),
                              ),
                            )
                            .toList(),
                        onChanged: (batch) =>
                            setLocal(() => sourceBatch = batch),
                      ),
                    if (!useBatch)
                      TextField(
                        controller: reference,
                        decoration: const InputDecoration(
                          labelText: 'Source item / reference',
                        ),
                      ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<HazardousMaterialCategory>(
                      initialValue: category,
                      decoration: const InputDecoration(
                        labelText: 'Hazardous category',
                      ),
                      items: HazardousMaterialCategory.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (item) => setLocal(() => category = item!),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: classification,
                      decoration: const InputDecoration(
                        labelText:
                            'Toxic material classification / hazard class',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: instructions,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Safety instructions',
                      ),
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
                  child: const Text('Identify'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runHazard(
        context,
        () => repository.identify(
          sourceBatch: useBatch ? sourceBatch : null,
          sourceReference: reference.text,
          category: category,
          classification: classification.text,
          weightKg: double.tryParse(weight.text) ?? 0,
          quantity: int.tryParse(quantity.text) ?? 0,
          safetyInstructions: instructions.text,
          actorId: currentUserId,
        ),
        'Hazardous waste identified.',
      );
    }
    for (final c in [
      reference,
      classification,
      weight,
      quantity,
      instructions,
    ]) {
      c.dispose();
    }
  }

  Future<void> _training(BuildContext context) async {
    final staff = TextEditingController(),
        course = TextEditingController(),
        certificate = TextEditingController();
    var completed = DateTime.now(),
        expires = DateTime.now().add(const Duration(days: 365));
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Staff safety training record'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: staff,
                    decoration: const InputDecoration(
                      labelText: 'Staff user ID',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: course,
                    decoration: const InputDecoration(
                      labelText: 'Course / competency',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: certificate,
                    decoration: const InputDecoration(
                      labelText: 'Certificate reference',
                    ),
                  ),
                  ListTile(
                    title: const Text('Completed'),
                    subtitle: Text('$completed'),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDate: completed,
                      );
                      if (date != null) setLocal(() => completed = date);
                    },
                  ),
                  ListTile(
                    title: const Text('Expires'),
                    subtitle: Text('$expires'),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: completed,
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                        initialDate: expires,
                      );
                      if (date != null) setLocal(() => expires = date);
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
                  child: const Text('Record'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runHazard(
        context,
        () => repository.recordTraining(
          staffId: staff.text,
          course: course.text,
          completedAt: completed,
          expiresAt: expires,
          certificateReference: certificate.text,
        ),
        'Safety training recorded.',
      );
    }
    staff.dispose();
    course.dispose();
    certificate.dispose();
  }
}

class HazardousWasteRecordScreen extends StatelessWidget {
  const HazardousWasteRecordScreen({
    super.key,
    required this.repository,
    required this.initial,
    required this.currentUserId,
    required this.canCertify,
  });
  final HazardousWasteRepository repository;
  final HazardousWasteRecord initial;
  final String currentUserId;
  final bool canCertify;

  @override
  Widget build(BuildContext context) => StreamBuilder<HazardousWasteRecord>(
    stream: repository.watchRecord(initial.id),
    initialData: initial,
    builder: (context, snapshot) {
      final record = snapshot.data!;
      return Scaffold(
        appBar: AppBar(
          title: Text(record.code),
          actions: [
            IconButton(
              onPressed: () => _certificate(record),
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Hazardous waste certificate',
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.category.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('Classification: ${record.classification}'),
                    Text(
                      'Weight: ${record.weightKg} kg • quantity ${record.quantity}',
                    ),
                    Text('Status: ${record.status.name}'),
                    Text('Source: ${record.sourceReference}'),
                    Text(
                      'Storage: ${record.storageLocation.isEmpty ? 'Unassigned' : record.storageLocation}',
                    ),
                    Text(
                      'Disposal facility: ${record.disposalFacility.isEmpty ? 'Unassigned' : record.disposalFacility}',
                    ),
                    const SizedBox(height: 8),
                    Text('Safety instructions: ${record.safetyInstructions}'),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => _storage(context, record),
                  child: const Text('Special storage'),
                ),
                FilledButton.tonal(
                  onPressed: () => _ppe(context, record),
                  child: const Text('PPE checklist'),
                ),
                if ([
                  HazardousMaterialCategory.lithiumBattery,
                  HazardousMaterialCategory.leadAcidBattery,
                ].contains(record.category))
                  FilledButton.tonal(
                    onPressed: () => _battery(context, record),
                    child: const Text('Battery handling'),
                  ),
                FilledButton.tonal(
                  onPressed: () => _incident(context, record),
                  child: const Text('Report incident'),
                ),
                FilledButton.tonal(
                  onPressed: () => _compliance(context, record),
                  child: const Text('Compliance document'),
                ),
                FilledButton.tonal(
                  onPressed: () => _facility(context, record),
                  child: const Text('Disposal facility'),
                ),
                FilledButton.tonal(
                  onPressed: record.disposalFacility.isEmpty
                      ? null
                      : () => _transfer(context, record),
                  child: const Text('Transfer'),
                ),
                FilledButton.tonal(
                  onPressed: record.status != HazardousWasteStatus.transferred
                      ? null
                      : () => _dispose(context, record),
                  child: const Text('Complete disposal'),
                ),
                if (canCertify)
                  FilledButton(
                    onPressed: record.status != HazardousWasteStatus.disposed
                        ? null
                        : () => _runHazard(
                            context,
                            () => repository.certify(record, currentUserId),
                            'Hazardous waste certified.',
                          ),
                    child: const Text('Certify'),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text(
              'Protective equipment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final entry in record.ppeChecklist.entries)
              ListTile(
                leading: Icon(entry.value ? Icons.check : Icons.close),
                title: Text(entry.key),
              ),
            Text(
              'Incident and emergency response',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<HazardousIncident>>(
              stream: repository.watchIncidents(record.id),
              builder: (context, snapshot) => Column(
                children: (snapshot.data ?? const <HazardousIncident>[])
                    .map(
                      (incident) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.emergency),
                          title: Text(
                            '${incident.severity.name} • ${incident.status.name}',
                          ),
                          subtitle: Text(
                            '${incident.description}\n${incident.emergencyActions}',
                          ),
                          isThreeLine: true,
                          trailing: incident.status == IncidentStatus.closed
                              ? null
                              : TextButton(
                                  onPressed: () =>
                                      _response(context, record, incident),
                                  child: const Text('Respond'),
                                ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Text(
              'Hazardous transfers',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<HazardousTransferRecord>>(
              stream: repository.watchTransfers(record.id),
              builder: (context, snapshot) => Column(
                children: (snapshot.data ?? const <HazardousTransferRecord>[])
                    .map(
                      (transfer) => ListTile(
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: Text('${transfer.from} → ${transfer.to}'),
                        subtitle: Text(
                          '${transfer.carrier} • Manifest ${transfer.manifestNumber}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Text(
              'Compliance documentation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: repository.watchComplianceDocuments(record.id),
              builder: (context, snapshot) => Column(
                children: (snapshot.data ?? const <Map<String, dynamic>>[])
                    .map(
                      (document) => ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(document['title'] ?? ''),
                        subtitle: Text(
                          '${document['reference'] ?? ''}\n${(document['expiresAt'] as Timestamp?)?.toDate() ?? ''}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _storage(
    BuildContext context,
    HazardousWasteRecord record,
  ) async {
    final location = TextEditingController(text: record.storageLocation),
        instructions = TextEditingController(text: record.safetyInstructions);
    final ok = await _form(context, 'Special storage assignment', 'Assign', [
      TextField(
        controller: location,
        decoration: const InputDecoration(
          labelText: 'Controlled storage location',
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: instructions,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Safety instructions'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runHazard(
        context,
        () => repository.assignStorage(
          record,
          location: location.text,
          safetyInstructions: instructions.text,
        ),
        'Special storage assigned.',
      );
    }
    location.dispose();
    instructions.dispose();
  }

  Future<void> _ppe(BuildContext context, HazardousWasteRecord record) async {
    final checks = <String, bool>{
      'Chemical-resistant gloves': false,
      'Safety goggles / face shield': false,
      'Protective clothing': false,
      'Respiratory protection if required': false,
      'Spill kit available': false,
    };
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Protective equipment checklist'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in checks.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: entry.value,
                      onChanged: (value) =>
                          setLocal(() => checks[entry.key] = value ?? false),
                      title: Text(entry.key),
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
      await _runHazard(
        context,
        () => repository.recordPpeChecklist(record, checks, currentUserId),
        'PPE checklist recorded.',
      );
    }
  }

  Future<void> _battery(
    BuildContext context,
    HazardousWasteRecord record,
  ) async {
    var insulated = false, isolated = false, protected = false;
    final notes = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Battery handling record'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: insulated,
                    onChanged: (value) =>
                        setLocal(() => insulated = value ?? false),
                    title: const Text('Terminals insulated'),
                  ),
                  CheckboxListTile(
                    value: isolated,
                    onChanged: (value) =>
                        setLocal(() => isolated = value ?? false),
                    title: const Text('Damaged batteries isolated'),
                  ),
                  CheckboxListTile(
                    value: protected,
                    onChanged: (value) =>
                        setLocal(() => protected = value ?? false),
                    title: const Text('Protected from charge / short circuit'),
                  ),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                      labelText: 'Handling notes',
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
      await _runHazard(
        context,
        () => repository.recordBatteryHandling(
          record,
          terminalsInsulated: insulated,
          damagedIsolated: isolated,
          chargeProtected: protected,
          notes: notes.text,
          actorId: currentUserId,
        ),
        'Battery handling recorded.',
      );
    }
    notes.dispose();
  }

  Future<void> _incident(
    BuildContext context,
    HazardousWasteRecord record,
  ) async {
    var severity = IncidentSeverity.moderate;
    final description = TextEditingController(),
        actions = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Incident report'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<IncidentSeverity>(
                    initialValue: severity,
                    items: IncidentSeverity.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (item) => setLocal(() => severity = item!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Incident description',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: actions,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Immediate emergency actions',
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
                  child: const Text('Report'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runHazard(
        context,
        () => repository.reportIncident(
          record,
          severity: severity,
          description: description.text,
          emergencyActions: actions.text,
          actorId: currentUserId,
        ),
        'Incident reported and material placed on hold.',
      );
    }
    description.dispose();
    actions.dispose();
  }

  Future<void> _response(
    BuildContext context,
    HazardousWasteRecord record,
    HazardousIncident incident,
  ) async {
    var status = IncidentStatus.responding;
    final actions = TextEditingController(text: incident.emergencyActions);
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Emergency response workflow'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<IncidentStatus>(
                    initialValue: status,
                    items: IncidentStatus.values
                        .where((item) => item != IncidentStatus.reported)
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (item) => setLocal(() => status = item!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: actions,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Response actions and findings',
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
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runHazard(
        context,
        () => repository.updateEmergencyResponse(
          record,
          incident,
          status: status,
          actions: actions.text,
          actorId: currentUserId,
        ),
        'Emergency response updated.',
      );
    }
    actions.dispose();
  }

  Future<void> _compliance(
    BuildContext context,
    HazardousWasteRecord record,
  ) async {
    final title = TextEditingController(),
        reference = TextEditingController(),
        notes = TextEditingController();
    DateTime? expires;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Compliance document'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Document title',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Reference / permit number',
                    ),
                  ),
                  ListTile(
                    title: const Text('Expiry date'),
                    subtitle: Text('${expires ?? 'No expiry'}'),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                        initialDate:
                            expires ??
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) setLocal(() => expires = date);
                    },
                  ),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Compliance notes',
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
      await _runHazard(
        context,
        () => repository.addComplianceDocument(
          record,
          title: title.text,
          reference: reference.text,
          expiresAt: expires,
          notes: notes.text,
          actorId: currentUserId,
        ),
        'Compliance document recorded.',
      );
    }
    title.dispose();
    reference.dispose();
    notes.dispose();
  }

  Future<void> _facility(
    BuildContext context,
    HazardousWasteRecord record,
  ) async {
    final facility = TextEditingController(text: record.disposalFacility);
    final ok = await _form(context, 'Disposal facility assignment', 'Assign', [
      TextField(
        controller: facility,
        decoration: const InputDecoration(
          labelText: 'Licensed disposal facility',
        ),
      ),
    ]);
    if (ok && context.mounted) {
      await _runHazard(
        context,
        () => repository.assignDisposalFacility(record, facility.text),
        'Disposal facility assigned.',
      );
    }
    facility.dispose();
  }

  Future<void> _transfer(
    BuildContext context,
    HazardousWasteRecord record,
  ) async {
    final carrier = TextEditingController(), manifest = TextEditingController();
    final ok = await _form(context, 'Hazardous transfer record', 'Transfer', [
      TextField(
        controller: carrier,
        decoration: const InputDecoration(labelText: 'Licensed carrier'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: manifest,
        decoration: const InputDecoration(labelText: 'Manifest number'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runHazard(
        context,
        () => repository.recordTransfer(
          record,
          carrier: carrier.text,
          manifestNumber: manifest.text,
          actorId: currentUserId,
        ),
        'Hazardous transfer recorded.',
      );
    }
    carrier.dispose();
    manifest.dispose();
  }

  Future<void> _dispose(
    BuildContext context,
    HazardousWasteRecord record,
  ) async {
    final method = TextEditingController(), receipt = TextEditingController();
    final ok = await _form(context, 'Complete hazardous disposal', 'Complete', [
      TextField(
        controller: method,
        decoration: const InputDecoration(
          labelText: 'Approved disposal method',
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: receipt,
        decoration: const InputDecoration(labelText: 'Facility receipt number'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runHazard(
        context,
        () => repository.completeDisposal(
          record,
          method: method.text,
          receiptNumber: receipt.text,
          actorId: currentUserId,
        ),
        'Hazardous disposal completed.',
      );
    }
    method.dispose();
    receipt.dispose();
  }

  Future<void> _certificate(HazardousWasteRecord record) async {
    final incidents = await repository.watchIncidents(record.id).first;
    final transfers = await repository.watchTransfers(record.id).first;
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Hazardous Waste Certificate'),
          pw.Text(
            'Certificate: ${record.certificateNumber.isEmpty ? 'DRAFT-${record.id.substring(0, 8).toUpperCase()}' : record.certificateNumber}',
          ),
          pw.Text('Waste record: ${record.code}'),
          pw.Text('Category: ${record.category.label}'),
          pw.Text('Classification: ${record.classification}'),
          pw.Text('Weight: ${record.weightKg} kg'),
          pw.Text('Source: ${record.sourceReference}'),
          pw.Text('Storage: ${record.storageLocation}'),
          pw.Text('Disposal facility: ${record.disposalFacility}'),
          pw.Text('Status: ${record.status.name}'),
          pw.SizedBox(height: 10),
          pw.Header(level: 1, text: 'Safety controls'),
          pw.Text(record.safetyInstructions),
          ...record.ppeChecklist.entries.map(
            (entry) => pw.Text(
              '${entry.key}: ${entry.value ? 'Complete' : 'Incomplete'}',
            ),
          ),
          pw.Header(level: 1, text: 'Incidents'),
          ...incidents.map(
            (incident) => pw.Text(
              '${incident.severity.name}: ${incident.description} - ${incident.status.name}',
            ),
          ),
          pw.Header(level: 1, text: 'Transfers'),
          ...transfers.map(
            (transfer) => pw.Text(
              '${transfer.from} to ${transfer.to}; ${transfer.carrier}; ${transfer.manifestNumber}',
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }
}

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
Future<void> _runHazard(
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
        SnackBar(content: Text('Hazardous operation failed: $error')),
      );
    }
  }
}
