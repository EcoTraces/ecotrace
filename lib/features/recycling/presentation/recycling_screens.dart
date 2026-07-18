import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/inventory_item.dart';
import '../data/recycling_repository.dart';
import '../domain/recycling_batch.dart';

class RecyclingDashboardScreen extends StatelessWidget {
  const RecyclingDashboardScreen({
    super.key,
    required this.repository,
    required this.inventoryRepository,
    required this.currentUserId,
    required this.canVerify,
  });
  final RecyclingRepository repository;
  final InventoryRepository inventoryRepository;
  final String currentUserId;
  final bool canVerify;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recycling process management')),
    body: StreamBuilder<List<RecyclingBatch>>(
      stream: repository.watchBatches(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load batches: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final batches = snapshot.data!;
        final input = batches.fold<double>(
          0,
          (sum, batch) => sum + batch.inputWeightKg,
        );
        final recovered = batches.fold<double>(
          0,
          (sum, batch) => sum + batch.recoveredWeightKg,
        );
        final losses = batches.fold<double>(
          0,
          (sum, batch) => sum + batch.processingLossKg,
        );
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Batch performance report',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        Text('Batches: ${batches.length}'),
                        Text('Input: ${input.toStringAsFixed(1)} kg'),
                        Text('Recovered: ${recovered.toStringAsFixed(1)} kg'),
                        Text('Losses: ${losses.toStringAsFixed(1)} kg'),
                        Text(
                          'Recovery: ${input == 0 ? '0.0' : (recovered / input * 100).toStringAsFixed(1)}%',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (batches.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No recycling batches.')),
              ),
            for (final batch in batches)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.recycling)),
                  title: Text(
                    '${batch.code} • ${batch.facilityName.isEmpty ? 'Facility unassigned' : batch.facilityName}',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${batch.stage.label} • ${batch.itemIds.length} items • ${batch.inputWeightKg.toStringAsFixed(1)} kg',
                      ),
                      Text(
                        'Recovery ${batch.recoveryEfficiencyPercent.toStringAsFixed(1)}% • unaccounted ${batch.unaccountedWeightKg.toStringAsFixed(2)} kg',
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: batch.completionVerified
                      ? const Icon(Icons.verified)
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecyclingBatchScreen(
                        repository: repository,
                        initial: batch,
                        currentUserId: currentUserId,
                        canVerify: canVerify,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _create(context),
      icon: const Icon(Icons.add),
      label: const Text('Create batch'),
    ),
  );

  Future<void> _create(BuildContext context) async {
    final items = await inventoryRepository.watchItems().first;
    if (!context.mounted) return;
    final candidates = items
        .where(
          (item) =>
              [
                ItemCondition.recyclable,
                ItemCondition.nonRecoverable,
                ItemCondition.hazardous,
              ].contains(item.condition) &&
              ![
                ProcessingStatus.recycling,
                ProcessingStatus.recovered,
                ProcessingStatus.disposed,
              ].contains(item.status),
        )
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recyclable inventory is available.')),
      );
      return;
    }
    final selected = <InventoryItem>{};
    final facilityId = TextEditingController();
    final facilityName = TextEditingController();
    final submitted =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocalState) => AlertDialog(
              title: const Text('Create recycling batch'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: facilityId,
                        decoration: const InputDecoration(
                          labelText: 'Facility ID',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: facilityName,
                        decoration: const InputDecoration(
                          labelText: 'Recycling facility',
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Select non-reusable inventory'),
                      ),
                      for (final item in candidates)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(item),
                          onChanged: (value) => setLocalState(
                            () => value == true
                                ? selected.add(item)
                                : selected.remove(item),
                          ),
                          title: Text(
                            '${item.itemCode} • ${item.brand} ${item.model}',
                          ),
                          subtitle: Text(
                            '${item.condition.name} • ${item.weight} kg',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (submitted && context.mounted) {
      await _runRecycle(
        context,
        () => repository.createBatch(
          items: selected.toList(),
          facilityId: facilityId.text,
          facilityName: facilityName.text,
          actorId: currentUserId,
        ),
        'Recycling batch created.',
      );
    }
    facilityId.dispose();
    facilityName.dispose();
  }
}

class RecyclingBatchScreen extends StatelessWidget {
  const RecyclingBatchScreen({
    super.key,
    required this.repository,
    required this.initial,
    required this.currentUserId,
    required this.canVerify,
  });
  final RecyclingRepository repository;
  final RecyclingBatch initial;
  final String currentUserId;
  final bool canVerify;

  @override
  Widget build(BuildContext context) => StreamBuilder<RecyclingBatch>(
    stream: repository.watchBatch(initial.id),
    initialData: initial,
    builder: (context, snapshot) {
      final batch = snapshot.data!;
      return Scaffold(
        appBar: AppBar(
          title: Text(batch.code),
          actions: [
            IconButton(
              onPressed: () => _certificate(batch),
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Recycling certificate',
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
                      batch.stage.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Facility: ${batch.facilityName.isEmpty ? 'Unassigned' : batch.facilityName}',
                    ),
                    Text('Items: ${batch.itemCodes.join(', ')}'),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value:
                          batch.stage.index /
                          (RecyclingStage.values.length - 1),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 22,
                  runSpacing: 8,
                  children: [
                    Text('Input ${batch.inputWeightKg.toStringAsFixed(2)} kg'),
                    Text(
                      'Recovered ${batch.recoveredWeightKg.toStringAsFixed(2)} kg',
                    ),
                    Text(
                      'Hazardous ${batch.hazardousWeightKg.toStringAsFixed(2)} kg',
                    ),
                    Text(
                      'Disposed ${batch.disposedWeightKg.toStringAsFixed(2)} kg',
                    ),
                    Text(
                      'Loss ${batch.processingLossKg.toStringAsFixed(2)} kg',
                    ),
                    Text(
                      'Unaccounted ${batch.unaccountedWeightKg.toStringAsFixed(2)} kg',
                    ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: batch.completionVerified
                      ? null
                      : () => _facility(context, batch),
                  icon: const Icon(Icons.factory_outlined),
                  label: const Text('Assign facility'),
                ),
                FilledButton.tonalIcon(
                  onPressed: batch.completionVerified
                      ? null
                      : () => _stage(context, batch),
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Update stage'),
                ),
                FilledButton.tonalIcon(
                  onPressed: batch.completionVerified
                      ? null
                      : () => _process(context, batch),
                  icon: const Icon(Icons.precision_manufacturing_outlined),
                  label: const Text('Sorting / dismantling'),
                ),
                FilledButton.tonalIcon(
                  onPressed: batch.completionVerified
                      ? null
                      : () => _loss(context, batch),
                  icon: const Icon(Icons.trending_down),
                  label: const Text('Record loss'),
                ),
                FilledButton.tonalIcon(
                  onPressed: batch.completionVerified
                      ? null
                      : () => _disposal(context, batch),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Final disposal'),
                ),
                if (canVerify)
                  FilledButton.icon(
                    onPressed: batch.completionVerified
                        ? null
                        : () => _verify(context, batch),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verify completion'),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text(
              'Processing records',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<RecyclingProcessRecord>>(
              stream: repository.watchProcessRecords(batch.id),
              builder: (context, snapshot) => Column(
                children: (snapshot.data ?? const <RecyclingProcessRecord>[])
                    .map(
                      (record) => ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: Text(
                          '${record.type} • ${record.material} ${record.component}',
                        ),
                        subtitle: Text(
                          '${record.quantity} units • ${record.weightKg} kg\n${record.notes}',
                        ),
                        isThreeLine: true,
                      ),
                    )
                    .toList(),
              ),
            ),
            Text(
              'Final disposal records',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<FinalDisposalRecord>>(
              stream: repository.watchDisposals(batch.id),
              builder: (context, snapshot) => Column(
                children: (snapshot.data ?? const <FinalDisposalRecord>[])
                    .map(
                      (record) => ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(
                          '${record.material} • ${record.weightKg} kg',
                        ),
                        subtitle: Text(
                          '${record.facility} • ${record.method}\nManifest ${record.manifestNumber}',
                        ),
                        isThreeLine: true,
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

  Future<void> _facility(BuildContext context, RecyclingBatch batch) async {
    final id = TextEditingController(text: batch.facilityId);
    final name = TextEditingController(text: batch.facilityName);
    final ok = await _form(context, 'Assign recycling facility', 'Assign', [
      TextField(
        controller: id,
        decoration: const InputDecoration(labelText: 'Facility ID'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Facility name'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runRecycle(
        context,
        () => repository.assignFacility(
          batch,
          facilityId: id.text,
          facilityName: name.text,
        ),
        'Facility assigned.',
      );
    }
    id.dispose();
    name.dispose();
  }

  Future<void> _stage(BuildContext context, RecyclingBatch batch) async {
    var stage = batch.stage;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Processing stage'),
              content: DropdownButtonFormField<RecyclingStage>(
                initialValue: stage,
                items: RecyclingStage.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setLocal(() => stage = value!),
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
      await _runRecycle(
        context,
        () => repository.updateStage(batch, stage, currentUserId),
        'Stage updated.',
      );
    }
  }

  Future<void> _process(BuildContext context, RecyclingBatch batch) async {
    var type = 'materialSort';
    final material = TextEditingController(),
        component = TextEditingController(),
        quantity = TextEditingController(text: '0'),
        weight = TextEditingController(text: '0'),
        notes = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Sorting, dismantling, or separation record'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: const [
                        DropdownMenuItem(
                          value: 'materialSort',
                          child: Text('Sort by material'),
                        ),
                        DropdownMenuItem(
                          value: 'dismantling',
                          child: Text('Dismantling'),
                        ),
                        DropdownMenuItem(
                          value: 'componentSeparation',
                          child: Text('Component separation'),
                        ),
                      ],
                      onChanged: (value) => setLocal(() => type = value!),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: material,
                      decoration: const InputDecoration(labelText: 'Material'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: component,
                      decoration: const InputDecoration(labelText: 'Component'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity'),
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
                      controller: notes,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Process notes',
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
                  child: const Text('Record'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runRecycle(
        context,
        () => repository.recordProcess(
          batch,
          type: type,
          material: material.text,
          component: component.text,
          quantity: int.tryParse(quantity.text) ?? 0,
          weightKg: double.tryParse(weight.text) ?? 0,
          notes: notes.text,
          actorId: currentUserId,
        ),
        'Processing record added.',
      );
    }
    for (final c in [material, component, quantity, weight, notes]) {
      c.dispose();
    }
  }

  Future<void> _loss(BuildContext context, RecyclingBatch batch) async {
    final weight = TextEditingController(), reason = TextEditingController();
    final ok = await _form(context, 'Record processing loss', 'Record', [
      TextField(
        controller: weight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Loss weight (kg)'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: reason,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Loss reason'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runRecycle(
        context,
        () => repository.recordLoss(
          batch,
          weightKg: double.tryParse(weight.text) ?? 0,
          reason: reason.text,
          actorId: currentUserId,
        ),
        'Processing loss recorded.',
      );
    }
    weight.dispose();
    reason.dispose();
  }

  Future<void> _disposal(BuildContext context, RecyclingBatch batch) async {
    final material = TextEditingController(),
        weight = TextEditingController(),
        facility = TextEditingController(),
        method = TextEditingController(),
        manifest = TextEditingController();
    final ok = await _form(context, 'Final disposal record', 'Record', [
      TextField(
        controller: material,
        decoration: const InputDecoration(labelText: 'Residual material'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: weight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Weight (kg)'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: facility,
        decoration: const InputDecoration(labelText: 'Disposal facility'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: method,
        decoration: const InputDecoration(labelText: 'Disposal method'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: manifest,
        decoration: const InputDecoration(labelText: 'Manifest number'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runRecycle(
        context,
        () => repository.recordFinalDisposal(
          batch,
          material: material.text,
          weightKg: double.tryParse(weight.text) ?? 0,
          facility: facility.text,
          method: method.text,
          manifestNumber: manifest.text,
          actorId: currentUserId,
        ),
        'Final disposal recorded.',
      );
    }
    for (final c in [material, weight, facility, method, manifest]) {
      c.dispose();
    }
  }

  Future<void> _verify(BuildContext context, RecyclingBatch batch) async {
    final notes = TextEditingController();
    final ok = await _form(
      context,
      'Recycling completion verification',
      'Verify',
      [
        Text(
          'Unaccounted weight: ${batch.unaccountedWeightKg.toStringAsFixed(3)} kg',
        ),
        const SizedBox(height: 10),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Verification notes'),
        ),
      ],
    );
    if (ok && context.mounted) {
      await _runRecycle(
        context,
        () => repository.verifyCompletion(
          batch,
          notes: notes.text,
          actorId: currentUserId,
        ),
        'Recycling completion verified.',
      );
    }
    notes.dispose();
  }

  Future<void> _certificate(RecyclingBatch batch) async {
    final records = await repository.watchProcessRecords(batch.id).first;
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Recycling Certificate'),
          pw.Text(
            'Certificate reference: RCF-${batch.id.substring(0, 8).toUpperCase()}',
          ),
          pw.Text('Batch: ${batch.code}'),
          pw.Text('Facility: ${batch.facilityName}'),
          pw.Text('Input: ${batch.inputWeightKg} kg'),
          pw.Text('Recovered: ${batch.recoveredWeightKg} kg'),
          pw.Text('Hazardous: ${batch.hazardousWeightKg} kg'),
          pw.Text('Final disposal: ${batch.disposedWeightKg} kg'),
          pw.Text('Processing loss: ${batch.processingLossKg} kg'),
          pw.Text(
            'Recovery efficiency: ${batch.recoveryEfficiencyPercent.toStringAsFixed(2)}%',
          ),
          pw.Text('Completion verified: ${batch.completionVerified}'),
          pw.Text('Verification notes: ${batch.verificationNotes}'),
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'Processing record'),
          ...records.reversed.map(
            (record) => pw.Text(
              '${record.at ?? ''} - ${record.type}: ${record.material} ${record.component}, ${record.weightKg} kg',
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

Future<void> _runRecycle(
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
        SnackBar(content: Text('Recycling operation failed: $error')),
      );
    }
  }
}
