import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../pickups/domain/pickup.dart';
import '../data/collection_centre_repository.dart';
import '../domain/collection_centre.dart';

class CollectionCentreDashboardScreen extends StatelessWidget {
  const CollectionCentreDashboardScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.canRegister,
  });

  final CollectionCentreRepository repository;
  final String currentUserId;
  final bool canRegister;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Collection centres')),
    body: StreamBuilder<List<CollectionCentre>>(
      stream: repository.watchCentres(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Unable to load centres: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final centres = snapshot.data!;
        final totalCapacity = centres.fold<double>(
          0,
          (sum, centre) => sum + centre.capacityKg,
        );
        final totalStock = centres.fold<double>(
          0,
          (sum, centre) => sum + centre.currentStockKg,
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
                      'Network performance',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        Text('Centres: ${centres.length}'),
                        Text('Stored: ${totalStock.toStringAsFixed(1)} kg'),
                        Text(
                          'Capacity: ${totalCapacity.toStringAsFixed(1)} kg',
                        ),
                        Text(
                          'Alerts: ${centres.where((item) => item.hasCapacityAlert).length}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: totalCapacity == 0
                          ? 0
                          : (totalStock / totalCapacity).clamp(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            if (centres.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No collection centres registered.')),
              ),
            for (final centre in centres)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      centre.hasCapacityAlert
                          ? Icons.warning_amber
                          : Icons.warehouse_outlined,
                    ),
                  ),
                  title: Text(centre.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(centre.address),
                      Text(
                        '${centre.currentStockKg.toStringAsFixed(1)} / ${centre.capacityKg.toStringAsFixed(1)} kg • ${centre.occupancyPercent.toStringAsFixed(0)}%',
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: (centre.occupancyPercent / 100).clamp(0, 1),
                        color: centre.hasCapacityAlert
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CollectionCentreDetailScreen(
                        repository: repository,
                        initial: centre,
                        currentUserId: currentUserId,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
    floatingActionButton: canRegister
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RegisterCollectionCentreScreen(
                  repository: repository,
                ),
              ),
            ),
            icon: const Icon(Icons.add_business),
            label: const Text('Register centre'),
          )
        : null,
  );
}

class RegisterCollectionCentreScreen extends StatefulWidget {
  const RegisterCollectionCentreScreen({super.key, required this.repository});
  final CollectionCentreRepository repository;

  @override
  State<RegisterCollectionCentreScreen> createState() =>
      _RegisterCollectionCentreState();
}

class _RegisterCollectionCentreState
    extends State<RegisterCollectionCentreScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final address = TextEditingController();
  final contactName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final weekdayHours = TextEditingController(text: '08:00–17:00');
  final weekendHours = TextEditingController(text: 'Closed');
  final capacity = TextEditingController();
  final alertPercent = TextEditingController(text: '80');
  final categories = <WasteCategory>{};
  double? latitude, longitude;
  bool busy = false;

  @override
  void dispose() {
    for (final controller in [
      name,
      address,
      contactName,
      email,
      phone,
      weekdayHours,
      weekendHours,
      capacity,
      alertPercent,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _attachLocation() async {
    var permission = await Permission.locationWhenInUse.status;
    if (!permission.isGranted) {
      permission = await Permission.locationWhenInUse.request();
    }
    if (!permission.isGranted || !await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enable foreground location to attach GPS coordinates.'),
          ),
        );
      }
      return;
    }
    final position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
      });
    }
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one waste category.')),
      );
      return;
    }
    setState(() => busy = true);
    try {
      await widget.repository.register(
        name: name.text,
        address: address.text,
        contactName: contactName.text,
        contactEmail: email.text,
        contactPhone: phone.text,
        latitude: latitude,
        longitude: longitude,
        operatingHours: {
          'Monday–Friday': weekdayHours.text.trim(),
          'Saturday–Sunday': weekendHours.text.trim(),
        },
        supportedCategories: categories.toList(),
        capacityKg: double.parse(capacity.text),
        capacityAlertPercent: double.parse(alertPercent.text),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Register collection centre')),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _requiredField(name, 'Centre name'),
          _requiredField(address, 'Physical address', lines: 2),
          OutlinedButton.icon(
            onPressed: _attachLocation,
            icon: const Icon(Icons.my_location),
            label: Text(
              latitude == null
                  ? 'Attach GPS coordinates'
                  : '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}',
            ),
          ),
          const SizedBox(height: 12),
          _requiredField(contactName, 'Contact person'),
          _requiredField(
            email,
            'Contact email',
            keyboardType: TextInputType.emailAddress,
          ),
          _requiredField(
            phone,
            'Contact phone',
            keyboardType: TextInputType.phone,
          ),
          _requiredField(weekdayHours, 'Monday–Friday hours'),
          _requiredField(weekendHours, 'Weekend hours'),
          Text('Supported waste categories', style: Theme.of(context).textTheme.titleMedium),
          Wrap(
            spacing: 8,
            children: WasteCategory.values
                .map(
                  (category) => FilterChip(
                    label: Text(category.label),
                    selected: categories.contains(category),
                    onSelected: (selected) => setState(
                      () => selected
                          ? categories.add(category)
                          : categories.remove(category),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          _requiredField(
            capacity,
            'Total storage capacity (kg)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            positiveNumber: true,
          ),
          _requiredField(
            alertPercent,
            'Capacity alert threshold (%)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            percent: true,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : _save,
            child: Text(busy ? 'Saving…' : 'Register centre'),
          ),
        ],
      ),
    ),
  );
}

class CollectionCentreDetailScreen extends StatelessWidget {
  const CollectionCentreDetailScreen({
    super.key,
    required this.repository,
    required this.initial,
    required this.currentUserId,
  });
  final CollectionCentreRepository repository;
  final CollectionCentre initial;
  final String currentUserId;

  @override
  Widget build(BuildContext context) => StreamBuilder<CollectionCentre>(
    stream: repository.watchCentre(initial.id),
    initialData: initial,
    builder: (context, snapshot) {
      final centre = snapshot.data!;
      return DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: Text(centre.name),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Receiving'),
                Tab(text: 'Storage'),
                Tab(text: 'Staff'),
                Tab(text: 'Safety'),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Centre actions',
                onSelected: (action) => _handleAction(context, centre, action),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'checkIn', child: Text('Check in items')),
                  PopupMenuItem(value: 'checkOut', child: Text('Check out stock')),
                  PopupMenuItem(value: 'section', child: Text('Add storage section')),
                  PopupMenuItem(value: 'staff', child: Text('Assign staff')),
                  PopupMenuItem(value: 'inspection', child: Text('Safety inspection')),
                ],
              ),
            ],
          ),
          body: TabBarView(
            children: [
              _OverviewTab(repository: repository, centre: centre),
              _ReceivingTab(
                repository: repository,
                centre: centre,
              ),
              _StorageTab(repository: repository, centre: centre),
              _StaffTab(repository: repository, centre: centre),
              _SafetyTab(repository: repository, centre: centre),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showCheckIn(context, centre),
            icon: const Icon(Icons.move_to_inbox),
            label: const Text('Check in'),
          ),
        ),
      );
    },
  );

  void _handleAction(
    BuildContext context,
    CollectionCentre centre,
    String action,
  ) {
    switch (action) {
      case 'checkIn':
        _showCheckIn(context, centre);
      case 'checkOut':
        _showCheckOut(context, centre);
      case 'section':
        _showAddSection(context, centre);
      case 'staff':
        _showAssignStaff(context, centre);
      case 'inspection':
        _showInspection(context, centre);
    }
  }

  Future<void> _showCheckIn(
    BuildContext context,
    CollectionCentre centre,
  ) async {
    final sections = await repository.watchSections(centre.id).first;
    if (!context.mounted) return;
    if (sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a storage section before check-in.')),
      );
      return;
    }
    final reference = TextEditingController();
    final count = TextEditingController();
    final weight = TextEditingController();
    final notes = TextEditingController();
    var category = centre.supportedCategories.firstOrNull ?? WasteCategory.other;
    var section = sections.first;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Item check-in and weighing'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: reference, decoration: const InputDecoration(labelText: 'Receiving reference')),
                const SizedBox(height: 10),
                DropdownButtonFormField<WasteCategory>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Waste category'),
                  items: (centre.supportedCategories.isEmpty ? WasteCategory.values : centre.supportedCategories)
                      .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                      .toList(),
                  onChanged: (value) => setLocalState(() => category = value!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<StorageSection>(
                  initialValue: section,
                  decoration: const InputDecoration(labelText: 'Storage section'),
                  items: sections.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                  onChanged: (value) => setLocalState(() => section = value!),
                ),
                const SizedBox(height: 10),
                TextField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Item count')),
                const SizedBox(height: 10),
                TextField(controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Scale weight (kg)')),
                const SizedBox(height: 10),
                TextField(controller: notes, decoration: const InputDecoration(labelText: 'Condition / notes'), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Check in')),
          ],
        ),
      ),
    );
    if (submitted == true && context.mounted) {
      await _run(
        context,
        () => repository.checkIn(
          centre.id,
          reference: reference.text,
          category: category,
          itemCount: int.tryParse(count.text) ?? 0,
          weightKg: double.tryParse(weight.text) ?? 0,
          sectionId: section.id,
          staffId: currentUserId,
          notes: notes.text,
        ),
        'Items checked in. Verify the scale weight from Receiving.',
      );
    }
    reference.dispose();
    count.dispose();
    weight.dispose();
    notes.dispose();
  }

  Future<void> _showCheckOut(
    BuildContext context,
    CollectionCentre centre,
  ) async {
    final sections = await repository.watchSections(centre.id).first;
    if (!context.mounted || sections.isEmpty) return;
    var section = sections.first;
    final weight = TextEditingController();
    final destination = TextEditingController();
    final notes = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Stock check-out'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<StorageSection>(
                  initialValue: section,
                  decoration: const InputDecoration(labelText: 'Storage section'),
                  items: sections.map((item) => DropdownMenuItem(value: item, child: Text('${item.name} (${item.currentStockKg.toStringAsFixed(1)} kg)'))).toList(),
                  onChanged: (value) => setLocalState(() => section = value!),
                ),
                const SizedBox(height: 10),
                TextField(controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)')),
                const SizedBox(height: 10),
                TextField(controller: destination, decoration: const InputDecoration(labelText: 'Destination / recipient')),
                const SizedBox(height: 10),
                TextField(controller: notes, decoration: const InputDecoration(labelText: 'Movement notes'), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Check out')),
          ],
        ),
      ),
    );
    if (submitted == true && context.mounted) {
      await _run(
        context,
        () => repository.checkOut(
          centre.id,
          section: section,
          weightKg: double.tryParse(weight.text) ?? 0,
          destination: destination.text,
          staffId: currentUserId,
          notes: notes.text,
        ),
        'Stock checked out and movement recorded.',
      );
    }
    weight.dispose();
    destination.dispose();
    notes.dispose();
  }

  Future<void> _showAddSection(
    BuildContext context,
    CollectionCentre centre,
  ) async {
    final name = TextEditingController();
    final capacity = TextEditingController();
    var category = centre.supportedCategories.firstOrNull ?? WasteCategory.other;
    var restricted = false;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add storage section'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Section name')),
              const SizedBox(height: 10),
              DropdownButtonFormField<WasteCategory>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Waste category'),
                items: WasteCategory.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
                onChanged: (value) => setLocalState(() => category = value!),
              ),
              const SizedBox(height: 10),
              TextField(controller: capacity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Capacity (kg)')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: restricted,
                onChanged: (value) => setLocalState(() => restricted = value),
                title: const Text('Restricted access'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (submitted == true && context.mounted) {
      await _run(
        context,
        () => repository.addSection(
          centre.id,
          name: name.text,
          category: category,
          capacityKg: double.tryParse(capacity.text) ?? 0,
          restricted: restricted,
        ),
        'Storage section added.',
      );
    }
    name.dispose();
    capacity.dispose();
  }

  Future<void> _showAssignStaff(
    BuildContext context,
    CollectionCentre centre,
  ) async {
    final userId = TextEditingController();
    final role = TextEditingController(text: 'operator');
    final submitted = await _simpleFormDialog(
      context,
      title: 'Assign centre staff',
      actionLabel: 'Assign',
      fields: [
        TextField(controller: userId, decoration: const InputDecoration(labelText: 'User ID')),
        const SizedBox(height: 10),
        TextField(controller: role, decoration: const InputDecoration(labelText: 'Centre role')),
      ],
    );
    if (submitted && context.mounted) {
      await _run(
        context,
        () => repository.assignStaff(centre.id, userId: userId.text, role: role.text),
        'Staff member assigned.',
      );
    }
    userId.dispose();
    role.dispose();
  }

  Future<void> _showInspection(
    BuildContext context,
    CollectionCentre centre,
  ) async {
    final checks = <String, bool>{
      'Fire equipment available': false,
      'Emergency exits clear': false,
      'PPE available': false,
      'Hazardous items isolated': false,
      'Storage aisles clear': false,
    };
    final notes = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Safety inspection'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in checks.entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: entry.value,
                    onChanged: (value) => setLocalState(() => checks[entry.key] = value ?? false),
                    title: Text(entry.key),
                  ),
                TextField(controller: notes, decoration: const InputDecoration(labelText: 'Findings and corrective actions'), maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
          ],
        ),
      ),
    ) ?? false;
    if (submitted && context.mounted) {
      await _run(
        context,
        () => repository.recordInspection(
          centre.id,
          inspectorId: currentUserId,
          checks: checks,
          notes: notes.text,
        ),
        'Safety inspection recorded.',
      );
    }
    notes.dispose();
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.repository, required this.centre});
  final CollectionCentreRepository repository;
  final CollectionCentre centre;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (centre.hasCapacityAlert)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.warning_amber),
            title: const Text('Capacity alert'),
            subtitle: Text('Storage is ${centre.occupancyPercent.toStringAsFixed(0)}% full. Plan a stock movement.'),
          ),
        ),
      _CapacityCard(centre: centre),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Location and contact', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(centre.address),
              Text('${centre.contactName} • ${centre.contactPhone}'),
              Text(centre.contactEmail),
              if (centre.latitude != null) Text('${centre.latitude!.toStringAsFixed(5)}, ${centre.longitude!.toStringAsFixed(5)}'),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Operating hours', style: Theme.of(context).textTheme.titleMedium),
              for (final entry in centre.operatingHours.entries) Text('${entry.key}: ${entry.value}'),
              const SizedBox(height: 8),
              Text('Accepted: ${centre.supportedCategories.map((item) => item.label).join(', ')}'),
            ],
          ),
        ),
      ),
      StreamBuilder<List<ReceivingRecord>>(
        stream: repository.watchReceivingRecords(centre.id),
        builder: (context, snapshot) {
          final records = snapshot.data ?? const <ReceivingRecord>[];
          final now = DateTime.now();
          final today = records.where((record) {
            final at = record.receivedAt;
            return at != null && at.year == now.year && at.month == now.month && at.day == now.day;
          }).toList();
          final weight = today.fold<double>(0, (sum, record) => sum + record.stockWeightKg);
          final items = today.fold<int>(0, (sum, record) => sum + record.itemCount);
          final verificationRate = records.isEmpty ? 0 : records.where((record) => record.verified).length / records.length * 100;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Centre performance', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      Text('Today: ${today.length} receipts'),
                      Text('Items: $items'),
                      Text('Received: ${weight.toStringAsFixed(1)} kg'),
                      Text('Weights verified: ${verificationRate.toStringAsFixed(0)}%'),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      StreamBuilder<List<StockMovement>>(
        stream: repository.watchMovements(centre.id),
        builder: (context, snapshot) => Card(
          child: ExpansionTile(
            title: const Text('Recent stock movements'),
            children: (snapshot.data ?? const <StockMovement>[])
                .take(10)
                .map((movement) => ListTile(
                      leading: Icon(movement.type == StockMovementType.checkOut ? Icons.outbox : Icons.move_to_inbox),
                      title: Text('${movement.type.name} • ${movement.weightKg.toStringAsFixed(1)} kg'),
                      subtitle: Text('${movement.destination}\n${movement.notes}'),
                      isThreeLine: true,
                    ))
                .toList(),
          ),
        ),
      ),
    ],
  );
}

class _ReceivingTab extends StatelessWidget {
  const _ReceivingTab({required this.repository, required this.centre});
  final CollectionCentreRepository repository;
  final CollectionCentre centre;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ReceivingRecord>>(
    stream: repository.watchReceivingRecords(centre.id),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty) return const Center(child: Text('No receiving records.'));
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: snapshot.data!.length,
        itemBuilder: (context, index) {
          final record = snapshot.data![index];
          return Card(
            child: ListTile(
              leading: Icon(record.verified ? Icons.verified : Icons.scale_outlined),
              title: Text('${record.reference} • ${record.category.label}'),
              subtitle: Text('${record.itemCount} items • ${record.stockWeightKg.toStringAsFixed(1)} kg\n${record.verified ? 'Weight verified' : 'Awaiting weight verification'}'),
              isThreeLine: true,
              trailing: record.verified
                  ? null
                  : TextButton(
                      onPressed: () => _verify(context, record),
                      child: const Text('Verify'),
                    ),
            ),
          );
        },
      );
    },
  );

  Future<void> _verify(BuildContext context, ReceivingRecord record) async {
    final controller = TextEditingController(text: record.recordedWeightKg.toString());
    final submitted = await _simpleFormDialog(
      context,
      title: 'Verify scale weight',
      actionLabel: 'Verify',
      fields: [
        TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Verified weight (kg)'),
        ),
      ],
    );
    if (submitted && context.mounted) {
      await _run(
        context,
        () => repository.verifyWeight(centre.id, record, double.tryParse(controller.text) ?? 0),
        'Weight verified and stock adjusted.',
      );
    }
    controller.dispose();
  }
}

class _StorageTab extends StatelessWidget {
  const _StorageTab({required this.repository, required this.centre});
  final CollectionCentreRepository repository;
  final CollectionCentre centre;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<StorageSection>>(
    stream: repository.watchSections(centre.id),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty) return const Center(child: Text('No storage sections configured.'));
      return ListView(
        padding: const EdgeInsets.all(12),
        children: snapshot.data!.map((section) => Card(
          child: ListTile(
            leading: Icon(section.restricted ? Icons.lock_outline : Icons.inventory_2_outlined),
            title: Text(section.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${section.category.label} • ${section.currentStockKg.toStringAsFixed(1)} / ${section.capacityKg.toStringAsFixed(1)} kg'),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: (section.occupancyPercent / 100).clamp(0, 1)),
              ],
            ),
            isThreeLine: true,
          ),
        )).toList(),
      );
    },
  );
}

class _StaffTab extends StatelessWidget {
  const _StaffTab({required this.repository, required this.centre});
  final CollectionCentreRepository repository;
  final CollectionCentre centre;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<CentreStaffAssignment>>(
    stream: repository.watchStaff(centre.id),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty) return const Center(child: Text('No staff assigned.'));
      return ListView(
        padding: const EdgeInsets.all(12),
        children: snapshot.data!.map((assignment) => Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(assignment.userId),
            subtitle: Text(assignment.role),
            trailing: Chip(label: Text(assignment.active ? 'Active' : 'Inactive')),
          ),
        )).toList(),
      );
    },
  );
}

class _SafetyTab extends StatelessWidget {
  const _SafetyTab({required this.repository, required this.centre});
  final CollectionCentreRepository repository;
  final CollectionCentre centre;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<SafetyInspection>>(
    stream: repository.watchInspections(centre.id),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty) return const Center(child: Text('No safety inspections recorded.'));
      return ListView(
        padding: const EdgeInsets.all(12),
        children: snapshot.data!.map((inspection) => Card(
          child: ListTile(
            leading: Icon(inspection.status == SafetyInspectionStatus.passed ? Icons.health_and_safety : Icons.warning_amber),
            title: Text('${inspection.score}% • ${inspection.status.name}'),
            subtitle: Text('${inspection.inspectorId}\n${inspection.notes}'),
            isThreeLine: true,
          ),
        )).toList(),
      );
    },
  );
}

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({required this.centre});
  final CollectionCentre centre;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Storage capacity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (centre.occupancyPercent / 100).clamp(0, 1),
            color: centre.hasCapacityAlert ? Theme.of(context).colorScheme.error : null,
          ),
          const SizedBox(height: 8),
          Text('${centre.currentStockKg.toStringAsFixed(1)} kg stored • ${centre.availableCapacityKg.toStringAsFixed(1)} kg available'),
          Text('${centre.occupancyPercent.toStringAsFixed(0)}% occupied • alert at ${centre.capacityAlertPercent.toStringAsFixed(0)}%'),
        ],
      ),
    ),
  );
}

Widget _requiredField(
  TextEditingController controller,
  String label, {
  int lines = 1,
  TextInputType? keyboardType,
  bool positiveNumber = false,
  bool percent = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextFormField(
    controller: controller,
    maxLines: lines,
    keyboardType: keyboardType,
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      if (value == null || value.trim().isEmpty) return 'Required';
      if (positiveNumber && (double.tryParse(value) ?? 0) <= 0) return 'Enter a positive number';
      if (percent) {
        final number = double.tryParse(value);
        if (number == null || number <= 0 || number > 100) return 'Enter a percentage from 1 to 100';
      }
      return null;
    },
  ),
);

Future<bool> _simpleFormDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required List<Widget> fields,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: fields),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(actionLabel)),
        ],
      ),
    ) ?? false;

Future<void> _run(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

void _showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Operation failed: $error')));
