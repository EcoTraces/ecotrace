import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/environmental_impact/domain/environmental_impact.dart';

void main() {
  const calculator = EnvironmentalImpactCalculator();
  final july = DateTime(2026, 7, 15);
  final june = DateTime(2026, 6, 15);

  EnvironmentalImpactSnapshot calculate() => calculator.calculate(
    EnvironmentalImpactInput(
      collected: [
        WeightedImpactEvent(weightKg: 100, occurredAt: july),
        WeightedImpactEvent(weightKg: 50, occurredAt: june),
      ],
      recycled: [
        WeightedImpactEvent(weightKg: 80, occurredAt: july),
        WeightedImpactEvent(weightKg: 25, occurredAt: june),
      ],
      recoveredMaterials: [
        WeightedImpactEvent(weightKg: 10, material: 'copper', occurredAt: july),
        WeightedImpactEvent(
          weightKg: 5,
          material: 'aluminium',
          occurredAt: july,
        ),
      ],
      hazardousHandled: [WeightedImpactEvent(weightKg: 4, occurredAt: july)],
      reusableDeviceDates: [july, july],
    ),
    now: DateTime(2026, 7, 17),
  );

  test('operational totals and landfill diversion avoid double counting', () {
    final impact = calculate();
    expect(impact.totalCollectedKg, 150);
    expect(impact.totalRecycledKg, 105);
    expect(impact.materialsRecoveredKg, 15);
    expect(impact.landfillDiversionRate, 70);
    expect(impact.reusableDevices, 2);
  });

  test('estimated sustainability indicators use documented factors', () {
    final impact = calculate();
    expect(impact.carbonEmissionsAvoidedKg, 180);
    expect(impact.energySavedKwh, 805);
    expect(impact.treesEquivalent, closeTo(180 / 21, .0001));
    expect(impact.waterPollutionReductionLitres, 4000);
  });

  test('material recovery and monthly comparison are preserved', () {
    final impact = calculate();
    expect(impact.materialBreakdownKg['copper'], 10);
    expect(impact.materialBreakdownKg['aluminium'], 5);
    expect(impact.monthly, hasLength(12));
    expect(impact.currentMonth!.collectedKg, 100);
    expect(impact.previousMonth!.collectedKg, 50);
    expect(impact.currentMonth!.landfillDiversionRate, 80);
    expect(impact.previousMonth!.landfillDiversionRate, 50);
  });

  test(
    'landfill diversion is bounded when legacy weights are inconsistent',
    () {
      final impact = calculator.calculate(
        EnvironmentalImpactInput(
          collected: [WeightedImpactEvent(weightKg: 10, occurredAt: july)],
          recycled: [WeightedImpactEvent(weightKg: 20, occurredAt: july)],
          recoveredMaterials: const [],
          hazardousHandled: const [],
          reusableDeviceDates: const [],
        ),
        now: july,
      );
      expect(impact.landfillDiversionRate, 100);
    },
  );
}
