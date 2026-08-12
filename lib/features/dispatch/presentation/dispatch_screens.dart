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
    this.canSchedule = false,
  });
  final DispatchRepository repository;
  final RouteRepository? routeRepository;
  final bool canGenerateRoutes;
  // Backend gates schedule creation (and its supporting reads) to
  // administrator/superAdministrator; hiding the FAB for other roles
  // (e.g. collector, driver) avoids a screen full of 403s.
  final bool canSchedule;
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
                      if (job.status == DispatchStatus.planned)
                        const PopupMenuItem(
                          value: 'dispatch',
                          child: Text('Dispatch team'),
                        ),
                      if (job.status == DispatchStatus.dispatched)
                        const PopupMenuItem(
                          value: 'start',
                          child: Text('Start collection'),
                        ),
                      if (job.status == DispatchStatus.inProgress)
                        const PopupMenuItem(
                          value: 'complete',
                          child: Text('Complete with evidence'),
                        ),
                      if (job.status != DispatchStatus.completed &&
                          job.status != DispatchStatus.cancelled)
                        const PopupMenuItem(
                          value: 'missed',
                          child: Text('Reschedule missed job'),
                        ),
                      if (job.status != DispatchStatus.completed &&
                          job.status != DispatchStatus.cancelled)
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancel schedule'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
    floatingActionButton: widget.canSchedule
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CreateScheduleScreen(repository: widget.repository),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Schedule'),
          )
        : null,
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
        if (files.isEmpty) throw StateError('Select at least one evidence image.');
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
          if (!context.mounted) return;
          final reason = await _reasonDialog(context, 'Reason for rescheduling');
          if (reason == null) return;
          await widget.repository.markMissedAndReschedule(
            job,
            DateTime(date.year, date.month, date.day, 9),
            reason: reason,
          );
        }
      }
      if (action == 'cancel') {
        if (!context.mounted) return;
        final reason = await _reasonDialog(context, 'Reason for cancellation');
        if (reason != null) {
          await widget.repository.cancel(job, reason);
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

  Future<String?> _reasonDialog(BuildContext context, String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Required reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Back')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 2) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
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
  List<NearbyPickupGroup> nearbyGroups = [];
  DispatchAvailability? availability;
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
    try {
      final values = await Future.wait([
        widget.repository.watchAssignablePickups().first,
        widget.repository.watchStaff().first,
        widget.repository.watchAvailableVehicles().first,
        widget.repository.nearbyGroups(),
      ]);
      pickups = values[0] as List<PickupRequest>;
      staff = values[1] as List<DispatchStaff>;
      vehicles = values[2] as List<Vehicle>;
      nearbyGroups = values[3] as List<NearbyPickupGroup>;
      availability = await widget.repository.availability(scheduled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load dispatch resources: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final availableStaff = availability?.availableStaffIds;
    final availableVehicles = availability?.availableVehicleIds;
    final collectors = staff.where(
      (x) =>
          x.role == 'collector' &&
          x.available &&
          (availableStaff == null || availableStaff.contains(x.id)),
    );
    final drivers = staff.where(
      (x) =>
          x.role == 'driver' &&
          x.available &&
          (availableStaff == null || availableStaff.contains(x.id)),
    );
    final selectableVehicles = vehicles.where(
      (x) => availableVehicles == null || availableVehicles.contains(x.id),
    );
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
                setState(() {
                  scheduled = DateTime(date.year, date.month, date.day, 9);
                  driverId = null;
                  vehicleId = null;
                  selectedCollectors.clear();
                });
                await _refreshAvailability();
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
            items: selectableVehicles
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
          if (nearbyGroups.isNotEmpty)
            ...nearbyGroups.map(
              (group) => Card(
                child: ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text('${group.serviceArea} • ${group.pickupIds.length} stops'),
                  subtitle: Text('${group.totalWeightKg.toStringAsFixed(1)} kg within nearby route group'),
                  trailing: TextButton(
                    onPressed: () => setState(() {
                      selectedPickups
                        ..clear()
                        ..addAll(group.pickupIds);
                      area.text = group.serviceArea;
                    }),
                    child: const Text('Select group'),
                  ),
                ),
              ),
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

  Future<void> _refreshAvailability() async {
    try {
      final result = await widget.repository.availability(scheduled);
      if (mounted) setState(() => availability = result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to refresh availability: $error')),
        );
      }
    }
  }
}
