import 'package:cloud_firestore/cloud_firestore.dart';

enum RecyclingStage {
  created,
  sorting,
  dismantling,
  componentSeparation,
  materialRecovery,
  hazardousHandling,
  finalDisposal,
  verification,
  completed,
}

extension RecyclingStageLabel on RecyclingStage {
  String get label => switch (this) {
    RecyclingStage.created => 'Created',
    RecyclingStage.sorting => 'Material sorting',
    RecyclingStage.dismantling => 'Dismantling',
    RecyclingStage.componentSeparation => 'Component separation',
    RecyclingStage.materialRecovery => 'Material recovery',
    RecyclingStage.hazardousHandling => 'Hazardous handling',
    RecyclingStage.finalDisposal => 'Final disposal',
    RecyclingStage.verification => 'Completion verification',
    RecyclingStage.completed => 'Completed',
  };

  List<RecyclingStage> get nextStages => switch (this) {
    RecyclingStage.created => const [RecyclingStage.sorting],
    RecyclingStage.sorting => const [RecyclingStage.dismantling],
    RecyclingStage.dismantling => const [RecyclingStage.componentSeparation],
    RecyclingStage.componentSeparation => const [
      RecyclingStage.materialRecovery,
      RecyclingStage.hazardousHandling,
    ],
    RecyclingStage.materialRecovery => const [
      RecyclingStage.hazardousHandling,
      RecyclingStage.finalDisposal,
      RecyclingStage.verification,
    ],
    RecyclingStage.hazardousHandling => const [
      RecyclingStage.materialRecovery,
      RecyclingStage.finalDisposal,
      RecyclingStage.verification,
    ],
    RecyclingStage.finalDisposal => const [RecyclingStage.verification],
    RecyclingStage.verification || RecyclingStage.completed => const [],
  };
}

class RecyclingBatch {
  const RecyclingBatch({
    required this.id,
    required this.code,
    required this.facilityId,
    required this.facilityName,
    required this.itemIds,
    required this.itemCodes,
    required this.inputWeightKg,
    required this.recoveredWeightKg,
    required this.hazardousWeightKg,
    required this.disposedWeightKg,
    required this.processingLossKg,
    required this.stage,
    required this.completionVerified,
    required this.verificationNotes,
    required this.createdAt,
    required this.completedAt,
  });
  final String id, code, facilityId, facilityName, verificationNotes;
  final List<String> itemIds, itemCodes;
  final double inputWeightKg,
      recoveredWeightKg,
      hazardousWeightKg,
      disposedWeightKg,
      processingLossKg;
  final RecyclingStage stage;
  final bool completionVerified;
  final DateTime? createdAt, completedAt;

  double get accountedWeightKg =>
      recoveredWeightKg +
      hazardousWeightKg +
      disposedWeightKg +
      processingLossKg;
  double get unaccountedWeightKg =>
      (inputWeightKg - accountedWeightKg).clamp(0, double.infinity);
  double get recoveryEfficiencyPercent =>
      inputWeightKg <= 0 ? 0 : recoveredWeightKg / inputWeightKg * 100;
  double get lossPercent =>
      inputWeightKg <= 0 ? 0 : processingLossKg / inputWeightKg * 100;

  factory RecyclingBatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RecyclingBatch(
      id: doc.id,
      code: data['batchCode'] ?? doc.id,
      facilityId: data['facilityId'] ?? '',
      facilityName: data['facilityName'] ?? '',
      itemIds: List<String>.from(data['itemIds'] as List? ?? const []),
      itemCodes: List<String>.from(data['itemCodes'] as List? ?? const []),
      inputWeightKg: (data['inputWeightKg'] as num? ?? 0).toDouble(),
      recoveredWeightKg: (data['recoveredWeightKg'] as num? ?? 0).toDouble(),
      hazardousWeightKg: (data['hazardousWeightKg'] as num? ?? 0).toDouble(),
      disposedWeightKg: (data['disposedWeightKg'] as num? ?? 0).toDouble(),
      processingLossKg: (data['processingLossKg'] as num? ?? 0).toDouble(),
      stage: RecyclingStage.values.byName(
        data['stage'] ?? RecyclingStage.created.name,
      ),
      completionVerified: data['completionVerified'] as bool? ?? false,
      verificationNotes: data['verificationNotes'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory RecyclingBatch.fromJson(Map<String, dynamic> data) => RecyclingBatch(
    id: data['id']?.toString() ?? '',
    code: data['batchCode']?.toString() ?? data['id']?.toString() ?? '',
    facilityId: data['facilityId']?.toString() ?? '',
    facilityName: data['facilityName']?.toString() ?? '',
    itemIds: List<String>.from(data['itemIds'] as List? ?? const []),
    itemCodes: List<String>.from(data['itemCodes'] as List? ?? const []),
    inputWeightKg: (data['inputWeightKg'] as num? ?? 0).toDouble(),
    recoveredWeightKg: (data['recoveredWeightKg'] as num? ?? 0).toDouble(),
    hazardousWeightKg: (data['hazardousWeightKg'] as num? ?? 0).toDouble(),
    disposedWeightKg: (data['disposedWeightKg'] as num? ?? 0).toDouble(),
    processingLossKg: (data['processingLossKg'] as num? ?? 0).toDouble(),
    stage: RecyclingStage.values.byName(
      data['stage']?.toString() ?? RecyclingStage.created.name,
    ),
    completionVerified: data['completionVerified'] as bool? ?? false,
    verificationNotes: data['verificationNotes']?.toString() ?? '',
    createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
    completedAt: DateTime.tryParse(data['completedAt']?.toString() ?? ''),
  );
}

class RecyclingProcessRecord {
  const RecyclingProcessRecord({
    required this.type,
    required this.material,
    required this.component,
    required this.quantity,
    required this.weightKg,
    required this.notes,
    required this.actorId,
    required this.at,
  });
  final String type, material, component, notes, actorId;
  final int quantity;
  final double weightKg;
  final DateTime? at;

  factory RecyclingProcessRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return RecyclingProcessRecord(
      type: data['type'] ?? '',
      material: data['material'] ?? '',
      component: data['component'] ?? '',
      quantity: data['quantity'] as int? ?? 0,
      weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
      notes: data['notes'] ?? '',
      actorId: data['actorId'] ?? '',
      at: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory RecyclingProcessRecord.fromJson(Map<String, dynamic> data) =>
      RecyclingProcessRecord(
        type: data['type']?.toString() ?? '',
        material: data['material']?.toString() ?? '',
        component: data['component']?.toString() ?? '',
        quantity: (data['quantity'] as num? ?? 0).toInt(),
        weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
        notes: data['notes']?.toString() ?? '',
        actorId: data['actorId']?.toString() ?? '',
        at: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
      );
}

class FinalDisposalRecord {
  const FinalDisposalRecord({
    required this.material,
    required this.weightKg,
    required this.facility,
    required this.method,
    required this.manifestNumber,
    required this.at,
  });
  final String material, facility, method, manifestNumber;
  final double weightKg;
  final DateTime? at;
  factory FinalDisposalRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return FinalDisposalRecord(
      material: data['material'] ?? '',
      weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
      facility: data['facility'] ?? '',
      method: data['method'] ?? '',
      manifestNumber: data['manifestNumber'] ?? '',
      at: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory FinalDisposalRecord.fromJson(Map<String, dynamic> data) =>
      FinalDisposalRecord(
        material: data['material']?.toString() ?? '',
        weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
        facility: data['facility']?.toString() ?? '',
        method: data['method']?.toString() ?? '',
        manifestNumber: data['manifestNumber']?.toString() ?? '',
        at: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
      );
}
