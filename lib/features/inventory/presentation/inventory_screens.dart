import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_item.dart';
import '../../classification/data/assessment_repository.dart';
import '../../classification/presentation/assessment_screen.dart';
import '../../traceability/data/traceability_repository.dart';
import '../../traceability/presentation/traceability_screens.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repository,
    this.canApprove = false,
  });
  final InventoryRepository repository;
  final bool canApprove;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String query = '';
  ItemCondition? condition;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('E-waste inventory'),
      actions: [
        IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: 'Scan item',
          onPressed: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) =>
                  TraceScannerScreen(repository: TraceabilityRepository()),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder),
          tooltip: 'Create batch',
          onPressed: () => _createBatch(c),
        ),
        IconButton(
          icon: const Icon(Icons.inventory_2_outlined),
          tooltip: 'Manage batches',
          onPressed: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) =>
                  InventoryBatchesScreen(repository: widget.repository),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.table_view),
          tooltip: 'Export CSV',
          onPressed: () => _exportCsv(c),
        ),
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'Export PDF',
          onPressed: () => _exportPdf(c),
        ),
      ],
    ),
    body: Column(
      children: [
        FutureBuilder<InventorySummary>(
          future: widget.repository.summary(),
          builder: (context, snapshot) {
            final summary = snapshot.data;
            if (summary == null) return const LinearProgressIndicator();
            return SizedBox(
              height: 88,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                scrollDirection: Axis.horizontal,
                children: [
                  _MetricCard(label: 'Items', value: '${summary.totalItems}'),
                  _MetricCard(
                    label: 'Weight',
                    value: '${summary.totalWeightKg.toStringAsFixed(1)} kg',
                  ),
                  _MetricCard(
                    label: 'Batched',
                    value: '${summary.batchedItems}',
                  ),
                  _MetricCard(label: 'Batches', value: '${summary.batches}'),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (x) => setState(() => query = x.toLowerCase()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search code, type, brand, model or serial',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<ItemCondition?>(
                value: condition,
                hint: const Text('Condition'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...ItemCondition.values.map(
                    (x) => DropdownMenuItem(value: x, child: Text(x.name)),
                  ),
                ],
                onChanged: (x) => setState(() => condition = x),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<InventoryItem>>(
            stream: widget.repository.watchItems(),
            builder: (c, s) {
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = s.data!
                  .where(
                    (x) =>
                        (condition == null || x.condition == condition) &&
                        ('${x.itemCode} ${x.deviceType} ${x.brand} ${x.model} ${x.serialNumber}'
                            .toLowerCase()
                            .contains(query)),
                  )
                  .toList();
              if (items.isEmpty) {
                return const Center(child: Text('No inventory items found.'));
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final x = items[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.devices_other),
                      title: Text('${x.itemCode} — ${x.brand} ${x.model}'),
                      subtitle: Text(
                        '${x.deviceType} • ${x.condition.name} • ${x.status.name}\n${x.location}',
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.push(
                        c,
                        MaterialPageRoute(
                          builder: (_) => InventoryDetailScreen(
                            repository: widget.repository,
                            item: x,
                            canApprove: widget.canApprove,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        c,
        MaterialPageRoute(
          builder: (_) =>
              RegisterInventoryScreen(repository: widget.repository),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Register item'),
    ),
  );
  Future<void> _createBatch(BuildContext c) async {
    final name = TextEditingController(), location = TextEditingController();
    final ok = await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: const Text('Create inventory batch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Batch name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: location,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await widget.repository.createBatch(
        name: name.text,
        location: location.text,
      );
    }
    name.dispose();
    location.dispose();
  }

  Future<List<InventoryItem>> _once() => widget.repository.watchItems().first;
  Future<void> _exportCsv(BuildContext c) async {
    final items = await _once();
    final rows = <List<dynamic>>[
      [
        'Item ID',
        'Type',
        'Brand',
        'Model',
        'Serial',
        'Condition',
        'Weight',
        'Location',
        'Status',
        'Batch',
      ],
      ...items.map(
        (x) => [
          x.itemCode,
          x.deviceType,
          x.brand,
          x.model,
          x.serialNumber,
          x.condition.name,
          x.weight,
          x.location,
          x.status.name,
          x.batchId ?? '',
        ],
      ),
    ];
    final data = csv.encode(rows);
    await SharePlus.instance.share(
      ShareParams(
        title: 'EcoTrace inventory',
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(data)),
            mimeType: 'text/csv',
            name: 'ecotrace_inventory.csv',
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf(BuildContext c) async {
    final items = await _once();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Inventory Report'),
          pw.Text('Generated ${DateTime.now()}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['ID', 'Device', 'Condition', 'kg', 'Location', 'Status'],
            data: items
                .map(
                  (x) => [
                    x.itemCode,
                    '${x.brand} ${x.model}',
                    x.condition.name,
                    x.weight,
                    x.location,
                    x.status.name,
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }
}

class RegisterInventoryScreen extends StatefulWidget {
  const RegisterInventoryScreen({super.key, required this.repository});
  final InventoryRepository repository;
  @override
  State<RegisterInventoryScreen> createState() => _RegisterInventoryState();
}

class _RegisterInventoryState extends State<RegisterInventoryScreen> {
  final type = TextEditingController(),
      brand = TextEditingController(),
      model = TextEditingController(),
      serial = TextEditingController(),
      weight = TextEditingController(),
      source = TextEditingController(),
      location = TextEditingController();
  ItemCondition condition = ItemCondition.working;
  final images = <XFile>[];
  bool busy = false;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Register collected item')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final pair in [
          (type, 'Device type'),
          (brand, 'Brand'),
          (model, 'Model'),
          (serial, 'Serial number'),
          (weight, 'Weight (kg)'),
          (source, 'Source'),
          (location, 'Current location'),
        ]) ...[
          TextField(
            controller: pair.$1,
            decoration: InputDecoration(labelText: pair.$2),
          ),
          const SizedBox(height: 12),
        ],
        DropdownButtonFormField(
          initialValue: condition,
          items: ItemCondition.values
              .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
              .toList(),
          onChanged: (x) => setState(() => condition = x!),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: images.length >= 5
              ? null
              : () async {
                  final picked = await ImagePicker().pickMultiImage(
                    imageQuality: 75,
                  );
                  setState(() => images.addAll(picked.take(5 - images.length)));
                },
          icon: const Icon(Icons.add_a_photo),
          label: Text('Item images (${images.length}/5)'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  final kg = double.tryParse(weight.text);
                  if (type.text.trim().isEmpty ||
                      source.text.trim().isEmpty ||
                      location.text.trim().isEmpty ||
                      kg == null ||
                      kg < 0) {
                    ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(
                        content: Text('Complete all required item fields.'),
                      ),
                    );
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    final bytes = await Future.wait(
                      images.map((x) => x.readAsBytes()),
                    );
                    await widget.repository.register(
                      deviceType: type.text,
                      brand: brand.text,
                      model: model.text,
                      serialNumber: serial.text,
                      condition: condition,
                      weight: kg,
                      source: source.text,
                      location: location.text,
                      images: bytes,
                    );
                    if (c.mounted) Navigator.pop(c);
                  } catch (e) {
                    if (c.mounted) {
                      ScaffoldMessenger.of(c).showSnackBar(
                        SnackBar(content: Text('Registration failed: $e')),
                      );
                    }
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Registering…' : 'Register item'),
        ),
      ],
    ),
  );
}

class InventoryDetailScreen extends StatelessWidget {
  const InventoryDetailScreen({
    super.key,
    required this.repository,
    required this.item,
    required this.canApprove,
  });
  final InventoryRepository repository;
  final InventoryItem item;
  final bool canApprove;
  @override
  Widget build(BuildContext c) => StreamBuilder<InventoryItem>(
    stream: repository.watchItem(item.id),
    initialData: item,
    builder: (c, s) {
      final x = s.data!;
      return Scaffold(
        appBar: AppBar(title: Text(x.itemCode)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: QrImageView(data: x.qrPayload, size: 180)),
            Center(child: SelectableText(x.itemCode)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${x.brand} ${x.model}',
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    Text('Device: ${x.deviceType}'),
                    Text('Serial: ${x.serialNumber}'),
                    Text('Condition: ${x.condition.name}'),
                    Text('Weight: ${x.weight} kg'),
                    Text('Source: ${x.source}'),
                    Text('Location: ${x.location}'),
                    Text('Status: ${x.status.name}'),
                    Text('Batch: ${x.batchId ?? 'Unassigned'}'),
                  ],
                ),
              ),
            ),
            if (x.imageUrls.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: x.imageUrls
                      .map(
                        (url) => Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.network(
                            url,
                            width: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            FilledButton.icon(
              onPressed: () => _update(c, x),
              icon: const Icon(Icons.update),
              label: const Text('Update status or location'),
            ),
            OutlinedButton.icon(
              onPressed: () => _editDetails(c, x),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit item details'),
            ),
            OutlinedButton.icon(
              onPressed: () => _replaceImages(c, x),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Replace item images'),
            ),
            OutlinedButton.icon(
              onPressed: () => x.batchId == null
                  ? _assignBatch(c, x)
                  : repository.unassignBatch(x),
              icon: const Icon(Icons.inventory_2),
              label: Text(
                x.batchId == null ? 'Assign to batch' : 'Remove from batch',
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) => AssessmentScreen(
                    item: x,
                    repository: AssessmentRepository(),
                    canApprove: canApprove,
                  ),
                ),
              ),
              icon: const Icon(Icons.biotech_outlined),
              label: const Text('Classify and assess'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) => TraceabilityScreen(
                    item: x,
                    repository: TraceabilityRepository(),
                  ),
                ),
              ),
              icon: const Icon(Icons.route),
              label: const Text('Traceability and custody'),
            ),
            Text('Item history', style: Theme.of(c).textTheme.titleLarge),
            StreamBuilder<List<InventoryEvent>>(
              stream: repository.watchHistory(x.id),
              builder: (c, h) => Column(
                children: (h.data ?? [])
                    .map(
                      (e) => ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(e.action),
                        subtitle: Text('${e.details}\n${e.at ?? ''}'),
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
  Future<void> _update(BuildContext c, InventoryItem x) async {
    var status = x.status;
    final loc = TextEditingController(text: x.location);
    final ok = await showDialog<bool>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Update processing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField(
                initialValue: status,
                items: ProcessingStatus.values
                    .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
                    .toList(),
                onChanged: (v) => set(() => status = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: loc,
                decoration: const InputDecoration(
                  labelText: 'Current location',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await repository.updateState(x, status: status, location: loc.text);
    }
    loc.dispose();
  }

  Future<void> _editDetails(BuildContext context, InventoryItem item) async {
    final type = TextEditingController(text: item.deviceType);
    final brand = TextEditingController(text: item.brand);
    final model = TextEditingController(text: item.model);
    final serial = TextEditingController(text: item.serialNumber);
    final weight = TextEditingController(text: item.weight.toString());
    final source = TextEditingController(text: item.source);
    var condition = item.condition;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit inventory item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: type,
                  decoration: const InputDecoration(labelText: 'Device type'),
                ),
                TextField(
                  controller: brand,
                  decoration: const InputDecoration(labelText: 'Brand'),
                ),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                TextField(
                  controller: serial,
                  decoration: const InputDecoration(labelText: 'Serial number'),
                ),
                TextField(
                  controller: weight,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weight (kg)'),
                ),
                TextField(
                  controller: source,
                  decoration: const InputDecoration(labelText: 'Source'),
                ),
                DropdownButtonFormField<ItemCondition>(
                  initialValue: condition,
                  items: ItemCondition.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => condition = value!),
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
    final kg = double.tryParse(weight.text);
    if (confirmed == true &&
        type.text.trim().isNotEmpty &&
        source.text.trim().isNotEmpty &&
        kg != null &&
        kg >= 0) {
      await repository.updateDetails(
        item,
        deviceType: type.text,
        brand: brand.text,
        model: model.text,
        serialNumber: serial.text,
        condition: condition,
        weight: kg,
        source: source.text,
      );
    }
    for (final controller in [type, brand, model, serial, weight, source]) {
      controller.dispose();
    }
  }

  Future<void> _replaceImages(BuildContext context, InventoryItem item) async {
    final selected = await ImagePicker().pickMultiImage(imageQuality: 75);
    if (selected.isEmpty) return;
    if (selected.length > 5) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select no more than five images.')),
        );
      }
      return;
    }
    await repository.replaceImages(
      item.id,
      await Future.wait(selected.map((image) => image.readAsBytes())),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item images updated.')));
    }
  }

  Future<void> _assignBatch(BuildContext c, InventoryItem x) async {
    final batches = await repository.watchBatches().first;
    if (!c.mounted) return;
    String? selected;
    final result = await showDialog<String>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Assign batch'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            items: batches
                .map(
                  (b) => DropdownMenuItem(
                    value: b.id,
                    child: Text('${b.code} — ${b.name}'),
                  ),
                )
                .toList(),
            onChanged: (v) => set(() => selected = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, selected),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await repository.assignBatch(x, result);
  }
}

class InventoryBatchesScreen extends StatelessWidget {
  const InventoryBatchesScreen({super.key, required this.repository});
  final InventoryRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventory batches')),
    body: StreamBuilder<List<InventoryBatch>>(
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
        if (batches.isEmpty) {
          return const Center(child: Text('No inventory batches.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: batches.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final batch = batches[index];
            return Card(
              child: ListTile(
                leading: Icon(
                  batch.closed ? Icons.inventory_2 : Icons.inventory_2_outlined,
                ),
                title: Text('${batch.code} — ${batch.name}'),
                subtitle: Text(
                  '${batch.itemCount} items • ${batch.totalWeight.toStringAsFixed(1)} kg\n${batch.location} • ${batch.status}',
                ),
                isThreeLine: true,
                trailing: Chip(label: Text(batch.closed ? 'Closed' : 'Open')),
                onTap: () => _edit(context, batch),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> _edit(BuildContext context, InventoryBatch batch) async {
    final name = TextEditingController(text: batch.name);
    final location = TextEditingController(text: batch.location);
    var status =
        ProcessingStatus.values
            .where((value) => value.name == batch.status)
            .firstOrNull ??
        ProcessingStatus.registered;
    var closed = batch.closed;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(batch.code),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Batch name'),
              ),
              TextField(
                controller: location,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              DropdownButtonFormField<ProcessingStatus>(
                initialValue: status,
                items: ProcessingStatus.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => status = value!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Close batch'),
                value: closed,
                onChanged: (value) => setState(() => closed = value),
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
    );
    if (confirmed == true &&
        name.text.trim().isNotEmpty &&
        location.text.trim().isNotEmpty) {
      await repository.updateBatch(
        batch,
        name: name.text,
        location: location.text,
        status: status,
        closed: closed,
      );
    }
    name.dispose();
    location.dispose();
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Card(
    child: SizedBox(
      width: 132,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
