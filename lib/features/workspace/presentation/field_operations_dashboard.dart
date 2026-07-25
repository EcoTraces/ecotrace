import 'package:flutter/material.dart';

import '../../auth/domain/app_role.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../../dispatch/domain/collection_schedule.dart';
import '../../fleet/data/fleet_repository.dart';
import '../../fleet/domain/vehicle.dart';
import '../domain/application_interface.dart';

class FieldOperationsDashboard extends StatelessWidget {
  const FieldOperationsDashboard({
    super.key,
    required this.userId,
    required this.displayName,
    required this.role,
    this.dispatchRepository,
    this.fleetRepository,
    this.schedulesStream,
    this.vehiclesStream,
    required this.onOpen,
    required this.onOpenMenu,
    required this.footer,
    required this.mobileLayout,
  }) : assert(dispatchRepository != null || schedulesStream != null),
       assert(fleetRepository != null || vehiclesStream != null);

  final String userId;
  final String displayName;
  final AppRole role;
  final DispatchRepository? dispatchRepository;
  final FleetRepository? fleetRepository;
  final Stream<List<CollectionSchedule>>? schedulesStream;
  final Stream<List<Vehicle>>? vehiclesStream;
  final ValueChanged<WorkspaceDestination> onOpen;
  final VoidCallback onOpenMenu;
  final Widget footer;
  final bool mobileLayout;

  bool get _isDriver => role == AppRole.driver;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CollectionSchedule>>(
    stream: schedulesStream ?? dispatchRepository!.watchDay(DateTime.now()),
    builder: (context, scheduleSnapshot) {
      if (scheduleSnapshot.hasError) {
        return _FieldMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Unable to load today’s assignments',
          message: scheduleSnapshot.error.toString(),
        );
      }
      final schedules =
          (scheduleSnapshot.data ?? const <CollectionSchedule>[])
              .where(
                (schedule) => _isDriver
                    ? schedule.driverId == userId
                    : schedule.collectorIds.contains(userId),
              )
              .toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      return StreamBuilder<List<Vehicle>>(
        stream: vehiclesStream ?? fleetRepository!.watchVehicles(),
        builder: (context, vehicleSnapshot) {
          final vehicles = vehicleSnapshot.data ?? const <Vehicle>[];
          final vehicle = _assignedVehicle(schedules, vehicles);
          return _FieldDashboardBody(
            schedules: schedules,
            vehicle: vehicle,
            displayName: displayName,
            isDriver: _isDriver,
            loading:
                scheduleSnapshot.connectionState == ConnectionState.waiting ||
                vehicleSnapshot.connectionState == ConnectionState.waiting,
            onOpen: onOpen,
            onOpenMenu: onOpenMenu,
            footer: footer,
            mobileLayout: mobileLayout,
          );
        },
      );
    },
  );

  Vehicle? _assignedVehicle(
    List<CollectionSchedule> schedules,
    List<Vehicle> vehicles,
  ) {
    final vehicleIds = schedules.map((schedule) => schedule.vehicleId).toSet();
    for (final vehicle in vehicles) {
      if (vehicleIds.contains(vehicle.id)) return vehicle;
    }
    if (_isDriver) {
      for (final vehicle in vehicles) {
        if (vehicle.driverId == userId) return vehicle;
      }
    }
    return null;
  }
}

class _FieldDashboardBody extends StatelessWidget {
  const _FieldDashboardBody({
    required this.schedules,
    required this.vehicle,
    required this.displayName,
    required this.isDriver,
    required this.loading,
    required this.onOpen,
    required this.onOpenMenu,
    required this.footer,
    required this.mobileLayout,
  });

  final List<CollectionSchedule> schedules;
  final Vehicle? vehicle;
  final String displayName;
  final bool isDriver;
  final bool loading;
  final ValueChanged<WorkspaceDestination> onOpen;
  final VoidCallback onOpenMenu;
  final Widget footer;
  final bool mobileLayout;

  @override
  Widget build(BuildContext context) {
    final completed = schedules
        .where((schedule) => schedule.status == DispatchStatus.completed)
        .length;
    final active = schedules
        .where(
          (schedule) =>
              schedule.status == DispatchStatus.dispatched ||
              schedule.status == DispatchStatus.inProgress,
        )
        .length;
    final urgent = schedules
        .where((schedule) => schedule.priority == DispatchPriority.urgent)
        .length;
    final totalStops = schedules.fold<int>(
      0,
      (total, schedule) => total + schedule.pickupIds.length,
    );
    final current = _currentSchedule;
    final progress = schedules.isEmpty ? 0.0 : completed / schedules.length;
    final cancelled = schedules
        .where((schedule) => schedule.status == DispatchStatus.cancelled)
        .length;
    final accent = isDriver ? const Color(0xFF075AC8) : const Color(0xFF087A52);

    if (mobileLayout) {
      return _MobileFieldDashboard(
        displayName: displayName,
        schedules: schedules,
        current: current,
        vehicle: vehicle,
        isDriver: isDriver,
        loading: loading,
        completed: completed,
        active: active,
        cancelled: cancelled,
        urgent: urgent,
        progress: progress,
        accent: accent,
        onOpen: onOpen,
        onOpenMenu: onOpenMenu,
      );
    }

    return ColoredBox(
      color: const Color(0xFFF5F8F6),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            sliver: SliverToBoxAdapter(
              child: _ShiftBanner(
                isDriver: isDriver,
                activeJobs: active,
                loading: loading,
                accent: accent,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverToBoxAdapter(
              child: _MetricGrid(
                metrics: [
                  _FieldMetric(
                    label: isDriver ? 'Trips Assigned' : 'Assigned',
                    value: '${schedules.length}',
                    icon: Icons.assignment_outlined,
                    color: accent,
                  ),
                  _FieldMetric(
                    label: 'Completed',
                    value: '$completed',
                    icon: Icons.task_alt,
                    color: const Color(0xFF15905A),
                  ),
                  _FieldMetric(
                    label: isDriver ? 'In Transit' : 'In Progress',
                    value: '$active',
                    icon: isDriver
                        ? Icons.local_shipping_outlined
                        : Icons.pending_actions_outlined,
                    color: const Color(0xFFF09B23),
                  ),
                  _FieldMetric(
                    label: isDriver ? 'Pending' : 'Cancelled',
                    value: isDriver
                        ? '${schedules.where((s) => s.status == DispatchStatus.planned).length}'
                        : '$cancelled',
                    icon: isDriver
                        ? Icons.schedule_outlined
                        : Icons.cancel_outlined,
                    color: const Color(0xFFE04E55),
                  ),
                  _FieldMetric(
                    label: isDriver ? 'On-time Delivery' : 'Completion Rate',
                    value: '${(progress * 100).round()}%',
                    icon: Icons.speed_outlined,
                    color: accent,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverToBoxAdapter(
              child: _ResponsiveRow(
                firstFlex: 7,
                secondFlex: 4,
                first: _CurrentAssignmentCard(
                  schedule: current,
                  isDriver: isDriver,
                  accent: accent,
                  onOpen: onOpen,
                ),
                second: _DailyProgressCard(
                  completed: completed,
                  total: schedules.length,
                  stops: totalStops,
                  progress: progress,
                  accent: accent,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverToBoxAdapter(
              child: _QuickActions(isDriver: isDriver, onOpen: onOpen),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverToBoxAdapter(
              child: _ResponsiveRow(
                firstFlex: 7,
                secondFlex: 4,
                first: _SchedulePanel(
                  schedules: schedules,
                  onOpen: () => onOpen(WorkspaceDestination.assignedPickups),
                ),
                second: Column(
                  children: [
                    _VehicleCard(
                      vehicle: vehicle,
                      isDriver: isDriver,
                      onOpen: () =>
                          onOpen(WorkspaceDestination.vehicleInformation),
                    ),
                    const SizedBox(height: 12),
                    const _SafetyCard(),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverToBoxAdapter(child: footer),
          ),
        ],
      ),
    );
  }

  CollectionSchedule? get _currentSchedule {
    if (schedules.isEmpty) return null;
    for (final schedule in schedules) {
      if (schedule.status == DispatchStatus.inProgress ||
          schedule.status == DispatchStatus.dispatched) {
        return schedule;
      }
    }
    for (final schedule in schedules) {
      if (schedule.status == DispatchStatus.planned) return schedule;
    }
    return schedules.first;
  }
}

class _MobileFieldDashboard extends StatelessWidget {
  const _MobileFieldDashboard({
    required this.displayName,
    required this.schedules,
    required this.current,
    required this.vehicle,
    required this.isDriver,
    required this.loading,
    required this.completed,
    required this.active,
    required this.cancelled,
    required this.urgent,
    required this.progress,
    required this.accent,
    required this.onOpen,
    required this.onOpenMenu,
  });

  final String displayName;
  final List<CollectionSchedule> schedules;
  final CollectionSchedule? current;
  final Vehicle? vehicle;
  final bool isDriver;
  final bool loading;
  final int completed;
  final int active;
  final int cancelled;
  final int urgent;
  final double progress;
  final Color accent;
  final ValueChanged<WorkspaceDestination> onOpen;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final pending = schedules
        .where((schedule) => schedule.status == DispatchStatus.planned)
        .length;
    final firstName = displayName.trim().split(RegExp(r'\s+')).first;
    return ColoredBox(
      color: const Color(0xFFF4F7F5),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _MobileFieldHero(
              firstName: firstName,
              isDriver: isDriver,
              accent: accent,
              onMenu: onOpenMenu,
              onNotifications: () => onOpen(WorkspaceDestination.notifications),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            sliver: SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -24),
                child: _MobileOverviewCard(
                  isDriver: isDriver,
                  accent: accent,
                  assigned: schedules.length,
                  completed: completed,
                  active: active,
                  pendingOrCancelled: isDriver ? pending : cancelled,
                ),
              ),
            ),
          ),
          if (loading)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: LinearProgressIndicator(color: accent),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            sliver: SliverToBoxAdapter(
              child: isDriver
                  ? _MobileCurrentTrip(
                      schedule: current,
                      vehicle: vehicle,
                      accent: accent,
                      progress: progress,
                      onOpen: onOpen,
                    )
                  : _MobileSchedule(
                      schedules: schedules,
                      accent: accent,
                      onOpen: onOpen,
                    ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            sliver: SliverToBoxAdapter(
              child: _MobileQuickActions(
                isDriver: isDriver,
                accent: accent,
                onOpen: onOpen,
              ),
            ),
          ),
          if (isDriver)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              sliver: SliverToBoxAdapter(
                child: _MobileVehicleStatus(vehicle: vehicle, accent: accent),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              sliver: SliverToBoxAdapter(
                child: _MobileRoutePreview(
                  stops: schedules.fold<int>(
                    0,
                    (sum, schedule) => sum + schedule.pickupIds.length,
                  ),
                  accent: accent,
                  urgent: urgent,
                  onOpen: () => onOpen(WorkspaceDestination.routeNavigation),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MobileFieldHero extends StatelessWidget {
  const _MobileFieldHero({
    required this.firstName,
    required this.isDriver,
    required this.accent,
    required this.onMenu,
    required this.onNotifications,
  });

  final String firstName;
  final bool isDriver;
  final Color accent;
  final VoidCallback onMenu;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) => Container(
    height: 218,
    padding: EdgeInsets.fromLTRB(
      18,
      MediaQuery.paddingOf(context).top + 12,
      18,
      42,
    ),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(accent, Colors.black, .24)!, accent],
      ),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onMenu,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    isDriver ? Icons.local_shipping_outlined : Icons.recycling,
                    color: accent,
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            const Text(
              'EcoTrace',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Notifications',
              onPressed: onNotifications,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x24FFFFFF),
                foregroundColor: Colors.white,
              ),
              icon: const Badge(
                label: Text('2'),
                child: Icon(Icons.notifications_none),
              ),
            ),
          ],
        ),
        const Spacer(),
        Text(
          'Hello, $firstName 👋',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          isDriver ? 'Driver' : 'Collector',
          style: const TextStyle(
            color: Color(0xE6FFFFFF),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _MobileOverviewCard extends StatelessWidget {
  const _MobileOverviewCard({
    required this.isDriver,
    required this.accent,
    required this.assigned,
    required this.completed,
    required this.active,
    required this.pendingOrCancelled,
  });

  final bool isDriver;
  final Color accent;
  final int assigned;
  final int completed;
  final int active;
  final int pendingOrCancelled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(13, 14, 13, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18051F15),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Today’s Overview',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            _MobileMetric(
              value: '$assigned',
              label: isDriver ? 'Trips' : 'Assigned',
              icon: isDriver
                  ? Icons.local_shipping_outlined
                  : Icons.assignment_outlined,
              color: accent,
            ),
            _MobileMetric(
              value: '$completed',
              label: 'Completed',
              icon: Icons.task_alt,
              color: const Color(0xFF15905A),
            ),
            _MobileMetric(
              value: '$active',
              label: isDriver ? 'In transit' : 'In progress',
              icon: Icons.schedule,
              color: const Color(0xFFF09B23),
            ),
            _MobileMetric(
              value: '$pendingOrCancelled',
              label: isDriver ? 'Pending' : 'Cancelled',
              icon: isDriver ? Icons.pending_actions : Icons.cancel_outlined,
              color: const Color(0xFFE04E55),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MobileMetric extends StatelessWidget {
  const _MobileMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 8, color: Color(0xFF69756F)),
        ),
      ],
    ),
  );
}

class _MobileCurrentTrip extends StatelessWidget {
  const _MobileCurrentTrip({
    required this.schedule,
    required this.vehicle,
    required this.accent,
    required this.progress,
    required this.onOpen,
  });

  final CollectionSchedule? schedule;
  final Vehicle? vehicle;
  final Color accent;
  final double progress;
  final ValueChanged<WorkspaceDestination> onOpen;

  @override
  Widget build(BuildContext context) => _MobileCard(
    title: 'Current Trip',
    child: schedule == null
        ? const _CompactEmpty(
            icon: Icons.route_outlined,
            text: 'No trip assigned for today.',
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.route, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'TR-${schedule!.id.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _StatusPill(status: schedule!.status),
                ],
              ),
              const SizedBox(height: 16),
              _TripPoint(
                active: true,
                title: 'Collection route',
                subtitle: schedule!.serviceArea.isEmpty
                    ? 'Assigned collection area'
                    : schedule!.serviceArea,
                accent: accent,
              ),
              _TripPoint(
                active: false,
                title: 'Processing facility',
                subtitle: '${schedule!.pickupIds.length} collection stops',
                accent: accent,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Vehicle ${vehicle?.registrationNumber ?? schedule!.vehicleId}',
                    style: const TextStyle(
                      color: Color(0xFF66726C),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: progress == 0 ? .12 : progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
                color: accent,
                backgroundColor: accent.withValues(alpha: .1),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: () => onOpen(WorkspaceDestination.routeNavigation),
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: const Text('View route'),
                ),
              ),
            ],
          ),
  );
}

class _TripPoint extends StatelessWidget {
  const _TripPoint({
    required this.active,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final bool active;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: active ? accent : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10, color: Color(0xFF69756F)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MobileSchedule extends StatelessWidget {
  const _MobileSchedule({
    required this.schedules,
    required this.accent,
    required this.onOpen,
  });

  final List<CollectionSchedule> schedules;
  final Color accent;
  final ValueChanged<WorkspaceDestination> onOpen;

  @override
  Widget build(BuildContext context) => _MobileCard(
    title: 'Today’s Schedule',
    action: TextButton(
      onPressed: () => onOpen(WorkspaceDestination.assignedPickups),
      child: Text('View all', style: TextStyle(color: accent, fontSize: 11)),
    ),
    child: schedules.isEmpty
        ? const _CompactEmpty(
            icon: Icons.event_available_outlined,
            text: 'No collections assigned for today.',
          )
        : Column(
            children: schedules
                .take(4)
                .map(
                  (schedule) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => onOpen(WorkspaceDestination.pickupDetails),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                _time(schedule.scheduledAt),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    schedule.serviceArea.isEmpty
                                        ? 'Collection route'
                                        : schedule.serviceArea,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${schedule.pickupIds.length} pickup items',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF69756F),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _StatusPill(status: schedule.status),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}

class _MobileQuickActions extends StatelessWidget {
  const _MobileQuickActions({
    required this.isDriver,
    required this.accent,
    required this.onOpen,
  });

  final bool isDriver;
  final Color accent;
  final ValueChanged<WorkspaceDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final actions = isDriver
        ? const [
            _ActionData(
              'View route',
              Icons.navigation_outlined,
              WorkspaceDestination.routeNavigation,
              Color(0xFF075AC8),
            ),
            _ActionData(
              'Update status',
              Icons.sync,
              WorkspaceDestination.updatePickupStatus,
              Color(0xFF15905A),
            ),
            _ActionData(
              'Load details',
              Icons.inventory_2_outlined,
              WorkspaceDestination.pickupDetails,
              Color(0xFFF09B23),
            ),
            _ActionData(
              'Report issue',
              Icons.warning_amber_rounded,
              WorkspaceDestination.reportFailedPickup,
              Color(0xFFE04E55),
            ),
          ]
        : const [
            _ActionData(
              'Scan QR code',
              Icons.qr_code_scanner,
              WorkspaceDestination.scanQrCode,
              Color(0xFF087A52),
            ),
            _ActionData(
              'Update status',
              Icons.sync,
              WorkspaceDestination.updatePickupStatus,
              Color(0xFF15905A),
            ),
            _ActionData(
              'Upload photo',
              Icons.camera_alt_outlined,
              WorkspaceDestination.uploadProof,
              Color(0xFF3978C8),
            ),
            _ActionData(
              'Report issue',
              Icons.warning_amber_rounded,
              WorkspaceDestination.reportFailedPickup,
              Color(0xFFE04E55),
            ),
          ];
    return _MobileCard(
      title: 'Quick Actions',
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            Expanded(
              child: InkWell(
                onTap: () => onOpen(actions[i].destination),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: actions[i].color.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          actions[i].icon,
                          color: actions[i].color,
                          size: 21,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        actions[i].label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (i < actions.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _MobileVehicleStatus extends StatelessWidget {
  const _MobileVehicleStatus({required this.vehicle, required this.accent});

  final Vehicle? vehicle;
  final Color accent;

  @override
  Widget build(BuildContext context) => _MobileCard(
    title: 'Vehicle Status',
    child: vehicle == null
        ? const _CompactEmpty(
            icon: Icons.local_shipping_outlined,
            text: 'No vehicle assigned.',
          )
        : Row(
            children: [
              Container(
                width: 74,
                height: 64,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.local_shipping, color: accent, size: 42),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle!.registrationNumber,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_label(vehicle!.type.name)} • ${vehicle!.capacityKg.toStringAsFixed(0)} kg',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF69756F),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _AvailabilityPill(availability: vehicle!.availability),
                  ],
                ),
              ),
            ],
          ),
  );
}

class _MobileRoutePreview extends StatelessWidget {
  const _MobileRoutePreview({
    required this.stops,
    required this.accent,
    required this.urgent,
    required this.onOpen,
  });

  final int stops;
  final Color accent;
  final int urgent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _MobileCard(
    title: 'Map & Route',
    action: TextButton(
      onPressed: onOpen,
      child: Text('Open route', style: TextStyle(color: accent, fontSize: 11)),
    ),
    child: Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF2EE), Color(0xFFDCEAE5)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _RoutePreviewPainter(accent)),
          ),
          Positioned(
            left: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$stops stops • $urgent urgent',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoutePreviewPainter extends CustomPainter {
  const _RoutePreviewPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height * .28),
      Offset(size.width, size.height * .72),
      road,
    );
    canvas.drawLine(
      Offset(size.width * .2, 0),
      Offset(size.width * .62, size.height),
      road,
    );
    final route = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * .12, size.height * .78)
      ..lineTo(size.width * .32, size.height * .54)
      ..lineTo(size.width * .51, size.height * .63)
      ..lineTo(size.width * .7, size.height * .28)
      ..lineTo(size.width * .88, size.height * .38);
    canvas.drawPath(path, route);
    final marker = Paint()..color = color;
    for (final point in [
      Offset(size.width * .12, size.height * .78),
      Offset(size.width * .51, size.height * .63),
      Offset(size.width * .88, size.height * .38),
    ]) {
      canvas.drawCircle(point, 7, marker);
      canvas.drawCircle(point, 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MobileCard extends StatelessWidget {
  const _MobileCard({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE0E9E3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 11),
        child,
      ],
    ),
  );
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF849189)),
          const SizedBox(height: 7),
          Text(
            text,
            style: const TextStyle(fontSize: 11, color: Color(0xFF69756F)),
          ),
        ],
      ),
    ),
  );
}

class _ShiftBanner extends StatelessWidget {
  const _ShiftBanner({
    required this.isDriver,
    required this.activeJobs,
    required this.loading,
    required this.accent,
  });

  final bool isDriver;
  final int activeJobs;
  final bool loading;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Color.lerp(accent, Colors.black, .38)!, accent],
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 23,
          backgroundColor: const Color(0x26FFFFFF),
          child: Icon(
            isDriver ? Icons.local_shipping_outlined : Icons.recycling,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isDriver ? 'Driver Operations' : 'Collector Operations',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                loading
                    ? 'Synchronizing today’s field assignments...'
                    : activeJobs > 0
                    ? '$activeJobs active assignment${activeJobs == 1 ? '' : 's'} in progress'
                    : 'Ready for today’s collection assignments',
                style: const TextStyle(color: Color(0xDFFFFFFF), fontSize: 11),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x26FFFFFF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF6FE39A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'On duty',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_FieldMetric> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? metrics.length
          : constraints.maxWidth >= 520
          ? 2
          : 1;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: metrics
            .map(
              (metric) => SizedBox(
                width: width,
                child: _MetricCard(metric: metric),
              ),
            )
            .toList(),
      );
    },
  );
}

class _FieldMetric {
  const _FieldMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _FieldMetric metric;

  @override
  Widget build(BuildContext context) => Container(
    height: 92,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE0E9E3)),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: metric.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(metric.icon, color: metric.color),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF15251E),
              ),
            ),
            Text(
              metric.label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF637069)),
            ),
          ],
        ),
      ],
    ),
  );
}

class _CurrentAssignmentCard extends StatelessWidget {
  const _CurrentAssignmentCard({
    required this.schedule,
    required this.isDriver,
    required this.accent,
    required this.onOpen,
  });

  final CollectionSchedule? schedule;
  final bool isDriver;
  final Color accent;
  final ValueChanged<WorkspaceDestination> onOpen;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Current Assignment',
    child: schedule == null
        ? const _EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No assignment scheduled for today',
            message: 'New dispatch jobs will appear here automatically.',
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F4EB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.route, color: Color(0xFF167D50)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          schedule!.serviceArea.isEmpty
                              ? 'Collection route'
                              : schedule!.serviceArea,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${_time(schedule!.scheduledAt)} • ${schedule!.pickupIds.length} pickup stops',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF65726B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _PriorityPill(priority: schedule!.priority),
                ],
              ),
              const SizedBox(height: 17),
              _AssignmentDetail(
                icon: Icons.local_shipping_outlined,
                label: 'Vehicle',
                value: schedule!.vehicleId.isEmpty
                    ? 'Not assigned'
                    : schedule!.vehicleId,
              ),
              _AssignmentDetail(
                icon: Icons.info_outline,
                label: 'Status',
                value: _label(schedule!.status.name),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: accent),
                      onPressed: () => onOpen(
                        isDriver
                            ? WorkspaceDestination.routeNavigation
                            : WorkspaceDestination.pickupDetails,
                      ),
                      icon: Icon(
                        isDriver ? Icons.navigation_outlined : Icons.list_alt,
                        size: 18,
                      ),
                      label: Text(isDriver ? 'Open route' : 'View pickups'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        onOpen(WorkspaceDestination.updatePickupStatus),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Update'),
                  ),
                ],
              ),
            ],
          ),
  );
}

class _AssignmentDetail extends StatelessWidget {
  const _AssignmentDetail({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFF5E6C65)),
        const SizedBox(width: 8),
        SizedBox(
          width: 55,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF69766F)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _DailyProgressCard extends StatelessWidget {
  const _DailyProgressCard({
    required this.completed,
    required this.total,
    required this.stops,
    required this.progress,
    required this.accent,
  });

  final int completed;
  final int total;
  final int stops;
  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Today’s Progress',
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 9,
                backgroundColor: const Color(0xFFE4ECE7),
                color: accent,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'complete',
                    style: TextStyle(fontSize: 9, color: Color(0xFF68766F)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SmallStat(value: '$completed/$total', label: 'Jobs'),
            Container(width: 1, height: 30, color: const Color(0xFFE1E9E4)),
            _SmallStat(value: '$stops', label: 'Stops'),
          ],
        ),
      ],
    ),
  );
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 9, color: Color(0xFF68766F)),
      ),
    ],
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.isDriver, required this.onOpen});

  final bool isDriver;
  final ValueChanged<WorkspaceDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final actions = isDriver
        ? const [
            _ActionData(
              'Route navigation',
              Icons.navigation_outlined,
              WorkspaceDestination.routeNavigation,
              Color(0xFF3978C8),
            ),
            _ActionData(
              'Pickup details',
              Icons.list_alt,
              WorkspaceDestination.pickupDetails,
              Color(0xFF167D50),
            ),
            _ActionData(
              'Update status',
              Icons.sync,
              WorkspaceDestination.updatePickupStatus,
              Color(0xFF7A56C2),
            ),
            _ActionData(
              'Failed pickup',
              Icons.report_problem_outlined,
              WorkspaceDestination.reportFailedPickup,
              Color(0xFFD67C19),
            ),
            _ActionData(
              'Collection history',
              Icons.history,
              WorkspaceDestination.collectionHistory,
              Color(0xFF168A83),
            ),
            _ActionData(
              'Vehicle details',
              Icons.local_shipping_outlined,
              WorkspaceDestination.vehicleInformation,
              Color(0xFF4B678F),
            ),
          ]
        : const [
            _ActionData(
              'Scan QR code',
              Icons.qr_code_scanner,
              WorkspaceDestination.scanQrCode,
              Color(0xFF3978C8),
            ),
            _ActionData(
              'Record weight',
              Icons.scale_outlined,
              WorkspaceDestination.recordWeight,
              Color(0xFF167D50),
            ),
            _ActionData(
              'Pickup details',
              Icons.list_alt,
              WorkspaceDestination.pickupDetails,
              Color(0xFF7A56C2),
            ),
            _ActionData(
              'Update status',
              Icons.sync,
              WorkspaceDestination.updatePickupStatus,
              Color(0xFF168A83),
            ),
            _ActionData(
              'Failed pickup',
              Icons.report_problem_outlined,
              WorkspaceDestination.reportFailedPickup,
              Color(0xFFD67C19),
            ),
            _ActionData(
              'Collection history',
              Icons.history,
              WorkspaceDestination.collectionHistory,
              Color(0xFF4B678F),
            ),
          ];
    return _Panel(
      title: 'Quick Actions',
      height: 158,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 900
              ? (constraints.maxWidth - 50) / 6
              : 150.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  SizedBox(
                    width: width,
                    child: _QuickActionButton(
                      data: actions[index],
                      onTap: () => onOpen(actions[index].destination),
                    ),
                  ),
                  if (index < actions.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActionData {
  const _ActionData(this.label, this.icon, this.destination, this.color);
  final String label;
  final IconData icon;
  final WorkspaceDestination destination;
  final Color color;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.data, required this.onTap});
  final _ActionData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: data.color.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(data.icon, color: data.color, size: 24),
            const SizedBox(height: 7),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SchedulePanel extends StatelessWidget {
  const _SchedulePanel({required this.schedules, required this.onOpen});

  final List<CollectionSchedule> schedules;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Today’s Schedule',
    actionLabel: 'View assignments',
    onAction: onOpen,
    height: 330,
    child: schedules.isEmpty
        ? const _EmptyState(
            icon: Icons.calendar_today_outlined,
            title: 'No jobs scheduled today',
            message: 'Assigned collection jobs will appear automatically.',
          )
        : ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: schedules.take(4).length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final schedule = schedules[index];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  onTap: onOpen,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  leading: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _statusColor(
                        schedule.status,
                      ).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _time(schedule.scheduledAt),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: _statusColor(schedule.status),
                      ),
                    ),
                  ),
                  title: Text(
                    schedule.serviceArea.isEmpty
                        ? 'Collection route'
                        : schedule.serviceArea,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    '${schedule.pickupIds.length} stops • Vehicle ${schedule.vehicleId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9),
                  ),
                  trailing: _StatusPill(status: schedule.status),
                ),
              );
            },
          ),
  );
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.isDriver,
    required this.onOpen,
  });

  final Vehicle? vehicle;
  final bool isDriver;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _Panel(
    title: isDriver ? 'Assigned Vehicle' : 'Collection Vehicle',
    actionLabel: 'Details',
    onAction: onOpen,
    height: 188,
    child: vehicle == null
        ? const _EmptyState(
            icon: Icons.no_transfer_outlined,
            title: 'No vehicle assigned',
            message: 'Vehicle details appear with a dispatch assignment.',
          )
        : Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F3EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_shipping,
                  size: 38,
                  color: Color(0xFF167D50),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle!.registrationNumber.isEmpty
                          ? vehicle!.id
                          : vehicle!.registrationNumber,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_label(vehicle!.type.name)} • ${vehicle!.capacityKg.toStringAsFixed(0)} kg capacity',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF65736C),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _AvailabilityPill(availability: vehicle!.availability),
                  ],
                ),
              ),
            ],
          ),
  );
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  @override
  Widget build(BuildContext context) => const _Panel(
    title: 'Before You Start',
    height: 130,
    child: Row(
      children: [
        Icon(Icons.health_and_safety_outlined, color: Color(0xFF167D50)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Confirm PPE, inspect the vehicle, secure collection containers, and keep emergency contacts available.',
            style: TextStyle(fontSize: 10, height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _ResponsiveRow extends StatelessWidget {
  const _ResponsiveRow({
    required this.first,
    required this.second,
    required this.firstFlex,
    required this.secondFlex,
  });

  final Widget first;
  final Widget second;
  final int firstFlex;
  final int secondFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 760) {
        return Column(children: [first, const SizedBox(height: 12), second]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: firstFlex, child: first),
          const SizedBox(width: 12),
          Expanded(flex: secondFlex, child: second),
        ],
      );
    },
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.height = 286,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE0E9E3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF167D50),
                  textStyle: const TextStyle(fontSize: 9),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
        const Divider(height: 15),
        Expanded(child: child),
      ],
    ),
  );
}

class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.priority});
  final DispatchPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      DispatchPriority.urgent => const Color(0xFFD35A34),
      DispatchPriority.high => const Color(0xFFD58A1F),
      DispatchPriority.normal => const Color(0xFF3978C8),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _label(priority.name),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final DispatchStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _label(status.name),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill({required this.availability});
  final VehicleAvailability availability;

  @override
  Widget build(BuildContext context) {
    final healthy =
        availability == VehicleAvailability.available ||
        availability == VehicleAvailability.dispatched;
    final color = healthy ? const Color(0xFF168452) : const Color(0xFFC4771C);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 7, color: color),
        const SizedBox(width: 5),
        Text(
          _label(availability.name),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 34, color: const Color(0xFF91A299)),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, color: Color(0xFF6B7871)),
        ),
      ],
    ),
  );
}

class _FieldMessage extends StatelessWidget {
  const _FieldMessage({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: const Color(0xFF65736C)),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

Color _statusColor(DispatchStatus status) => switch (status) {
  DispatchStatus.completed => const Color(0xFF168452),
  DispatchStatus.inProgress => const Color(0xFF3978C8),
  DispatchStatus.dispatched => const Color(0xFF7A56C2),
  DispatchStatus.missed || DispatchStatus.cancelled => const Color(0xFFC65D3E),
  DispatchStatus.planned => const Color(0xFFD08720),
};

String _time(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}

String _label(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    )
    .split(' ')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
