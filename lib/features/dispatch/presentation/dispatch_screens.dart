import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../fleet/domain/vehicle.dart';
import '../../pickups/domain/pickup.dart';
import '../../routing/data/route_repository.dart';
import '../data/dispatch_repository.dart';
import '../domain/collection_schedule.dart';

class DispatchDashboardScreen extends StatefulWidget {
  const DispatchDashboardScreen({
    super.key,
    required this.repository,
    this.routeRepository,
    this.canGenerateRoutes = false,
  });
  final DispatchRepository repository;
  final RouteRepository? routeRepository;
  final bool canGenerateRoutes;
  @override
  State<DispatchDashboardScreen> createState() => _DispatchDashboardState();
}

class _DispatchDashboardState extends State<DispatchDashboardScreen> {
  DateTime day = DateTime.now();
  final generatingRoutes = <String>{};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Collection dispatch'),
      actions: [
        IconButton(
          icon: const Icon(Icons.calendar_month),
          onPressed: () async {
            final selected = await showDatePicker(
              context: context,
              initialDate: day,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (selected != null) setState(() => day = selected);
          },
        ),
      ],
    ),
    body: StreamBuilder<List<CollectionSchedule>>(
      stream: widget.repository.watchDay(day),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final schedules = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 24,
                  children: [
                    Text('Jobs: ${schedules.length}'),
                    Text(
                      'Active: ${schedules.where((x) => x.status == DispatchStatus.inProgress).length}',
                    ),
                    Text(
                      'Completed: ${schedules.where((x) => x.status == DispatchStatus.completed).length}',
                    ),
                    Text(
                      'Urgent: ${schedules.where((x) => x.priority == DispatchPriority.urgent).length}',
                    ),
                  ],
                ),
              ),
            ),
            for (final job in schedules)
              Card(
                child: ListTile(
                  leading: Icon(
                    job.priority == DispatchPriority.urgent
                        ? Icons.priority_high
                        : Icons.route,
                  ),
                  title: Text('${job.scheduledAt} • ${job.serviceArea}'),
                  subtitle: Text(
                    '${job.status.name} • ${job.pickupIds.length} pickups\nDriver ${job.driverId} • Vehicle ${job.vehicleId}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => _action(context, job, action),
                    itemBuilder: (_) => [
                      if (widget.canGenerateRoutes)
                        PopupMenuItem(
                          value: 'generateRoute',
                          enabled: !generatingRoutes.contains(job.id),
                          child: Row(
                            children: [
                              const Icon(Icons.alt_route, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                generatingRoutes.contains(job.id)
                                    ? 'Generating route...'
                                    : 'Generate route',
                              ),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'dispatch',
                        child: Text('Dispatch team'),
                      ),
                      const PopupMenuItem(
                        value: 'start',
                        child: Text('Start collection'),
                      ),
                      const PopupMenuItem(
                        value: 'complete',
                        child: Text('Complete with evidence'),
                      ),
                      const PopupMenuItem(
                        value: 'missed',
                        child: Text('Reschedule missed job'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateScheduleScreen(repository: widget.repository),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Schedule'),
    ),
  );

  Future<void> _action(
    BuildContext context,
    CollectionSchedule job,
    String action,
  ) async {
    try {
      if (action == 'generateRoute') {
        if (generatingRoutes.contains(job.id)) return;
        setState(() => generatingRoutes.add(job.id));
        final route = await (widget.routeRepository ?? RouteRepository())
            .optimize(job);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Route ready for driver ${job.driverId}: '
                '${route.stops.length} stops, '
                '${route.distanceKm.toStringAsFixed(1)} km.',
              ),
            ),
          );
        }
      }
      if (action == 'dispatch') await widget.repository.dispatch(job);
      if (action == 'start') await widget.repository.start(job);
      if (action == 'complete') {
        final files = await ImagePicker().pickMultiImage(imageQuality: 70);
        await widget.repository.complete(
          job,
          await Future.wait(files.map((x) => x.readAsBytes())),
        );
      }
      if (action == 'missed') {
        if (!context.mounted) return;
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now().add(const Duration(days: 1)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) {
          await widget.repository.markMissedAndReschedule(
            job,
            DateTime(date.year, date.month, date.day, 9),
          );
        }
      }
    } catch (error) {
      if (context.mounted) {
        final label = action == 'generateRoute'
            ? 'Route generation failed'
            : 'Dispatch action failed';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label: $error')));
      }
    } finally {
      if (action == 'generateRoute' && mounted) {
        setState(() => generatingRoutes.remove(job.id));
      }
    }
  }
}

class CreateScheduleScreen extends StatefulWidget {
  const CreateScheduleScreen({super.key, required this.repository});
  final DispatchRepository repository;
  @override
  State<CreateScheduleScreen> createState() => _CreateScheduleState();
}

class _CreateScheduleState extends State<CreateScheduleScreen> {
  List<PickupRequest> pickups = [];
  List<DispatchStaff> staff = [];
  List<Vehicle> vehicles = [];
  final selectedPickups = <String>{};
  final selectedCollectors = <String>{};
  final area = TextEditingController();
  String? driverId;
  String? vehicleId;
  DispatchPriority priority = DispatchPriority.normal;
  DateTime scheduled = DateTime.now().add(const Duration(days: 1));
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    area.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    pickups = await widget.repository.watchAssignablePickups().first;
    staff = await widget.repository.watchStaff().first;
    vehicles = await widget.repository.watchAvailableVehicles().first;
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final collectors = staff.where((x) => x.role == 'collector' && x.available);
    final drivers = staff.where((x) => x.role == 'driver' && x.available);
    return Scaffold(
      appBar: AppBar(title: const Text('Create collection schedule')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: area,
            decoration: const InputDecoration(
              labelText: 'Service area / route group',
            ),
          ),
          ListTile(
            title: const Text('Collection date'),
            subtitle: Text('$scheduled'),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: scheduled,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setState(
                  () =>
                      scheduled = DateTime(date.year, date.month, date.day, 9),
                );
              }
            },
          ),
          DropdownButtonFormField<DispatchPriority>(
            initialValue: priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: DispatchPriority.values
                .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                .toList(),
            onChanged: (x) => setState(() => priority = x!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: driverId,
            decoration: const InputDecoration(labelText: 'Available driver'),
            items: drivers
                .map((x) => DropdownMenuItem(value: x.id, child: Text(x.name)))
                .toList(),
            onChanged: (x) => setState(() => driverId = x),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: vehicleId,
            decoration: const InputDecoration(labelText: 'Available vehicle'),
            items: vehicles
                .map(
                  (x) => DropdownMenuItem(
                    value: x.id,
                    child: Text('${x.registrationNumber} • ${x.capacityKg} kg'),
                  ),
                )
                .toList(),
            onChanged: (x) => setState(() => vehicleId = x),
          ),
          const Divider(),
          Text(
            'Collection team',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...collectors.map(
            (x) => CheckboxListTile(
              value: selectedCollectors.contains(x.id),
              title: Text(x.name),
              subtitle: Text(x.id),
              onChanged: (value) => setState(
                () => value!
                    ? selectedCollectors.add(x.id)
                    : selectedCollectors.remove(x.id),
              ),
            ),
          ),
          const Divider(),
          Text(
            'Nearby pickups',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...pickups.map(
            (x) => CheckboxListTile(
              value: selectedPickups.contains(x.id),
              title: Text('${x.category.name} • ${x.location}'),
              subtitle: Text('${x.weight} kg • ${x.status.name}'),
              onChanged: (value) => setState(
                () => value!
                    ? selectedPickups.add(x.id)
                    : selectedPickups.remove(x.id),
              ),
            ),
          ),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: const Text('Create schedule'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (driverId == null ||
        vehicleId == null ||
        selectedPickups.isEmpty ||
        area.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a route, pickups, driver, and vehicle.'),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      await widget.repository.create(
        scheduledAt: scheduled,
        pickups: pickups.where((x) => selectedPickups.contains(x.id)).toList(),
        collectorIds: selectedCollectors.toList(),
        driverId: driverId!,
        vehicle: vehicles.firstWhere((x) => x.id == vehicleId),
        priority: priority,
        serviceArea: area.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
        setState(() => busy = false);
      }
    }
  }
}
