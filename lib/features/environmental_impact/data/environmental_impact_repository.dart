import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/environmental_impact.dart';

class EnvironmentalImpactRepository {
  EnvironmentalImpactRepository({
    FirebaseFirestore? firestore,
    EnvironmentalImpactCalculator? calculator,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _calculator = calculator ?? const EnvironmentalImpactCalculator();

  final FirebaseFirestore _db;
  final EnvironmentalImpactCalculator _calculator;

  Stream<EnvironmentalImpactSnapshot> watchImpact() {
    late StreamController<EnvironmentalImpactSnapshot> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    var inventory = <Map<String, dynamic>>[];
    var recycling = <Map<String, dynamic>>[];
    var materials = <Map<String, dynamic>>[];
    var hazardous = <Map<String, dynamic>>[];
    var repairs = <Map<String, dynamic>>[];
    final ready = <String>{};

    void emit() {
      if (ready.length < 5 || controller.isClosed) return;
      controller.add(
        _calculator.calculate(
          EnvironmentalImpactInput(
            collected: inventory
                .map(
                  (data) => WeightedImpactEvent(
                    weightKg: (data['weight'] as num? ?? 0).toDouble(),
                    occurredAt: _date(data['createdAt']),
                  ),
                )
                .toList(),
            recycled: recycling
                .where(
                  (data) =>
                      data['stage'] == 'completed' ||
                      data['completionVerified'] == true,
                )
                .map(
                  (data) => WeightedImpactEvent(
                    weightKg: (data['inputWeightKg'] as num? ?? 0).toDouble(),
                    occurredAt:
                        _date(data['completedAt']) ?? _date(data['updatedAt']),
                  ),
                )
                .toList(),
            recoveredMaterials: materials
                .map(
                  (data) => WeightedImpactEvent(
                    weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
                    material: data['material'] ?? 'other',
                    occurredAt: _date(data['createdAt']),
                  ),
                )
                .toList(),
            hazardousHandled: hazardous
                .where(
                  (data) =>
                      data['status'] == 'disposed' ||
                      data['status'] == 'certified',
                )
                .map(
                  (data) => WeightedImpactEvent(
                    weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
                    occurredAt:
                        _date(data['certifiedAt']) ??
                        _date(data['disposedAt']) ??
                        _date(data['updatedAt']),
                  ),
                )
                .toList(),
            reusableDeviceDates: repairs
                .where((data) => data['status'] == 'completed')
                .map((data) => _date(data['completedAt']))
                .toList(),
          ),
        ),
      );
    }

    void listen(
      String name,
      String collection,
      void Function(List<Map<String, dynamic>>) update,
    ) {
      subscriptions.add(
        _db.collection(collection).snapshots().listen((snapshot) {
          update(snapshot.docs.map((doc) => doc.data()).toList());
          ready.add(name);
          emit();
        }, onError: controller.addError),
      );
    }

    controller = StreamController<EnvironmentalImpactSnapshot>.broadcast(
      onListen: () {
        listen('inventory', 'inventoryItems', (value) => inventory = value);
        listen('recycling', 'recyclingBatches', (value) => recycling = value);
        listen(
          'materials',
          'recoveredMaterialLots',
          (value) => materials = value,
        );
        listen(
          'hazardous',
          'hazardousWasteRecords',
          (value) => hazardous = value,
        );
        listen('repairs', 'repairJobs', (value) => repairs = value);
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Stream<List<EnvironmentalImpactReport>> watchReports() => _db
      .collection('environmentalImpactReports')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(EnvironmentalImpactReport.fromDoc).toList()..sort(
              (a, b) => (b.generatedAt ?? DateTime(2000)).compareTo(
                a.generatedAt ?? DateTime(2000),
              ),
            ),
      );

  Future<void> saveReport(
    EnvironmentalImpactSnapshot impact, {
    required String periodLabel,
    required String actorId,
  }) => _db.collection('environmentalImpactReports').add({
    'periodLabel': periodLabel.trim(),
    'totalCollectedKg': impact.totalCollectedKg,
    'totalRecycledKg': impact.totalRecycledKg,
    'landfillDiversionRate': impact.landfillDiversionRate,
    'materialsRecoveredKg': impact.materialsRecoveredKg,
    'carbonAvoidedKg': impact.carbonEmissionsAvoidedKg,
    'energySavedKwh': impact.energySavedKwh,
    'hazardousHandledKg': impact.hazardousSafelyHandledKg,
    'reusableDevices': impact.reusableDevices,
    'treesEquivalent': impact.treesEquivalent,
    'waterPollutionReductionLitres': impact.waterPollutionReductionLitres,
    'materialBreakdownKg': impact.materialBreakdownKg,
    'factorVersion': ImpactFactors.version,
    'generatedBy': actorId,
    'generatedAt': FieldValue.serverTimestamp(),
  });

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : null;
}
