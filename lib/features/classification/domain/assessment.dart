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

class ItemAssessment {
  const ItemAssessment({
    required this.id,
    required this.category,
    required this.materials,
    required this.hazards,
    required this.reusability,
    required this.repairability,
    required this.recommendation,
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
      recoveryValue: (x['recoveryValue'] as num).toDouble(),
      confidence: (x['confidence'] as num).toDouble(),
      status: AssessmentStatus.values.byName(x['status']),
      notes: x['notes'] ?? '',
    );
  }
}
