import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/hazardous/domain/hazardous_waste.dart';
import 'package:wastemanagementsystem/features/recovery/domain/recovered_material.dart';
import 'package:wastemanagementsystem/features/recycling/domain/recycling_batch.dart';

void main() {
  group('Recycling process calculations', () {
    const batch = RecyclingBatch(
      id: 'batch-1',
      code: 'RCY-001',
      facilityId: 'facility-1',
      facilityName: 'Central recycler',
      itemIds: ['item-1'],
      itemCodes: ['EW-001'],
      inputWeightKg: 100,
      recoveredWeightKg: 72,
      hazardousWeightKg: 8,
      disposedWeightKg: 15,
      processingLossKg: 5,
      stage: RecyclingStage.verification,
      completionVerified: false,
      verificationNotes: '',
      createdAt: null,
      completedAt: null,
    );

    test('mass balance accounts for all processing outputs', () {
      expect(batch.accountedWeightKg, 100);
      expect(batch.unaccountedWeightKg, 0);
      expect(batch.lossPercent, 5);
    });

    test('recovery efficiency uses input and recovered weight', () {
      expect(batch.recoveryEfficiencyPercent, 72);
      expect(RecyclingStage.values.length, 9);
    });
  });

  test('resource recovery supports every specified material', () {
    expect(RecoverableMaterial.values.map((material) => material.label), [
      'Copper',
      'Aluminium',
      'Steel',
      'Plastic',
      'Glass',
      'Gold',
      'Silver',
      'Lithium',
      'Cobalt',
      'Circuit boards',
    ]);

    const lot = RecoveredMaterialLot(
      id: 'lot-1',
      lotCode: 'MAT-001',
      recyclingBatchId: 'batch-1',
      recyclingBatchCode: 'RCY-001',
      material: RecoverableMaterial.copper,
      weightKg: 12.5,
      quantity: 1,
      qualityGrade: MaterialQualityGrade.gradeA,
      storageLocation: 'Bay A',
      unitMarketValue: 8,
      buyerId: '',
      status: MaterialLotStatus.salesReady,
      saleRevenue: 0,
      createdAt: null,
    );
    expect(lot.estimatedMarketValue, 100);
  });

  test('hazardous PPE is complete only when every control is checked', () {
    const complete = HazardousWasteRecord(
      id: 'haz-1',
      code: 'HAZ-001',
      sourceBatchId: 'batch-1',
      sourceReference: 'RCY-001',
      category: HazardousMaterialCategory.lithiumBattery,
      classification: 'Class 9',
      weightKg: 8,
      quantity: 3,
      storageLocation: 'Battery vault',
      safetyInstructions: 'Insulate terminals.',
      ppeChecklist: {'Gloves': true, 'Eye protection': true},
      disposalFacility: '',
      status: HazardousWasteStatus.stored,
      certificateNumber: '',
      createdAt: null,
    );
    expect(complete.ppeComplete, isTrue);

    const incomplete = HazardousWasteRecord(
      id: 'haz-2',
      code: 'HAZ-002',
      sourceBatchId: '',
      sourceReference: 'Manual intake',
      category: HazardousMaterialCategory.mercury,
      classification: 'Toxic',
      weightKg: 1,
      quantity: 1,
      storageLocation: 'Cabinet 2',
      safetyInstructions: 'Use spill tray.',
      ppeChecklist: {'Gloves': true, 'Respirator': false},
      disposalFacility: '',
      status: HazardousWasteStatus.secured,
      certificateNumber: '',
      createdAt: null,
    );
    expect(incomplete.ppeComplete, isFalse);
  });
}
