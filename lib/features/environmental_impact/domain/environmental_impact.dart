import 'package:cloud_firestore/cloud_firestore.dart';

class ImpactFactors {
  const ImpactFactors({
    this.reuseCarbonKgPerDevice = 50,
    this.reuseEnergyKwhPerDevice = 200,
    this.treeCarbonKgPerYear = 21,
    this.waterProtectedLitresPerHazardousKg = 1000,
  });

  final double reuseCarbonKgPerDevice;
  final double reuseEnergyKwhPerDevice;
  final double treeCarbonKgPerYear;
  final double waterProtectedLitresPerHazardousKg;

  static const version = 'EcoTrace impact factors v1';

  double materialCarbonFactor(String material) => switch (material) {
    'copper' => 3.5,
    'aluminium' => 9.0,
    'steel' => 1.8,
    'plastic' => 2.5,
    'glass' => .3,
    'gold' => 17.0,
    'silver' => 12.0,
    'lithium' => 5.0,
    'cobalt' => 6.0,
    'circuitBoards' => 4.5,
    _ => 1.0,
  };

  double materialEnergyFactor(String material) => switch (material) {
    'copper' => 18.0,
    'aluminium' => 45.0,
    'steel' => 8.0,
    'plastic' => 14.0,
    'glass' => 2.0,
    'gold' => 80.0,
    'silver' => 60.0,
    'lithium' => 25.0,
    'cobalt' => 30.0,
    'circuitBoards' => 22.0,
    _ => 5.0,
  };
}

class WeightedImpactEvent {
  const WeightedImpactEvent({
    required this.weightKg,
    required this.occurredAt,
    this.material = '',
  });
  final double weightKg;
  final DateTime? occurredAt;
  final String material;
}

class EnvironmentalImpactInput {
  const EnvironmentalImpactInput({
    required this.collected,
    required this.recycled,
    required this.recoveredMaterials,
    required this.hazardousHandled,
    required this.reusableDeviceDates,
  });
  final List<WeightedImpactEvent> collected;
  final List<WeightedImpactEvent> recycled;
  final List<WeightedImpactEvent> recoveredMaterials;
  final List<WeightedImpactEvent> hazardousHandled;
  final List<DateTime?> reusableDeviceDates;
}

class MonthlyEnvironmentalImpact {
  const MonthlyEnvironmentalImpact({
    required this.month,
    required this.collectedKg,
    required this.recycledKg,
    required this.materialsRecoveredKg,
    required this.hazardousHandledKg,
    required this.reusableDevices,
    required this.carbonAvoidedKg,
    required this.energySavedKwh,
  });
  final DateTime month;
  final double collectedKg,
      recycledKg,
      materialsRecoveredKg,
      hazardousHandledKg,
      carbonAvoidedKg,
      energySavedKwh;
  final int reusableDevices;
  double get landfillDiversionRate =>
      collectedKg <= 0 ? 0 : (recycledKg / collectedKg * 100).clamp(0, 100);

  factory MonthlyEnvironmentalImpact.fromJson(Map<String, dynamic> data) =>
      MonthlyEnvironmentalImpact(
        month:
            DateTime.tryParse(data['month']?.toString() ?? '') ??
            DateTime.now(),
        collectedKg: (data['collectedKg'] as num? ?? 0).toDouble(),
        recycledKg: (data['recycledKg'] as num? ?? 0).toDouble(),
        materialsRecoveredKg: (data['materialsRecoveredKg'] as num? ?? 0)
            .toDouble(),
        hazardousHandledKg: (data['hazardousHandledKg'] as num? ?? 0)
            .toDouble(),
        reusableDevices: (data['reusableDevices'] as num? ?? 0).toInt(),
        carbonAvoidedKg: (data['carbonAvoidedKg'] as num? ?? 0).toDouble(),
        energySavedKwh: (data['energySavedKwh'] as num? ?? 0).toDouble(),
      );
}

class EnvironmentalImpactSnapshot {
  const EnvironmentalImpactSnapshot({
    required this.totalCollectedKg,
    required this.totalRecycledKg,
    required this.materialsRecoveredKg,
    required this.hazardousSafelyHandledKg,
    required this.reusableDevices,
    required this.carbonEmissionsAvoidedKg,
    required this.energySavedKwh,
    required this.treesEquivalent,
    required this.waterPollutionReductionLitres,
    required this.materialBreakdownKg,
    required this.monthly,
    required this.generatedAt,
  });
  final double totalCollectedKg,
      totalRecycledKg,
      materialsRecoveredKg,
      hazardousSafelyHandledKg,
      carbonEmissionsAvoidedKg,
      energySavedKwh,
      treesEquivalent,
      waterPollutionReductionLitres;
  final int reusableDevices;
  final Map<String, double> materialBreakdownKg;
  final List<MonthlyEnvironmentalImpact> monthly;
  final DateTime generatedAt;

  double get landfillDiversionRate => totalCollectedKg <= 0
      ? 0
      : (totalRecycledKg / totalCollectedKg * 100).clamp(0, 100);
  MonthlyEnvironmentalImpact? get currentMonth =>
      monthly.isEmpty ? null : monthly.last;
  MonthlyEnvironmentalImpact? get previousMonth =>
      monthly.length < 2 ? null : monthly[monthly.length - 2];

  factory EnvironmentalImpactSnapshot.fromJson(Map<String, dynamic> data) {
    final breakdown = <String, double>{};
    for (final entry in (data['materialBreakdownKg'] as Map? ?? const {})
        .entries) {
      breakdown[entry.key.toString()] = (entry.value as num? ?? 0)
          .toDouble();
    }
    return EnvironmentalImpactSnapshot(
      totalCollectedKg: (data['totalCollectedKg'] as num? ?? 0).toDouble(),
      totalRecycledKg: (data['totalRecycledKg'] as num? ?? 0).toDouble(),
      materialsRecoveredKg: (data['materialsRecoveredKg'] as num? ?? 0)
          .toDouble(),
      hazardousSafelyHandledKg: (data['hazardousSafelyHandledKg'] as num? ?? 0)
          .toDouble(),
      reusableDevices: (data['reusableDevicesRecovered'] as num? ?? 0)
          .toInt(),
      carbonEmissionsAvoidedKg: (data['carbonEmissionsAvoidedKg'] as num? ?? 0)
          .toDouble(),
      energySavedKwh: (data['energySavedKwh'] as num? ?? 0).toDouble(),
      treesEquivalent: (data['treesEquivalent'] as num? ?? 0).toDouble(),
      waterPollutionReductionLitres:
          (data['waterPollutionReductionLitres'] as num? ?? 0).toDouble(),
      materialBreakdownKg: breakdown,
      monthly: (data['monthly'] as List? ?? const [])
          .map(
            (entry) => MonthlyEnvironmentalImpact.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(),
      generatedAt: DateTime.now(),
    );
  }
}

class EnvironmentalImpactCalculator {
  const EnvironmentalImpactCalculator({this.factors = const ImpactFactors()});
  final ImpactFactors factors;

  EnvironmentalImpactSnapshot calculate(
    EnvironmentalImpactInput input, {
    DateTime? now,
  }) {
    final generatedAt = now ?? DateTime.now();
    final collected = _sum(input.collected);
    final recycled = _sum(input.recycled);
    final recovered = _sum(input.recoveredMaterials);
    final hazardous = _sum(input.hazardousHandled);
    final breakdown = <String, double>{};
    var carbon =
        input.reusableDeviceDates.length * factors.reuseCarbonKgPerDevice;
    var energy =
        input.reusableDeviceDates.length * factors.reuseEnergyKwhPerDevice;
    for (final event in input.recoveredMaterials) {
      breakdown.update(
        event.material,
        (value) => value + event.weightKg,
        ifAbsent: () => event.weightKg,
      );
      carbon += event.weightKg * factors.materialCarbonFactor(event.material);
      energy += event.weightKg * factors.materialEnergyFactor(event.material);
    }
    final months = <MonthlyEnvironmentalImpact>[];
    for (var offset = 11; offset >= 0; offset--) {
      final month = DateTime(generatedAt.year, generatedAt.month - offset);
      final materialEvents = input.recoveredMaterials
          .where((event) => _sameMonth(event.occurredAt, month))
          .toList();
      final deviceCount = input.reusableDeviceDates
          .where((date) => _sameMonth(date, month))
          .length;
      var monthlyCarbon = deviceCount * factors.reuseCarbonKgPerDevice;
      var monthlyEnergy = deviceCount * factors.reuseEnergyKwhPerDevice;
      for (final event in materialEvents) {
        monthlyCarbon +=
            event.weightKg * factors.materialCarbonFactor(event.material);
        monthlyEnergy +=
            event.weightKg * factors.materialEnergyFactor(event.material);
      }
      months.add(
        MonthlyEnvironmentalImpact(
          month: month,
          collectedKg: _sum(
            input.collected.where(
              (event) => _sameMonth(event.occurredAt, month),
            ),
          ),
          recycledKg: _sum(
            input.recycled.where(
              (event) => _sameMonth(event.occurredAt, month),
            ),
          ),
          materialsRecoveredKg: _sum(materialEvents),
          hazardousHandledKg: _sum(
            input.hazardousHandled.where(
              (event) => _sameMonth(event.occurredAt, month),
            ),
          ),
          reusableDevices: deviceCount,
          carbonAvoidedKg: monthlyCarbon,
          energySavedKwh: monthlyEnergy,
        ),
      );
    }
    return EnvironmentalImpactSnapshot(
      totalCollectedKg: collected,
      totalRecycledKg: recycled,
      materialsRecoveredKg: recovered,
      hazardousSafelyHandledKg: hazardous,
      reusableDevices: input.reusableDeviceDates.length,
      carbonEmissionsAvoidedKg: carbon,
      energySavedKwh: energy,
      treesEquivalent: factors.treeCarbonKgPerYear <= 0
          ? 0
          : carbon / factors.treeCarbonKgPerYear,
      waterPollutionReductionLitres:
          hazardous * factors.waterProtectedLitresPerHazardousKg,
      materialBreakdownKg: breakdown,
      monthly: months,
      generatedAt: generatedAt,
    );
  }

  double _sum(Iterable<WeightedImpactEvent> events) =>
      events.fold(0, (total, event) => total + event.weightKg);

  bool _sameMonth(DateTime? date, DateTime month) =>
      date != null && date.year == month.year && date.month == month.month;
}

class EnvironmentalImpactReport {
  const EnvironmentalImpactReport({
    required this.id,
    required this.periodLabel,
    required this.totalCollectedKg,
    required this.totalRecycledKg,
    required this.landfillDiversionRate,
    required this.carbonAvoidedKg,
    required this.generatedBy,
    required this.generatedAt,
  });
  final String id, periodLabel, generatedBy;
  final double totalCollectedKg,
      totalRecycledKg,
      landfillDiversionRate,
      carbonAvoidedKg;
  final DateTime? generatedAt;

  factory EnvironmentalImpactReport.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return EnvironmentalImpactReport(
      id: doc.id,
      periodLabel: data['periodLabel'] ?? '',
      totalCollectedKg: (data['totalCollectedKg'] as num? ?? 0).toDouble(),
      totalRecycledKg: (data['totalRecycledKg'] as num? ?? 0).toDouble(),
      landfillDiversionRate: (data['landfillDiversionRate'] as num? ?? 0)
          .toDouble(),
      carbonAvoidedKg: (data['carbonAvoidedKg'] as num? ?? 0).toDouble(),
      generatedBy: data['generatedBy'] ?? '',
      generatedAt: (data['generatedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory EnvironmentalImpactReport.fromJson(Map<String, dynamic> data) {
    final period = (data['period'] ?? '').toString();
    return EnvironmentalImpactReport(
      id: (data['id'] ?? period).toString(),
      periodLabel: _periodLabel(period),
      totalCollectedKg: (data['totalCollectedKg'] as num? ?? 0).toDouble(),
      totalRecycledKg: (data['totalRecycledKg'] as num? ?? 0).toDouble(),
      landfillDiversionRate: (data['landfillDiversionRate'] as num? ?? 0)
          .toDouble(),
      carbonAvoidedKg: (data['carbonEmissionsAvoidedKg'] as num? ?? 0)
          .toDouble(),
      generatedBy: (data['generatedBy'] ?? '').toString(),
      generatedAt: DateTime.tryParse(data['generatedAt']?.toString() ?? ''),
    );
  }

  static String _periodLabel(String period) {
    final parts = period.split('-');
    if (parts.length != 2) return period;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return period;
    }
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[month - 1]} $year impact snapshot';
  }
}
