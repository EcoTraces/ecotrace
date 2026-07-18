import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/repairs/domain/repair_job.dart';

void main() {
  test('repair workflow contains all required statuses in order', () {
    expect(RepairStatus.values, [
      RepairStatus.awaitingAssessment,
      RepairStatus.diagnosed,
      RepairStatus.approved,
      RepairStatus.repairInProgress,
      RepairStatus.qualityTesting,
      RepairStatus.completed,
      RepairStatus.rejected,
      RepairStatus.unrepairable,
    ]);
  });

  test('repair status labels match the operational language', () {
    expect(RepairStatus.awaitingAssessment.label, 'Awaiting assessment');
    expect(RepairStatus.repairInProgress.label, 'Repair in progress');
    expect(RepairStatus.qualityTesting.label, 'Quality testing');
  });

  test('spare part usage calculates total cost', () {
    const part = SparePartUsage(
      id: 'part-1',
      name: 'Battery',
      partNumber: 'BAT-01',
      quantity: 3,
      unitCost: 12.5,
      recordedBy: 'tech-1',
      recordedAt: null,
    );
    expect(part.totalCost, 37.5);
  });

  test('refurbishment grades expose clear labels', () {
    expect(RefurbishmentGrade.gradeA.label, 'Grade A');
    expect(RefurbishmentGrade.partsOnly.label, 'Parts only');
  });
}
