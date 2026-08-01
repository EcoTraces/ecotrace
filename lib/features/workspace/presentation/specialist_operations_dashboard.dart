import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_currency.dart';
import '../../auth/domain/app_role.dart';
import '../../compliance/data/compliance_repository.dart';
import '../../compliance/domain/compliance_record.dart';
import '../../environmental_impact/data/environmental_impact_repository.dart';
import '../../environmental_impact/domain/environmental_impact.dart';
import '../../notifications/presentation/notification_badge.dart';
import '../../recovery/data/resource_recovery_repository.dart';
import '../../recovery/domain/recovered_material.dart';
import '../../recycling/data/recycling_repository.dart';
import '../../recycling/domain/recycling_batch.dart';
import '../../repairs/data/repair_repository.dart';
import '../../repairs/domain/repair_job.dart';
import '../domain/application_interface.dart';

/// A live, responsive dashboard for the three processing and regulatory roles.
///
/// Web and Windows use the same information-dense desktop composition. On
/// narrower screens the content becomes a touch-friendly mobile dashboard.
class SpecialistOperationsDashboard extends StatelessWidget {
  const SpecialistOperationsDashboard({
    super.key,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.onOpen,
    required this.onOpenMenu,
    required this.footer,
    required this.mobileLayout,
    this.complianceRepository,
    this.environmentalImpactRepository,
    this.repairRepository,
    this.recyclingRepository,
    this.resourceRecoveryRepository,
    this.documentsStream,
    this.inspectionsStream,
    this.violationsStream,
    this.impactStream,
    this.repairJobsStream,
    this.recyclingBatchesStream,
    this.recoveredMaterialsStream,
  }) : assert(
         role == AppRole.environmentalOfficer ||
             role == AppRole.repairTechnician ||
             role == AppRole.recycler,
       );

  final String userId;
  final String displayName;
  final AppRole role;
  final ValueChanged<WorkspaceDestination> onOpen;
  final VoidCallback onOpenMenu;
  final Widget footer;
  final bool mobileLayout;

  final ComplianceRepository? complianceRepository;
  final EnvironmentalImpactRepository? environmentalImpactRepository;
  final RepairRepository? repairRepository;
  final RecyclingRepository? recyclingRepository;
  final ResourceRecoveryRepository? resourceRecoveryRepository;

  final Stream<List<ComplianceDocument>>? documentsStream;
  final Stream<List<ComplianceInspection>>? inspectionsStream;
  final Stream<List<ComplianceViolation>>? violationsStream;
  final Stream<EnvironmentalImpactSnapshot>? impactStream;
  final Stream<List<RepairJob>>? repairJobsStream;
  final Stream<List<RecyclingBatch>>? recyclingBatchesStream;
  final Stream<List<RecoveredMaterialLot>>? recoveredMaterialsStream;

  @override
  Widget build(BuildContext context) => switch (role) {
    AppRole.environmentalOfficer => _environmentalDashboard(),
    AppRole.repairTechnician => _technicianDashboard(),
    AppRole.recycler => _recyclerDashboard(),
    _ => const SizedBox.shrink(),
  };

  Widget _environmentalDashboard() {
    final documents = documentsStream ?? complianceRepository!.watchDocuments();
    final inspections =
        inspectionsStream ?? complianceRepository!.watchInspections();
    final violations =
        violationsStream ?? complianceRepository!.watchViolations();
    final impact = impactStream ?? environmentalImpactRepository!.watchImpact();

    return StreamBuilder<List<ComplianceDocument>>(
      stream: documents,
      builder: (context, documentSnapshot) =>
          StreamBuilder<List<ComplianceInspection>>(
            stream: inspections,
            builder: (context, inspectionSnapshot) =>
                StreamBuilder<List<ComplianceViolation>>(
                  stream: violations,
                  builder: (context, violationSnapshot) =>
                      StreamBuilder<EnvironmentalImpactSnapshot>(
                        stream: impact,
                        builder: (context, impactSnapshot) {
                          final model = _SpecialistDashboardModel.environmental(
                            displayName: displayName,
                            documents:
                                documentSnapshot.data ??
                                const <ComplianceDocument>[],
                            inspections:
                                inspectionSnapshot.data ??
                                const <ComplianceInspection>[],
                            violations:
                                violationSnapshot.data ??
                                const <ComplianceViolation>[],
                            impact: impactSnapshot.data,
                            mobileLayout: mobileLayout,
                            loading: _isLoading([
                              documentSnapshot,
                              inspectionSnapshot,
                              violationSnapshot,
                              impactSnapshot,
                            ]),
                            errorMessage: _errorMessage([
                              documentSnapshot.error,
                              inspectionSnapshot.error,
                              violationSnapshot.error,
                              impactSnapshot.error,
                            ]),
                          );
                          return _SpecialistDashboardBody(
                            model: model,
                            onOpen: onOpen,
                            onOpenMenu: onOpenMenu,
                            footer: footer,
                            mobileLayout: mobileLayout,
                          );
                        },
                      ),
                ),
          ),
    );
  }

  Widget _technicianDashboard() {
    final jobs = repairJobsStream ?? repairRepository!.watchJobs();
    return StreamBuilder<List<RepairJob>>(
      stream: jobs,
      builder: (context, snapshot) {
        final visibleJobs = (snapshot.data ?? const <RepairJob>[])
            .where(
              (job) => job.technicianId.isEmpty || job.technicianId == userId,
            )
            .toList();
        return _SpecialistDashboardBody(
          model: _SpecialistDashboardModel.technician(
            displayName: displayName,
            jobs: visibleJobs,
            mobileLayout: mobileLayout,
            loading: snapshot.connectionState == ConnectionState.waiting,
            errorMessage: snapshot.error?.toString() ?? '',
          ),
          onOpen: onOpen,
          onOpenMenu: onOpenMenu,
          footer: footer,
          mobileLayout: mobileLayout,
        );
      },
    );
  }

  Widget _recyclerDashboard() {
    final batches =
        recyclingBatchesStream ?? recyclingRepository!.watchBatches();
    final materials =
        recoveredMaterialsStream ?? resourceRecoveryRepository!.watchLots();
    return StreamBuilder<List<RecyclingBatch>>(
      stream: batches,
      builder: (context, batchSnapshot) =>
          StreamBuilder<List<RecoveredMaterialLot>>(
            stream: materials,
            builder: (context, materialSnapshot) => _SpecialistDashboardBody(
              model: _SpecialistDashboardModel.recycler(
                displayName: displayName,
                batches: batchSnapshot.data ?? const <RecyclingBatch>[],
                materials:
                    materialSnapshot.data ?? const <RecoveredMaterialLot>[],
                mobileLayout: mobileLayout,
                loading: _isLoading([batchSnapshot, materialSnapshot]),
                errorMessage: _errorMessage([
                  batchSnapshot.error,
                  materialSnapshot.error,
                ]),
              ),
              onOpen: onOpen,
              onOpenMenu: onOpenMenu,
              footer: footer,
              mobileLayout: mobileLayout,
            ),
          ),
    );
  }

  static bool _isLoading(List<AsyncSnapshot<Object?>> snapshots) =>
      snapshots.any(
        (snapshot) =>
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData,
      );

  static String _errorMessage(List<Object?> errors) => errors
      .where((error) => error != null)
      .map((error) => error.toString())
      .toSet()
      .join('\n');
}

class _SpecialistDashboardModel {
  const _SpecialistDashboardModel({
    required this.displayName,
    required this.roleTitle,
    required this.systemLabel,
    required this.tagline,
    required this.accent,
    required this.metrics,
    required this.actions,
    required this.breakdownTitle,
    required this.breakdownTotal,
    required this.breakdownUnit,
    required this.breakdown,
    required this.trendTitle,
    required this.trendValues,
    required this.activitiesTitle,
    required this.activities,
    required this.workflowTitle,
    required this.workflow,
    required this.loading,
    required this.errorMessage,
  });

  final String displayName;
  final String roleTitle;
  final String systemLabel;
  final String tagline;
  final Color accent;
  final List<_DashboardMetric> metrics;
  final List<_DashboardAction> actions;
  final String breakdownTitle;
  final double breakdownTotal;
  final String breakdownUnit;
  final List<_DashboardBreakdown> breakdown;
  final String trendTitle;
  final List<double> trendValues;
  final String activitiesTitle;
  final List<_DashboardActivity> activities;
  final String workflowTitle;
  final List<_DashboardWorkflow> workflow;
  final bool loading;
  final String errorMessage;

  factory _SpecialistDashboardModel.environmental({
    required String displayName,
    required List<ComplianceDocument> documents,
    required List<ComplianceInspection> inspections,
    required List<ComplianceViolation> violations,
    required EnvironmentalImpactSnapshot? impact,
    required bool mobileLayout,
    required bool loading,
    required String errorMessage,
  }) {
    const accent = Color(0xFF087A45);
    final score = ComplianceScore.calculate(
      documents: documents,
      inspections: inspections,
      violations: violations,
    );
    final openViolations = violations
        .where(
          (violation) => violation.status != ComplianceViolationStatus.resolved,
        )
        .length;
    final validDocuments = documents
        .where(
          (document) =>
              document.status == ComplianceDocumentStatus.valid &&
              !document.isExpired,
        )
        .length;
    final collected = impact?.totalCollectedKg ?? 0;
    final recycled = impact?.totalRecycledKg ?? 0;
    final recovered = impact?.materialsRecoveredKg ?? 0;
    final hazardous = impact?.hazardousSafelyHandledKg ?? 0;

    final inspectionActivities = [...inspections]
      ..sort(
        (a, b) => _latestDate(
          b.completedAt,
          b.scheduledAt,
        ).compareTo(_latestDate(a.completedAt, a.scheduledAt)),
      );
    final violationActivities = [...violations]
      ..sort(
        (a, b) => _latestDate(
          b.reportedAt,
          b.correctiveActionDueAt,
        ).compareTo(_latestDate(a.reportedAt, a.correctiveActionDueAt)),
      );
    final activities =
        <_DashboardActivity>[
          ...inspectionActivities
              .take(3)
              .map(
                (inspection) => _DashboardActivity(
                  icon: Icons.fact_check_outlined,
                  title:
                      inspection.status == ComplianceInspectionStatus.completed
                      ? 'Inspection completed'
                      : 'Inspection ${_sentenceCase(inspection.status.name)}',
                  subtitle: inspection.entityName.isEmpty
                      ? 'Environmental compliance inspection'
                      : inspection.entityName,
                  status: _sentenceCase(inspection.status.name),
                  color:
                      inspection.status == ComplianceInspectionStatus.completed
                      ? accent
                      : const Color(0xFFF09B23),
                  date: inspection.completedAt ?? inspection.scheduledAt,
                ),
              ),
          ...violationActivities
              .take(2)
              .map(
                (violation) => _DashboardActivity(
                  icon: Icons.warning_amber_rounded,
                  title: 'Violation ${_sentenceCase(violation.status.name)}',
                  subtitle: violation.entityName.isEmpty
                      ? violation.requirement
                      : violation.entityName,
                  status: _sentenceCase(violation.severity.name),
                  color: violation.severity == ViolationSeverity.critical
                      ? const Color(0xFFE1484F)
                      : const Color(0xFFF09B23),
                  date: violation.reportedAt,
                ),
              ),
        ]..sort(
          (a, b) =>
              _latestDate(b.date, null).compareTo(_latestDate(a.date, null)),
        );

    final groupedViolations = <String, int>{};
    for (final violation in violations) {
      final label = violation.requirement.trim().isEmpty
          ? _sentenceCase(violation.severity.name)
          : violation.requirement.trim();
      groupedViolations.update(label, (value) => value + 1, ifAbsent: () => 1);
    }
    final violationGroups = groupedViolations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _SpecialistDashboardModel(
      displayName: displayName,
      roleTitle: 'Environmental Officer',
      systemLabel: 'Environmental Officer',
      tagline: 'Monitor. Protect. Sustain. Together for a cleaner environment.',
      accent: accent,
      metrics: [
        _DashboardMetric(
          label: 'Total Inspections',
          value: _whole(inspections.length),
          supporting: 'Compliance checks',
          icon: Icons.assignment_turned_in_outlined,
          color: accent,
        ),
        _DashboardMetric(
          label: 'Violations Found',
          value: _whole(openViolations),
          supporting: 'Open actions',
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFE1484F),
        ),
        _DashboardMetric(
          label: 'Compliance Rate',
          value: '${score.overall.round()}%',
          supporting: 'Overall score',
          icon: Icons.verified_user_outlined,
          color: const Color(0xFF7656D6),
        ),
        _DashboardMetric(
          label: 'Valid Documents',
          value: _whole(validDocuments),
          supporting: 'Active certificates',
          icon: Icons.workspace_premium_outlined,
          color: const Color(0xFFF09B23),
        ),
        _DashboardMetric(
          label: 'E-Waste Collected',
          value: '${_compact(collected)} kg',
          supporting: 'Verified records',
          icon: Icons.recycling,
          color: const Color(0xFF2477D4),
        ),
      ],
      actions: const [
        _DashboardAction(
          label: 'New inspection',
          icon: Icons.fact_check_outlined,
          destination: WorkspaceDestination.compliance,
          color: Color(0xFF087A45),
        ),
        _DashboardAction(
          label: 'Log violation',
          icon: Icons.warning_amber_rounded,
          destination: WorkspaceDestination.compliance,
          color: Color(0xFFE1484F),
        ),
        _DashboardAction(
          label: 'Track e-waste',
          icon: Icons.travel_explore,
          destination: WorkspaceDestination.inventory,
          color: Color(0xFF2477D4),
        ),
        _DashboardAction(
          label: 'Upload evidence',
          icon: Icons.cloud_upload_outlined,
          destination: WorkspaceDestination.certificates,
          color: Color(0xFF7656D6),
        ),
        _DashboardAction(
          label: 'Generate report',
          icon: Icons.analytics_outlined,
          destination: WorkspaceDestination.reports,
          color: Color(0xFFF09B23),
        ),
      ],
      breakdownTitle: 'E-Waste Management Overview',
      breakdownTotal: collected,
      breakdownUnit: 'kg managed',
      breakdown: [
        _DashboardBreakdown(
          label: 'Collected',
          value: collected,
          color: accent,
        ),
        _DashboardBreakdown(
          label: 'Recycled',
          value: recycled,
          color: const Color(0xFF2477D4),
        ),
        _DashboardBreakdown(
          label: 'Materials recovered',
          value: recovered,
          color: const Color(0xFF7656D6),
        ),
        _DashboardBreakdown(
          label: 'Hazardous handled',
          value: hazardous,
          color: const Color(0xFFF09B23),
        ),
      ],
      trendTitle: 'Environmental Collection Trend',
      trendValues:
          impact?.monthly.map((month) => month.collectedKg).toList() ??
          const [0, 0, 0, 0, 0, 0],
      activitiesTitle: 'Recent Compliance Activities',
      activities: activities.take(5).toList(),
      workflowTitle: 'Top Violation Types',
      workflow: violationGroups.isEmpty
          ? const [
              _DashboardWorkflow(
                label: 'No violations recorded',
                value: 0,
                color: Color(0xFF087A45),
              ),
            ]
          : violationGroups
                .take(4)
                .map(
                  (entry) => _DashboardWorkflow(
                    label: entry.key,
                    value: entry.value,
                    color: entry.value == violationGroups.first.value
                        ? const Color(0xFFE1484F)
                        : const Color(0xFFF09B23),
                  ),
                )
                .toList(),
      loading: loading,
      errorMessage: errorMessage,
    );
  }

  factory _SpecialistDashboardModel.technician({
    required String displayName,
    required List<RepairJob> jobs,
    required bool mobileLayout,
    required bool loading,
    required String errorMessage,
  }) {
    final accent = mobileLayout
        ? const Color(0xFF087A45)
        : const Color(0xFF0B5FB8);
    final inProgress = jobs
        .where(
          (job) =>
              job.status == RepairStatus.diagnosed ||
              job.status == RepairStatus.approved ||
              job.status == RepairStatus.repairInProgress ||
              job.status == RepairStatus.qualityTesting,
        )
        .length;
    final pending = jobs
        .where((job) => job.status == RepairStatus.awaitingAssessment)
        .length;
    final completed = jobs
        .where((job) => job.status == RepairStatus.completed)
        .length;
    final recyclingReady = jobs
        .where(
          (job) =>
              job.status == RepairStatus.unrepairable ||
              job.status == RepairStatus.rejected,
        )
        .length;
    final turnaroundDays = jobs
        .where((job) => job.createdAt != null && job.completedAt != null)
        .map(
          (job) => job.completedAt!.difference(job.createdAt!).inHours / 24.0,
        )
        .toList();
    final averageTurnaround = turnaroundDays.isEmpty
        ? 0
        : turnaroundDays.reduce((a, b) => a + b) / turnaroundDays.length;
    final sortedJobs = [...jobs]
      ..sort(
        (a, b) => _latestDate(
          b.createdAt,
          b.completedAt,
        ).compareTo(_latestDate(a.createdAt, a.completedAt)),
      );
    final statusCounts = <RepairStatus, int>{
      for (final status in RepairStatus.values)
        status: jobs.where((job) => job.status == status).length,
    };

    return _SpecialistDashboardModel(
      displayName: displayName,
      roleTitle: 'Technician',
      systemLabel: 'Technician Dashboard',
      tagline: "Here's what's happening in your repair workshop today.",
      accent: accent,
      metrics: [
        _DashboardMetric(
          label: 'Work Orders',
          value: _whole(jobs.length),
          supporting: 'Assigned queue',
          icon: Icons.handyman_outlined,
          color: accent,
        ),
        _DashboardMetric(
          label: 'In Progress',
          value: _whole(inProgress),
          supporting: 'Active repairs',
          icon: Icons.build_circle_outlined,
          color: const Color(0xFFF09B23),
        ),
        _DashboardMetric(
          label: 'Completed',
          value: _whole(completed),
          supporting: 'Quality approved',
          icon: Icons.task_alt,
          color: const Color(0xFF15905A),
        ),
        _DashboardMetric(
          label: 'Avg. Turnaround',
          value: '${averageTurnaround.toStringAsFixed(1)} days',
          supporting: 'Completed jobs',
          icon: Icons.speed_outlined,
          color: const Color(0xFF7656D6),
        ),
        _DashboardMetric(
          label: 'Ready for Recycling',
          value: _whole(recyclingReady),
          supporting: 'Unrepairable items',
          icon: Icons.recycling,
          color: const Color(0xFF2477D4),
        ),
      ],
      actions: const [
        _DashboardAction(
          label: 'New repair job',
          icon: Icons.playlist_add,
          destination: WorkspaceDestination.repairJobs,
          color: Color(0xFF087A45),
        ),
        _DashboardAction(
          label: 'Scan & assess',
          icon: Icons.qr_code_scanner,
          destination: WorkspaceDestination.scanQrCode,
          color: Color(0xFF2477D4),
        ),
        _DashboardAction(
          label: 'My repair jobs',
          icon: Icons.handyman_outlined,
          destination: WorkspaceDestination.repairJobs,
          color: Color(0xFFF09B23),
        ),
        _DashboardAction(
          label: 'Inventory',
          icon: Icons.inventory_2_outlined,
          destination: WorkspaceDestination.inventory,
          color: Color(0xFF7656D6),
        ),
        _DashboardAction(
          label: 'Reports',
          icon: Icons.description_outlined,
          destination: WorkspaceDestination.reports,
          color: Color(0xFF0B5FB8),
        ),
      ],
      breakdownTitle: 'Task Condition',
      breakdownTotal: jobs.length.toDouble(),
      breakdownUnit: 'repair jobs',
      breakdown: [
        _DashboardBreakdown(
          label: 'In progress',
          value: inProgress.toDouble(),
          color: const Color(0xFFF09B23),
        ),
        _DashboardBreakdown(
          label: 'Awaiting assessment',
          value: pending.toDouble(),
          color: const Color(0xFF2477D4),
        ),
        _DashboardBreakdown(
          label: 'Completed',
          value: completed.toDouble(),
          color: const Color(0xFF15905A),
        ),
        _DashboardBreakdown(
          label: 'Unrepairable',
          value: recyclingReady.toDouble(),
          color: const Color(0xFFE1484F),
        ),
      ],
      trendTitle: 'Workshop Productivity',
      trendValues: sortedJobs.isEmpty
          ? const [0, 0, 0, 0, 0, 0]
          : sortedJobs
                .take(12)
                .toList()
                .reversed
                .map((job) => job.progressPercent.toDouble())
                .toList(),
      activitiesTitle: 'Recent Repair Jobs',
      activities: sortedJobs
          .take(5)
          .map(
            (job) => _DashboardActivity(
              icon: _repairIcon(job.deviceName),
              title: job.deviceName.isEmpty ? 'Repair job' : job.deviceName,
              subtitle:
                  '${job.itemCode.isEmpty ? job.id : job.itemCode} · ${job.faults.isEmpty ? 'Assessment pending' : job.faults.first}',
              status: job.status.label,
              color: _repairStatusColor(job.status),
              date: job.completedAt ?? job.createdAt,
            ),
          )
          .toList(),
      workflowTitle: 'Repair Workflow',
      workflow: [
        _DashboardWorkflow(
          label: 'Assessment',
          value: statusCounts[RepairStatus.awaitingAssessment] ?? 0,
          color: const Color(0xFF2477D4),
        ),
        _DashboardWorkflow(
          label: 'Diagnosed & approved',
          value:
              (statusCounts[RepairStatus.diagnosed] ?? 0) +
              (statusCounts[RepairStatus.approved] ?? 0),
          color: const Color(0xFF7656D6),
        ),
        _DashboardWorkflow(
          label: 'Repairing & testing',
          value:
              (statusCounts[RepairStatus.repairInProgress] ?? 0) +
              (statusCounts[RepairStatus.qualityTesting] ?? 0),
          color: const Color(0xFFF09B23),
        ),
        _DashboardWorkflow(
          label: 'Completed',
          value: completed,
          color: const Color(0xFF15905A),
        ),
      ],
      loading: loading,
      errorMessage: errorMessage,
    );
  }

  factory _SpecialistDashboardModel.recycler({
    required String displayName,
    required List<RecyclingBatch> batches,
    required List<RecoveredMaterialLot> materials,
    required bool mobileLayout,
    required bool loading,
    required String errorMessage,
  }) {
    const accent = Color(0xFF087A45);
    final inputWeight = batches.fold<double>(
      0,
      (total, batch) => total + batch.inputWeightKg,
    );
    final recoveredWeight = batches.fold<double>(
      0,
      (total, batch) => total + batch.recoveredWeightKg,
    );
    final inProgress = batches
        .where(
          (batch) =>
              batch.stage != RecyclingStage.created &&
              batch.stage != RecyclingStage.completed,
        )
        .length;
    final completed = batches
        .where((batch) => batch.stage == RecyclingStage.completed)
        .length;
    final verified = batches.where((batch) => batch.completionVerified).length;
    final recoveryRate = inputWeight <= 0
        ? 0.0
        : recoveredWeight / inputWeight * 100;
    final complianceRate = completed <= 0 ? 0.0 : verified / completed * 100;
    final earnings = materials.fold<double>(
      0,
      (total, lot) =>
          total +
          (lot.saleRevenue > 0 ? lot.saleRevenue : lot.estimatedMarketValue),
    );
    final materialGroups = <RecoverableMaterial, double>{};
    for (final lot in materials) {
      materialGroups.update(
        lot.material,
        (value) => value + lot.weightKg,
        ifAbsent: () => lot.weightKg,
      );
    }
    final groupEntries = materialGroups.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedBatches = [...batches]
      ..sort(
        (a, b) => _latestDate(
          b.createdAt,
          b.completedAt,
        ).compareTo(_latestDate(a.createdAt, a.completedAt)),
      );
    final stageCounts = <RecyclingStage, int>{
      for (final stage in RecyclingStage.values)
        stage: batches.where((batch) => batch.stage == stage).length,
    };

    return _SpecialistDashboardModel(
      displayName: displayName,
      roleTitle: 'Recycler',
      systemLabel: 'Recycler Dashboard',
      tagline: "Let's build a cleaner and more sustainable tomorrow.",
      accent: accent,
      metrics: [
        _DashboardMetric(
          label: 'Total Batches',
          value: _whole(batches.length),
          supporting: 'Waste received',
          icon: Icons.inventory_2_outlined,
          color: accent,
        ),
        _DashboardMetric(
          label: 'Total Weight',
          value: '${_compact(inputWeight)} kg',
          supporting: 'Batch input',
          icon: Icons.scale_outlined,
          color: const Color(0xFF2477D4),
        ),
        _DashboardMetric(
          label: 'Recovery Rate',
          value: '${recoveryRate.round()}%',
          supporting: 'Materials recovered',
          icon: Icons.recycling,
          color: const Color(0xFF7656D6),
        ),
        _DashboardMetric(
          label: 'Compliance Score',
          value: '${complianceRate.round()}%',
          supporting: 'Verified batches',
          icon: Icons.verified_user_outlined,
          color: const Color(0xFF15905A),
        ),
        _DashboardMetric(
          label: 'Recovery Value',
          value: AppCurrency.format(earnings, fractionDigits: 0),
          supporting: 'Estimated & sold',
          icon: Icons.monetization_on_outlined,
          color: const Color(0xFFF09B23),
        ),
      ],
      actions: const [
        _DashboardAction(
          label: 'Receive waste',
          icon: Icons.local_shipping_outlined,
          destination: WorkspaceDestination.receivedItems,
          color: Color(0xFF087A45),
        ),
        _DashboardAction(
          label: 'Start processing',
          icon: Icons.recycling,
          destination: WorkspaceDestination.recyclingBatches,
          color: Color(0xFF2477D4),
        ),
        _DashboardAction(
          label: 'Record materials',
          icon: Icons.inventory_2_outlined,
          destination: WorkspaceDestination.resourceRecovery,
          color: Color(0xFF7656D6),
        ),
        _DashboardAction(
          label: 'Scan QR code',
          icon: Icons.qr_code_scanner,
          destination: WorkspaceDestination.scanQrCode,
          color: Color(0xFF087A45),
        ),
        _DashboardAction(
          label: 'Reports',
          icon: Icons.analytics_outlined,
          destination: WorkspaceDestination.reports,
          color: Color(0xFFF09B23),
        ),
      ],
      breakdownTitle: 'Material Recovery',
      breakdownTotal: materials.fold<double>(
        0,
        (total, lot) => total + lot.weightKg,
      ),
      breakdownUnit: 'kg recovered',
      breakdown: groupEntries.isEmpty
          ? const [
              _DashboardBreakdown(
                label: 'No materials recorded',
                value: 0,
                color: Color(0xFF087A45),
              ),
            ]
          : [
              for (
                var index = 0;
                index < math.min(5, groupEntries.length);
                index++
              )
                _DashboardBreakdown(
                  label: groupEntries[index].key.label,
                  value: groupEntries[index].value,
                  color: _chartColors[index % _chartColors.length],
                ),
            ],
      trendTitle: 'Recovery Trend',
      trendValues: sortedBatches.isEmpty
          ? const [0, 0, 0, 0, 0, 0]
          : sortedBatches
                .take(12)
                .toList()
                .reversed
                .map((batch) => batch.recoveredWeightKg)
                .toList(),
      activitiesTitle: 'Recent Recycling Batches',
      activities: sortedBatches
          .take(5)
          .map(
            (batch) => _DashboardActivity(
              icon: Icons.recycling,
              title: batch.code,
              subtitle:
                  '${batch.facilityName.isEmpty ? 'Recycling facility' : batch.facilityName} · ${_compact(batch.inputWeightKg)} kg',
              status: batch.stage.label,
              color: batch.stage == RecyclingStage.completed
                  ? const Color(0xFF15905A)
                  : batch.stage == RecyclingStage.hazardousHandling
                  ? const Color(0xFFE1484F)
                  : const Color(0xFF2477D4),
              date: batch.completedAt ?? batch.createdAt,
            ),
          )
          .toList(),
      workflowTitle: 'Recycling Workflow',
      workflow: [
        _DashboardWorkflow(
          label: 'Received & sorted',
          value:
              (stageCounts[RecyclingStage.created] ?? 0) +
              (stageCounts[RecyclingStage.sorting] ?? 0),
          color: const Color(0xFF2477D4),
        ),
        _DashboardWorkflow(
          label: 'Processing',
          value: inProgress,
          color: const Color(0xFFF09B23),
        ),
        _DashboardWorkflow(
          label: 'Recovered lots',
          value: materials.length,
          color: const Color(0xFF7656D6),
        ),
        _DashboardWorkflow(
          label: 'Completed & verified',
          value: verified,
          color: const Color(0xFF15905A),
        ),
      ],
      loading: loading,
      errorMessage: errorMessage,
    );
  }
}

class _SpecialistDashboardBody extends StatelessWidget {
  const _SpecialistDashboardBody({
    required this.model,
    required this.onOpen,
    required this.onOpenMenu,
    required this.footer,
    required this.mobileLayout,
  });

  final _SpecialistDashboardModel model;
  final ValueChanged<WorkspaceDestination> onOpen;
  final VoidCallback onOpenMenu;
  final Widget footer;
  final bool mobileLayout;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF5F8F6),
    child: mobileLayout
        ? _MobileSpecialistDashboard(
            model: model,
            onOpen: onOpen,
            onOpenMenu: onOpenMenu,
          )
        : _DesktopSpecialistDashboard(
            model: model,
            onOpen: onOpen,
            footer: footer,
          ),
  );
}

class _DesktopSpecialistDashboard extends StatelessWidget {
  const _DesktopSpecialistDashboard({
    required this.model,
    required this.onOpen,
    required this.footer,
  });

  final _SpecialistDashboardModel model;
  final ValueChanged<WorkspaceDestination> onOpen;
  final Widget footer;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      if (model.loading)
        SliverToBoxAdapter(
          child: LinearProgressIndicator(color: model.accent, minHeight: 2),
        ),
      if (model.errorMessage.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _DataNotice(message: model.errorMessage),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        sliver: SliverToBoxAdapter(
          child: _MetricGrid(metrics: model.metrics, mobile: false),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        sliver: SliverToBoxAdapter(
          child: _ResponsivePair(
            firstFlex: 5,
            secondFlex: 7,
            first: _BreakdownCard(model: model),
            second: _TrendCard(model: model),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        sliver: SliverToBoxAdapter(
          child: _ResponsivePair(
            firstFlex: 7,
            secondFlex: 5,
            first: _ActivitiesCard(model: model),
            second: Column(
              children: [
                _WorkflowCard(model: model),
                const SizedBox(height: 12),
                _QuickActionsCard(model: model, onOpen: onOpen, compact: true),
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
  );
}

class _MobileSpecialistDashboard extends StatelessWidget {
  const _MobileSpecialistDashboard({
    required this.model,
    required this.onOpen,
    required this.onOpenMenu,
  });

  final _SpecialistDashboardModel model;
  final ValueChanged<WorkspaceDestination> onOpen;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: SafeArea(
          bottom: false,
          child: _MobileRoleHeader(
            model: model,
            onOpenMenu: onOpenMenu,
            onNotifications: () => onOpen(WorkspaceDestination.notifications),
          ),
        ),
      ),
      if (model.loading)
        SliverToBoxAdapter(
          child: LinearProgressIndicator(color: model.accent, minHeight: 2),
        ),
      if (model.errorMessage.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          sliver: SliverToBoxAdapter(
            child: _DataNotice(message: model.errorMessage),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        sliver: SliverToBoxAdapter(child: _MobileGreeting(model: model)),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        sliver: SliverToBoxAdapter(
          child: _MetricGrid(
            metrics: model.metrics.take(4).toList(),
            mobile: true,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        sliver: SliverToBoxAdapter(
          child: _QuickActionsCard(
            model: model,
            onOpen: onOpen,
            compact: false,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        sliver: SliverToBoxAdapter(child: _BreakdownCard(model: model)),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        sliver: SliverToBoxAdapter(child: _ActivitiesCard(model: model)),
      ),
    ],
  );
}

class _MobileRoleHeader extends StatelessWidget {
  const _MobileRoleHeader({
    required this.model,
    required this.onOpenMenu,
    required this.onNotifications,
  });

  final _SpecialistDashboardModel model;
  final VoidCallback onOpenMenu;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 7, 12, 7),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Open menu',
            onPressed: onOpenMenu,
            icon: const Icon(Icons.menu),
          ),
          Icon(Icons.recycling, color: model.accent, size: 30),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EcoTrace',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(
                  model.systemLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: model.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: onNotifications,
            icon: const NotificationBadgeIcon(),
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 19,
            backgroundColor: model.accent.withValues(alpha: .12),
            foregroundColor: model.accent,
            child: Text(
              _initials(model.displayName),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MobileGreeting extends StatelessWidget {
  const _MobileGreeting({required this.model});

  final _SpecialistDashboardModel model;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          model.accent,
          Color.lerp(model.accent, const Color(0xFF003D36), .58)!,
        ],
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_dayGreeting()},',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                model.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                model.tagline,
                style: const TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(
          width: 82,
          height: 82,
          decoration: const BoxDecoration(
            color: Color(0x24FFFFFF),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.public, color: Colors.white, size: 52),
        ),
      ],
    ),
  );
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, required this.mobile});

  final List<_DashboardMetric> metrics;
  final bool mobile;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = mobile
          ? (constraints.maxWidth >= 560 ? 4 : 2)
          : constraints.maxWidth >= 1150
          ? 5
          : constraints.maxWidth >= 720
          ? 3
          : 2;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final metric in metrics)
            SizedBox(
              width: width,
              height: mobile ? 116 : 122,
              child: _MetricCard(metric: metric, mobile: mobile),
            ),
        ],
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.mobile});

  final _DashboardMetric metric;
  final bool mobile;

  @override
  Widget build(BuildContext context) => _DashboardCard(
    padding: EdgeInsets.all(mobile ? 13 : 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Container(
              width: mobile ? 34 : 40,
              height: mobile ? 34 : 40,
              decoration: BoxDecoration(
                color: metric.color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                metric.icon,
                size: mobile ? 19 : 22,
                color: metric.color,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: mobile ? 20 : 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          metric.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: mobile ? 11 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          metric.supporting,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.model});

  final _SpecialistDashboardModel model;

  @override
  Widget build(BuildContext context) => _DashboardCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardTitle(title: model.breakdownTitle, trailing: 'This month'),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            final chart = _DonutChart(
              total: model.breakdownTotal,
              unit: model.breakdownUnit,
              segments: model.breakdown,
            );
            final legend = _BreakdownLegend(
              total: model.breakdownTotal,
              items: model.breakdown,
            );
            if (compact) {
              return Column(
                children: [
                  Center(child: chart),
                  const SizedBox(height: 18),
                  legend,
                ],
              );
            }
            return Row(
              children: [
                chart,
                const SizedBox(width: 22),
                Expanded(child: legend),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({
    required this.total,
    required this.unit,
    required this.segments,
  });

  final double total;
  final String unit;
  final List<_DashboardBreakdown> segments;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 142,
    height: 142,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _DonutPainter(segments)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(31),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _compact(total),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  unit,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 9,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.segments);

  final List<_DashboardBreakdown> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.shortestSide * .16;
    final background = Paint()
      ..color = const Color(0xFFE6ECE8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, background);
    final positive = segments.where((segment) => segment.value > 0).toList();
    final sum = positive.fold<double>(
      0,
      (total, segment) => total + segment.value,
    );
    if (sum <= 0) return;
    var start = -math.pi / 2;
    for (final segment in positive) {
      final sweep = math.pi * 2 * segment.value / sum;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = stroke;
      canvas.drawArc(
        rect.deflate(stroke / 2),
        start,
        math.max(0, sweep - .025),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.segments != segments;
}

class _BreakdownLegend extends StatelessWidget {
  const _BreakdownLegend({required this.total, required this.items});

  final double total;
  final List<_DashboardBreakdown> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _compact(item.value),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  total <= 0
                      ? '0%'
                      : '${(item.value / total * 100).clamp(0, 999).round()}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.model});

  final _SpecialistDashboardModel model;

  @override
  Widget build(BuildContext context) => _DashboardCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardTitle(title: model.trendTitle, trailing: 'Last 12 periods'),
        const SizedBox(height: 22),
        SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              values: model.trendValues,
              color: model.accent,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Earlier', style: Theme.of(context).textTheme.labelSmall),
            Text('Current', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    ),
  );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E9E4)
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final points = values.isEmpty ? const <double>[0] : values;
    final maxValue = points.fold<double>(0, math.max);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? size.width / 2
          : size.width * index / (points.length - 1);
      final y = size.height - (points[index] / safeMax * (size.height - 12));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: .015)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    if (points.isNotEmpty) {
      for (var index = 0; index < points.length; index++) {
        final x = points.length == 1
            ? size.width / 2
            : size.width * index / (points.length - 1);
        final y = size.height - (points[index] / safeMax * (size.height - 12));
        canvas.drawCircle(Offset(x, y), 3.4, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _ActivitiesCard extends StatelessWidget {
  const _ActivitiesCard({required this.model});

  final _SpecialistDashboardModel model;

  @override
  Widget build(BuildContext context) {
    final activities = model.activities.isEmpty
        ? [
            _DashboardActivity(
              icon: Icons.inbox_outlined,
              title: 'No recent activity',
              subtitle: 'New operational records will appear here.',
              status: 'Ready',
              color: model.accent,
              date: null,
            ),
          ]
        : model.activities;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(title: model.activitiesTitle, trailing: 'View all'),
          const SizedBox(height: 8),
          for (var index = 0; index < activities.length; index++) ...[
            _ActivityTile(activity: activities[index]),
            if (index < activities.length - 1)
              const Divider(height: 1, indent: 47),
          ],
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final _DashboardActivity activity;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: activity.color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(activity.icon, color: activity.color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activity.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                activity.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatDate(activity.date),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 9,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: activity.color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                activity.status,
                style: TextStyle(
                  color: activity.color,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({required this.model});

  final _SpecialistDashboardModel model;

  @override
  Widget build(BuildContext context) {
    final maximum = model.workflow.fold<int>(
      0,
      (value, item) => math.max(value, item.value),
    );
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(title: model.workflowTitle, trailing: 'Live'),
          const SizedBox(height: 14),
          for (final item in model.workflow)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Text(
                        '${item.value}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: maximum <= 0 ? 0 : item.value / maximum,
                      minHeight: 7,
                      color: item.color,
                      backgroundColor: item.color.withValues(alpha: .1),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.model,
    required this.onOpen,
    required this.compact,
  });

  final _SpecialistDashboardModel model;
  final ValueChanged<WorkspaceDestination> onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) => _DashboardCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardTitle(title: 'Quick Actions', trailing: 'View all'),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = compact
                ? (constraints.maxWidth >= 460 ? 3 : 2)
                : (constraints.maxWidth >= 520 ? 5 : 4);
            const gap = 9.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final action in model.actions)
                  SizedBox(
                    width: width,
                    height: compact ? 86 : 91,
                    child: Material(
                      color: action.color.withValues(alpha: .055),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onOpen(action.destination),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: action.color.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  action.icon,
                                  size: 19,
                                  color: action.color,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                action.label,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
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
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
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
      if (constraints.maxWidth < 780) {
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

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDDE6E0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0B271C),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      Text(
        trailing,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _DataNotice extends StatelessWidget {
  const _DataNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5E9),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFF4C47C)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.cloud_off_outlined, color: Color(0xFFB76800)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Live data is temporarily unavailable. The dashboard will update automatically when access returns.\n$message',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.supporting,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String supporting;
  final IconData icon;
  final Color color;
}

class _DashboardAction {
  const _DashboardAction({
    required this.label,
    required this.icon,
    required this.destination,
    required this.color,
  });

  final String label;
  final IconData icon;
  final WorkspaceDestination destination;
  final Color color;
}

class _DashboardBreakdown {
  const _DashboardBreakdown({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class _DashboardActivity {
  const _DashboardActivity({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.color,
    required this.date,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final Color color;
  final DateTime? date;
}

class _DashboardWorkflow {
  const _DashboardWorkflow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

const _chartColors = [
  Color(0xFF087A45),
  Color(0xFF2477D4),
  Color(0xFF7656D6),
  Color(0xFFF09B23),
  Color(0xFF23A6A3),
];

DateTime _latestDate(DateTime? first, DateTime? second) =>
    first ?? second ?? DateTime(2000);

String _whole(num value) => value.round().toString();

String _compact(double value) {
  if (value.abs() >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}m';
  }
  if (value.abs() >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(1);
}

String _sentenceCase(String value) {
  final words = value
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ')
      .trim()
      .split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return value;
  final normalized = words.join(' ').toLowerCase();
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Now';
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return 'Today';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'ET';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

String _dayGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

IconData _repairIcon(String deviceName) {
  final value = deviceName.toLowerCase();
  if (value.contains('phone')) return Icons.smartphone_outlined;
  if (value.contains('laptop')) return Icons.laptop_outlined;
  if (value.contains('desktop') || value.contains('computer')) {
    return Icons.desktop_windows_outlined;
  }
  return Icons.devices_other_outlined;
}

Color _repairStatusColor(RepairStatus status) => switch (status) {
  RepairStatus.completed => const Color(0xFF15905A),
  RepairStatus.rejected || RepairStatus.unrepairable => const Color(0xFFE1484F),
  RepairStatus.repairInProgress ||
  RepairStatus.qualityTesting => const Color(0xFFF09B23),
  _ => const Color(0xFF2477D4),
};
