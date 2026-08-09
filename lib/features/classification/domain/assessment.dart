import 'package:cloud_firestore/cloud_firestore.dart';

enum DeviceCategory {
  mobilePhones,
  laptops,
  desktopComputers,
  televisions,
  printers,
  batteries,
  accessories,
  networkingEquipment,
  householdAppliances,
  industrialElectronics,
}

enum TreatmentRecommendation {
  reuse,
  repair,
  refurbish,
  recycle,
  hazardousDisposal,
  finalDisposal,
}

enum AssessmentStatus { pendingSupervisor, approved, rejected }

enum AssessmentOrigin { manual, aiAssisted }

class ItemAssessment {
  const ItemAssessment({
    required this.id,
    required this.category,
    required this.materials,
    required this.hazards,
    required this.reusability,
    required this.repairability,
    required this.recommendation,
    required this.assessedCondition,
    required this.origin,
    required this.recoveryValue,
    required this.confidence,
    required this.status,
    required this.notes,
  });
  final String id, notes;
  final DeviceCategory category;
  final Map<String, double> materials;
  final List<String> hazards;
  final int reusability, repairability;
  final TreatmentRecommendation recommendation;
  final String assessedCondition;
  final AssessmentOrigin origin;
  final double recoveryValue, confidence;
  final AssessmentStatus status;
  factory ItemAssessment.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return ItemAssessment(
      id: d.id,
      category: DeviceCategory.values.byName(x['category']),
      materials: Map<String, double>.from(x['materials'] ?? {}),
      hazards: List<String>.from(x['hazards'] ?? []),
      reusability: x['reusability'],
      repairability: x['repairability'],
      recommendation: TreatmentRecommendation.values.byName(
        x['recommendation'],
      ),
      assessedCondition: x['assessedCondition']?.toString() ?? 'recyclable',
      origin: AssessmentOrigin.values.byName(
        x['origin']?.toString() ?? AssessmentOrigin.manual.name,
      ),
      recoveryValue: (x['recoveryValue'] as num).toDouble(),
      confidence: (x['confidence'] as num).toDouble(),
      status: AssessmentStatus.values.byName(x['status']),
      notes: x['notes'] ?? '',
    );
  }
  factory ItemAssessment.fromJson(Map<String, dynamic> x) => ItemAssessment(
    id: x['id']?.toString() ?? '',
    category: DeviceCategory.values.byName(
      x['category']?.toString() ?? 'accessories',
    ),
    materials: (x['materials'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
    ),
    hazards: List<String>.from(x['hazards'] ?? const []),
    reusability: (x['reusability'] as num? ?? 0).toInt(),
    repairability: (x['repairability'] as num? ?? 0).toInt(),
    recommendation: TreatmentRecommendation.values.byName(
      x['recommendation']?.toString() ?? 'recycle',
    ),
    assessedCondition: x['assessedCondition']?.toString() ?? 'recyclable',
    origin: AssessmentOrigin.values.byName(
      x['origin']?.toString() ?? AssessmentOrigin.manual.name,
    ),
    recoveryValue: (x['recoveryValue'] as num? ?? 0).toDouble(),
    confidence: (x['confidence'] as num? ?? 0).toDouble(),
    status: AssessmentStatus.values.byName(
      x['status']?.toString() ?? 'pendingSupervisor',
    ),
    notes: x['notes']?.toString() ?? '',
  );
}
