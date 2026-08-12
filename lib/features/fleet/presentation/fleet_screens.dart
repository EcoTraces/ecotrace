import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/fleet_repository.dart';
import '../domain/vehicle.dart';

class FleetScreen extends StatelessWidget {
  const FleetScreen({
    super.key,
    required this.repository,
    this.isFleetManager = false,
  });
  final FleetRepository repository;
  // Backend gates driver assignment, inspections, and maintenance scheduling
  // to administrator/superAdministrator; other operational roles that reach
  // this screen (collector, driver, recycler, etc.) can still view vehicles
  // and log fuel/mileage/location/breakdowns, which are open to `operators`.
  final bool isFleetManager;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Fleet management')),
    body: StreamBuilder<List<Vehicle>>(
      stream: repository.watchVehicles(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) {
          return const Center(child: Text('No vehicles registered.'));
        }
        final vehicles = s.data!;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            FutureBuilder<List<FleetAlert>>(
              future: repository.getAlerts(),
              builder: (context, snapshot) {
                final alerts = snapshot.data ?? const <FleetAlert>[];
                if (alerts.isEmpty) return const SizedBox.shrink();
                return Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ExpansionTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text('${alerts.length} fleet alert(s)'),
                    children: alerts.map((alert) => ListTile(
                      title: Text('${alert.registrationNumber}: ${alert.title}'),
                      subtitle: alert.dueAt == null ? null : Text('${alert.dueAt}'),
                    )).toList(),
                  ),
                );
              },
            ),
            FutureBuilder<List<VehicleUtilization>>(
              future: repository.getUtilization(
                from: DateTime.now().subtract(const Duration(days: 30)),
                to: DateTime.now().add(const Duration(days: 1)),
              ),
              builder: (context, snapshot) {
                final rows = snapshot.data ?? const <VehicleUtilization>[];
                if (rows.isEmpty) return const SizedBox.shrink();
                return Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.analytics_outlined),
                    title: const Text('30-day vehicle utilization'),
                    children: rows.map((row) => ListTile(
                      title: Text(row.registrationNumber),
                      subtitle: Text('${row.trips} trips • ${row.pickupCount} pickups • ${row.distanceKm.toStringAsFixed(1)} km'),
                      trailing: Text('${row.utilizationScore.toStringAsFixed(0)}%'),
                    )).toList(),
                  ),
                );
              },
            ),
            ...vehicles.map((v) => Card(
              child: ListTile(
                leading: Icon(
                  v.expiresWithin(const Duration(days: 30))
                      ? Icons.warning_amber
                      : Icons.local_shipping,
                ),
                title: Text(v.registrationNumber),
                subtitle: Text(
                  '${v.type.name} • ${v.availability.name} • ${v.capacityKg} kg\nDriver: ${v.driverId.isEmpty ? 'Unassigned' : v.driverId} • ${v.mileageKm} km',
                ),
                isThreeLine: true,
                onTap: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => VehicleDetailScreen(
                      repository: repository,
                      vehicle: v,
                      isFleetManager: isFleetManager,
                    ),
                  ),
                ),
              ),
            )),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        c,
        MaterialPageRoute(
          builder: (_) => RegisterVehicleScreen(repository: repository),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Register vehicle'),
    ),
  );
}

class RegisterVehicleScreen extends StatefulWidget {
  const RegisterVehicleScreen({super.key, required this.repository});
  final FleetRepository repository;
  @override
  State<RegisterVehicleScreen> createState() => _RegisterVehicleState();
}

class _RegisterVehicleState extends State<RegisterVehicleScreen> {
  final registration = TextEditingController(),
      capacity = TextEditingController(),
      driver = TextEditingController();
  VehicleType type = VehicleType.van;
  DateTime insurance = DateTime.now().add(const Duration(days: 365)),
      licence = DateTime.now().add(const Duration(days: 365));
  bool busy = false;

  @override
  void dispose() {
    registration.dispose();
    capacity.dispose();
    driver.dispose();
    super.dispose();
  }

  Future<DateTime> _date(BuildContext c, DateTime value) async =>
      (await showDatePicker(
        context: c,
        initialDate: value,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
      )) ??
      value;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Register vehicle')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: registration,
          decoration: const InputDecoration(labelText: 'Registration number'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Vehicle type'),
          items: VehicleType.values
              .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
              .toList(),
          onChanged: (x) => setState(() => type = x!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: capacity,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Capacity (kg)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: driver,
          decoration: const InputDecoration(
            labelText: 'Assigned driver user ID',
          ),
        ),
        ListTile(
          title: const Text('Insurance expiry'),
          subtitle: Text('$insurance'),
          onTap: () async {
            insurance = await _date(c, insurance);
            setState(() {});
          },
        ),
        ListTile(
          title: const Text('Licence expiry'),
          subtitle: Text('$licence'),
          onTap: () async {
            licence = await _date(c, licence);
            setState(() {});
          },
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  final kg = double.tryParse(capacity.text);
                  if (registration.text.trim().isEmpty ||
                      kg == null ||
                      kg <= 0) {
                    ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Enter a registration number and valid capacity.',
                        ),
                      ),
                    );
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    await widget.repository.register(
                      registrationNumber: registration.text,
                      type: type,
                      capacityKg: kg,
                      driverId: driver.text,
                      insuranceExpiry: insurance,
                      licenceExpiry: licence,
                    );
                    if (!c.mounted) return;
                    ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(
                        content: Text('Vehicle registered successfully.'),
                      ),
                    );
                    Navigator.pop(c);
                  } catch (error) {
                    if (!c.mounted) return;
                    ScaffoldMessenger.of(c).showSnackBar(
                      SnackBar(content: Text('Unable to register vehicle: $error')),
                    );
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Register vehicle'),
        ),
      ],
    ),
  );
}

class VehicleDetailScreen extends StatelessWidget {
  const VehicleDetailScreen({
    super.key,
    required this.repository,
    required this.vehicle,
    this.isFleetManager = false,
  });
  final FleetRepository repository;
  final Vehicle vehicle;
  final bool isFleetManager;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(vehicle.registrationNumber)),
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
                  '${vehicle.type.name} • ${vehicle.availability.name}',
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                Text('Capacity: ${vehicle.capacityKg} kg'),
                Text(
                  'Driver: ${vehicle.driverId.isEmpty ? 'Unassigned' : vehicle.driverId}',
                ),
                Text('Mileage: ${vehicle.mileageKm} km'),
                Text('Fuel: ${vehicle.fuelLitres} L'),
                Text('Insurance: ${vehicle.insuranceExpiry}'),
                Text('Licence: ${vehicle.licenceExpiry}'),
                Text(
                  'Location: ${vehicle.latitude ?? '—'}, ${vehicle.longitude ?? '—'}',
                ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            if (isFleetManager)
              FilledButton.tonal(
                onPressed: () => _assignDriver(c),
                child: const Text('Assign driver'),
              ),
            if (isFleetManager)
              FilledButton.tonal(
                onPressed: () => _event(c, 'inspection'),
                child: const Text('Inspection'),
              ),
            FilledButton.tonal(
              onPressed: () => _event(c, 'fuel'),
              child: const Text('Fuel'),
            ),
            FilledButton.tonal(
              onPressed: () => _event(c, 'mileage'),
              child: const Text('Mileage'),
            ),
            FilledButton.tonal(
              onPressed: () => _event(c, 'location'),
              child: const Text('Location'),
            ),
            if (isFleetManager)
              FilledButton.tonal(
                onPressed: () => _event(c, 'maintenance'),
                child: const Text('Maintenance'),
              ),
            FilledButton.tonal(
              onPressed: () => _event(c, 'breakdown'),
              child: const Text('Breakdown'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) => FleetWorkScreen(
                    repository: repository,
                    vehicle: vehicle,
                    maintenance: true,
                  ),
                ),
              ),
              child: const Text('Maintenance records'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) => FleetWorkScreen(
                    repository: repository,
                    vehicle: vehicle,
                    maintenance: false,
                  ),
                ),
              ),
              child: const Text('Breakdown records'),
            ),
          ],
        ),
        const Divider(),
        Text('Vehicle history', style: Theme.of(c).textTheme.titleLarge),
        StreamBuilder<List<FleetEvent>>(
          stream: repository.watchEvents(vehicle.id),
          builder: (c, s) => Column(
            children: (s.data ?? [])
                .map(
                  (e) => ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(e.type),
                    subtitle: Text('${e.details}\n${e.at ?? ''}'),
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(),
        Text(
          'Trip history and utilization',
          style: Theme.of(c).textTheme.titleLarge,
        ),
        StreamBuilder<List<FleetTrip>>(
          stream: repository.watchTrips(vehicle.id),
          builder: (c, snapshot) {
            final trips = snapshot.data ?? [];
            final pickups = trips.fold<int>(
              0,
              (total, trip) => total + trip.pickupCount,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${trips.length} completed trips • $pickups pickups served',
                ),
                ...trips.map(
                  (trip) => ListTile(
                    leading: const Icon(Icons.route),
                    title: Text('Schedule ${trip.scheduleId}'),
                    subtitle: Text(
                      '${trip.pickupCount} pickups • ${trip.completedAt ?? ''}',
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
  Future<void> _assignDriver(BuildContext context) async {
    final controller = TextEditingController(text: vehicle.driverId);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assign driver'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Driver user ID',
            helperText: 'Leave blank to unassign the current driver.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await repository.assignDriver(vehicle.id, controller.text);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Driver assignment updated.')),
          );
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to assign driver: $error')),
          );
        }
      }
    }
    controller.dispose();
  }
  Future<void> _event(BuildContext c, String type) async {
    final details = TextEditingController(),
        value1 = TextEditingController(),
        value2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text('Record $type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: details,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            if (['fuel', 'mileage', 'location'].contains(type))
              TextField(
                controller: value1,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: type == 'location'
                      ? 'Latitude'
                      : type == 'fuel'
                      ? 'Fuel litres'
                      : 'Mileage km',
                ),
              ),
            if (type == 'location')
              TextField(
                controller: value2,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Longitude'),
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
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repository.recordEvent(
        vehicle,
        type: type,
        details: details.text,
        availability: type == 'breakdown'
            ? VehicleAvailability.breakdown
            : type == 'maintenance'
            ? VehicleAvailability.maintenance
            : null,
        fuel: type == 'fuel' ? double.tryParse(value1.text) : null,
        mileage: type == 'mileage' ? double.tryParse(value1.text) : null,
        latitude: type == 'location' ? double.tryParse(value1.text) : null,
        longitude: type == 'location' ? double.tryParse(value2.text) : null,
      );
    }
    details.dispose();
    value1.dispose();
    value2.dispose();
  }
}

class FleetWorkScreen extends StatefulWidget {
  const FleetWorkScreen({
    super.key,
    required this.repository,
    required this.vehicle,
    required this.maintenance,
  });

  final FleetRepository repository;
  final Vehicle vehicle;
  final bool maintenance;

  @override
  State<FleetWorkScreen> createState() => _FleetWorkScreenState();
}

class _FleetWorkScreenState extends State<FleetWorkScreen> {
  late Future<List<FleetWorkRecord>> records = _load();

  Future<List<FleetWorkRecord>> _load() => widget.maintenance
      ? widget.repository.getMaintenance(widget.vehicle.id)
      : widget.repository.getBreakdowns(widget.vehicle.id);

  void _reload() => setState(() => records = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.maintenance ? 'Maintenance records' : 'Breakdowns'),
    ),
    body: FutureBuilder<List<FleetWorkRecord>>(
      future: records,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Unable to load records: ${snapshot.error}'));
        }
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) return const Center(child: Text('No records found.'));
        return ListView(
          padding: const EdgeInsets.all(12),
          children: rows
              .map(
                (record) => Card(
                  child: ListTile(
                    leading: Icon(
                      record.status == 'completed' || record.status == 'resolved'
                          ? Icons.check_circle_outline
                          : Icons.build_circle_outlined,
                    ),
                    title: Text('${record.type} • ${record.status}'),
                    subtitle: Text(
                      '${record.description}\n${record.scheduledAt ?? ''} • SLE ${record.costSLE.toStringAsFixed(2)}',
                    ),
                    isThreeLine: true,
                    trailing: record.status == 'completed' ||
                            record.status == 'resolved'
                        ? null
                        : TextButton(
                            onPressed: () => widget.maintenance
                                ? _completeMaintenance(record)
                                : _resolveBreakdown(record),
                            child: Text(widget.maintenance ? 'Complete' : 'Resolve'),
                          ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );

  Future<void> _completeMaintenance(FleetWorkRecord record) async {
    final work = TextEditingController();
    final cost = TextEditingController();
    DateTime nextDate = DateTime.now().add(const Duration(days: 90));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Complete maintenance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: work,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Work performed'),
              ),
              TextField(
                controller: cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Actual cost (SLE)'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Next maintenance'),
                subtitle: Text('$nextDate'),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: nextDate,
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (selected != null) setDialogState(() => nextDate = selected);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Select evidence'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        final amount = double.tryParse(cost.text);
        if (work.text.trim().length < 2 || amount == null || amount < 0) {
          throw StateError('Enter the work performed and a valid cost.');
        }
        final files = await ImagePicker().pickMultiImage(imageQuality: 75);
        await widget.repository.completeMaintenance(
          vehicleId: widget.vehicle.id,
          recordId: record.id,
          actualCostSLE: amount,
          workPerformed: work.text,
          nextMaintenanceAt: nextDate,
          evidence: await Future.wait(files.map((file) => file.readAsBytes())),
        );
        _reload();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to complete maintenance: $error')),
          );
        }
      }
    }
    work.dispose();
    cost.dispose();
  }

  Future<void> _resolveBreakdown(FleetWorkRecord record) async {
    final resolution = TextEditingController();
    final cost = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve breakdown'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: resolution,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Resolution'),
            ),
            TextField(
              controller: cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Repair cost (SLE)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        final amount = double.tryParse(cost.text);
        if (resolution.text.trim().length < 2 || amount == null || amount < 0) {
          throw StateError('Enter a resolution and valid repair cost.');
        }
        await widget.repository.resolveBreakdown(
          vehicleId: widget.vehicle.id,
          recordId: record.id,
          resolution: resolution.text,
          repairCostSLE: amount,
        );
        _reload();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to resolve breakdown: $error')),
          );
        }
      }
    }
    resolution.dispose();
    cost.dispose();
  }
}
