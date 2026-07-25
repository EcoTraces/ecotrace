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
    required this.role,
    required this.dispatchRepository,
    required this.fleetRepository,
    required this.onOpen,
    required this.footer,
  });

  final String userId;
  final AppRole role;
  final DispatchRepository dispatchRepository;
  final FleetRepository fleetRepository;
  final ValueChanged<WorkspaceDestination> onOpen;
  final Widget footer;

  bool get _isDriver => role == AppRole.driver;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CollectionSchedule>>(
    stream: dispatchRepository.watchDay(DateTime.now()),
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
        stream: fleetRepository.watchVehicles(),
        builder: (context, vehicleSnapshot) {
          final vehicles = vehicleSnapshot.data ?? const <Vehicle>[];
          final vehicle = _assignedVehicle(schedules, vehicles);
          return _FieldDashboardBody(
            schedules: schedules,
            vehicle: vehicle,
            isDriver: _isDriver,
            loading:
                scheduleSnapshot.connectionState == ConnectionState.waiting ||
                vehicleSnapshot.connectionState == ConnectionState.waiting,
            onOpen: onOpen,
            footer: footer,
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
    required this.isDriver,
    required this.loading,
    required this.onOpen,
    required this.footer,
  });

  final List<CollectionSchedule> schedules;
  final Vehicle? vehicle;
  final bool isDriver;
  final bool loading;
  final ValueChanged<WorkspaceDestination> onOpen;
  final Widget footer;

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
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverToBoxAdapter(
              child: _MetricGrid(
                metrics: [
                  _FieldMetric(
                    label: 'Today’s Jobs',
                    value: '${schedules.length}',
                    icon: Icons.assignment_outlined,
                    color: const Color(0xFF167D50),
                  ),
                  _FieldMetric(
                    label: 'Collection Stops',
                    value: '$totalStops',
                    icon: Icons.location_on_outlined,
                    color: const Color(0xFF3978C8),
                  ),
                  _FieldMetric(
                    label: 'Completed',
                    value: '$completed',
                    icon: Icons.task_alt,
                    color: const Color(0xFF15905A),
                  ),
                  _FieldMetric(
                    label: 'Urgent',
                    value: '$urgent',
                    icon: Icons.priority_high_rounded,
                    color: const Color(0xFFE18A1D),
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
                  onOpen: onOpen,
                ),
                second: _DailyProgressCard(
                  completed: completed,
                  total: schedules.length,
                  stops: totalStops,
                  progress: progress,
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

class _ShiftBanner extends StatelessWidget {
  const _ShiftBanner({
    required this.isDriver,
    required this.activeJobs,
    required this.loading,
  });

  final bool isDriver;
  final int activeJobs;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF064C3F), Color(0xFF167D50)],
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
          ? 4
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
    required this.onOpen,
  });

  final CollectionSchedule? schedule;
  final bool isDriver;
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
  });

  final int completed;
  final int total;
  final int stops;
  final double progress;

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
                color: const Color(0xFF168253),
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
              return ListTile(
                onTap: onOpen,
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                leading: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _statusColor(schedule.status).withValues(alpha: .1),
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${schedule.pickupIds.length} stops • Vehicle ${schedule.vehicleId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9),
                ),
                trailing: _StatusPill(status: schedule.status),
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
