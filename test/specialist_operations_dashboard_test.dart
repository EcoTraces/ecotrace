import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/auth/domain/app_role.dart';
import 'package:wastemanagementsystem/features/compliance/domain/compliance_record.dart';
import 'package:wastemanagementsystem/features/environmental_impact/domain/environmental_impact.dart';
import 'package:wastemanagementsystem/features/recovery/domain/recovered_material.dart';
import 'package:wastemanagementsystem/features/recycling/domain/recycling_batch.dart';
import 'package:wastemanagementsystem/features/repairs/domain/repair_job.dart';
import 'package:wastemanagementsystem/features/workspace/presentation/specialist_operations_dashboard.dart';

void main() {
  group('responsive specialist operations dashboards', () {
    testWidgets(
      'environmental officer mobile dashboard is compliance focused',
      (tester) async {
        await _setSurface(tester, const Size(390, 844));
        await _pumpDashboard(
          tester,
          role: AppRole.environmentalOfficer,
          displayName: 'Fatmata Bangura',
        );

        expect(find.text('Environmental Officer'), findsOneWidget);
        expect(find.text('Total Inspections'), findsOneWidget);
        expect(find.text('Violations Found'), findsOneWidget);
        expect(find.text('Quick Actions'), findsOneWidget);
        expect(find.text('E-Waste Management Overview'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('environmental officer web dashboard shows live overview', (
      tester,
    ) async {
      await _setSurface(tester, const Size(1440, 900));
      await _pumpDashboard(
        tester,
        role: AppRole.environmentalOfficer,
        displayName: 'Fatmata Bangura',
      );

      expect(find.text('Compliance Rate'), findsOneWidget);
      expect(find.text('E-Waste Collected'), findsOneWidget);
      expect(find.text('Environmental Collection Trend'), findsOneWidget);
      expect(find.text('Recent Compliance Activities'), findsOneWidget);
      expect(find.text('Top Violation Types'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('technician mobile dashboard follows repair workflow', (
      tester,
    ) async {
      await _setSurface(tester, const Size(390, 844));
      await _pumpDashboard(
        tester,
        role: AppRole.repairTechnician,
        displayName: 'John Technician',
      );

      expect(find.text('Technician Dashboard'), findsOneWidget);
      expect(find.text('Work Orders'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('New repair job'), findsOneWidget);
      expect(find.text('Task Condition'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('technician web and Windows dashboard shows repair analytics', (
      tester,
    ) async {
      await _setSurface(tester, const Size(1440, 900));
      await _pumpDashboard(
        tester,
        role: AppRole.repairTechnician,
        displayName: 'John Technician',
      );

      expect(find.text('Avg. Turnaround'), findsOneWidget);
      expect(find.text('Recent Repair Jobs'), findsOneWidget);
      expect(find.text('Repair Workflow'), findsOneWidget);
      expect(find.text('Workshop Productivity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'recycler mobile dashboard emphasizes processing and recovery',
      (tester) async {
        await _setSurface(tester, const Size(390, 844));
        await _pumpDashboard(
          tester,
          role: AppRole.recycler,
          displayName: 'James Recycler',
        );

        expect(find.text('Recycler Dashboard'), findsOneWidget);
        expect(find.text('Total Batches'), findsOneWidget);
        expect(find.text('Recovery Rate'), findsOneWidget);
        expect(find.text('Receive waste'), findsOneWidget);
        expect(find.text('Material Recovery'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('recycler web dashboard shows batch and material operations', (
      tester,
    ) async {
      await _setSurface(tester, const Size(1440, 900));
      await _pumpDashboard(
        tester,
        role: AppRole.recycler,
        displayName: 'James Recycler',
      );

      expect(find.text('Total Weight'), findsOneWidget);
      expect(find.text('Compliance Score'), findsOneWidget);
      expect(find.text('Recovery Trend'), findsOneWidget);
      expect(find.text('Recent Recycling Batches'), findsOneWidget);
      expect(find.text('Recycling Workflow'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required AppRole role,
  required String displayName,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087A45)),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SpecialistOperationsDashboard(
          userId: 'specialist-1',
          displayName: displayName,
          role: role,
          onOpen: (_) {},
          onOpenMenu: () {},
          footer: const SizedBox(height: 60),
          mobileLayout: tester.view.physicalSize.width < 1000,
          documentsStream: Stream.value(_documents),
          inspectionsStream: Stream.value(_inspections),
          violationsStream: Stream.value(_violations),
          impactStream: Stream.value(_impact),
          repairJobsStream: Stream.value(_repairJobs),
          recyclingBatchesStream: Stream.value(_batches),
          recoveredMaterialsStream: Stream.value(_materials),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final _documents = [
  ComplianceDocument(
    id: 'doc-1',
    type: ComplianceDocumentType.environmentalCertificate,
    title: 'Environmental certificate',
    referenceNumber: 'EPA-001',
    entityName: 'GreenTech Centre',
    regulatoryBodyId: 'epa',
    regulatoryBodyName: 'EPA Sierra Leone',
    status: ComplianceDocumentStatus.valid,
    documentUrls: const [],
    issuedAt: DateTime(2026, 1, 1),
    expiresAt: DateTime(2027, 1, 1),
    submittedAt: DateTime(2026, 1, 1),
    notes: '',
  ),
];

final _inspections = [
  ComplianceInspection(
    id: 'inspection-1',
    entityName: 'GreenTech Recycling Centre',
    regulatoryBodyId: 'epa',
    inspectorName: 'Fatmata Bangura',
    scheduledAt: DateTime(2026, 7, 24, 9),
    completedAt: DateTime(2026, 7, 24, 11),
    status: ComplianceInspectionStatus.completed,
    checklist: const {'Safe storage': true, 'PPE available': true},
    score: 96,
    findings: 'Compliant',
    recommendations: '',
    reportUrls: const [],
  ),
];

final _violations = [
  ComplianceViolation(
    id: 'violation-1',
    referenceNumber: 'VIO-001',
    entityName: 'Old Laptop Market',
    requirement: 'Unauthorized disposal',
    description: 'Open dumping of electronic waste',
    severity: ViolationSeverity.major,
    status: ComplianceViolationStatus.correctiveAction,
    correctiveActionPlan: 'Move items to approved storage',
    correctiveActionOwner: 'Site manager',
    correctiveActionDueAt: DateTime(2026, 8, 1),
    resolutionEvidence: '',
    reportedAt: DateTime(2026, 7, 24, 10),
    resolvedAt: null,
  ),
];

final _impact = EnvironmentalImpactSnapshot(
  totalCollectedKg: 256,
  totalRecycledKg: 172,
  materialsRecoveredKg: 72,
  hazardousSafelyHandledKg: 10,
  reusableDevices: 18,
  carbonEmissionsAvoidedKg: 460,
  energySavedKwh: 2100,
  treesEquivalent: 22,
  waterPollutionReductionLitres: 10000,
  materialBreakdownKg: const {'copper': 35, 'plastic': 22, 'steel': 15},
  monthly: [
    MonthlyEnvironmentalImpact(
      month: DateTime(2026, 6),
      collectedKg: 180,
      recycledKg: 120,
      materialsRecoveredKg: 48,
      hazardousHandledKg: 8,
      reusableDevices: 12,
      carbonAvoidedKg: 320,
      energySavedKwh: 1600,
    ),
    MonthlyEnvironmentalImpact(
      month: DateTime(2026, 7),
      collectedKg: 256,
      recycledKg: 172,
      materialsRecoveredKg: 72,
      hazardousHandledKg: 10,
      reusableDevices: 18,
      carbonAvoidedKg: 460,
      energySavedKwh: 2100,
    ),
  ],
  generatedAt: DateTime(2026, 7, 25),
);

final _repairJobs = [
  RepairJob(
    id: 'repair-1',
    itemId: 'item-1',
    itemCode: 'ECO-LAP-001',
    deviceName: 'Laptop repair',
    status: RepairStatus.repairInProgress,
    assessmentNotes: 'Screen damaged',
    diagnosis: 'Replace display assembly',
    faults: const ['Screen replacement'],
    technicianId: 'specialist-1',
    estimatedRepairCost: 1250,
    actualPartsCost: 800,
    progressPercent: 65,
    qualityChecks: const {},
    qualityNotes: '',
    grade: null,
    warrantyStart: null,
    warrantyEnd: null,
    disposition: RefurbishedDisposition.pending,
    dispositionApproved: false,
    resalePrice: null,
    donationRecipient: '',
    createdAt: DateTime(2026, 7, 23),
    completedAt: null,
  ),
  RepairJob(
    id: 'repair-2',
    itemId: 'item-2',
    itemCode: 'ECO-PHN-002',
    deviceName: 'Smartphone repair',
    status: RepairStatus.completed,
    assessmentNotes: 'Battery fault',
    diagnosis: 'Replace battery',
    faults: const ['Battery issue'],
    technicianId: 'specialist-1',
    estimatedRepairCost: 600,
    actualPartsCost: 420,
    progressPercent: 100,
    qualityChecks: const {'Power test': true},
    qualityNotes: 'Passed',
    grade: RefurbishmentGrade.gradeA,
    warrantyStart: DateTime(2026, 7, 24),
    warrantyEnd: DateTime(2026, 10, 24),
    disposition: RefurbishedDisposition.resale,
    dispositionApproved: true,
    resalePrice: 3500,
    donationRecipient: '',
    createdAt: DateTime(2026, 7, 20),
    completedAt: DateTime(2026, 7, 24),
  ),
];

final _batches = [
  RecyclingBatch(
    id: 'batch-1',
    code: 'BAT-2026-001',
    facilityId: 'facility-1',
    facilityName: 'Freetown Recycling Facility',
    itemIds: const ['item-1', 'item-2'],
    itemCodes: const ['ECO-001', 'ECO-002'],
    inputWeightKg: 126,
    recoveredWeightKg: 96,
    hazardousWeightKg: 8,
    disposedWeightKg: 12,
    processingLossKg: 10,
    stage: RecyclingStage.materialRecovery,
    completionVerified: false,
    verificationNotes: '',
    createdAt: DateTime(2026, 7, 24),
    completedAt: null,
  ),
  RecyclingBatch(
    id: 'batch-2',
    code: 'BAT-2026-002',
    facilityId: 'facility-1',
    facilityName: 'Freetown Recycling Facility',
    itemIds: const ['item-3'],
    itemCodes: const ['ECO-003'],
    inputWeightKg: 80,
    recoveredWeightKg: 65,
    hazardousWeightKg: 5,
    disposedWeightKg: 5,
    processingLossKg: 5,
    stage: RecyclingStage.completed,
    completionVerified: true,
    verificationNotes: 'Verified',
    createdAt: DateTime(2026, 7, 20),
    completedAt: DateTime(2026, 7, 23),
  ),
];

final _materials = [
  RecoveredMaterialLot(
    id: 'lot-1',
    lotCode: 'MAT-001',
    recyclingBatchId: 'batch-1',
    recyclingBatchCode: 'BAT-2026-001',
    material: RecoverableMaterial.copper,
    weightKg: 48,
    quantity: 1,
    qualityGrade: MaterialQualityGrade.gradeA,
    storageLocation: 'Section A',
    unitMarketValue: 160,
    buyerId: '',
    status: MaterialLotStatus.salesReady,
    saleRevenue: 0,
    createdAt: DateTime(2026, 7, 24),
  ),
  RecoveredMaterialLot(
    id: 'lot-2',
    lotCode: 'MAT-002',
    recyclingBatchId: 'batch-1',
    recyclingBatchCode: 'BAT-2026-001',
    material: RecoverableMaterial.plastic,
    weightKg: 32,
    quantity: 1,
    qualityGrade: MaterialQualityGrade.gradeB,
    storageLocation: 'Section B',
    unitMarketValue: 28,
    buyerId: '',
    status: MaterialLotStatus.stored,
    saleRevenue: 0,
    createdAt: DateTime(2026, 7, 24),
  ),
];
