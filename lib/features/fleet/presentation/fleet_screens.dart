import 'package:flutter/material.dart';
import '../data/fleet_repository.dart';
import '../domain/vehicle.dart';

class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key, required this.repository});
  final FleetRepository repository;
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
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: s.data!.length,
          itemBuilder: (c, i) {
            final v = s.data![i];
            return Card(
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
                    builder: (_) =>
                        VehicleDetailScreen(repository: repository, vehicle: v),
                  ),
                ),
              ),
            );
          },
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
  });
  final FleetRepository repository;
  final Vehicle vehicle;
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
            FilledButton.tonal(
              onPressed: () => _event(c, 'maintenance'),
              child: const Text('Maintenance'),
            ),
            FilledButton.tonal(
              onPressed: () => _event(c, 'breakdown'),
              child: const Text('Breakdown'),
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
